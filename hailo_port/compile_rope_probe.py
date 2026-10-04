"""Partial RoPE probe: rotate 64 of 256 dims. Host supplies cos and sin.

The stock ``rotate_half`` is negate-one-half then concat. DFC 5.4.0 fuses that
into ``_handle_neg_feature_shuffle`` and raises IndexError. ``masked`` swaps
the halves and multiplies by a constant sign instead.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ONNX_DIR = ROOT / "artifacts" / "onnx"
SEQUENCE = 8
HEADS = 16
HEAD_DIM = 256
ROTARY = 64


def _module(masked: bool, unsqueeze_cos: bool):
    import torch
    from transformers.models.qwen3_5.modeling_qwen3_5 import rotate_half

    sys.path.insert(0, str(ROOT / "hailo_port"))
    from graphs import rotate_half_masked

    class PartialRope(torch.nn.Module):
        def forward(self, query: torch.Tensor, cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
            if unsqueeze_cos:
                cos = cos.unsqueeze(1)
                sin = sin.unsqueeze(1)
            rotated = query[..., :ROTARY]
            passed = query[..., ROTARY:]
            spun = rotate_half_masked(rotated) if masked else rotate_half(rotated)
            return torch.cat((rotated * cos + spun * sin, passed), dim=-1)

    return PartialRope().eval()


def _sample(unsqueeze_cos: bool):
    import torch

    if unsqueeze_cos:
        query = torch.zeros(1, HEADS, SEQUENCE, HEAD_DIM)
    else:
        query = torch.zeros(1, SEQUENCE, HEAD_DIM)
    cos = torch.zeros(1, SEQUENCE, ROTARY)
    sin = torch.zeros(1, SEQUENCE, ROTARY)
    return query, cos, sin


def export_one(name: str, masked: bool, unsqueeze_cos: bool) -> Path:
    import torch

    ONNX_DIR.mkdir(parents=True, exist_ok=True)
    path = ONNX_DIR / f"{name}.onnx"
    torch.onnx.export(
        _module(masked, unsqueeze_cos),
        _sample(unsqueeze_cos),
        path,
        dynamo=True,
        opset_version=18,
        external_data=False,
        input_names=["query", "cos", "sin"],
        output_names=["rotated"],
    )
    print(path, path.stat().st_size, flush=True)
    return path


def export_all() -> None:
    export_one("qwen35_rope_masked_rank3", masked=True, unsqueeze_cos=False)
    export_one("qwen35_rope_stock_rank3", masked=False, unsqueeze_cos=False)
    export_one("qwen35_rope_masked_rank4", masked=True, unsqueeze_cos=True)
    export_one("qwen35_rope_stock_rank4", masked=False, unsqueeze_cos=True)


def _print_layers(runner) -> None:
    for layer in runner._hn:
        print(
            f"LAYER {layer.op} {layer.name} in={getattr(layer, 'input_shapes', None)} out={layer.output_shapes}",
            flush=True,
        )


def parse_one(name: str) -> None:
    from hailo_sdk_client import ClientRunner

    path = ONNX_DIR / f"{name}.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(path), name, disable_onnx_simplifier=True)
    print("STATE", runner.state, flush=True)
    _print_layers(runner)
    har = ROOT / "artifacts" / f"{name}.har"
    runner.save_har(str(har))
    print(f"HAR {har} bytes={har.stat().st_size}", flush=True)


def _numpy_rope(query: np.ndarray, cos: np.ndarray, sin: np.ndarray, rank4: bool) -> np.ndarray:
    if rank4:
        cos = cos[:, None]
        sin = sin[:, None]
    rotated = query[..., :ROTARY]
    passed = query[..., ROTARY:]
    half = ROTARY // 2
    swapped = np.concatenate((rotated[..., half:], rotated[..., :half]), axis=-1)
    sign = np.concatenate((-np.ones(half), np.ones(half))).astype(np.float32)
    embedded = rotated * cos + swapped * sign * sin
    return np.concatenate((embedded, passed), axis=-1)


def compile_one(name: str, calibration_rows: int) -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    path = ONNX_DIR / f"{name}.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(path), name, disable_onnx_simplifier=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    inputs = list(runner._hn.get_input_layers())
    rng = np.random.default_rng(0)
    calib = {}
    for layer in inputs:
        shape = [calibration_rows, *layer.output_shapes[0][1:]]
        calib[layer.name] = rng.standard_normal(shape).astype(np.float32)
        print("CALIB", layer.name, calib[layer.name].shape, flush=True)
    runner.optimize(calib)
    print("OPTIMIZED", runner.state, flush=True)

    rank4 = "rank4" in name
    rows = 4
    rng = np.random.default_rng(1)
    if rank4:
        query = rng.standard_normal((rows, HEADS, SEQUENCE, HEAD_DIM)).astype(np.float32)
    else:
        query = rng.standard_normal((rows, SEQUENCE, HEAD_DIM)).astype(np.float32)
    cos = rng.standard_normal((rows, SEQUENCE, ROTARY)).astype(np.float32)
    sin = rng.standard_normal((rows, SEQUENCE, ROTARY)).astype(np.float32)
    expected = _numpy_rope(query, cos, sin, rank4)

    feed = {}
    tensors = [query, cos, sin]
    # Hailo renames the ONNX inputs to input_layer1..3 in that order.
    for layer, array in zip(sorted(inputs, key=lambda item: item.name), tensors, strict=True):
        hailo_shape = layer.output_shapes[0]
        array = np.asarray(array, dtype=np.float32)
        while array.ndim < len(hailo_shape):
            array = array[:, None]
        feed[layer.name] = array
        print("FEED", layer.name, array.shape, "hailo", hailo_shape, flush=True)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = np.array(runner.infer(ctx, feed))
    while quantized.ndim > expected.ndim:
        quantized = np.squeeze(quantized, axis=1)
    left = expected.astype(np.float64).ravel()
    right = quantized.astype(np.float64).ravel()
    cosine = float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right)))
    print(
        f"quantized cosine {cosine:.6f} mse {float(np.mean((left - right) ** 2)):.6e} "
        f"max {float(np.max(np.abs(left - right))):.6e}",
        flush=True,
    )
    hef = runner.compile()
    hef_path = ROOT / "artifacts" / f"{name}.hef"
    hef_path.write_bytes(hef)
    generated = ROOT / "hailo_port" / "generated" / f"{name}.hef"
    generated.parent.mkdir(parents=True, exist_ok=True)
    generated.write_bytes(hef)
    print(f"HEF {hef_path} bytes={len(hef)}", flush=True)


def export_attention(unroll: bool = False) -> None:
    """Layer-3 attention, no MLP, masked RoPE. Host still supplies cos and sin."""
    import torch

    sys.path.insert(0, str(ROOT / "hailo_port"))
    from graphs import AttentionOnlyMaskedRope, causal_mask
    from run_experiments import load_decoder
    from transformers.models.qwen3_5.modeling_qwen3_5 import Qwen3_5TextRotaryEmbedding

    layer, config = load_decoder(3)
    module = AttentionOnlyMaskedRope(layer, unroll_heads=unroll).eval()
    rotary = Qwen3_5TextRotaryEmbedding(config).eval()
    torch.manual_seed(0)
    hidden = torch.randn(1, SEQUENCE, config.hidden_size)
    position = torch.arange(SEQUENCE).view(1, 1, -1).expand(3, 1, -1)
    with torch.inference_mode():
        cos, sin = rotary(hidden, position)
        got = module(hidden, cos, sin)
        official, _ = layer.self_attn(
            hidden_states=layer.input_layernorm(hidden),
            position_embeddings=(cos, sin),
            attention_mask=causal_mask(hidden),
        )
        delta = float((got - (hidden + official)).abs().max())
    print(f"masked vs official max_abs {delta:.6e} cos {tuple(cos.shape)}", flush=True)
    if delta > 1e-4:
        raise SystemExit(f"rope mismatch {delta}")
    name = "qwen35_attention_unrolled_rope" if unroll else "qwen35_attention_masked_rope"
    path = ONNX_DIR / f"{name}.onnx"
    torch.onnx.export(
        module,
        (hidden, cos, sin),
        path,
        dynamo=True,
        opset_version=18,
        external_data=True,
        input_names=["hidden", "cos", "sin"],
        output_names=["hidden_out"],
    )
    data = path.with_suffix(".onnx.data")
    print(path, path.stat().st_size, data.stat().st_size if data.exists() else 0, flush=True)


def dump_attention_reference(rows: int) -> None:
    import torch

    sys.path.insert(0, str(ROOT / "hailo_port"))
    from graphs import AttentionOnlyMaskedRope
    from run_experiments import load_decoder
    from transformers.models.qwen3_5.modeling_qwen3_5 import Qwen3_5TextRotaryEmbedding

    layer, config = load_decoder(3)
    module = AttentionOnlyMaskedRope(layer).eval()
    rotary = Qwen3_5TextRotaryEmbedding(config).eval()
    torch.manual_seed(2)
    hidden = torch.randn(rows, SEQUENCE, config.hidden_size)
    position = torch.arange(SEQUENCE).view(1, 1, -1).expand(3, rows, -1)
    with torch.inference_mode():
        cos, sin = rotary(hidden, position)
        output = module(hidden, cos, sin)
    path = ROOT / "artifacts" / "clef_slice" / "rope_attn_ref.npz"
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez(path, hidden=hidden.numpy(), cos=cos.numpy(), sin=sin.numpy(), output=output.numpy())
    print(path, output.shape, flush=True)


def score_attention(calibration_rows: int, correction: str = "zp_comp_none") -> None:
    from hailo_model_optimization.algorithms.matmul_equalization.matmul_equalization import (
        MatmulEqualization,
    )
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    ref = np.load(ROOT / "artifacts" / "clef_slice" / "rope_attn_ref.npz")
    path = ONNX_DIR / "qwen35_attention_masked_rope.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(
        str(path),
        "clef_experimental_attention_masked_rope",
        disable_onnx_simplifier=True,
    )
    MatmulEqualization.should_skip_algo = lambda self: True
    # matmul1's default zp compensation multiplies a 4096-vector by a
    # length-8 tensor and the emulator raises. The compiled HEF does not
    # use this override.
    runner.load_model_script(
        "pre_quantization_optimization(matmul_correction, layers=[matmul1], "
        f"correction_type={correction})\n"
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    inputs = list(runner._hn.get_input_layers())
    rng = np.random.default_rng(0)
    calib = {}
    for layer in inputs:
        shape = [calibration_rows, *layer.output_shapes[0][1:]]
        calib[layer.name] = rng.standard_normal(shape).astype(np.float32)
    runner.optimize(calib)
    arrays = [ref["hidden"], ref["cos"], ref["sin"]]
    feed = {}
    for layer, array in zip(sorted(inputs, key=lambda item: item.name), arrays, strict=True):
        array = array.astype(np.float32)
        while array.ndim < len(layer.output_shapes[0]):
            array = array[:, None]
        feed[layer.name] = array
        print("FEED", layer.name, array.shape, flush=True)
    expected = ref["output"]
    saved = {}
    for context in (
        InferenceContext.SDK_NATIVE,
        InferenceContext.SDK_FP_OPTIMIZED,
        InferenceContext.SDK_QUANTIZED,
    ):
        with runner.infer_context(context) as ctx:
            got = np.array(runner.infer(ctx, feed))
        while got.ndim > expected.ndim:
            got = np.squeeze(got, axis=1)
        saved[context.value] = got.astype(np.float32)
        left = expected.astype(np.float64).ravel()
        right = got.astype(np.float64).ravel()
        cosine = float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right)))
        print(
            f"{context.value} cosine {cosine:.6f} mse {float(np.mean((left - right) ** 2)):.6e} "
            f"max {float(np.max(np.abs(left - right))):.6e}",
            flush=True,
        )
    if correction != "zp_comp_none":
        return
    path = ROOT / "artifacts" / "clef_slice" / "rope_attn_score.npz"
    np.savez(
        path,
        hidden=ref["hidden"],
        cos=ref["cos"],
        sin=ref["sin"],
        output=expected.astype(np.float32),
        native=saved["sdk_native"],
        quantized=saved["sdk_quantized"],
    )
    print(path, flush=True)


def score_decisions() -> None:
    """Host MLP and FP32 head on the saved Hailo attention outputs."""
    import json

    import torch

    sys.path.insert(0, str(ROOT / "hailo_port"))
    sys.path.insert(0, str(ROOT / "hailo_port" / "upstream"))
    from graphs import StaticJointHead, causal_mask
    from joint_schema_model import JointSchemaHead
    from run_experiments import decision_from_logits, load_decoder
    from safetensors.torch import load_file

    data = np.load(ROOT / "artifacts" / "clef_slice" / "rope_attn_score.npz")
    layer, _ = load_decoder(3)
    layer.eval()
    hidden = torch.from_numpy(data["hidden"])
    cos = torch.from_numpy(data["cos"])
    sin = torch.from_numpy(data["sin"])
    with torch.inference_mode():
        official = layer(hidden, position_embeddings=(cos, sin), attention_mask=causal_mask(hidden))

        def finish(attn: np.ndarray) -> torch.Tensor:
            tensor = torch.from_numpy(attn)
            return tensor + layer.mlp(layer.post_attention_layernorm(tensor))

        finished = {
            "official": official,
            "native": finish(data["native"]),
            "quantized": finish(data["quantized"]),
        }
    config = json.loads((ROOT / "artifacts" / "weights" / "joint_head_config.json").read_text())
    head = JointSchemaHead(**config).eval()
    head.load_state_dict(load_file(ROOT / "artifacts" / "weights" / "joint_head.safetensors"), strict=True)
    static = StaticJointHead(head.float(), (3, 2)).eval()
    torch.manual_seed(1)
    embedding = torch.randn(24, 4096)
    token_ids = torch.arange(16)
    spans = ((6, 8), (8, 10), (10, 12), (12, 14), (14, 16))
    lexical = torch.stack([embedding[token_ids[start:end]].mean(0) for start, end in spans])
    type_ids = torch.tensor([1, 0])
    names = (["paid", "overdue", "draft"], ["true", "false"])
    cases = hidden.shape[0]
    for label in ("native", "quantized"):
        agreements = 0
        high_confidence = 0
        logit_cosines = []
        prob_abs = []
        with torch.inference_mode():
            for index in range(cases):
                left_h = finished["official"][index : index + 1]
                right_h = finished[label][index : index + 1]
                left_logits = static(torch.cat([left_h, left_h], dim=1), lexical, type_ids)
                right_logits = static(torch.cat([right_h, right_h], dim=1), lexical, type_ids)
                left = left_logits.float().numpy()
                right = right_logits.float().numpy()
                logit_cosines.append(float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right))))
                left_choices = []
                right_choices = []
                for start, question_names in ((0, names[0]), (3, names[1])):
                    original = decision_from_logits(left_logits[start : start + len(question_names)], question_names)
                    changed = decision_from_logits(right_logits[start : start + len(question_names)], question_names)
                    left_choices.append(original["choice"])
                    right_choices.append(changed["choice"])
                    prob_abs.append(
                        max(
                            abs(original["probabilities"][name] - changed["probabilities"][name])
                            for name in question_names
                        )
                    )
                    if (
                        original["choice"] != changed["choice"]
                        and original["margin"] >= 0.2
                        and original["confidence"] >= 0.7
                    ):
                        high_confidence += 1
                agreements += int(left_choices == right_choices)
        left_np = finished["official"].float().numpy().astype(np.float64).ravel()
        right_np = finished[label].float().numpy().astype(np.float64).ravel()
        print(
            f"{label} block cosine {float(left_np @ right_np / (np.linalg.norm(left_np) * np.linalg.norm(right_np))):.6f} "
            f"max {float(np.max(np.abs(left_np - right_np))):.6e} "
            f"agreement {agreements / cases:.3f} high_confidence {high_confidence} "
            f"logit_cosine_min {min(logit_cosines):.6f} prob_abs_max {max(prob_abs):.6f}",
            flush=True,
        )


def dump_group_qkv(rows: int = 12, kv_heads: int = 1) -> None:
    """Q, K, and V for the first ``kv_heads`` real layer-3 groups, after host RoPE."""
    import torch

    sys.path.insert(0, str(ROOT / "hailo_port"))
    from graphs import UnrolledAttentionCore, apply_partial_rope
    from run_experiments import load_decoder
    from transformers.models.qwen3_5.modeling_qwen3_5 import (
        Qwen3_5TextRotaryEmbedding,
        eager_attention_forward,
    )

    layer, config = load_decoder(3)
    attention = layer.self_attn
    group = attention.num_key_value_groups
    rotary = Qwen3_5TextRotaryEmbedding(config).eval()
    torch.manual_seed(2)
    hidden = torch.randn(rows, SEQUENCE, config.hidden_size)
    position = torch.arange(SEQUENCE).view(1, 1, -1).expand(3, rows, -1)
    with torch.inference_mode():
        cos, sin = rotary(hidden, position)
        normalized = layer.input_layernorm(hidden)
        input_shape = normalized.shape[:-1]
        hidden_shape = (*input_shape, -1, attention.head_dim)
        query_states, _gate = torch.chunk(
            attention.q_proj(normalized).view(*input_shape, -1, attention.head_dim * 2),
            2,
            dim=-1,
        )
        query_states = attention.q_norm(query_states.view(hidden_shape)).transpose(1, 2)
        key_states = attention.k_norm(attention.k_proj(normalized).view(hidden_shape)).transpose(1, 2)
        value_states = attention.v_proj(normalized).view(hidden_shape).transpose(1, 2)
        query_states = apply_partial_rope(query_states, cos.unsqueeze(1), sin.unsqueeze(1))
        key_states = apply_partial_rope(key_states, cos.unsqueeze(1), sin.unsqueeze(1))
        query_group = query_states[:, : kv_heads * group]
        key_group = key_states[:, :kv_heads]
        value_group = value_states[:, :kv_heads]
        packed = query_group.permute(0, 2, 1, 3).reshape(rows, SEQUENCE, -1)
        reference = UnrolledAttentionCore()(packed, key_group, value_group)
    path = ROOT / "artifacts" / "clef_slice" / f"group{kv_heads}_qkv.npz"
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez(
        path,
        hidden=hidden.numpy(),
        cos=cos.numpy(),
        sin=sin.numpy(),
        query=packed.numpy(),
        key=key_group.numpy(),
        value=value_group.numpy(),
        reference=reference.numpy(),
        kv_heads=np.array(kv_heads),
    )
    print(path, packed.shape, key_group.shape, reference.shape, flush=True)


def quantize_saved_group(calibration_rows: int = 64, kv_heads: int = 1) -> None:
    """Quantized emulator of a compiled KV-group HEF on the saved real QKV."""
    from hailo_model_optimization.algorithms.fix_zp_comp_encoding.fix_zp_comp_encoding import (
        FixZpCompEncoding,
    )
    from hailo_model_optimization.algorithms.matmul_equalization.matmul_equalization import (
        MatmulEqualization,
    )
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    heads = kv_heads * 4
    suffix = _core_suffix(heads, kv_heads)
    model_name = f"clef_experimental_attn_unrolled{suffix}" if suffix else "clef_experimental_attn_unrolled"
    data = np.load(ROOT / "artifacts" / "clef_slice" / f"group{kv_heads}_qkv.npz")
    path = ONNX_DIR / f"qwen35_attention_unrolled_core{suffix}.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(path), model_name, disable_onnx_simplifier=True)
    original_walk = FixZpCompEncoding._get_first_real_weight_layer

    def walk(self, layer_name):
        try:
            return original_walk(self, layer_name)
        except RuntimeError:
            return layer_name

    FixZpCompEncoding._get_first_real_weight_layer = walk
    MatmulEqualization.should_skip_algo = lambda self: True
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    inputs = list(runner._hn.get_input_layers())
    rng = np.random.default_rng(0)
    calib = {
        layer.name: rng.standard_normal([calibration_rows, *layer.output_shapes[0][1:]]).astype(np.float32)
        for layer in inputs
    }
    runner.optimize(calib)
    arrays = [data["query"], data["key"], data["value"]]
    feed = {}
    for layer, array in zip(sorted(inputs, key=lambda item: item.name), arrays, strict=True):
        array = np.asarray(array, dtype=np.float32)
        hailo_shape = layer.output_shapes[0]
        if array.ndim == 4 and list(array.shape[1:]) != list(hailo_shape[1:]):
            array = np.transpose(array, (0, 2, 3, 1))
        while array.ndim < len(hailo_shape):
            array = array[:, None]
        feed[layer.name] = array
        print("FEED", layer.name, array.shape, hailo_shape, flush=True)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        got = np.array(runner.infer(ctx, feed))
    expected = data["reference"]
    cosine, mse, maximum = _score_arrays(expected, got)
    print(f"group quantized cosine {cosine:.6f} mse {mse:.6e} max {maximum:.6e}", flush=True)
    out = ROOT / "artifacts" / "clef_slice" / f"group{kv_heads}_hailo.npz"
    np.savez(out, hailo=got.astype(np.float32))
    print(out, got.shape, flush=True)


def score_group_decisions(kv_heads: int = 1) -> None:
    """Decisions after replacing the first KV groups with the quantized Hailo core."""
    import json

    import torch

    sys.path.insert(0, str(ROOT / "hailo_port"))
    sys.path.insert(0, str(ROOT / "hailo_port" / "upstream"))
    from graphs import StaticJointHead, causal_mask
    from joint_schema_model import JointSchemaHead
    from run_experiments import decision_from_logits, load_decoder
    from safetensors.torch import load_file
    from transformers.models.qwen3_5.modeling_qwen3_5 import eager_attention_forward

    saved = np.load(ROOT / "artifacts" / "clef_slice" / f"group{kv_heads}_qkv.npz")
    hailo = np.load(ROOT / "artifacts" / "clef_slice" / f"group{kv_heads}_hailo.npz")["hailo"]
    while hailo.ndim > 3:
        hailo = np.squeeze(hailo, axis=1)
    layer, _config = load_decoder(3)
    attention = layer.self_attn
    hidden = torch.from_numpy(saved["hidden"])
    cos = torch.from_numpy(saved["cos"])
    sin = torch.from_numpy(saved["sin"])
    reference = torch.from_numpy(saved["reference"])
    hailo_group = torch.from_numpy(hailo.astype(np.float32))
    width = reference.shape[-1]
    with torch.inference_mode():
        normalized = layer.input_layernorm(hidden)
        input_shape = normalized.shape[:-1]
        hidden_shape = (*input_shape, -1, attention.head_dim)
        _query, gate = torch.chunk(
            attention.q_proj(normalized).view(*input_shape, -1, attention.head_dim * 2),
            2,
            dim=-1,
        )
        gate = torch.sigmoid(gate.reshape(*input_shape, -1))
        query_states = attention.q_norm(_query.view(hidden_shape)).transpose(1, 2)
        key_states = attention.k_norm(attention.k_proj(normalized).view(hidden_shape)).transpose(1, 2)
        value_states = attention.v_proj(normalized).view(hidden_shape).transpose(1, 2)
        from graphs import apply_partial_rope

        query_states = apply_partial_rope(query_states, cos.unsqueeze(1), sin.unsqueeze(1))
        key_states = apply_partial_rope(key_states, cos.unsqueeze(1), sin.unsqueeze(1))
        mixed, _weights = eager_attention_forward(
            attention,
            query_states,
            key_states,
            value_states,
            causal_mask(hidden),
            scaling=attention.scaling,
            dropout=0.0,
        )
        mixed = mixed.reshape(*input_shape, -1).contiguous()
        hailo_mix = mixed.clone()
        float_mix = mixed.clone()
        hailo_mix[:, :, :width] = hailo_group
        float_mix[:, :, :width] = reference

        def block_from(attended: torch.Tensor) -> torch.Tensor:
            projected = attention.o_proj(attended * gate)
            hidden_states = hidden + projected
            return hidden_states + layer.mlp(layer.post_attention_layernorm(hidden_states))

        official = layer(hidden, position_embeddings=(cos, sin), attention_mask=causal_mask(hidden))
        finished = {
            "official": official,
            "float_group": block_from(float_mix),
            "hailo_group": block_from(hailo_mix),
        }
    config = json.loads((ROOT / "artifacts" / "weights" / "joint_head_config.json").read_text())
    head = JointSchemaHead(**config).eval()
    head.load_state_dict(load_file(ROOT / "artifacts" / "weights" / "joint_head.safetensors"), strict=True)
    static = StaticJointHead(head.float(), (3, 2)).eval()
    torch.manual_seed(1)
    embedding = torch.randn(24, 4096)
    token_ids = torch.arange(16)
    spans = ((6, 8), (8, 10), (10, 12), (12, 14), (14, 16))
    lexical = torch.stack([embedding[token_ids[start:end]].mean(0) for start, end in spans])
    type_ids = torch.tensor([1, 0])
    names = (["paid", "overdue", "draft"], ["true", "false"])
    cases = hidden.shape[0]
    for label in ("float_group", "hailo_group"):
        agreements = 0
        high_confidence = 0
        logit_cosines = []
        prob_abs = []
        with torch.inference_mode():
            for index in range(cases):
                left_h = finished["official"][index : index + 1]
                right_h = finished[label][index : index + 1]
                repeated_left = torch.cat([left_h, left_h], dim=1)
                repeated_right = torch.cat([right_h, right_h], dim=1)
                left_logits = static(repeated_left, lexical, type_ids)
                right_logits = static(repeated_right, lexical, type_ids)
                left = left_logits.float().numpy()
                right = right_logits.float().numpy()
                logit_cosines.append(float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right))))
                left_choices = []
                right_choices = []
                for start, question_names in ((0, names[0]), (3, names[1])):
                    original = decision_from_logits(left_logits[start : start + len(question_names)], question_names)
                    changed = decision_from_logits(right_logits[start : start + len(question_names)], question_names)
                    left_choices.append(original["choice"])
                    right_choices.append(changed["choice"])
                    prob_abs.append(
                        max(
                            abs(original["probabilities"][name] - changed["probabilities"][name])
                            for name in question_names
                        )
                    )
                    if (
                        original["choice"] != changed["choice"]
                        and original["margin"] >= 0.2
                        and original["confidence"] >= 0.7
                    ):
                        high_confidence += 1
                agreements += int(left_choices == right_choices)
        left_np = finished["official"].float().numpy().astype(np.float64).ravel()
        right_np = finished[label].float().numpy().astype(np.float64).ravel()
        print(
            f"{label} block cosine {float(left_np @ right_np / (np.linalg.norm(left_np) * np.linalg.norm(right_np))):.6f} "
            f"max {float(np.max(np.abs(left_np - right_np))):.6e} "
            f"agreement {agreements / cases:.3f} high_confidence {high_confidence} "
            f"logit_cosine_min {min(logit_cosines):.6f} prob_abs_max {max(prob_abs):.6f}",
            flush=True,
        )


def export_shared_kv_group() -> None:
    """Four query heads sharing one KV head.

    The ONNX optimizer folds that single KV axis into a bare Squeeze, and
    Hailo rejects the Squeeze. Leaving the optimizer off keeps a Slice in
    front of the Squeeze, which parses. The mask is a buffer so the graph
    does not contain Trilu or Where.
    """
    import torch

    sys.path.insert(0, str(ROOT / "hailo_port"))
    from graphs import UnrolledAttentionCore

    class Buffered(torch.nn.Module):
        def __init__(self) -> None:
            super().__init__()
            allowed = torch.ones(SEQUENCE, SEQUENCE, dtype=torch.bool).tril()
            mask = torch.zeros(1, SEQUENCE, SEQUENCE).masked_fill(~allowed, -64.0)
            self.register_buffer("flat_mask", mask)

        def forward(self, query: torch.Tensor, key: torch.Tensor, value: torch.Tensor) -> torch.Tensor:
            dim = key.shape[-1]
            heads = query.shape[-1] // dim
            group = heads // key.shape[1]
            key_w = key.permute(0, 3, 2, 1)
            value_w = value.permute(0, 3, 2, 1)
            scale = dim**-0.5
            outputs = []
            for index in range(heads):
                kv = index // group
                query_head = query.narrow(-1, index * dim, dim)
                key_head = key_w.narrow(-1, kv, 1).squeeze(-1)
                value_head = value_w.narrow(-1, kv, 1).squeeze(-1).transpose(-1, -2)
                scores = torch.matmul(query_head, key_head) * scale + self.flat_mask
                outputs.append(torch.matmul(torch.softmax(scores, dim=-1), value_head))
            return torch.cat(outputs, dim=-1)

    module = Buffered().eval()
    suffix = _core_suffix(4, 1)
    query = torch.zeros(1, SEQUENCE, 4 * 256)
    key = torch.zeros(1, 1, SEQUENCE, 256)
    value = torch.zeros(1, 1, SEQUENCE, 256)
    path = ONNX_DIR / f"qwen35_attention_unrolled_core{suffix}.onnx"
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        module,
        (query, key, value),
        path,
        dynamo=True,
        opset_version=18,
        external_data=False,
        optimize=False,
        input_names=["query", "key", "value"],
        output_names=["attended"],
    )
    torch.manual_seed(2)
    query = torch.randn(4, SEQUENCE, 4 * 256)
    key = torch.randn(4, 1, SEQUENCE, 256)
    value = torch.randn(4, 1, SEQUENCE, 256)
    with torch.inference_mode():
        output = module(query, key, value)
        reference = UnrolledAttentionCore()(query, key, value)
    gap = float((output - reference).abs().max())
    ref = ROOT / "artifacts" / "clef_slice" / f"unrolled_core_ref{suffix}.npz"
    ref.parent.mkdir(parents=True, exist_ok=True)
    np.savez(ref, query=query.numpy(), key=key.numpy(), value=value.numpy(), output=output.numpy())
    print(path, path.stat().st_size, output.shape, f"gap {gap:.3e}", flush=True)


def _core_suffix(heads: int, kv_heads: int) -> str:
    if heads == 16 and kv_heads == 4:
        return ""
    return f"_{heads}h_{kv_heads}kv"


def export_unrolled_core(heads: int = 16, kv_heads: int = 4) -> None:
    import torch

    if heads % kv_heads != 0:
        raise SystemExit(f"{heads} query heads do not divide into {kv_heads} KV heads")
    sys.path.insert(0, str(ROOT / "hailo_port"))
    from graphs import UnrolledAttentionCore

    module = UnrolledAttentionCore().eval()
    suffix = _core_suffix(heads, kv_heads)
    query = torch.zeros(1, SEQUENCE, heads * 256)
    key = torch.zeros(1, kv_heads, SEQUENCE, 256)
    value = torch.zeros(1, kv_heads, SEQUENCE, 256)
    path = ONNX_DIR / f"qwen35_attention_unrolled_core{suffix}.onnx"
    torch.onnx.export(
        module,
        (query, key, value),
        path,
        dynamo=True,
        opset_version=18,
        external_data=False,
        input_names=["query", "key", "value"],
        output_names=["attended"],
    )
    torch.manual_seed(2)
    query = torch.randn(4, SEQUENCE, heads * 256)
    key = torch.randn(4, kv_heads, SEQUENCE, 256)
    value = torch.randn(4, kv_heads, SEQUENCE, 256)
    with torch.inference_mode():
        output = module(query, key, value)
    ref = ROOT / "artifacts" / "clef_slice" / f"unrolled_core_ref{suffix}.npz"
    ref.parent.mkdir(parents=True, exist_ok=True)
    np.savez(ref, query=query.numpy(), key=key.numpy(), value=value.numpy(), output=output.numpy())
    print(path, path.stat().st_size, output.shape, flush=True)


def _score_arrays(expected: np.ndarray, got: np.ndarray) -> tuple[float, float, float]:
    while got.ndim > expected.ndim:
        got = np.squeeze(got, axis=1)
    left = expected.astype(np.float64).ravel()
    right = got.astype(np.float64).ravel()
    cosine = float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right)))
    return cosine, float(np.mean((left - right) ** 2)), float(np.max(np.abs(left - right)))


def _short_name(layer) -> str:
    return layer.name.split("/")[-1]


def _kv_group_context_script(runner) -> str:
    """Put each KV head's matmul chain in its own context.

    The automatic search of twelve query heads and three KV heads accepted
    18 contexts and then failed in the splitter. One group already fits in
    one context, so three contexts is the split to try.
    """
    graph = runner._hn

    def successors(layer):
        return list(graph.successors(layer))

    def predecessors(layer):
        return list(graph.predecessors(layer))

    key = next(layer for layer in graph if _short_name(layer) == "input_layer2")
    key_slices = []
    for node in successors(key):
        key_slices.extend(child for child in successors(node) if _short_name(child).startswith("slice"))
    if not key_slices:
        raise SystemExit("no key slices to split into contexts")
    stop = {"concat1", "output_layer1", "feature_splitter1"}
    groups = []
    for key_slice in key_slices:
        seen = set()
        stack = list(successors(key_slice))
        while stack:
            node = stack.pop()
            if node in seen or _short_name(node) in stop or _short_name(node).startswith("input_layer"):
                continue
            seen.add(node)
            stack.extend(successors(node))
        pending = list(seen)
        while pending:
            node = pending.pop()
            for pred in predecessors(node):
                if pred in seen or _short_name(pred) in stop or _short_name(pred).startswith("input_layer"):
                    continue
                slice_children = [child for child in successors(pred) if _short_name(child).startswith("slice")]
                if len(slice_children) > 1:
                    continue
                if any(pred in group for group in groups):
                    continue
                seen.add(pred)
                pending.append(pred)
        groups.append(seen)
    for layer in graph:
        if _short_name(layer) in {"feature_splitter1", "concat1", "output_layer1"}:
            groups[0].add(layer)
    lines = []
    for index, group in enumerate(groups):
        names = sorted(_short_name(layer) for layer in group)
        lines.append(f"context_{index} = context([{', '.join(names)}])")
        print(f"CONTEXT {index} layers={len(names)}", flush=True)
    return "\n".join(lines) + "\n"


def score_unrolled_core(
    calibration_rows: int,
    heads: int = 16,
    kv_heads: int = 4,
    manual_contexts: bool = False,
) -> None:
    from hailo_model_optimization.algorithms.matmul_equalization.matmul_equalization import (
        MatmulEqualization,
    )
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    suffix = _core_suffix(heads, kv_heads)
    model_name = "clef_experimental_attn_unrolled" if suffix == "" else f"clef_experimental_attn_unrolled{suffix}"
    path = ONNX_DIR / f"qwen35_attention_unrolled_core{suffix}.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(path), model_name, disable_onnx_simplifier=True)
    groups = []
    for layer in runner._hn:
        if "matmul" in layer.name:
            groups.append((layer.name, getattr(layer, "groups", None)))
    print("MATMULS", len(groups), groups[:4], flush=True)
    # QK matmuls are transposed and signed, so they need zp_comp_block. The
    # encoding fix walks back to a weight producer and raises on this
    # activation-only path. Stop the walk and keep going.
    from hailo_model_optimization.algorithms.fix_zp_comp_encoding.fix_zp_comp_encoding import (
        FixZpCompEncoding,
    )

    original_walk = FixZpCompEncoding._get_first_real_weight_layer

    def walk(self, layer_name):
        try:
            return original_walk(self, layer_name)
        except RuntimeError as exc:
            print(f"zp walk stopped at {layer_name}: {exc}", flush=True)
            return layer_name

    FixZpCompEncoding._get_first_real_weight_layer = walk
    params = runner.get_params()
    rewritten = {}
    for key, value in params.items():
        if hasattr(value, "ndim") and key.endswith("additive_mask:0"):
            value = np.array(value, copy=True)
            # finfo.min makes the softmax exponent fit produce NaNs.
            value[value < -1000] = np.float32(-64)
            if value.ndim == 2:
                value = value.reshape(1, *value.shape)
            print("widened", key, tuple(value.shape), flush=True)
        rewritten[key] = value
    runner.load_params(rewritten)
    MatmulEqualization.should_skip_algo = lambda self: True
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    inputs = list(runner._hn.get_input_layers())
    rng = np.random.default_rng(0)
    calib = {
        layer.name: rng.standard_normal([calibration_rows, *layer.output_shapes[0][1:]]).astype(np.float32)
        for layer in inputs
    }
    runner.optimize(calib)
    ref = np.load(ROOT / "artifacts" / "clef_slice" / f"unrolled_core_ref{suffix}.npz")
    arrays = [ref["query"], ref["key"], ref["value"]]
    feed = {}
    for layer, array in zip(sorted(inputs, key=lambda item: item.name), arrays, strict=True):
        array = np.asarray(array, dtype=np.float32)
        hailo_shape = layer.output_shapes[0]
        if array.ndim == 4 and list(array.shape[1:]) != list(hailo_shape[1:]):
            array = np.transpose(array, (0, 2, 3, 1))
        while array.ndim < len(hailo_shape):
            array = array[:, None]
        feed[layer.name] = array
        print("FEED", layer.name, array.shape, layer.output_shapes[0], flush=True)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        got = np.array(runner.infer(ctx, feed))
    expected = ref["output"]
    cosine, mse, maximum = _score_arrays(expected, got)
    print(f"quantized cosine {cosine:.6f} mse {mse:.6e} max {maximum:.6e}", flush=True)
    if manual_contexts:
        # Optimize replaces softmax and ew_add, so the context script has to
        # name the layers that exist after that pass.
        runner.load_model_script(_kv_group_context_script(runner))
    # The 64-row file stays. A larger calibration set is a different HEF.
    dest_name = model_name if calibration_rows == 64 else f"{model_name}_c{calibration_rows}"
    if manual_contexts:
        dest_name += "_ctx"
    dest = ROOT / "hailo_port" / "generated" / f"{dest_name}.hef"
    if dest.exists():
        print(f"keep {dest} bytes={dest.stat().st_size}", flush=True)
    else:
        hef = runner.compile()
        dest.write_bytes(hef)
        print(f"HEF {dest} bytes={len(hef)}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "export"
    try:
        if command == "export":
            export_all()
        elif command == "export-attention":
            export_attention()
        elif command == "export-unrolled":
            export_attention(unroll=True)
        elif command == "dump-group":
            rows = int(sys.argv[2]) if len(sys.argv) > 2 else 12
            kv_heads = int(sys.argv[3]) if len(sys.argv) > 3 else 1
            dump_group_qkv(rows, kv_heads)
        elif command == "quant-group":
            rows = int(sys.argv[2]) if len(sys.argv) > 2 else 64
            kv_heads = int(sys.argv[3]) if len(sys.argv) > 3 else 1
            quantize_saved_group(rows, kv_heads)
        elif command == "score-group":
            score_group_decisions(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
        elif command == "export-gqa":
            export_shared_kv_group()
        elif command == "export-core":
            heads = int(sys.argv[2]) if len(sys.argv) > 2 else 16
            kv_heads = int(sys.argv[3]) if len(sys.argv) > 3 else 4
            export_unrolled_core(heads, kv_heads)
        elif command == "score-core":
            rows = int(sys.argv[2]) if len(sys.argv) > 2 else 64
            heads = int(sys.argv[3]) if len(sys.argv) > 3 else 16
            kv_heads = int(sys.argv[4]) if len(sys.argv) > 4 else 4
            manual_contexts = len(sys.argv) > 5 and sys.argv[5] == "contexts"
            score_unrolled_core(rows, heads, kv_heads, manual_contexts)
        elif command == "dump-attention":
            dump_attention_reference(int(sys.argv[2]) if len(sys.argv) > 2 else 4)
        elif command == "score-attention":
            correction = sys.argv[3] if len(sys.argv) > 3 else "zp_comp_none"
            score_attention(int(sys.argv[2]) if len(sys.argv) > 2 else 64, correction)
        elif command == "score-decisions":
            score_decisions()
        elif command == "parse":
            parse_one(sys.argv[2])
        elif command == "compile":
            rows = int(sys.argv[3]) if len(sys.argv) > 3 else 64
            compile_one(sys.argv[2], rows)
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

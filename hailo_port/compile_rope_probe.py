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


def export_attention() -> None:
    """Layer-3 attention, no MLP, masked RoPE. Host still supplies cos and sin."""
    import torch

    sys.path.insert(0, str(ROOT / "hailo_port"))
    from graphs import AttentionOnlyMaskedRope, causal_mask
    from run_experiments import load_decoder
    from transformers.models.qwen3_5.modeling_qwen3_5 import Qwen3_5TextRotaryEmbedding

    layer, config = load_decoder(3)
    module = AttentionOnlyMaskedRope(layer).eval()
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
    path = ONNX_DIR / "qwen35_attention_masked_rope.onnx"
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


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "export"
    try:
        if command == "export":
            export_all()
        elif command == "export-attention":
            export_attention()
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

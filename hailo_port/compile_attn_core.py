"""Compile one Qwen3.5 full-attention core: scaled QK^T, causal mask, softmax, AV.

Head dimension 256 and sequence 8 match one Clef-Flash full-attention head.
Q, K, and V are inputs. The projections, RoPE, and output gate stay on the host.
Hailo DFC 5.4.0 fused a rank-3 mask into softmax and then crashed in the
post-fuser while broadcasting that mask. The mask4 variant stores the mask as
[1, 1, S, S] so the constant matches the Hailo scores tensor [-1, 1, S, S].
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts" / "clef_slice"
SEQUENCE = 8
HEAD = 256
PACKED = HEAD * 3


def causal_mask(rank4: bool) -> torch.Tensor:
    allowed = torch.ones(SEQUENCE, SEQUENCE, dtype=torch.bool).tril()
    mask = torch.zeros(1, 1, SEQUENCE, SEQUENCE, dtype=torch.float32).masked_fill(
        ~allowed.view(1, 1, SEQUENCE, SEQUENCE),
        torch.finfo(torch.float32).min,
    )
    return mask if rank4 else mask.reshape(1, SEQUENCE, SEQUENCE)


class PackedAttention(torch.nn.Module):
    def __init__(self, variant: str) -> None:
        super().__init__()
        self.variant = variant
        if variant != "nomask":
            self.register_buffer("mask", causal_mask(rank4=variant == "mask4"))

    def forward(self, qkv: torch.Tensor) -> torch.Tensor:
        query, key, value = torch.split(qkv, HEAD, dim=-1)
        scale = HEAD**-0.5
        if self.variant == "scale_k":
            scores = torch.matmul(query, (key * scale).transpose(-1, -2))
        else:
            scores = torch.matmul(query, key.transpose(-1, -2)) * scale
        if self.variant != "nomask":
            scores = scores + self.mask
        return torch.matmul(torch.softmax(scores, dim=-1), value)


def export_variant(variant: str) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    module = PackedAttention(variant).eval()
    sample = torch.zeros(1, SEQUENCE, PACKED)
    path = OUT / f"attn_core_{variant}_s{SEQUENCE}_d{HEAD}.onnx"
    torch.onnx.export(module, (sample,), path, dynamo=True, opset_version=18, external_data=False)
    print(path, flush=True)
    return path


def reference(variant: str, samples: torch.Tensor) -> np.ndarray:
    module = PackedAttention(variant).eval()
    with torch.inference_mode():
        return module(samples).numpy()


def compile_variant(variant: str, calibration_rows: int) -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    onnx_path = OUT / f"attn_core_{variant}_s{SEQUENCE}_d{HEAD}.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(
        str(onnx_path),
        "clef_experimental_attn_core",
        disable_onnx_simplifier=True,
    )
    model = runner._hn
    for layer in model:
        shapes = getattr(layer, "input_shapes", None)
        extra = ""
        additive = getattr(layer, "additive_mask", None)
        if additive is not None:
            extra = f" additive_mask={tuple(np.shape(additive))}"
        print(
            f"LAYER {layer.op} {layer.name} in={shapes} out={layer.output_shapes}{extra}",
            flush=True,
        )
    runner.save_har(str(OUT / f"clef_experimental_attn_core_{variant}.har"))
    # The parser stores the causal mask as [S, S]. The post-fuser builds a constant
    # input of shape [-1, *mask.shape], which is rank 3, and then crashes while
    # broadcasting it onto scores of shape [-1, 1, S, S]. A leading 1 makes the
    # constant [-1, 1, S, S].
    params = runner.get_params()
    rewritten = {}
    for key in list(params.keys()):
        value = params[key]
        if not hasattr(value, "shape"):
            continue
        if key.endswith("additive_mask:0") and value.ndim == 2:
            value = value.reshape(1, *value.shape)
            print(f"widened {key} to {value.shape}", flush=True)
        rewritten[key] = value
    if rewritten:
        runner.load_params(rewritten)
    # Both matmul inputs are activations. The default zp_comp_block walks backward
    # looking for a weight producer and raises when the walk reaches the input.
    script = (
        "pre_quantization_optimization(matmul_correction, layers=[matmul1, matmul2], "
        "correction_type=zp_comp_none)\n"
    )
    if calibration_rows > 64:
        script += (
            "model_optimization_config(calibration, batch_size=8, "
            f"calibset_size={calibration_rows})\n"
        )
    runner.load_model_script(script)

    torch.manual_seed(0)
    samples = torch.randn(max(calibration_rows, 4), SEQUENCE, PACKED)
    expected = reference(variant, samples[:4])
    calib = samples[:calibration_rows].numpy()[:, None, :, :].astype(np.float32)
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)

    dataset = samples[:4].numpy()[:, None, :, :].astype(np.float32)
    probe = samples[:1].clone()
    scrambled = probe.clone()
    scrambled[:, 1:, HEAD * 2 :] = torch.randn(1, SEQUENCE - 1, HEAD)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = np.array(runner.infer(ctx, dataset))
        leaked = np.array(runner.infer(ctx, scrambled.numpy()[:, None, :, :].astype(np.float32)))
    while quantized.ndim > expected.ndim:
        quantized = quantized.squeeze(1)
    while leaked.ndim > expected.ndim:
        leaked = leaked.squeeze(1)
    left = expected.astype(np.float64).ravel()
    right = quantized.astype(np.float64).ravel()
    cosine = float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right)))
    print(
        f"quantized cosine {cosine:.6f} mse {float(np.mean((left - right) ** 2)):.6e} "
        f"max {float(np.max(np.abs(left - right))):.6e}",
        flush=True,
    )
    quant_leak = float(np.max(np.abs(quantized[0, 0] - leaked[0, 0])))
    ref_probe = reference(variant, probe)
    ref_scrambled = reference(variant, scrambled)
    ref_leak = float(np.max(np.abs(ref_probe[0, 0] - ref_scrambled[0, 0])))
    print(f"future_token_leak quantized {quant_leak:.6e} reference {ref_leak:.6e}", flush=True)
    hef = runner.compile()
    hef_path = OUT / f"clef_experimental_attn_core_{variant}.hef"
    hef_path.write_bytes(hef)
    print(f"HEF {hef_path} bytes={len(hef)}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "export"
    variant = sys.argv[2] if len(sys.argv) > 2 else "mask4"
    calibration_rows = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    try:
        if command == "export":
            export_variant(variant)
        elif command == "compile":
            compile_variant(variant, calibration_rows)
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

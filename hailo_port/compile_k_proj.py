"""Compile a real Clef-Flash layer-3 Q, K, or V projection.

K and V are bias-free linears, hidden 4096 to 1024 (four KV heads of dimension
256). Q is hidden 4096 to 8192, which includes the per-head output gate.
RMSNorm and RoPE stay on the host. These are the full published matrices.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np
import torch
from safetensors.torch import load_file

ROOT = Path(__file__).resolve().parents[1]
WEIGHTS = ROOT / "artifacts" / "weights" / "clef_layer_3.safetensors"
OUT = ROOT / "artifacts" / "clef_slice"
HIDDEN = 4096
SEQUENCE = 8
PROJECTIONS = {
    "k": ("model.language_model.layers.3.self_attn.k_proj.weight", 1024),
    "v": ("model.language_model.layers.3.self_attn.v_proj.weight", 1024),
    "q": ("model.language_model.layers.3.self_attn.q_proj.weight", 8192),
}


class KeyProjection(torch.nn.Module):
    def __init__(self, outputs: int) -> None:
        super().__init__()
        self.proj = torch.nn.Linear(HIDDEN, outputs, bias=False)

    def forward(self, hidden: torch.Tensor) -> torch.Tensor:
        return self.proj(hidden)


def load_projection(which: str) -> KeyProjection:
    key, outputs = PROJECTIONS[which]
    raw = load_file(WEIGHTS)
    module = KeyProjection(outputs).eval()
    with torch.no_grad():
        module.proj.weight.copy_(raw[key].float())
    return module


def export_projection(which: str) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    module = load_projection(which)
    sample = torch.zeros(1, SEQUENCE, HIDDEN)
    path = OUT / f"clef_layer3_{which}_proj.onnx"
    torch.onnx.export(module, (sample,), path, dynamo=True, opset_version=18, external_data=False)
    print(path, flush=True)
    return path


def compile_projection(which: str, calibration_rows: int) -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    net_name = f"clef_experimental_{which}_proj"
    onnx_path = OUT / f"clef_layer3_{which}_proj.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(onnx_path), net_name, disable_onnx_simplifier=True)
    for layer in runner._hn:
        print(
            f"LAYER {layer.op} {layer.name} in={layer.input_shapes} out={layer.output_shapes}",
            flush=True,
        )
    runner.save_har(str(OUT / f"{net_name}.har"))
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    torch.manual_seed(0)
    samples = torch.randn(max(calibration_rows, 4), SEQUENCE, HIDDEN)
    module = load_projection(which)
    with torch.inference_mode():
        expected = module(samples[:4]).numpy()
    calib = samples[:calibration_rows].numpy()[:, None, :, :].astype(np.float32)
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    dataset = samples[:4].numpy()[:, None, :, :].astype(np.float32)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = np.array(runner.infer(ctx, dataset))
    while quantized.ndim > expected.ndim:
        quantized = quantized.squeeze(1)
    left = expected.astype(np.float64).ravel()
    right = quantized.astype(np.float64).ravel()
    cosine = float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right)))
    print(
        f"quantized cosine {cosine:.6f} mse {float(np.mean((left - right) ** 2)):.6e} "
        f"max {float(np.max(np.abs(left - right))):.6e}",
        flush=True,
    )
    hef = runner.compile()
    hef_path = OUT / f"{net_name}.hef"
    hef_path.write_bytes(hef)
    print(f"HEF {hef_path} bytes={len(hef)}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "export"
    which = sys.argv[2] if len(sys.argv) > 2 else "k"
    calibration_rows = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    if which not in PROJECTIONS:
        raise SystemExit(f"unknown projection {which}")
    try:
        if command == "export":
            export_projection(which)
        elif command == "compile":
            compile_projection(which, calibration_rows)
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

"""Compile a leading tile of the real Clef-Flash layer-3 SwiGLU.

The full projection is hidden 4096 and intermediate 12288. Hailo-10H single-context
placement failed for that graph. This tile keeps the top-left block of those
exact weight matrices: hidden 1024, intermediate 3072. It is real Clef data,
not a numerically equivalent subgraph of the full MLP.
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
HIDDEN = 1024
INTERMEDIATE = 3072
SEQUENCE = 8
PREFIX = "model.language_model.layers.3.mlp."


class SwiGLU(torch.nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.gate = torch.nn.Linear(HIDDEN, INTERMEDIATE, bias=False)
        self.up = torch.nn.Linear(HIDDEN, INTERMEDIATE, bias=False)
        self.down = torch.nn.Linear(INTERMEDIATE, HIDDEN, bias=False)

    def forward(self, hidden: torch.Tensor) -> torch.Tensor:
        return self.down(torch.nn.functional.silu(self.gate(hidden)) * self.up(hidden))


def load_tile() -> SwiGLU:
    raw = load_file(WEIGHTS)
    module = SwiGLU().eval()
    with torch.no_grad():
        module.gate.weight.copy_(raw[PREFIX + "gate_proj.weight"][:INTERMEDIATE, :HIDDEN].float())
        module.up.weight.copy_(raw[PREFIX + "up_proj.weight"][:INTERMEDIATE, :HIDDEN].float())
        module.down.weight.copy_(raw[PREFIX + "down_proj.weight"][:HIDDEN, :INTERMEDIATE].float())
    return module


def export_tile() -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    module = load_tile()
    sample = torch.zeros(1, SEQUENCE, HIDDEN)
    path = OUT / "clef_layer3_swiglu_h1024.onnx"
    torch.onnx.export(module, (sample,), path, dynamo=True, opset_version=18, external_data=False)
    print(path, flush=True)
    return path


def compile_tile() -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    onnx_path = OUT / "clef_layer3_swiglu_h1024.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(onnx_path), "clef_experimental_mlp_h1024_tile")
    runner.save_har(str(OUT / "clef_experimental_mlp_h1024_tile.har"))
    module = load_tile()
    torch.manual_seed(0)
    samples = torch.randn(4, SEQUENCE, HIDDEN)
    with torch.inference_mode():
        reference = module(samples).numpy()
    calib = np.random.default_rng(0).standard_normal((8, 1, SEQUENCE, HIDDEN), dtype=np.float32)
    runner.optimize(calib)
    dataset = samples.numpy()[:, None, :, :].astype(np.float32)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = np.array(runner.infer(ctx, dataset))
    while quantized.ndim > reference.ndim:
        quantized = quantized.squeeze(1)
    left = reference.astype(np.float64).ravel()
    right = quantized.astype(np.float64).ravel()
    cosine = float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right)))
    print(
        f"quantized cosine {cosine:.6f} mse {float(np.mean((left - right) ** 2)):.6e} "
        f"max {float(np.max(np.abs(left - right))):.6e}",
        flush=True,
    )
    hef = runner.compile()
    hef_path = OUT / "clef_experimental_mlp_h1024_tile.hef"
    hef_path.write_bytes(hef)
    print(f"HEF {hef_path} bytes={len(hef)}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "export"
    try:
        export_tile() if command == "export" else compile_tile()
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

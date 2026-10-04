"""Compile one real Clef joint-head projection, hidden 4096 to width 1024.

question_projection is bias-free. The same shape already compiles as the
decoder k_proj. This run uses the published head weights.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np
import torch
from safetensors.torch import load_file

ROOT = Path(__file__).resolve().parents[1]
WEIGHTS = ROOT / "artifacts" / "weights" / "joint_head.safetensors"
OUT = ROOT / "artifacts" / "clef_slice"
HIDDEN = 4096
WIDTH = 1024
SEQUENCE = 8
KEY = "question_projection.weight"


class Projection(torch.nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.proj = torch.nn.Linear(HIDDEN, WIDTH, bias=False)

    def forward(self, hidden: torch.Tensor) -> torch.Tensor:
        return self.proj(hidden)


def load_projection() -> Projection:
    raw = load_file(WEIGHTS)
    module = Projection().eval()
    with torch.no_grad():
        module.proj.weight.copy_(raw[KEY].float())
    return module


def export_projection() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    module = load_projection()
    path = OUT / "clef_head_question_projection.onnx"
    torch.onnx.export(
        module,
        (torch.zeros(1, SEQUENCE, HIDDEN),),
        path,
        dynamo=True,
        opset_version=18,
        external_data=False,
    )
    print(path, flush=True)


def compile_projection(calibration_rows: int) -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(
        str(OUT / "clef_head_question_projection.onnx"),
        "clef_head_test_question_proj",
        disable_onnx_simplifier=True,
    )
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    torch.manual_seed(0)
    samples = torch.randn(max(calibration_rows, 4), SEQUENCE, HIDDEN)
    module = load_projection()
    with torch.inference_mode():
        expected = module(samples[:4]).numpy()
    calib = samples[:calibration_rows].numpy()[:, None, :, :].astype(np.float32)
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = np.array(runner.infer(ctx, calib[:4]))
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
    path = OUT / "clef_head_test_question_proj.hef"
    path.write_bytes(hef)
    print(f"HEF {path} bytes={len(hef)}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "export"
    rows = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
    try:
        if command == "export":
            export_projection()
        elif command == "compile":
            compile_projection(rows)
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

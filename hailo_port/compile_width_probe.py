"""Compile a tiny SwiGLU at increasing widths to find the Hailo-10H allocator boundary.

The real Clef MLP is hidden 4096 and intermediate 12288. This probe uses the same
formula with smaller static shapes so a finished HEF, or a compiler error, is
measured instead of inferred from the full-width run.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts" / "width_probe"


class SwiGLU(torch.nn.Module):
    def __init__(self, hidden: int, intermediate: int):
        super().__init__()
        self.gate = torch.nn.Linear(hidden, intermediate, bias=False)
        self.up = torch.nn.Linear(hidden, intermediate, bias=False)
        self.down = torch.nn.Linear(intermediate, hidden, bias=False)

    def forward(self, hidden: torch.Tensor) -> torch.Tensor:
        return self.down(torch.nn.functional.silu(self.gate(hidden)) * self.up(hidden))


def export_width(hidden: int, sequence: int = 8) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(hidden)
    module = SwiGLU(hidden, hidden * 3).eval()
    sample = torch.randn(1, sequence, hidden)
    path = OUT / f"swiglu_h{hidden}_s{sequence}.onnx"
    torch.onnx.export(module, (sample,), path, dynamo=True, opset_version=18, external_data=False)
    return path


def compile_width(hidden: int, sequence: int = 8) -> str:
    from hailo_sdk_client import ClientRunner

    onnx_path = OUT / f"swiglu_h{hidden}_s{sequence}.onnx"
    if not onnx_path.exists():
        export_width(hidden, sequence)
    name = f"clef_width_h{hidden}"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(onnx_path), name)
    har = OUT / f"{name}.har"
    runner.save_har(str(har))
    calib = np.random.default_rng(hidden).standard_normal((8, 1, sequence, hidden), dtype=np.float32)
    runner.optimize(calib)
    hef = runner.compile()
    hef_path = OUT / f"{name}.hef"
    hef_path.write_bytes(hef)
    return f"HEF {hef_path} bytes={len(hef)} har={har.stat().st_size}"


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "compile"
    hidden = int(sys.argv[2]) if len(sys.argv) > 2 else 64
    try:
        if command == "export":
            print(export_width(hidden), flush=True)
        else:
            print(compile_width(hidden), flush=True)
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

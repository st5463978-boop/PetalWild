"""Compile the real Clef layer-0 depthwise causal conv.

The scatter-free linear block exports this conv with the kernel as a dynamic
input, and Hailo then crashes in ``get_dynamic_kernel_shape``. Here the kernel
is a Conv1d parameter, shape (8192, 1, 4). The fetched shard has no conv bias,
so this graph is the published kernel with bias left at zero.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from safetensors.torch import load_file

ROOT = Path(__file__).resolve().parents[1]
WEIGHTS = ROOT / "artifacts" / "weights" / "clef_layer_0.safetensors"
OUT = ROOT / "artifacts" / "clef_slice"
CHANNELS = 8192
KERNEL = 4
SEQUENCE = 8
KEY = "model.language_model.layers.0.linear_attn.conv1d.weight"


class CausalDepthwise(torch.nn.Module):
    def __init__(self) -> None:
        super().__init__()
        # NCHW: channels stay the feature axis, time is width. A channels-last
        # Conv1d made Hailo swap those and report groups 0.
        self.conv = torch.nn.Conv2d(CHANNELS, CHANNELS, (1, KERNEL), groups=CHANNELS, bias=False)

    def forward(self, hidden: torch.Tensor) -> torch.Tensor:
        # hidden is [batch, channels, 1, time].
        hidden = F.pad(hidden, (KERNEL - 1, 0, 0, 0))
        return self.conv(hidden)


def load_conv() -> CausalDepthwise:
    raw = load_file(WEIGHTS)
    module = CausalDepthwise().eval()
    with torch.no_grad():
        module.conv.weight.copy_(raw[KEY].float().unsqueeze(2))
    return module


def export_conv() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "clef_layer0_depthwise_conv.onnx"
    torch.onnx.export(
        load_conv(),
        (torch.zeros(1, CHANNELS, 1, SEQUENCE),),
        path,
        dynamo=True,
        opset_version=18,
        external_data=False,
    )
    print(path, flush=True)


def compile_conv(calibration_rows: int) -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(
        str(OUT / "clef_layer0_depthwise_conv.onnx"),
        "clef_experimental_depthwise_conv",
        disable_onnx_simplifier=True,
    )
    for layer in runner._hn:
        print(f"LAYER {layer.op} {layer.name} in={layer.input_shapes} out={layer.output_shapes}", flush=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    torch.manual_seed(0)
    samples = torch.randn(max(calibration_rows, 4), CHANNELS, 1, SEQUENCE)
    module = load_conv()
    with torch.inference_mode():
        expected = module(samples[:4]).numpy()
    # Hailo stores this input as NHWC [-1, 1, 8, 8192], not NCHW.
    nchw = samples[:calibration_rows].numpy().astype(np.float32)
    calib = np.transpose(nchw, (0, 2, 3, 1))
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = np.array(runner.infer(ctx, calib[:4]))
    print(f"quantized shape {quantized.shape}", flush=True)
    quantized = np.transpose(quantized, (0, 3, 1, 2))
    left = expected.astype(np.float64).ravel()
    right = quantized.astype(np.float64).ravel()
    cosine = float(left @ right / (np.linalg.norm(left) * np.linalg.norm(right)))
    print(
        f"quantized cosine {cosine:.6f} mse {float(np.mean((left - right) ** 2)):.6e} "
        f"max {float(np.max(np.abs(left - right))):.6e}",
        flush=True,
    )
    hef = runner.compile()
    path = OUT / "clef_experimental_depthwise_conv.hef"
    path.write_bytes(hef)
    print(f"HEF {path} bytes={len(hef)}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "export"
    rows = int(sys.argv[2]) if len(sys.argv) > 2 else 256
    try:
        if command == "export":
            export_conv()
        elif command == "compile":
            compile_conv(rows)
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

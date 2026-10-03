"""Compile the parsed no-RoPE full-attention block.

This is one decoder block with rotary application removed. The HAR is the
parse result. RoPE still crashes the fuser in the unmodified block.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
HAR = ROOT / "artifacts" / "clef_experimental_full_attention_no_rope.har"


def compile_block(calibration_rows: int) -> None:
    from hailo_sdk_client import ClientRunner

    runner = ClientRunner(har=str(HAR))
    print("STATE", runner.state, flush=True)
    for layer in runner._hn.get_input_layers():
        print(f"INPUT {layer.name} {layer.output_shapes}", flush=True)
    if "quant" not in str(runner.state):
        runner.load_model_script(
            "model_optimization_config(calibration, batch_size=8, "
            f"calibset_size={calibration_rows})\n"
        )
        inputs = list(runner._hn.get_input_layers())
        if len(inputs) == 1:
            shape = [calibration_rows, *inputs[0].output_shapes[0][1:]]
            calib = np.random.default_rng(0).standard_normal(shape).astype(np.float32)
            print("CALIB", calib.shape, flush=True)
        else:
            rng = np.random.default_rng(0)
            calib = {}
            for layer in inputs:
                shape = [calibration_rows, *layer.output_shapes[0][1:]]
                calib[layer.name] = rng.standard_normal(shape).astype(np.float32)
                print("CALIB", layer.name, calib[layer.name].shape, flush=True)
        runner.optimize(calib)
        print("OPTIMIZED", runner.state, flush=True)
    hef = runner.compile()
    path = ROOT / "artifacts" / "clef_experimental_full_attention_no_rope.hef"
    path.write_bytes(hef)
    print(f"HEF {path} bytes={len(hef)}", flush=True)


def main() -> None:
    rows = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    try:
        compile_block(rows)
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

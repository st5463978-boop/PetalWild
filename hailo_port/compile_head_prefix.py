"""Quantize and compile the parsed joint-head prefix.

The HAR is the subgraph Hailo accepted: hidden norm, span mean-pools, two
projections, and the start of lexical L2. It is not the decision logits.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
HAR = ROOT / "artifacts" / "clef_slice" / "clef_head_host_type.har"
OUT = ROOT / "artifacts" / "clef_slice"


def compile_prefix(calibration_rows: int) -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    runner = ClientRunner(har=str(HAR))
    inputs = list(runner._hn.get_input_layers())
    for layer in inputs:
        print(f"INPUT {layer.name} shape={layer.output_shapes}", flush=True)
    rng = np.random.default_rng(0)
    calib = {}
    for layer in inputs:
        shape = [calibration_rows, *layer.output_shapes[0][1:]]
        calib[layer.name] = rng.standard_normal(shape).astype(np.float32)
        print(f"CALIB {layer.name} {calib[layer.name].shape}", flush=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    sample = {name: value[:4] for name, value in calib.items()}
    with runner.infer_context(InferenceContext.SDK_FP_OPTIMIZED) as native_ctx:
        native = runner.infer(native_ctx, sample)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as quant_ctx:
        quantized = runner.infer(quant_ctx, sample)
    natives = native if isinstance(native, (list, tuple)) else [native]
    quants = quantized if isinstance(quantized, (list, tuple)) else [quantized]
    for index, (left, right) in enumerate(zip(natives, quants)):
        left_v = np.asarray(left, dtype=np.float64).ravel()
        right_v = np.asarray(right, dtype=np.float64).ravel()
        denom = np.linalg.norm(left_v) * np.linalg.norm(right_v)
        cosine = float(left_v @ right_v / denom) if denom else 0.0
        print(
            f"output {index} cosine {cosine:.6f} "
            f"max {float(np.max(np.abs(left_v - right_v))):.6e}",
            flush=True,
        )
    hef = runner.compile()
    path = OUT / "clef_head_test_prefix.hef"
    path.write_bytes(hef)
    print(f"HEF {path} bytes={len(hef)}", flush=True)


def main() -> None:
    rows = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    try:
        compile_prefix(rows)
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

"""Parse the static Clef joint-schema head.

The published export feeds `type_ids` as a rank-1 int64 tensor. Hailo DFC 5.4.0
has no default format for rank 1, so `get_input_layer_shapes` raises
`TypeError: object of type 'NoneType' has no len()`. This script names that
input as a single channel axis and records whatever the parser does next.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ONNX = ROOT / "artifacts" / "onnx" / "clef_decision_head.onnx"


def parse_head() -> None:
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import Dims

    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(
        str(ONNX),
        "clef_head_test",
        net_input_format={
            "sequence_hidden": [Dims.BATCH, Dims.WIDTH, Dims.CHANNELS],
            "lexical": [Dims.WIDTH, Dims.CHANNELS],
            "type_ids": [Dims.CHANNELS],
        },
        disable_onnx_simplifier=True,
    )
    for layer in runner._hn:
        print(
            f"LAYER {layer.op} {layer.name} in={getattr(layer, 'input_shapes', None)} out={layer.output_shapes}",
            flush=True,
        )
    out = ROOT / "artifacts" / "clef_slice" / "clef_head_test.har"
    out.parent.mkdir(parents=True, exist_ok=True)
    runner.save_har(str(out))
    print(f"HAR {out}", flush=True)


def main() -> None:
    try:
        parse_head()
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

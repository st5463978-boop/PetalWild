"""Parse the scatter-free Clef linear-attention block.

DFC 5.4.0 raises StopIteration in
`_is_spatial_flatten_with_features_to_heads_reshape` when a reshape has no
predecessor node. This treats that reshape as not the heads pattern and
records the next parser result.
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ONNX = ROOT / "artifacts" / "onnx" / "qwen35_linear_block_scatter_free.onnx"


def _guard_head_reshape() -> None:
    from hailo_sdk_client.model_translator.onnx_translator import onnx_graph

    original = onnx_graph.ONNXGraphNode.update_output_format

    def guarded(self):
        try:
            return original(self)
        except (StopIteration, IndexError) as exc:
            print(f"format failed {self.op} {self.name}: {type(exc).__name__}", flush=True)
            return None

    onnx_graph.ONNXGraphNode.update_output_format = guarded


def parse_block() -> None:
    from hailo_sdk_client import ClientRunner

    _guard_head_reshape()
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(ONNX), "clef_experimental_linear_block", disable_onnx_simplifier=True)
    ops = {}
    for layer in runner._hn:
        ops[str(layer.op)] = ops.get(str(layer.op), 0) + 1
    print("LAYERS", ops, flush=True)
    out = ROOT / "artifacts" / "clef_slice" / "clef_experimental_linear_block.har"
    runner.save_har(str(out))
    print(f"HAR {out}", flush=True)


def main() -> None:
    try:
        parse_block()
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

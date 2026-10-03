"""Parse the static Clef joint-schema head.

The published export feeds `type_ids` as a rank-1 int64 tensor. Hailo DFC 5.4.0
has no default format for rank 1, so `get_input_layer_shapes` raises
`TypeError: object of type 'NoneType' has no len()`. Naming that input as one
channel gets past the crash and fails later in `is_null_transpose_near_torch_tile`.

`export` moves the type-embedding lookup to the host. The graph then takes a
rank-2 float tensor, which is the embedding rows for the fixed question types.
"""

from __future__ import annotations

import json
import sys
import traceback
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "hailo_port"))
sys.path.insert(0, str(ROOT / "hailo_port" / "upstream"))
ONNX = ROOT / "artifacts" / "onnx" / "clef_decision_head.onnx"
HOST_ONNX = ROOT / "artifacts" / "clef_slice" / "clef_head_host_type.onnx"
FOLDED_ONNX = ROOT / "artifacts" / "clef_slice" / "clef_head_host_type_folded.onnx"
WEIGHTS = ROOT / "artifacts" / "weights" / "joint_head.safetensors"
CONFIG = ROOT / "artifacts" / "weights" / "joint_head_config.json"


class HostType(torch.nn.Module):
    def forward(self, vectors: torch.Tensor) -> torch.Tensor:
        return vectors


def export_host_type() -> None:
    from graphs import StaticJointHead
    from joint_schema_model import JointSchemaHead
    from safetensors.torch import load_file

    config = json.loads(CONFIG.read_text())
    reference = JointSchemaHead(**config).eval().float()
    reference.load_state_dict(load_file(WEIGHTS), strict=True)
    replaced = JointSchemaHead(**config).eval().float()
    replaced.load_state_dict(load_file(WEIGHTS), strict=True)
    replaced.type_embedding = HostType()
    official = StaticJointHead(reference, (3, 2)).eval()
    hosted = StaticJointHead(replaced, (3, 2)).eval()
    torch.manual_seed(0)
    hidden = torch.randn(1, 16, 4096)
    lexical = torch.randn(5, 4096)
    type_ids = torch.tensor([1, 0], dtype=torch.long)
    with torch.inference_mode():
        vectors = reference.type_embedding(type_ids)
        left = official(hidden, lexical, type_ids)
        right = hosted(hidden, lexical, vectors)
    delta = float((left - right).abs().max())
    print(f"host type max abs {delta:.6e}", flush=True)
    HOST_ONNX.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        hosted,
        (hidden, lexical, vectors),
        HOST_ONNX,
        dynamo=True,
        opset_version=18,
        external_data=True,
    )
    print(HOST_ONNX, flush=True)


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


def _guard_empty_transpose_shapes() -> None:
    """DFC 5.4.0 assumes every transpose already has a shape and a predecessor.

    `is_null_transpose` raises IndexError or StopIteration on `node_Transpose_130`
    in the joint head. That transpose is not one of the special patterns, so the
    classifier can return false.
    """

    from hailo_sdk_client.model_translator.onnx_translator import onnx_graph

    original = onnx_graph.ONNXGraphNode.is_null_transpose

    def guarded(self):
        try:
            return original(self)
        except (IndexError, StopIteration) as exc:
            print(f"null-transpose check failed {self.name}: {type(exc).__name__}", flush=True)
            return False

    onnx_graph.ONNXGraphNode.is_null_transpose = guarded

    from hailo_sdk_client.model_translator.onnx_translator.onnx_translator import ONNXConverter

    create_layer = ONNXConverter._layer_callback_from_vertex

    def named(self, vertex):
        try:
            return create_layer(self, vertex)
        except Exception:
            print(
                f"layer failed {vertex.op} {vertex.name} "
                f"in_format={vertex.input_format} out_format={vertex.output_format}",
                flush=True,
            )
            raise

    ONNXConverter._layer_callback_from_vertex = named

    from hailo_sdk_common.hailo_nn.hn_layers.layer import Layer

    original_replace = Layer.replace_input_shape

    def replace_input_shape(self, old_name, new_input_shape):
        if old_name in self._input_layers:
            idx = self._input_layers.index(old_name)
            if idx >= len(self._input_shapes):
                print(
                    f"pad input shapes on {self.name} for {old_name} "
                    f"({len(self._input_shapes)} shapes, index {idx})",
                    flush=True,
                )
                while len(self._input_shapes) <= idx:
                    self._input_shapes.append(new_input_shape)
                return
        return original_replace(self, old_name, new_input_shape)

    Layer.replace_input_shape = replace_input_shape


def fold_constant_transpose() -> None:
    """Remove the one transpose whose input is a weight initializer.

    DFC classifies that transpose as if it had a predecessor node and raises
    StopIteration or IndexError. The permutation is [1, 0], so the weight can
    be stored already transposed.
    """

    import numpy as np
    import onnx
    from onnx import numpy_helper

    model = onnx.load(HOST_ONNX)
    initializers = {item.name: item for item in model.graph.initializer}
    transpose = next(node for node in model.graph.node if node.name == "node_Transpose_130")
    source = numpy_helper.to_array(initializers[transpose.input[0]])
    folded = numpy_helper.from_array(np.transpose(source, (1, 0)), name="option_question_projection_T")
    model.graph.initializer.append(folded)
    for node in model.graph.node:
        for index, value in enumerate(node.input):
            if value == transpose.output[0]:
                node.input[index] = folded.name
    model.graph.node.remove(transpose)
    # Expand-to-[N, 1024] is the repeated question vector inside the feature
    # concat. Hailo treats Expand-into-Concat as a rank-4 class-token pattern
    # and indexes a missing spatial axis. Tile with a single non-unit repeat
    # is the same values.
    for expand_name, repeats in (("node_expand_2", (3, 1)), ("node_expand_5", (2, 1))):
        node = next(item for item in model.graph.node if item.name == expand_name)
        repeats_name = f"{expand_name}_repeats"
        model.graph.initializer.append(
            numpy_helper.from_array(np.asarray(repeats, dtype=np.int64), name=repeats_name)
        )
        tile = onnx.helper.make_node(
            "Tile",
            inputs=[node.input[0], repeats_name],
            outputs=list(node.output),
            name=f"{expand_name}_tile",
        )
        index = list(model.graph.node).index(node)
        model.graph.node.remove(node)
        model.graph.node.insert(index, tile)
    # node_layer_norm_9 normalizes a [2, 1024] stack and arrives with an empty
    # format. Flatten sets [batch, channels] even when its input has no format,
    # which is the only rank-2 path that does not call _convert_axes_to_nhwc.
    # Each summary is normalized on its own, then stacked. That matches a
    # last-axis norm of the stacked pair.
    layernorm = next(item for item in model.graph.node if item.name == "node_layer_norm_9")
    scale, bias = layernorm.input[1], layernorm.input[2]
    produced = layernorm.output[0]
    normalized = []
    replacement = []
    for index, source in enumerate(("sum_1", "sum_2")):
        flat = f"summary_{index}_flat"
        normed = f"summary_{index}_norm"
        replacement.append(
            onnx.helper.make_node("Flatten", [source], [flat], name=f"node_summary_{index}_flat", axis=0)
        )
        replacement.append(
            onnx.helper.make_node(
                "LayerNormalization",
                [flat, scale, bias],
                [normed],
                name=f"node_summary_{index}_norm",
                axis=-1,
                epsilon=1e-5,
            )
        )
        normalized.append(normed)
    replacement.append(onnx.helper.make_node("Concat", normalized, [produced], name="node_summary_norm_cat", axis=0))
    for name in ("node_layer_norm_9", "node_stack_2", "node_Unsqueeze_355", "node_Unsqueeze_357"):
        node = next(item for item in model.graph.node if item.name == name)
        model.graph.node.remove(node)
    insert_at = list(model.graph.node).index(next(item for item in model.graph.node if item.name == "node_add_8"))
    for offset, extra in enumerate(replacement):
        model.graph.node.insert(insert_at + offset, extra)
    onnx.save(model, FOLDED_ONNX)
    print(FOLDED_ONNX, flush=True)


def parse_host_type() -> None:
    from hailo_sdk_client import ClientRunner

    _guard_empty_transpose_shapes()
    runner = ClientRunner(hw_arch="hailo10h")
    # The full graph names these nodes as the supported prefix. They stop
    # before the batch-axis concat, gather, and softmax errors.
    runner.translate_onnx_model(
        str(FOLDED_ONNX),
        "clef_head_test",
        start_node_names=["sequence_hidden", "lexical"],
        end_node_names=["node_stack", "node_unsqueeze_6", "node_select_1", "node_div_3", "node_linear_19"],
        disable_onnx_simplifier=True,
    )
    for layer in runner._hn:
        print(
            f"LAYER {layer.op} {layer.name} in={getattr(layer, 'input_shapes', None)} out={layer.output_shapes}",
            flush=True,
        )
    out = ROOT / "artifacts" / "clef_slice" / "clef_head_host_type.har"
    runner.save_har(str(out))
    print(f"HAR {out}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "parse"
    try:
        if command == "export":
            export_host_type()
        elif command == "parse":
            parse_head()
        elif command == "fold":
            fold_constant_transpose()
        elif command == "parse-host":
            parse_host_type()
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

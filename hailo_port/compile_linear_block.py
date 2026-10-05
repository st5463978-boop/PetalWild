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
ONNX = ROOT / "artifacts" / "onnx" / "qwen35_linear_block_static_conv.onnx"
SOURCE = ROOT / "artifacts" / "onnx" / "qwen35_linear_block_scatter_free.onnx"
SCAN = ROOT / "artifacts" / "onnx" / "qwen35_linear_scan_static_conv.onnx"


def _guard_head_reshape() -> None:
    from hailo_sdk_client.model_translator.onnx_translator import onnx_graph

    original = onnx_graph.ONNXGraphNode.update_output_format

    def guarded(self):
        try:
            return original(self)
        except (StopIteration, IndexError) as exc:
            print(f"format failed {self.op} {self.name}: {type(exc).__name__}: {exc}", flush=True)
            traceback.print_exc()
            return None

    onnx_graph.ONNXGraphNode.update_output_format = guarded


def fold_static_conv() -> None:
    """Point the depthwise conv at its weight initializer.

    Squeeze then Unsqueeze hides ``conv1d.weight`` from Hailo, so the kernel
    stays a rank-3 activation and ``get_dynamic_kernel_shape`` indexes axis 3.
    """
    import onnx

    model = onnx.load(SOURCE, load_external_data=False)
    conv = next(node for node in model.graph.node if node.name == "node_Conv_166")
    conv.input[1] = "layer.linear_attn.conv1d.weight"
    drop = {"node_squeeze", "node_unsqueeze"}
    kept = [node for node in model.graph.node if node.name not in drop]
    del model.graph.node[:]
    model.graph.node.extend(kept)
    onnx.save(model, ONNX)
    print(ONNX, ONNX.stat().st_size, flush=True)


def extract_scan() -> None:
    """Keep the depthwise conv and the Gated DeltaNet scan.

    The 4096-to-8192 QKV projection stays outside. Its output is the ``transpose``
    input. Beta and decay still see the layer-norm activation ``mul_1``.
    """
    import onnx
    from onnx import TensorProto, helper

    model = onnx.load(ONNX, load_external_data=False)
    by_out = {output: node for node in model.graph.node for output in node.output}
    initializers = {item.name: item for item in model.graph.initializer}
    shapes = {}
    for value in list(model.graph.value_info) + list(model.graph.input):
        shapes[value.name] = [
            dim.dim_value if dim.dim_value else dim.dim_param
            for dim in value.type.tensor_type.shape.dim
        ]
    blocked = {"transpose", "mul_1"}
    seen: set[str] = set()
    kept_names: set[str] = set()
    pending = ["stack"]
    while pending:
        name = pending.pop()
        if name in seen or name in blocked:
            continue
        seen.add(name)
        node = by_out.get(name)
        if node is None:
            continue
        kept_names.add(node.name)
        for item in node.input:
            if item not in initializers:
                pending.append(item)
    ordered = [node for node in model.graph.node if node.name in kept_names]
    # ConstantOfShape startswith "Constant", so Hailo calls parse_raw_data and
    # indexes an attribute this node does not have. The tensor is the zero state.
    state_nodes = [node for node in ordered if node.op_type == "ConstantOfShape"]
    ordered = [node for node in ordered if node.op_type != "ConstantOfShape"]
    used_inits: set[str] = set()
    for node in ordered:
        for item in node.input:
            if item in initializers:
                used_inits.add(item)
    graph = helper.make_graph(
        ordered,
        "clef_experimental_linear_scan",
        [
            helper.make_tensor_value_info("mul_1", TensorProto.FLOAT, shapes["mul_1"]),
            helper.make_tensor_value_info("transpose", TensorProto.FLOAT, shapes["transpose"]),
        ],
        [helper.make_tensor_value_info("stack", TensorProto.FLOAT, shapes["stack"])],
    )
    for name in sorted(used_inits):
        graph.initializer.append(initializers[name])
    import numpy as np
    from onnx import numpy_helper

    for node in state_nodes:
        shape = [int(dim) for dim in shapes[node.output[0]]]
        graph.initializer.append(numpy_helper.from_array(np.zeros(shape, np.float32), name=node.output[0]))
    extracted = helper.make_model(graph, opset_imports=model.opset_import)
    extracted.ir_version = model.ir_version
    onnx.save(extracted, SCAN)
    print(SCAN, SCAN.stat().st_size, "nodes", len(ordered), flush=True)


# Hailo named these as the last nodes it could parse. They are the per-step
# beta and decay broadcasts, before Expand, repeat_interleave, and ReduceSum.
SCAN_END_NODES = [
    "node_unsqueeze_37",
    "node_unsqueeze_23",
    "node_unsqueeze_38",
    "node_unsqueeze_2",
    "node_unsqueeze_10",
    "node_unsqueeze_16",
    "node_unsqueeze_44",
    "node_unsqueeze_51",
    "node_unsqueeze_24",
    "node_unsqueeze_9",
    "node_unsqueeze_17",
    "node_unsqueeze_52",
    "node_select_27",
    "node_unsqueeze_45",
    "node_unsqueeze_3",
    "node_unsqueeze_31",
    "node_unsqueeze_30",
]


def parse_block(end_node_names: list[str] | None = None, input_format: dict | None = None) -> None:
    from hailo_sdk_client import ClientRunner

    _guard_head_reshape()
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(
        str(SCAN),
        "clef_experimental_linear_scan",
        end_node_names=end_node_names,
        net_input_format=input_format,
        disable_onnx_simplifier=True,
    )
    ops = {}
    for layer in runner._hn:
        ops[str(layer.op)] = ops.get(str(layer.op), 0) + 1
        print(f"LAYER {layer.op} {layer.name} in={layer.input_shapes} out={layer.output_shapes}", flush=True)
    print("LAYERS", ops, flush=True)
    out = ROOT / "artifacts" / "clef_slice" / "clef_experimental_linear_scan.har"
    runner.save_har(str(out))
    print(f"HAR {out}", flush=True)


def compile_prefix(calibration_rows: int) -> None:
    import numpy as np
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    har = ROOT / "artifacts" / "clef_slice" / "clef_experimental_linear_scan.har"
    runner = ClientRunner(har=str(har))
    calib = {}
    rng = np.random.default_rng(0)
    for layer in runner._hn.get_input_layers():
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
            f"output {index} cosine {cosine:.6f} max {float(np.max(np.abs(left_v - right_v))):.6e}",
            flush=True,
        )
    hef = runner.compile()
    path = ROOT / "artifacts" / "clef_slice" / "clef_experimental_linear_scan.hef"
    path.write_bytes(hef)
    print(f"HEF {path} bytes={len(hef)}", flush=True)


def export_qkv(kind: str) -> Path:
    """Q, K, and V as three outputs, with no later reshape for Hailo to fuse."""
    import numpy as np
    import onnx
    from onnx import TensorProto, helper, numpy_helper

    path = ROOT / "artifacts" / "onnx" / f"qwen35_qkv_{kind}.onnx"
    path.parent.mkdir(parents=True, exist_ok=True)
    mixed = helper.make_tensor_value_info("mixed", TensorProto.FLOAT, [1, 8, 8192])
    outputs = [
        helper.make_tensor_value_info(name, TensorProto.FLOAT, [1, 8, channels])
        for name, channels in (("query", 2048), ("key", 2048), ("value", 4096))
    ]
    initializers = []
    if kind == "split":
        initializers.append(numpy_helper.from_array(np.array([2048, 2048, 4096], np.int64), "sizes"))
        nodes = [helper.make_node("Split", ["mixed", "sizes"], ["query", "key", "value"], axis=2)]
    elif kind == "slice":
        nodes = []
        for name, start, end in (("query", 0, 2048), ("key", 2048, 4096), ("value", 4096, 8192)):
            start_name, end_name, axis_name = f"{name}_start", f"{name}_end", f"{name}_axis"
            initializers.append(numpy_helper.from_array(np.array([start], np.int64), start_name))
            initializers.append(numpy_helper.from_array(np.array([end], np.int64), end_name))
            initializers.append(numpy_helper.from_array(np.array([2], np.int64), axis_name))
            nodes.append(helper.make_node("Slice", ["mixed", start_name, end_name, axis_name], [name]))
    else:
        raise SystemExit(f"unknown qkv kind {kind}")
    graph = helper.make_graph(nodes, f"clef_experimental_qkv_{kind}", [mixed], outputs, initializers)
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 18)])
    onnx.checker.check_model(model)
    onnx.save(model, path)
    print(path, path.stat().st_size, flush=True)
    return path


def compile_qkv(kind: str, calibration_rows: int) -> None:
    import numpy as np
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    path = export_qkv(kind)
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(path), f"clef_experimental_qkv_{kind}", disable_onnx_simplifier=True)
    for layer in runner._hn:
        print(f"LAYER {layer.op} {layer.name} in={layer.input_shapes} out={layer.output_shapes}", flush=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    rng = np.random.default_rng(0)
    hailo_input = next(iter(runner._hn.get_input_layers()))
    shape = [calibration_rows, *hailo_input.output_shapes[0][1:]]
    calib = rng.standard_normal(shape).astype(np.float32)
    print(f"CALIB {hailo_input.name} {calib.shape}", flush=True)
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    sample = calib[:4]
    reference = np.split(sample.reshape(4, 8, 8192), [2048, 4096], axis=-1)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = runner.infer(ctx, sample)
    outputs = quantized if isinstance(quantized, (list, tuple)) else [quantized]
    for index, (got, expect) in enumerate(zip(outputs, reference)):
        print(f"output {index} shape {np.asarray(got).shape}", flush=True)
        got_v = np.asarray(got, dtype=np.float64)
        got_v = np.squeeze(got_v)
        got_v = got_v.reshape(expect.shape)
        cosine = float(got_v.ravel() @ expect.ravel() / (np.linalg.norm(got_v) * np.linalg.norm(expect)))
        print(
            f"output {index} cosine {cosine:.6f} max {float(np.max(np.abs(got_v - expect))):.6e}",
            flush=True,
        )
    hef = runner.compile()
    out = ROOT / "artifacts" / "clef_slice" / f"clef_experimental_qkv_{kind}.hef"
    out.write_bytes(hef)
    print(f"HEF {out} bytes={len(hef)}", flush=True)


def _conv_silu_split():
    import torch
    import torch.nn.functional as F
    from compile_depthwise_conv import KERNEL, load_conv

    conv = load_conv()

    class ConvSiluSplit(torch.nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.conv = conv.conv

        def forward(self, hidden: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
            activated = F.silu(self.conv(F.pad(hidden, (KERNEL - 1, 0, 0, 0))))
            mixed = activated.squeeze(2).transpose(1, 2)
            return mixed[:, :, :2048], mixed[:, :, 2048:4096], mixed[:, :, 4096:]

    return ConvSiluSplit


def export_conv_qkv() -> Path:
    """Depthwise conv, SiLU, then Q/K/V as channel slices.

    A single Split becomes a feature splitter, which cannot be a graph output.
    Slices are the split that compiled on their own. Export with system Python;
    the Hailo venv has no onnxscript.
    """
    import torch
    from compile_depthwise_conv import SEQUENCE

    path = ROOT / "artifacts" / "onnx" / "qwen35_conv_qkv_slice.onnx"
    module = _conv_silu_split()().eval()
    torch.onnx.export(
        module,
        (torch.zeros(1, 8192, 1, SEQUENCE),),
        path,
        dynamo=True,
        opset_version=18,
        external_data=False,
    )
    print(path, path.stat().st_size, flush=True)
    return path


def compile_conv_qkv(calibration_rows: int) -> None:
    import numpy as np
    import torch
    from compile_depthwise_conv import SEQUENCE
    from hailo_sdk_client import ClientRunner
    from hailo_sdk_client.exposed_definitions import InferenceContext

    path = ROOT / "artifacts" / "onnx" / "qwen35_conv_qkv_slice.onnx"
    runner = ClientRunner(hw_arch="hailo10h")
    runner.translate_onnx_model(str(path), "clef_experimental_conv_qkv", disable_onnx_simplifier=True)
    for layer in runner._hn:
        print(f"LAYER {layer.op} {layer.name} in={layer.input_shapes} out={layer.output_shapes}", flush=True)
    runner.load_model_script(
        "model_optimization_config(calibration, batch_size=8, "
        f"calibset_size={calibration_rows})\n"
    )
    torch.manual_seed(0)
    samples = torch.randn(max(calibration_rows, 4), 8192, 1, SEQUENCE)
    with torch.inference_mode():
        expected = _conv_silu_split()().eval()(samples[:4])
    nchw = samples[:calibration_rows].numpy().astype(np.float32)
    calib = np.transpose(nchw, (0, 2, 3, 1))
    runner.optimize(calib)
    print("OPTIMIZED", flush=True)
    with runner.infer_context(InferenceContext.SDK_QUANTIZED) as ctx:
        quantized = runner.infer(ctx, calib[:4])
    outputs = quantized if isinstance(quantized, (list, tuple)) else [quantized]
    for index, (got, expect) in enumerate(zip(outputs, expected)):
        got_v = np.squeeze(np.asarray(got, dtype=np.float64))
        expect_v = expect.numpy().astype(np.float64)
        print(f"output {index} shape {got_v.shape} expect {expect_v.shape}", flush=True)
        # Hailo stores the sliced features as width and the time axis as channels.
        if got_v.shape == (expect_v.shape[0], expect_v.shape[2], expect_v.shape[1]):
            got_v = np.transpose(got_v, (0, 2, 1))
        cosine = float(got_v.ravel() @ expect_v.ravel() / (np.linalg.norm(got_v) * np.linalg.norm(expect_v)))
        print(
            f"output {index} cosine {cosine:.6f} max {float(np.max(np.abs(got_v - expect_v))):.6e}",
            flush=True,
        )
    hef = runner.compile()
    out = ROOT / "artifacts" / "clef_slice" / "clef_experimental_conv_qkv.hef"
    out.write_bytes(hef)
    print(f"HEF {out} bytes={len(hef)}", flush=True)


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "parse"
    try:
        if command == "fold":
            fold_static_conv()
        elif command == "extract":
            extract_scan()
        elif command == "parse":
            parse_block()
        elif command == "compile":
            compile_prefix(int(sys.argv[2]) if len(sys.argv) > 2 else 256)
        elif command == "qkv":
            kind = sys.argv[2] if len(sys.argv) > 2 else "split"
            rows = int(sys.argv[3]) if len(sys.argv) > 3 else 256
            compile_qkv(kind, rows)
        elif command == "export-conv":
            export_conv_qkv()
        elif command == "conv-qkv":
            compile_conv_qkv(int(sys.argv[2]) if len(sys.argv) > 2 else 256)
        elif command == "parse-prefix":
            from hailo_sdk_client.exposed_definitions import Dims

            # Rank-3 default is [batch, width, channels], which reads this conv
            # input as 8 channels. The published layout is [batch, channels, time].
            parse_block(
                SCAN_END_NODES,
                {
                    "mul_1": [Dims.BATCH, Dims.WIDTH, Dims.CHANNELS],
                    "transpose": [Dims.BATCH, Dims.CHANNELS, Dims.WIDTH],
                },
            )
        else:
            raise SystemExit(f"unknown command {command}")
    except Exception:
        traceback.print_exc()
        raise SystemExit(1)


if __name__ == "__main__":
    main()

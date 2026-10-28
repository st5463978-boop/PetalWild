"""ONNX contract checks for the static seq-128 student.

Gelu nodes are rewritten to the erf decomposition. Neg-into-Concat is the
rotate_half pattern that crashes DFC 5.4.0's fuser; that pattern is rejected
rather than rewritten, because the sign-swap form has to be exported from
PyTorch.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

HALO_OPS = {"Loop", "If", "NonZero", "Optional", "SequenceAt", "NonMaxSuppression", "ScatterND", "ScatterElements", "Gelu"}


class GraphError(ValueError):
    """The ONNX graph is missing, or it is not safe to quantize."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load(path: Path):
    try:
        import onnx
    except ImportError as exc:
        raise GraphError(f"onnx is not installed, so the graph was not checked: {exc}") from exc
    if not path.is_file():
        raise GraphError(f"ONNX file not found: {path}")
    model = onnx.load(str(path))
    return onnx, model


def neg_into_concat(model) -> list[str]:
    neg_outs = {out for node in model.graph.node if node.op_type == "Neg" for out in node.output}
    hits = []
    for node in model.graph.node:
        if node.op_type == "Concat" and any(value in neg_outs for value in node.input):
            hits.append(node.name or node.output[0])
    return hits


def summarize(path: Path) -> dict:
    onnx, model = _load(path)
    onnx.checker.check_model(model)
    ops = sorted({node.op_type for node in model.graph.node})
    consumed = {value for node in model.graph.node for value in node.input}
    inputs = []
    for value in model.graph.input:
        shape = [dim.dim_value or (dim.dim_param or -1) for dim in value.type.tensor_type.shape.dim]
        inputs.append({"name": value.name, "shape": shape, "elem": value.type.tensor_type.elem_type})
    outputs = []
    for value in model.graph.output:
        shape = [dim.dim_value or (dim.dim_param or -1) for dim in value.type.tensor_type.shape.dim]
        outputs.append({"name": value.name, "shape": shape, "elem": value.type.tensor_type.elem_type})
    mask = next((item for item in inputs if item["name"] == "attention_mask"), None)
    ids = next((item for item in inputs if item["name"] == "input_ids"), None)
    return {
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
        "opset": [op.version for op in model.opset_import],
        "ops": ops,
        "forbidden": sorted(set(ops) & HALO_OPS),
        "neg_into_concat": neg_into_concat(model),
        "inputs": inputs,
        "outputs": outputs,
        "attention_mask_is_input": mask is not None,
        "attention_mask_used": "attention_mask" in consumed,
        "attention_mask_shape": None if mask is None else mask["shape"],
        "input_ids_shape": None if ids is None else ids["shape"],
    }


def assert_contract(summary: dict) -> None:
    if summary["input_ids_shape"] != [1, 128]:
        raise GraphError(f"input_ids shape {summary['input_ids_shape']} != [1, 128]")
    if not summary["attention_mask_is_input"] or not summary["attention_mask_used"]:
        raise GraphError(
            "attention_mask is not an input that the graph consumes. "
            "Refusing to quantize a model that cannot see padding."
        )
    if summary["attention_mask_shape"] != [1, 128]:
        raise GraphError(f"attention_mask shape {summary['attention_mask_shape']} != [1, 128]")
    blocked = list(summary["forbidden"])
    if summary["neg_into_concat"]:
        blocked.append("Neg->Concat rotate_half")
    if blocked:
        raise GraphError(
            "graph is not DFC-safe: "
            + ", ".join(blocked)
            + ". Re-export from model.py (gelu_erf and sign-swap RoPE) and the round-2 checkpoint. "
            "Do not calibrate this graph."
        )


def rewrite_gelu(src: Path, dest: Path) -> dict:
    """Replace Gelu nodes with the erf decomposition. Other nodes stay put."""
    onnx, model = _load(src)
    import numpy as np
    from onnx import helper, numpy_helper

    made = 0
    for node in list(model.graph.node):
        if node.op_type != "Gelu":
            continue
        approx = 0
        for attr in node.attribute:
            if attr.name == "approximate":
                approx = int(attr.i)
        if approx != 0:
            raise GraphError(f"Gelu approximate={approx} is not the erf form; not rewriting {node.name}")
        stem = node.name or f"gelu_{made}"
        scale_name = f"{stem}_inv_sqrt2"
        half_name = f"{stem}_half"
        one_name = f"{stem}_one"
        model.graph.initializer.extend(
            [
                numpy_helper.from_array(np.array(1.0 / np.sqrt(2.0), dtype=np.float32), scale_name),
                numpy_helper.from_array(np.array(0.5, dtype=np.float32), half_name),
                numpy_helper.from_array(np.array(1.0, dtype=np.float32), one_name),
            ]
        )
        scaled = f"{stem}_scaled"
        erfed = f"{stem}_erf"
        plus = f"{stem}_plus"
        half_x = f"{stem}_half_x"
        source = node.input[0]
        out = node.output[0]
        extra = [
            helper.make_node("Mul", [source, scale_name], [scaled], name=f"{stem}_mul_scale"),
            helper.make_node("Erf", [scaled], [erfed], name=f"{stem}_erf"),
            helper.make_node("Add", [erfed, one_name], [plus], name=f"{stem}_add_one"),
            helper.make_node("Mul", [source, half_name], [half_x], name=f"{stem}_mul_half"),
            helper.make_node("Mul", [half_x, plus], [out], name=f"{stem}_mul_out"),
        ]
        index = list(model.graph.node).index(node)
        model.graph.node.remove(node)
        for offset, extra_node in enumerate(extra):
            model.graph.node.insert(index + offset, extra_node)
        made += 1
    if made == 0:
        raise GraphError(f"no Gelu nodes in {src}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    onnx.checker.check_model(model)
    onnx.save(model, str(dest))
    return {"rewritten_gelu": made, "path": str(dest), "sha256": sha256_file(dest)}


def make_gelu_probe(path: Path) -> None:
    """Tiny Gelu graph used to test the rewrite. Not a JEV-H model."""
    import onnx
    from onnx import TensorProto, helper

    node = helper.make_node("Gelu", ["x"], ["y"], name="probe_gelu")
    graph = helper.make_graph(
        [node],
        "probe",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, [1])],
        [helper.make_tensor_value_info("y", TensorProto.FLOAT, [1])],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 20)])
    path.parent.mkdir(parents=True, exist_ok=True)
    onnx.save(model, str(path))

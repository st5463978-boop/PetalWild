"""Static ONNX export, ORT parity check, Hailo DFC op audit, calibration tensors."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import numpy as np
import torch

from encode import SEQ_LEN
from model import OptionScorer

ALLOWED_OPSETS = set(range(13, 18))
FORBIDDEN_OPS = {
    "Loop",
    "If",
    "NonZero",
    "Nonzero",
    "SequenceAt",
    "SequenceConstruct",
    "SequenceEmpty",
    "Optional",
    "OptionalGetElement",
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def export_onnx(model: OptionScorer, path: Path, opset: int = 17) -> dict[str, Any]:
    if opset not in ALLOWED_OPSETS:
        raise ValueError(f"opset {opset} not in 13-17")
    path.parent.mkdir(parents=True, exist_ok=True)
    model = model.eval().cpu()
    ids = torch.zeros(1, SEQ_LEN, dtype=torch.long)
    mask = torch.zeros(1, SEQ_LEN, dtype=torch.float32)
    ids[0, :8] = torch.arange(8)
    mask[0, :8] = 1.0
    try:
        model.set_static_shapes(True)
        torch.onnx.export(
            model,
            (ids, mask),
            str(path),
            input_names=["input_ids", "attention_mask"],
            output_names=["logit"],
            opset_version=opset,
            do_constant_folding=True,
            dynamo=False,
        )
        return inspect_onnx(path)
    finally:
        model.set_static_shapes(False)


def inspect_onnx(path: Path) -> dict[str, Any]:
    import onnx

    model = onnx.load(str(path))
    onnx.checker.check_model(model)
    ops = sorted({n.op_type for n in model.graph.node})
    forbidden = sorted(set(ops) & FORBIDDEN_OPS)
    # Dynamic reshape: Reshape whose shape input is a graph input or a non-initializer
    init_names = {t.name for t in model.graph.initializer}
    graph_inputs = {i.name for i in model.graph.input}
    producers = {out: n for n in model.graph.node for out in n.output}

    def _const_valued(name: str, depth: int = 0) -> bool:
        if not name or depth > 16:
            return False
        if name in init_names:
            return True
        if name in graph_inputs:
            return False
        node = producers.get(name)
        if node is None:
            return False
        if node.op_type in ("Constant", "ConstantOfShape"):
            return node.op_type == "Constant"
        if node.op_type in ("Concat", "Unsqueeze", "Squeeze", "Cast", "Gather", "Slice", "Shape"):
            if node.op_type == "Shape":
                return False
            return all(_const_valued(inp, depth + 1) for inp in node.input if inp)
        return False

    dynamic_reshape = []
    for node in model.graph.node:
        if node.op_type != "Reshape":
            continue
        shape_in = node.input[1] if len(node.input) > 1 else ""
        if shape_in in graph_inputs or not _const_valued(shape_in):
            dynamic_reshape.append(node.name or shape_in)

    def _shape(vi) -> list:
        dims = []
        for d in vi.type.tensor_type.shape.dim:
            dims.append(d.dim_value if d.dim_value else (d.dim_param or "?"))
        return dims

    inputs = [{"name": i.name, "shape": _shape(i), "dtype": i.type.tensor_type.elem_type} for i in model.graph.input if i.name not in init_names]
    outputs = [{"name": o.name, "shape": _shape(o), "dtype": o.type.tensor_type.elem_type} for o in model.graph.output]
    mask_used = _mask_is_used(model)
    return {
        "path": str(path),
        "sha256": sha256_file(path),
        "ir_version": int(model.ir_version),
        "opset": int(model.opset_import[0].version) if model.opset_import else None,
        "ops": ops,
        "forbidden_ops": forbidden,
        "shape_ops": sum(1 for n in model.graph.node if n.op_type == "Shape"),
        "dynamic_reshape_nodes": dynamic_reshape,
        "inputs": inputs,
        "outputs": outputs,
        "attention_mask_used": mask_used,
        "n_nodes": len(model.graph.node),
        "bytes": path.stat().st_size,
    }


def _mask_is_used(model) -> bool:
    names = {i.name for i in model.graph.input}
    if "attention_mask" not in names:
        return False
    consumers = [n for n in model.graph.node if "attention_mask" in n.input]
    if consumers:
        return True
    # constant folding may rename; search initial graph input consumers via identity
    for n in model.graph.node:
        if any("attention_mask" in (inp or "") for inp in n.input):
            return True
        if n.op_type in ("Add", "Mul", "Sub") and any("mask" in (inp or "").lower() for inp in n.input):
            return True
    return False


def verify_ort_parity(
    pt_model: OptionScorer,
    onnx_path: Path,
    input_ids: np.ndarray,
    attention_mask: np.ndarray,
    min_cos: float = 0.999,
) -> dict[str, Any]:
    import onnxruntime as ort

    pt_model.eval()
    sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    pt_chunks = []
    ort_chunks = []
    try:
        pt_model.set_static_shapes(True)
        for i in range(int(input_ids.shape[0])):
            ids = np.ascontiguousarray(input_ids[i : i + 1].astype(np.int64))
            mask = np.ascontiguousarray(attention_mask[i : i + 1].astype(np.float32))
            with torch.no_grad():
                pt_chunks.append(pt_model(torch.from_numpy(ids), torch.from_numpy(mask)).cpu().numpy().reshape(-1))
            ort_chunks.append(
                np.asarray(
                    sess.run(None, {"input_ids": ids, "attention_mask": mask})[0],
                    dtype=np.float64,
                ).reshape(-1)
            )
    finally:
        pt_model.set_static_shapes(False)
    pt_logits = np.concatenate(pt_chunks).astype(np.float64)
    ort_logits = np.concatenate(ort_chunks).astype(np.float64)
    if pt_logits.shape != ort_logits.shape:
        raise RuntimeError(f"shape mismatch pt {pt_logits.shape} ort {ort_logits.shape}")
    a, b = pt_logits, ort_logits
    denom = (np.linalg.norm(a) * np.linalg.norm(b)) + 1e-12
    cos = float(np.dot(a, b) / denom)
    max_abs = float(np.max(np.abs(a - b)))
    ok = cos >= min_cos
    return {
        "n": int(a.size),
        "cosine": cos,
        "max_abs": max_abs,
        "mean_abs": float(np.mean(np.abs(a - b))),
        "ok": ok,
        "min_cos": min_cos,
    }


def save_calib(
    out_dir: Path,
    input_ids: np.ndarray,
    attention_mask: np.ndarray,
    meta: dict[str, Any],
) -> dict[str, Any]:
    if input_ids.shape[0] < 256:
        raise ValueError(f"need >=256 calib rows, got {input_ids.shape[0]}")
    out_dir.mkdir(parents=True, exist_ok=True)
    ids_path = out_dir / "input_ids.npy"
    mask_path = out_dir / "attention_mask.npy"
    np.save(ids_path, input_ids.astype(np.int64))
    np.save(mask_path, attention_mask.astype(np.int64))
    info = {
        "n": int(input_ids.shape[0]),
        "seq_len": int(input_ids.shape[1]),
        "input_ids": str(ids_path),
        "attention_mask": str(mask_path),
        "input_ids_sha256": sha256_file(ids_path),
        "attention_mask_sha256": sha256_file(mask_path),
        **meta,
    }
    (out_dir / "meta.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    return info

"""Static ONNX export (opset 13-17) + calib npy + PyTorch/ORT parity check."""

from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np
import torch
from torch import nn

from .config import OPSET, SEQ_LEN

FORBIDDEN_OPS = {"Loop", "If", "NonZero", "Optional", "SequenceAt", "NonMaxSuppression"}


def export_onnx(model: nn.Module, path: Path, opset: int = OPSET, output_name: str = "logit") -> dict:
    model.eval()
    if hasattr(model, "export_static"):
        model.export_static = True
    path.parent.mkdir(parents=True, exist_ok=True)
    ids = torch.zeros(1, SEQ_LEN, dtype=torch.long)
    mask = torch.ones(1, SEQ_LEN, dtype=torch.long)
    ids[0, 0] = 50281  # CLS
    kwargs = dict(
        export_params=True,
        opset_version=opset,
        do_constant_folding=True,
        input_names=["input_ids", "attention_mask"],
        output_names=[output_name],
        dynamic_axes=None,
    )
    try:
        torch.onnx.export(model, (ids, mask), str(path), dynamo=False, **kwargs)
    except TypeError:
        torch.onnx.export(model, (ids, mask), str(path), **kwargs)
    return inspect_onnx(path, opset=opset)


def inspect_onnx(path: Path, opset: int | None = None) -> dict:
    import onnx

    m = onnx.load(str(path))
    onnx.checker.check_model(m)
    ops = sorted({n.op_type for n in m.graph.node})
    bad = sorted(FORBIDDEN_OPS.intersection(ops))
    if bad:
        raise RuntimeError(f"forbidden ONNX ops for Hailo DFC: {bad}")
    consumed = {i for n in m.graph.node for i in n.input}
    dyn = []
    in_shapes = {}
    for i in m.graph.input:
        dims = []
        for d in i.type.tensor_type.shape.dim:
            if d.dim_param:
                dyn.append(f"{i.name}:{d.dim_param}")
            dims.append(d.dim_value if d.dim_value else d.dim_param or -1)
        in_shapes[i.name] = dims
    out_shapes = {}
    for o in m.graph.output:
        dims = []
        for d in o.type.tensor_type.shape.dim:
            if d.dim_param:
                dyn.append(f"{o.name}:{d.dim_param}")
            dims.append(d.dim_value if d.dim_value else d.dim_param or -1)
        out_shapes[o.name] = dims
    if dyn:
        raise RuntimeError(f"dynamic ONNX dims (Hailo wants static): {dyn}")
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    if "attention_mask" not in consumed:
        raise RuntimeError("attention_mask is an input but is unused in the ONNX graph")
    return {
        "path": str(path),
        "sha256": sha,
        "opset": opset if opset is not None else (m.opset_import[0].version if m.opset_import else None),
        "ops": ops,
        "inputs": in_shapes,
        "outputs": out_shapes,
        "seq_len": SEQ_LEN,
        "batch": 1,
        "attention_mask_used": True,
        "input_ids_is_input": "input_ids" in in_shapes,
        "attention_mask_is_input": "attention_mask" in in_shapes,
        "bytes": path.stat().st_size,
    }


def parity_check(
    model: nn.Module,
    onnx_path: Path,
    ids: np.ndarray,
    mask: np.ndarray,
    min_cos: float = 0.999,
    output_name: str | None = None,
) -> dict:
    import onnxruntime as ort

    model.eval()
    was = getattr(model, "export_static", None)
    if hasattr(model, "export_static"):
        model.export_static = True
    pt_rows = []
    onx_rows = []
    sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    out_name = output_name or sess.get_outputs()[0].name
    with torch.no_grad():
        for i in range(ids.shape[0]):
            row_i = ids[i : i + 1].astype(np.int64)
            row_m = mask[i : i + 1].astype(np.int64)
            pt_rows.append(model(torch.from_numpy(row_i), torch.from_numpy(row_m)).cpu().numpy().reshape(-1))
            onx_rows.append(sess.run([out_name], {"input_ids": row_i, "attention_mask": row_m})[0].reshape(-1))
    if was is not None:
        model.export_static = was
    pt = np.concatenate(pt_rows)
    onx = np.concatenate(onx_rows)
    a = pt.astype(np.float64)
    b = onx.astype(np.float64)
    na = np.linalg.norm(a)
    nb = np.linalg.norm(b)
    cos = float((a @ b) / (na * nb)) if na > 0 and nb > 0 else float("nan")
    max_abs = float(np.max(np.abs(a - b)))
    if not (cos >= min_cos):
        raise RuntimeError(f"ONNX/PyTorch cos {cos:.6f} < {min_cos}")
    return {"cos": cos, "max_abs": max_abs, "n": int(a.size), "output_name": out_name}


def save_calib(ids: np.ndarray, mask: np.ndarray, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    p_ids = out_dir / "calib_input_ids.npy"
    p_mask = out_dir / "calib_attention_mask.npy"
    np.save(p_ids, ids.astype(np.int64))
    np.save(p_mask, mask.astype(np.int64))
    return {
        "n": int(ids.shape[0]),
        "shape": list(ids.shape),
        "input_ids": str(p_ids),
        "attention_mask": str(p_mask),
        "input_ids_sha256": hashlib.sha256(p_ids.read_bytes()).hexdigest(),
        "attention_mask_sha256": hashlib.sha256(p_mask.read_bytes()).hexdigest(),
    }

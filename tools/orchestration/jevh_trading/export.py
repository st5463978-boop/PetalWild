"""Static ONNX export (opset 13-17) + calib npy + PyTorch parity check."""

from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np
import torch

from .config import OPSET, SEQ_LEN
from .model import PairScorer

FORBIDDEN_OPS = {"Loop", "If", "NonZero"}


def export_onnx(model: PairScorer, path: Path, opset: int = OPSET) -> dict:
    model.eval()
    model.export_static = True
    path.parent.mkdir(parents=True, exist_ok=True)
    ids = torch.zeros(1, SEQ_LEN, dtype=torch.long)
    mask = torch.ones(1, SEQ_LEN, dtype=torch.long)
    ids[0, 0] = 50281  # CLS
    torch.onnx.export(
        model,
        (ids, mask),
        str(path),
        export_params=True,
        opset_version=opset,
        do_constant_folding=True,
        input_names=["input_ids", "attention_mask"],
        output_names=["logit"],
        dynamic_axes=None,
    )
    import onnx

    m = onnx.load(str(path))
    onnx.checker.check_model(m)
    ops = sorted({n.op_type for n in m.graph.node})
    bad = sorted(FORBIDDEN_OPS.intersection(ops))
    if bad:
        raise RuntimeError(f"forbidden ONNX ops for Hailo DFC: {bad}")
    # reshape with computed dims is rejected by checking initializers: we only used view with B,S from input
    in_shapes = {i.name: [d.dim_value for d in i.type.tensor_type.shape.dim] for i in m.graph.input}
    out_shapes = {o.name: [d.dim_value for d in o.type.tensor_type.shape.dim] for o in m.graph.output}
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    return {
        "path": str(path),
        "sha256": sha,
        "opset": opset,
        "ops": ops,
        "inputs": in_shapes,
        "outputs": out_shapes,
        "seq_len": SEQ_LEN,
        "batch": 1,
    }


def parity_check(model: PairScorer, onnx_path: Path, ids: np.ndarray, mask: np.ndarray, min_cos: float = 0.999) -> dict:
    import onnxruntime as ort

    model.eval()
    was = model.export_static
    model.export_static = True
    pt_rows = []
    onx_rows = []
    sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    with torch.no_grad():
        for i in range(ids.shape[0]):
            row_i = ids[i : i + 1].astype(np.int64)
            row_m = mask[i : i + 1].astype(np.int64)
            pt_rows.append(model(torch.from_numpy(row_i), torch.from_numpy(row_m)).cpu().numpy().reshape(-1))
            onx_rows.append(sess.run(["logit"], {"input_ids": row_i, "attention_mask": row_m})[0].reshape(-1))
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
    return {"cos": cos, "max_abs": max_abs, "n": int(a.size)}


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

"""Static ONNX export + Hailo-oriented graph checks + ORT parity."""
from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

import numpy as np
import torch

FORBIDDEN_OPS = {
    "Loop",
    "If",
    "NonZero",
    "Nonzero",
    "Where",  # data-dependent select; we keep the graph additive-mask only
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def export_static_onnx(
    model: torch.nn.Module,
    path: Path,
    seq_len: int,
    opset: int = 17,
) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    model.eval()
    dummy_ids = torch.randint(1, 100, (1, seq_len), dtype=torch.long)
    dummy_mask = torch.ones(1, seq_len, dtype=torch.long)
    dummy_mask[0, seq_len // 2 :] = 0  # mixed mask so the input cannot be constant-folded away
    dynamic_ok = False
    kwargs: dict[str, Any] = dict(
        input_names=["input_ids", "attention_mask"],
        output_names=["logits"],
        opset_version=opset,
        do_constant_folding=True,
    )
    with torch.no_grad():
        try:
            torch.onnx.export(model, (dummy_ids, dummy_mask), str(path), dynamo=False, **kwargs)
        except TypeError:
            torch.onnx.export(model, (dummy_ids, dummy_mask), str(path), **kwargs)
            dynamic_ok = True
    info = inspect_onnx(path, seq_len)
    info["export_used_mixed_mask"] = True
    info["torch_onnx_legacy"] = not dynamic_ok
    return info


def inspect_onnx(path: Path, seq_len: int) -> dict[str, Any]:
    import onnx
    from onnx import numpy_helper, shape_inference

    model = onnx.load(str(path))
    try:
        model = shape_inference.infer_shapes(model)
    except Exception as exc:  # noqa: BLE001
        model = onnx.load(str(path))
        inferred = f"shape_inference_failed:{type(exc).__name__}"
    else:
        inferred = "ok"

    inputs = []
    for inp in model.graph.input:
        dims = [d.dim_value if d.dim_value else d.dim_param or "?" for d in inp.type.tensor_type.shape.dim]
        et = inp.type.tensor_type.elem_type
        inputs.append({"name": inp.name, "shape": dims, "elem_type": et})
    outputs = []
    for out in model.graph.output:
        dims = [d.dim_value if d.dim_value else d.dim_param or "?" for d in out.type.tensor_type.shape.dim]
        et = out.type.tensor_type.elem_type
        outputs.append({"name": out.name, "shape": dims, "elem_type": et})

    op_counts: dict[str, int] = {}
    reshape_dynamic = []
    for node in model.graph.node:
        op_counts[node.op_type] = op_counts.get(node.op_type, 0) + 1
        if node.op_type == "Reshape" and len(node.input) > 1:
            shape_name = node.input[1]
            init_names = {i.name for i in model.graph.initializer}
            const_names = {n.output[0] for n in model.graph.node if n.op_type in ("Constant", "ConstantOfShape") and n.output}
            if shape_name not in init_names and shape_name not in const_names:
                reshape_dynamic.append(node.name or shape_name)

    forbidden_hit = sorted(op for op in op_counts if op in FORBIDDEN_OPS)
    # Additive mask graphs may still contain Where from GELU/LayerNorm exporters.
    # Hailo DFC forbids If/Loop/NonZero/dynamic Reshape; Where from GELU is not in that list
    # but we still flag a real If/Loop/NonZero.
    hard_forbidden = sorted(op for op in ("Loop", "If", "NonZero", "Nonzero") if op in op_counts)

    produced = {o for n in model.graph.node for o in n.output}
    consumed = {i for n in model.graph.node for i in n.input}
    mask_used = "attention_mask" in consumed or any(
        "attention_mask" in (n.name or "") or "attention_mask" in "".join(n.input) for n in model.graph.node
    )
    # Also: mask is an input that feeds at least one node.
    mask_consumers = [n.op_type for n in model.graph.node if "attention_mask" in n.input]
    if not mask_consumers:
        # exporters often rename after the first Cast/Identity
        for n in model.graph.node:
            if n.op_type in ("Cast", "Identity") and n.input and n.input[0] == "attention_mask":
                alias = n.output[0]
                mask_consumers.extend(m.op_type for m in model.graph.node if alias in m.input)

    def _static_shape(dims: list) -> bool:
        return all(isinstance(d, int) and d > 0 for d in dims)

    issues = []
    if hard_forbidden:
        issues.append(f"forbidden_ops={hard_forbidden}")
    if reshape_dynamic:
        issues.append(f"dynamic_reshape={reshape_dynamic[:8]}")
    if not mask_used and not mask_consumers:
        issues.append("attention_mask_not_consumed")
    for spec, expect in (
        (inputs, [("input_ids", [1, seq_len]), ("attention_mask", [1, seq_len])]),
    ):
        got = {x["name"]: x["shape"] for x in spec}
        for name, shape in expect:
            if name not in got:
                issues.append(f"missing_input:{name}")
            elif got[name] != shape:
                issues.append(f"input_shape {name} {got[name]} != {shape}")
    if not outputs or outputs[0]["name"] != "logits":
        issues.append("expected_output_logits")
    elif not _static_shape(outputs[0]["shape"]):
        issues.append(f"dynamic_output_shape={outputs[0]['shape']}")

    # unused Where warning is informational only
    info = {
        "path": str(path),
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
        "ir_version": model.ir_version,
        "opset": [int(o.version) for o in model.opset_import],
        "inputs": inputs,
        "outputs": outputs,
        "op_counts": dict(sorted(op_counts.items())),
        "forbidden_ops_present": forbidden_hit,
        "hard_forbidden_ops": hard_forbidden,
        "dynamic_reshape": reshape_dynamic,
        "attention_mask_consumers": mask_consumers[:12],
        "attention_mask_used": bool(mask_consumers) or mask_used,
        "shape_inference": inferred,
        "issues": issues,
        "ok": not issues,
    }
    _ = numpy_helper  # keep import used
    return info


def ort_logits(path: Path, input_ids: np.ndarray, attention_mask: np.ndarray) -> np.ndarray:
    import onnxruntime as ort

    sess = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    out = sess.run(
        ["logits"],
        {
            "input_ids": input_ids.astype(np.int64),
            "attention_mask": attention_mask.astype(np.int64),
        },
    )[0]
    return np.asarray(out, dtype=np.float32)


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, dtype=np.float64).reshape(-1)
    b = np.asarray(b, dtype=np.float64).reshape(-1)
    na = np.linalg.norm(a)
    nb = np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def verify_parity(
    torch_model: torch.nn.Module,
    onnx_path: Path,
    records: list[dict[str, Any]],
    max_pairs: int = 256,
) -> dict[str, Any]:
    torch_model.eval()
    pt_all = []
    ort_all = []
    n = 0
    with torch.no_grad():
        for rec in records:
            for ids, mask in zip(rec["input_ids"], rec["attention_mask"]):
                id_t = torch.tensor([ids], dtype=torch.long)
                mk_t = torch.tensor([mask], dtype=torch.long)
                pt = torch_model(id_t, mk_t).cpu().numpy().reshape(-1)
                ot = ort_logits(onnx_path, id_t.numpy(), mk_t.numpy()).reshape(-1)
                pt_all.append(pt)
                ort_all.append(ot)
                n += 1
                if n >= max_pairs:
                    break
            if n >= max_pairs:
                break
    pt_a = np.concatenate(pt_all)
    ort_a = np.concatenate(ort_all)
    cos = cosine(pt_a, ort_a)
    mae = float(np.mean(np.abs(pt_a - ort_a)))
    mx = float(np.max(np.abs(pt_a - ort_a)))
    return {
        "n_pairs": n,
        "cosine": cos,
        "mae": mae,
        "max_abs": mx,
        "ok": cos >= 0.999,
    }


def assert_mask_affects_output(model: torch.nn.Module, seq_len: int) -> dict[str, Any]:
    """Sanity: zeroing the second half of the mask must change the logit."""
    model.eval()
    ids = torch.randint(2, 80, (1, seq_len), dtype=torch.long)
    full = torch.ones(1, seq_len, dtype=torch.long)
    half = full.clone()
    half[0, seq_len // 2 :] = 0
    with torch.no_grad():
        a = model(ids, full).reshape(-1)
        b = model(ids, half).reshape(-1)
    delta = float((a - b).abs().max().item())
    return {"delta": delta, "ok": delta > 1e-5}

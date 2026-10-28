"""Shapes, heads, and agreement rules for the 68M v5 Hailo student.

Choice, Noul, and Score are one CLS scorer with three prompt modes, matching
encode.build_input. They are not three weight matrices.
"""
from __future__ import annotations

import ast
import math
from pathlib import Path

SEQ_LEN = 128
VOCAB = 50368
PAD_ID = 50283
CLS_ID = 50281
SEP_ID = 50282
EXPORT_BATCH = 1
# Held-out decision agreement required before a HEF is accepted.
# Not applied when the HEF was never executed.
AGREEMENT_FLOOR = 0.99
CONFIDENT_WRONG_PROB = 0.65
EXPECTED_ONNX_SHA256 = "7f78a56e9a692c6c83baf064b86219919a2d7f8870c9813a4ffae50d4a89e292"
EXPECTED_ONNX_BYTES = 277144914
ONNX_NAME = "jevh_68m_v5_seq128.onnx"
CKPT_NAMES = ("jevh_68m_v5_r2.pt", "jevh_68m_v5.pt")
LIVE_DECIDE_PORT = 8771
DEV_DECIDE_PORT = 8772
QTYPES = ("choice", "noul", "score")

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "artifacts"
MODEL_PY = ROOT / "model.py"
ENCODE_PY = ROOT / "encode.py"


def _assigned_ints(path: Path, names: set[str]) -> dict[str, int]:
    tree = ast.parse(path.read_text())
    found: dict[str, int] = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            name = node.targets[0]
            if isinstance(name, ast.Name) and name.id in names:
                if isinstance(node.value, ast.Constant) and isinstance(node.value.value, int):
                    found[name.id] = node.value.value
    missing = names - set(found)
    if missing:
        raise RuntimeError(f"{path} is missing {sorted(missing)}")
    return found


def architecture_constants() -> dict[str, int]:
    """Read the student contract from source, without importing torch or tokenizers."""
    model = _assigned_ints(MODEL_PY, {"SEQ_LEN", "VOCAB", "PAD_ID"})
    encode = _assigned_ints(ENCODE_PY, {"SEQ_LEN", "CLS_ID"})
    if model["SEQ_LEN"] != encode["SEQ_LEN"]:
        raise RuntimeError(f"model.SEQ_LEN {model['SEQ_LEN']} != encode.SEQ_LEN {encode['SEQ_LEN']}")
    model.update(encode)
    return model


def softmax(logits: list[float]) -> list[float]:
    if not logits:
        raise ValueError("softmax needs at least one logit")
    peak = max(logits)
    exps = [math.exp(x - peak) for x in logits]
    total = sum(exps)
    if total <= 0.0 or math.isnan(total):
        raise ValueError("softmax denominator was not positive")
    return [v / total for v in exps]


def decide_from_logits(logits: list[float], options: list[str]) -> dict:
    if len(logits) != len(options):
        raise ValueError(f"{len(logits)} logits for {len(options)} options")
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    probs = softmax(logits)
    index = max(range(len(probs)), key=lambda i: (probs[i], -i))
    order = sorted(probs, reverse=True)
    margin = order[0] - order[1]
    return {
        "index": index,
        "choice": options[index],
        "logits": [float(x) for x in logits],
        "probs": probs,
        "scores": probs,
        "confidence": probs[index],
        "margin": margin,
    }


def decision_agreement(left: list[int], right: list[int]) -> float:
    if len(left) != len(right) or not left:
        raise ValueError("agreement needs two equal non-empty index lists")
    hits = sum(a == b for a, b in zip(left, right))
    return hits / len(left)


def confident_wrong(probs: list[float], pred: list[int], gold: list[int], threshold: float = CONFIDENT_WRONG_PROB) -> int:
    if not (len(probs) == len(pred) == len(gold)):
        raise ValueError("confident-wrong lists differ in length")
    return sum(
        p >= threshold and a != g
        for p, a, g in zip(probs, pred, gold)
    )


def expected_calibration_error(confidences: list[float], correct: list[bool], bins: int = 10) -> float:
    if len(confidences) != len(correct) or not confidences:
        raise ValueError("ECE needs paired confidences and correctness")
    if bins < 1:
        raise ValueError("bins must be positive")
    total = len(confidences)
    error = 0.0
    for b in range(bins):
        lo = b / bins
        hi = (b + 1) / bins
        bucket = [
            (c, ok)
            for c, ok in zip(confidences, correct)
            if (lo <= c < hi) or (b == bins - 1 and c == 1.0)
        ]
        if not bucket:
            continue
        acc = sum(1.0 for _, ok in bucket if ok) / len(bucket)
        conf = sum(c for c, _ in bucket) / len(bucket)
        error += (len(bucket) / total) * abs(acc - conf)
    return error


def accept_agreement(measured: float | None) -> dict:
    """A missing measurement is not a pass. A number under the floor is a reject."""
    if measured is None:
        return {"accepted": False, "measured": None, "floor": AGREEMENT_FLOOR, "reason": "not measured"}
    if measured + 1e-12 < AGREEMENT_FLOOR:
        return {
            "accepted": False,
            "measured": measured,
            "floor": AGREEMENT_FLOOR,
            "reason": f"agreement {measured:.4f} is below {AGREEMENT_FLOOR:.2f}",
        }
    return {"accepted": True, "measured": measured, "floor": AGREEMENT_FLOOR, "reason": "measured agreement met the floor"}

"""Score the chip. A teacher answer is not a chip failure.

Counted only when the chip is wrong and chip confidence >= 0.90.
training_eligible stays false.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any

CONFIDENT_WRONG = 0.90


def fingerprint(case: dict) -> str:
    key = {
        "family": case.get("family"),
        "question": " ".join(str(case.get("question", "")).split()),
        "options": list(case.get("options") or []),
        "answer": case.get("answer"),
    }
    blob = json.dumps(key, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def numeric_confidence(blob: dict | None) -> float | None:
    if not isinstance(blob, dict):
        return None
    value = blob.get("confidence")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    scores = blob.get("scores")
    if (
        isinstance(scores, list)
        and scores
        and all(isinstance(item, (int, float)) and not isinstance(item, bool) for item in scores)
    ):
        return float(max(scores))
    return None


def _clean_choice(raw: Any) -> str:
    text = str(raw or "")
    for token in ("<|im_end|>", "<|im_start|>"):
        text = text.replace(token, "")
    return text.strip()


def map_choice(blob: dict, options: list[str]) -> dict:
    if not isinstance(blob, dict):
        return {"ok": False, "bug": "response_not_object"}
    index = blob.get("index")
    choice = _clean_choice(blob.get("choice"))
    if isinstance(index, int) and not isinstance(index, bool) and 0 <= index < len(options):
        by_index = options[index]
        if choice and choice in options and choice != by_index:
            return {
                "ok": False,
                "bug": "index_choice_mismatch",
                "index": index,
                "choice": choice,
                "by_index": by_index,
            }
        return {"ok": True, "option": by_index, "index": index, "bug": None}
    if choice in options:
        return {"ok": True, "option": choice, "index": options.index(choice), "bug": None}
    return {"ok": False, "bug": "unmapped_choice", "choice": choice, "index": index}


def chip_blob(payload: dict) -> dict | None:
    """The student head only. A CPU teacher answer is not the chip."""
    if not isinstance(payload, dict):
        return None
    chip = payload.get("chip")
    if isinstance(chip, dict) and ("index" in chip or "choice" in chip):
        return chip
    decided = str(payload.get("decided_by") or payload.get("device") or "").lower()
    if "teacher" in decided or "cpu" in decided or "llama" in decided:
        return None
    if payload.get("escalated") is True:
        return None
    if any(token in decided for token in ("student", "chip", "hef", "npu", "hailojev")):
        return payload
    model = str(payload.get("model") or "").lower()
    if "hef" in model or "hailojev_student" in model:
        return payload
    return None


def score_attempt(case: dict, payload: dict, seen: set[str] | None = None) -> dict:
    options = list(case["options"])
    seen = seen if seen is not None else set()
    fp = fingerprint(case)
    blob = chip_blob(payload)
    row = {
        "id": case["id"],
        "kind": "adversarial",
        "family": "reversibility",
        "action": case.get("action"),
        "fingerprint": fp,
        "question": case["question"],
        "options": options,
        "answer": case["answer"],
        "why": case["why"],
        "training_eligible": False,
        "bucket": "CANARY-EVAL",
        "valid_atomic": True,
        "independently_establishable": True,
        "production_escalated": bool(payload.get("escalated")),
        "jev_source": "chip" if isinstance(blob, dict) else "missing_chip",
        "teacher_choice": payload.get("choice") if payload.get("escalated") else None,
        "model": (blob or {}).get("model") or payload.get("model"),
        "latency_ms": payload.get("latency_ms"),
        "decision_id": payload.get("decision_id"),
        "chip_npu_ms": blob.get("npu_ms") if isinstance(blob, dict) else None,
    }
    if fp in seen:
        row.update({"counted_failure": False, "skip": "duplicate", "bucket": "QUARANTINE"})
        return row
    if not isinstance(blob, dict):
        row.update({"counted_failure": False, "skip": "no_forced_jev", "bucket": "QUARANTINE"})
        return row
    mapped = map_choice(blob, options)
    confidence = numeric_confidence(blob)
    row["jev_choice"] = mapped.get("option")
    row["jev_index"] = mapped.get("index")
    row["jev_confidence"] = confidence
    row["jev_scores"] = blob.get("scores")
    row["map_bug"] = mapped.get("bug")
    if not mapped.get("ok"):
        row.update(
            {
                "counted_failure": False,
                "skip": mapped.get("bug") or "index_bug",
                "bucket": "QUARANTINE",
            }
        )
        return row
    wrong = mapped["option"] != case["answer"]
    confident = confidence is not None and confidence >= CONFIDENT_WRONG
    counted = bool(wrong and confident)
    row["jev_wrong"] = wrong
    row["confident"] = confident
    row["counted_failure"] = counted
    row["skip"] = None
    if counted:
        row["bucket"] = "QUARANTINE"
    return row

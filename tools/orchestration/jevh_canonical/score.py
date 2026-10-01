"""Score a forced JEV chip answer. The CPU teacher is not a chip answer.

Counted failure: valid atomic case, chip choice wrong, chip confidence >= 0.90,
not a duplicate, not an index/harness bug. training_eligible stays false.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any

CONFIDENT_WRONG = 0.90


def fingerprint(case: dict) -> str:
    key = {
        "kind": case.get("kind"),
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
    """Map with index. Never default to options[0]."""
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


def _teacherish(payload: dict) -> bool:
    decided = str(payload.get("decided_by") or "").lower()
    device = str(payload.get("device") or "").lower()
    model = str(payload.get("model") or "").lower()
    return (
        "teacher" in decided
        or "cpu" in device
        or "qwen" in model
        or model.endswith(".gguf")
        or ".gguf" in model
    )


def jev_forced(payload: dict) -> dict:
    """Chip object only. A teacher completion is not a forced JEV answer."""
    chip = payload.get("chip")
    if isinstance(chip, dict) and ("index" in chip or "choice" in chip):
        return {"source": "chip", "blob": chip}
    if payload.get("escalated") is True or _teacherish(payload):
        return {"source": "missing_chip", "blob": None}
    decided = str(payload.get("decided_by") or payload.get("device") or "").lower()
    if any(token in decided for token in ("student", "chip", "hef", "npu", "hailojev")):
        return {"source": "top", "blob": payload}
    if "index" in payload or "choice" in payload:
        return {"source": "top", "blob": payload}
    return {"source": "missing_chip", "blob": None}


def score_attempt(case: dict, payload: dict, seen: set[str] | None = None) -> dict:
    options = list(case["options"])
    seen = seen if seen is not None else set()
    fp = fingerprint(case)
    forced = jev_forced(payload)
    production_escalated = bool(payload.get("escalated"))
    row = {
        "id": case["id"],
        "kind": case["kind"],
        "family": case["family"],
        "fingerprint": fp,
        "question": case["question"],
        "options": options,
        "answer": case["answer"],
        "why": case["why"],
        "training_eligible": False,
        "bucket": "CANARY-EVAL",
        "valid_atomic": True,
        "independently_establishable": True,
        "production_escalated": production_escalated,
        "routing_should_escalate": False,
        "jev_source": forced["source"],
        "teacher_choice": payload.get("choice") if production_escalated else None,
        "teacher_model": payload.get("model") if production_escalated else None,
        "model": None,
        "latency_ms": payload.get("latency_ms"),
        "decision_id": payload.get("decision_id"),
        "chip_npu_ms": None,
    }
    if isinstance(payload.get("chip"), dict):
        row["chip_npu_ms"] = payload["chip"].get("npu_ms")
        row["model"] = payload["chip"].get("model")
    if fp in seen:
        row.update({"counted_failure": False, "skip": "duplicate", "bucket": "QUARANTINE"})
        return row
    blob = forced["blob"]
    if not isinstance(blob, dict):
        row.update(
            {
                "counted_failure": False,
                "skip": "no_forced_jev",
                "bucket": "QUARANTINE",
                "model": None,
            }
        )
        return row
    if row["model"] is None:
        row["model"] = blob.get("model") or payload.get("model")
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

"""Grade the chip. The Pi CPU teacher is not the grader.

Counted failure:
  ownership case, two real workers
  + named worker is the established answer
  + chip chooses the other worker
  + chip confidence >= 0.90
  + not a duplicate
  + not an index or position-slot bug

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


def chip_blob(payload: dict) -> dict | None:
    """Return the chip object only. A teacher top-level choice is not the chip."""
    chip = payload.get("chip")
    if isinstance(chip, dict) and ("index" in chip or "choice" in chip or "confidence" in chip):
        return chip
    decided = str(payload.get("decided_by") or "").lower()
    device = str(payload.get("device") or "").lower()
    model = str(payload.get("model") or "").lower()
    teacherish = (
        payload.get("escalated") is True
        or "teacher" in decided
        or "cpu" in device
        or "gguf" in model
        or "qwen" in model
    )
    if teacherish:
        return None
    if "index" in payload or "choice" in payload:
        return payload
    return None


def score_attempt(case: dict, payload: dict, seen: set[str] | None = None) -> dict:
    options = list(case["options"])
    seen = seen if seen is not None else set()
    fp = fingerprint(case)
    blob = chip_blob(payload)
    escalated = bool(payload.get("escalated")) or str(payload.get("decided_by") or "").lower() == "teacher"
    row = {
        "id": case["id"],
        "kind": case["kind"],
        "family": case["family"],
        "contrast": case.get("contrast"),
        "fingerprint": fp,
        "question": case["question"],
        "options": options,
        "answer": case["answer"],
        "named": case.get("named"),
        "bystander": case.get("bystander"),
        "why": case["why"],
        "training_eligible": False,
        "bucket": "CANARY-EVAL",
        "valid_atomic": len(options) == 2 and case["answer"] in options,
        "independently_establishable": True,
        "production_escalated": escalated,
        "routing_should_escalate": False,
        "model": payload.get("model"),
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
    row["jev_wrong"] = wrong
    row["confident"] = confident
    row["counted_failure"] = bool(wrong and confident)
    row["skip"] = None
    if row["counted_failure"]:
        row["bucket"] = "QUARANTINE"
    return row


def clear_position_bias(rows: list[dict]) -> None:
    """Same option slot on a flip pair is a harness bug, not a counted failure."""
    by_id = {row.get("id"): row for row in rows}
    for row in rows:
        rid = str(row.get("id") or "")
        if not rid.endswith("-flip"):
            continue
        base = by_id.get(rid[: -len("-flip")])
        if not isinstance(base, dict):
            continue
        if base.get("skip") in {"duplicate", "no_forced_jev", "index_choice_mismatch", "unmapped_choice"}:
            continue
        if row.get("skip") in {"duplicate", "no_forced_jev", "index_choice_mismatch", "unmapped_choice"}:
            continue
        b_index = base.get("jev_index")
        f_index = row.get("jev_index")
        if b_index not in (0, 1) or b_index != f_index:
            continue
        if base.get("jev_choice") == row.get("jev_choice"):
            continue
        for item in (base, row):
            if item.get("counted_failure"):
                item["counted_failure"] = False
                item["skip"] = "position_index_bias"
                item["bucket"] = "QUARANTINE"

"""Score one forced JEV answer. Escalation is recorded, never offered as a choice.

Counted failure:
  valid atomic case
  + independently establishable answer
  + JEV (chip) chooses wrong
  + chip confidence >= 0.90
  + not duplicate
  + not an index/harness bug

JEV is the chip / student head when present. The teacher path is not JEV.
training_eligible stays false.
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
    """Map with index. Never default to options[0]. Flag index/choice fights."""
    if not isinstance(blob, dict):
        return {"ok": False, "bug": "response_not_object"}
    index = blob.get("index")
    choice = _clean_choice(blob.get("choice"))
    by_index = None
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
    letter = choice[:1].upper()
    if letter.isalpha() and len(choice) <= 3:
        presented = ord(letter) - ord("A")
        shuffle = blob.get("shuffle_order")
        if isinstance(shuffle, list) and presented < len(shuffle):
            orig = shuffle[presented]
            if isinstance(orig, int) and 0 <= orig < len(options):
                return {
                    "ok": True,
                    "option": options[orig],
                    "index": orig,
                    "bug": None,
                    "via": "shuffle_letter",
                }
        # A letter without a trustworthy index is an index/harness risk.
        return {"ok": False, "bug": "letter_without_index", "choice": choice}
    return {"ok": False, "bug": "unmapped_choice", "choice": choice, "index": index}


def jev_forced(payload: dict) -> dict:
    """Forced JEV answer is the chip when the service also ran a teacher."""
    chip = payload.get("chip")
    if isinstance(chip, dict) and ("index" in chip or "choice" in chip):
        return {"source": "chip", "blob": chip}
    decided = str(payload.get("decided_by") or payload.get("device") or "").lower()
    if any(token in decided for token in ("student", "chip", "hef", "npu", "hailojev")):
        return {"source": "top", "blob": payload}
    if payload.get("escalated") is True:
        return {"source": "missing_chip", "blob": None}
    return {"source": "top", "blob": payload}


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
        "model": payload.get("model"),
        "latency_ms": payload.get("latency_ms"),
        "decision_id": payload.get("decision_id"),
        "chip_npu_ms": (payload.get("chip") or {}).get("npu_ms")
        if isinstance(payload.get("chip"), dict)
        else None,
    }
    if fp in seen:
        row.update(
            {
                "counted_failure": False,
                "skip": "duplicate",
                "bucket": "QUARANTINE",
            }
        )
        return row
    blob = forced["blob"]
    if not isinstance(blob, dict):
        row.update(
            {
                "counted_failure": False,
                "skip": "no_forced_jev",
                "bucket": "QUARANTINE",
            }
        )
        return row
    if "shuffle_order" not in blob and payload.get("shuffle_order") is not None:
        blob = dict(blob)
        blob["shuffle_order"] = payload.get("shuffle_order")
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
    elif confident and not wrong:
        row["bucket"] = "CANARY-EVAL"
    else:
        row["bucket"] = "CANARY-EVAL"
    return row

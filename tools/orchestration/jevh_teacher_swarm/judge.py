"""Turn one decide payload into a corpus row.

JEV is the chip. A teacher fallback is not a counted failure and is not gold.
"""

from __future__ import annotations

from jevh_clean_core.score import score_attempt
from jevh_teacher_swarm.analysis.dedupe import near_duplicate
from jevh_teacher_swarm.shuffle import original_option

_HEF_MARKERS = ("ettin68m", "352c0f6d")


def chip_backed(payload: dict) -> bool:
    chip = payload.get("chip")
    if not isinstance(chip, dict):
        return False
    if "index" not in chip and "choice" not in chip:
        return False
    blob = " ".join(
        str(payload.get(key) or "") + " " + str(chip.get(key) or "")
        for key in ("model", "device", "decided_by")
    ).lower()
    return any(marker in blob for marker in _HEF_MARKERS)


def judge(case: dict, payload: dict, state: dict, cfg: dict) -> dict:
    """state mutates when a new unique failure is accepted."""
    presented = list(case["presented_options"])
    gold = case["verifier_answer"]
    score_case = {
        "id": case["id"],
        "kind": case["kind"],
        "family": case["attack_family"],
        "question": case["question"],
        "options": presented,
        "answer": gold,
        "why": case.get("teacher_rationale", ""),
    }
    scored = score_attempt(score_case, payload, set())
    backed = chip_backed(payload)
    threshold = payload.get("threshold", cfg["production_escalate_below"])
    row = {
        **{key: case[key] for key in (
            "id",
            "lane",
            "domain",
            "subdomain",
            "attack_family",
            "mechanism_id",
            "kind",
            "question",
            "fingerprint",
            "partition",
            "probe",
        )},
        "original_options": case["original_options"],
        "presented_options": presented,
        "presented_to_original": case["presented_to_original"],
        "original_to_presented": case["original_to_presented"],
        "answer_original_index": case["answer_original_index"],
        "answer_presented_index": case["answer_presented_index"],
        "teacher_answer": case["teacher_answer"],
        "verifier_answer": gold,
        "teacher_verifier_agree": True,
        "training_eligible": False,
        "training_selected": False,
        "gold": gold,
        "jev_source": "chip" if backed else scored.get("jev_source"),
        "chip_backed": backed,
        "model": payload.get("model"),
        "device": payload.get("device"),
        "decided_by": payload.get("decided_by"),
        "decision_id": payload.get("decision_id"),
        "latency_ms": payload.get("latency_ms"),
        "server_shuffle_order": payload.get("shuffle_order"),
        "server_presented_index": payload.get("presented_index"),
        "production_escalated": bool(payload.get("escalated")),
        "escalate_threshold": threshold,
        "teacher_choice_on_wire": payload.get("choice"),
        "counted_unique": False,
        "counted_failure": False,
    }
    if not backed:
        row.update(
            {
                "bucket": "QUARANTINE",
                "skip": "no_forced_jev",
                "jev_choice": None,
                "jev_index": None,
                "jev_confidence": None,
                "jev_scores": None,
                "jev_wrong": None,
                "would_production_escalate": True,
                "failure_class": "harness" if payload.get("escalated") else "missing_chip",
            }
        )
        return row

    if not scored.get("map_bug") and isinstance(scored.get("jev_index"), int):
        try:
            recovered = original_option(case, scored["jev_index"])
        except (IndexError, KeyError):
            recovered = None
        if recovered != scored.get("jev_choice"):
            row.update(
                {
                    "bucket": "QUARANTINE",
                    "skip": "shuffle_map_mismatch",
                    "failure_class": "harness",
                    "jev_choice": scored.get("jev_choice"),
                    "jev_index": scored.get("jev_index"),
                    "jev_confidence": None,
                    "would_production_escalate": bool(payload.get("escalated")),
                }
            )
            return row

    confidence = scored.get("jev_confidence")
    wrong = scored.get("jev_wrong")
    skip = scored.get("skip")
    row.update(
        {
            "jev_choice": scored.get("jev_choice"),
            "jev_index": scored.get("jev_index"),
            "jev_confidence": confidence,
            "jev_scores": scored.get("jev_scores"),
            "jev_wrong": wrong,
            "chip_npu_ms": scored.get("chip_npu_ms"),
            "skip": skip,
            "confident": bool(isinstance(confidence, (int, float)) and confidence >= cfg["confident_wrong_min"]),
            "confident_095": bool(isinstance(confidence, (int, float)) and confidence >= cfg["confident_095"]),
            "confident_098": bool(isinstance(confidence, (int, float)) and confidence >= cfg["confident_098"]),
            "would_production_escalate": bool(payload.get("escalated"))
            or (isinstance(confidence, (int, float)) and confidence < float(threshold)),
        }
    )
    if skip:
        row["bucket"] = "QUARANTINE"
        row["failure_class"] = "harness"
        return row
    if wrong and row["confident"]:
        duplicate = _already_known(case, gold, state, cfg["near_duplicate_ratio"])
        if duplicate:
            row.update(
                {
                    "bucket": "REJECTED",
                    "skip": "near_duplicate",
                    "near_duplicate_of": duplicate,
                    "failure_class": "reasoning_descendant",
                    "counted_failure": False,
                    "counted_unique": False,
                }
            )
            return row
        row.update(
            {
                "bucket": "ACCEPTED_FAILURE",
                "skip": None,
                "failure_class": "reasoning",
                "counted_failure": True,
                "counted_unique": True,
            }
        )
        state["mechanisms"].add(case["mechanism_id"])
        state["questions"].append((case["question"], gold))
        return row
    if wrong:
        row.update({"bucket": "REJECTED", "skip": "below_confidence", "failure_class": "reasoning_low_confidence"})
        return row
    row.update({"bucket": "ACCEPTED_CORRECT", "skip": None, "failure_class": None})
    return row


def _already_known(case: dict, gold: str, state: dict, ratio: float) -> str | None:
    if case["mechanism_id"] in state["mechanisms"]:
        return case["mechanism_id"]
    for question, answer in state["questions"]:
        if near_duplicate(case["question"], question, ratio, gold, answer):
            return "lexical"
    return None


def empty_state(seed_rows: list[dict] | None = None) -> dict:
    state = {"mechanisms": set(), "questions": []}
    for row in seed_rows or []:
        if row.get("counted_unique"):
            state["mechanisms"].add(row["mechanism_id"])
            state["questions"].append((row["question"], row.get("verifier_answer") or row.get("answer") or row.get("gold")))
    return state

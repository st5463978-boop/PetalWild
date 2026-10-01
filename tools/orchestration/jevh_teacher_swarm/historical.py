"""Import clean-core chip failures, collapsed to unique mechanisms."""

from __future__ import annotations

from jevh_teacher_swarm.analysis.dedupe import legacy_mechanism


def collapse_historical(rows: list[dict], minimum: float = 0.90) -> tuple[list[dict], list[dict]]:
    grouped: dict[str, list[dict]] = {}
    for row in rows:
        if not row.get("counted_failure"):
            continue
        if row.get("jev_source") != "chip":
            continue
        confidence = row.get("jev_confidence")
        if not isinstance(confidence, (int, float)) or confidence < minimum:
            continue
        model = str(row.get("model") or "")
        if "ettin68m" not in model and "352c0f6d" not in model:
            continue
        grouped.setdefault(legacy_mechanism(row), []).append(row)
    unique = []
    dupes = []
    for mechanism, items in grouped.items():
        head, *rest = items
        unique.append(_row(head, mechanism, True))
        for item in rest:
            dupes.append(_row(item, mechanism, False))
    return unique, dupes


def _row(source: dict, mechanism: str, counted_unique: bool) -> dict:
    return {
        "id": source["id"],
        "origin": "jevh_clean_core",
        "mechanism_id": mechanism,
        "attack_family": source.get("family"),
        "kind": source.get("kind"),
        "question": source.get("question"),
        "answer": source.get("answer"),
        "verifier_answer": source.get("answer"),
        "gold": source.get("answer"),
        "jev_choice": source.get("jev_choice"),
        "jev_confidence": source.get("jev_confidence"),
        "jev_source": "chip",
        "model": source.get("model"),
        "latency_ms": source.get("latency_ms"),
        "chip_npu_ms": source.get("chip_npu_ms"),
        "decision_id": source.get("decision_id"),
        "counted_failure": counted_unique,
        "counted_unique": counted_unique,
        "training_eligible": False,
        "training_selected": False,
        "partition": "CANARY",
        "bucket": "ACCEPTED_FAILURE" if counted_unique else "REJECTED",
        "skip": None if counted_unique else "near_duplicate",
        "failure_class": "reasoning",
        "teacher_verifier_agree": True,
        "jev_wrong": True,
        "confident": True,
        "why": source.get("why"),
    }

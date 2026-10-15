"""Validate teacher claims against the interpreter, then shuffle."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

from jevh_clean_core.cases import FORBIDDEN_OPTIONS
from jevh_clean_core.score import fingerprint
from jevh_teacher_swarm.shuffle import mapping_ok, shuffle_options
from jevh_teacher_swarm.verifiers.deterministic.interpret import interpret

_NUM = re.compile(r"\d+(?:\.\d+)?")
PACKAGE = Path(__file__).resolve().parent


def tree(root: Path | None = None) -> dict[str, Path]:
    base = root or PACKAGE
    return {
        "root": base,
        "pending": base / "queue" / "pending.jsonl",
        "inflight": base / "queue" / "in_flight.jsonl",
        "accepted_failures": base / "corpus" / "accepted_failures.jsonl",
        "accepted_correct": base / "corpus" / "accepted_correct.jsonl",
        "rejected": base / "corpus" / "rejected.jsonl",
        "quarantine": base / "corpus" / "quarantine.jsonl",
        "attempts": base / "corpus" / "attempts.jsonl",
        "batch": base / "teachers" / "outputs" / "batch_001.jsonl",
        "status": base / "reports" / "current_status.md",
        "agreement": base / "reports" / "teacher_agreement.md",
        "families": base / "reports" / "failure_families.md",
    }


def _numbers(value):
    if isinstance(value, bool):
        return
    if isinstance(value, (int, float)):
        yield float(value)
        return
    if isinstance(value, dict):
        for item in value.values():
            yield from _numbers(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from _numbers(item)


def numbers_covered(question: str, facts: dict) -> bool:
    have = list(_numbers(facts))
    for raw in _NUM.findall(question):
        target = float(raw)
        if not any(abs(item - target) < 1e-9 for item in have):
            return False
    return True


def validate_case(case: dict) -> tuple[dict | None, str | None]:
    options = list(case.get("options") or [])
    claim = case.get("teacher_answer")
    if not 2 <= len(options) <= 6 or len(set(options)) != len(options):
        return None, "malformed_options"
    if claim not in options:
        return None, "teacher_answer_not_in_options"
    if any(str(option).strip().lower() in FORBIDDEN_OPTIONS for option in options):
        return None, "forbidden_option"
    if not str(case.get("question", "")).endswith("?"):
        return None, "malformed_question"
    if not numbers_covered(case["question"], case.get("facts") or {}):
        return None, "facts_miss_question_numbers"
    try:
        verified = interpret(case["rule"], case["facts"])
    except (KeyError, TypeError, ValueError) as exc:
        return None, f"verifier_error:{exc}"
    if verified != claim:
        return None, "teacher_verifier_disagree"
    if verified not in options:
        return None, "verifier_answer_not_in_options"
    prepared = dict(case)
    prepared["verifier_answer"] = verified
    prepared["teacher_verifier_agree"] = True
    prepared["teacher_answer_index"] = options.index(claim)
    prepared["partition"] = "CANARY" if _canary(case["id"]) else "TRAIN"
    prepared["training_eligible"] = False
    prepared["training_selected"] = False
    mapping = shuffle_options(options, verified, case["id"])
    if not mapping_ok(mapping):
        return None, "shuffle_map"
    prepared.update(mapping)
    prepared["fingerprint"] = fingerprint(
        {
            "kind": case["kind"],
            "question": case["question"],
            "options": options,
            "answer": verified,
        }
    )
    return prepared, None


def _canary(case_id: str) -> bool:
    digest = hashlib.sha256(case_id.encode()).hexdigest()
    return int(digest[:2], 16) % 5 == 0


def prepare_batch(cases: list[dict]) -> tuple[list[dict], list[dict]]:
    ready = []
    quarantined = []
    seen = set()
    for case in cases:
        if case["id"] in seen:
            quarantined.append({"id": case["id"], "reason": "duplicate_id", "bucket": "QUARANTINE"})
            continue
        seen.add(case["id"])
        prepared, reason = validate_case(case)
        if reason:
            quarantined.append({"id": case.get("id"), "reason": reason, "bucket": "QUARANTINE", "training_eligible": False})
            continue
        ready.append(prepared)
    return ready, quarantined

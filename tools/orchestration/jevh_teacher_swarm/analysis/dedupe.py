"""Normalised hashes and lexical near-duplicate checks.

Same gold answer plus high overlap counts as one failure.
A minimal pair with opposite gold answers can both count.
"""

from __future__ import annotations

import hashlib
import re
from difflib import SequenceMatcher

_TOKEN = re.compile(r"[a-z0-9]+")


def normalise(text: str) -> str:
    lowered = text.lower()
    lowered = re.sub(r"\d+(?:\.\d+)?", "#", lowered)
    words = _TOKEN.findall(lowered.replace("#", " # "))
    return " ".join(words)


def normalised_hash(text: str) -> str:
    return hashlib.sha256(normalise(text).encode()).hexdigest()[:16]


def similar(left: str, right: str) -> float:
    return SequenceMatcher(None, normalise(left), normalise(right)).ratio()


def near_duplicate(left: str, right: str, ratio: float, answer_left: str, answer_right: str) -> bool:
    if normalise(left) == normalise(right):
        return True
    if answer_left != answer_right:
        return False
    return similar(left, right) >= ratio


def legacy_mechanism(row: dict) -> str:
    """Collapse clean-core confident-wrong rows that share one bug."""
    kind = row.get("kind")
    answer = row.get("answer")
    family = row.get("family")
    if kind == "source_stale" and answer == "fresh":
        return "fresh_within_limit"
    if kind == "human_approval" and family == "spend_threshold" and answer == "required":
        return "approval_spend_over"
    if kind == "canonical_contradicted" and answer == "consistent":
        return "nonauthoritative_not_contradiction"
    return f"legacy:{row.get('id')}"

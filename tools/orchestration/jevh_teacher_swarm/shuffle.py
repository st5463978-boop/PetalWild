"""Reversible option shuffle.

original index → presented index → JEV index → original option.
"""

from __future__ import annotations

import hashlib
import random


def rng_for(case_id: str) -> random.Random:
    seed = int(hashlib.sha256(case_id.encode()).hexdigest()[:8], 16)
    return random.Random(seed)


def shuffle_options(options: list[str], answer: str, case_id: str) -> dict:
    if answer not in options:
        raise ValueError("answer not in options")
    order = list(range(len(options)))
    rng_for(case_id).shuffle(order)
    presented = [options[index] for index in order]
    original_to_presented = [0] * len(options)
    for presented_index, original_index in enumerate(order):
        original_to_presented[original_index] = presented_index
    answer_original = options.index(answer)
    return {
        "original_options": list(options),
        "presented_options": presented,
        "presented_to_original": order,
        "original_to_presented": original_to_presented,
        "answer": answer,
        "answer_original_index": answer_original,
        "answer_presented_index": original_to_presented[answer_original],
    }


def original_option(mapping: dict, presented_index: int) -> str:
    original_index = mapping["presented_to_original"][presented_index]
    return mapping["original_options"][original_index]


def mapping_ok(mapping: dict) -> bool:
    original = mapping["original_options"]
    presented = mapping["presented_options"]
    back = mapping["presented_to_original"]
    forward = mapping["original_to_presented"]
    if len(original) != len(presented) or sorted(back) != list(range(len(original))):
        return False
    for presented_index, original_index in enumerate(back):
        if presented[presented_index] != original[original_index]:
            return False
        if forward[original_index] != presented_index:
            return False
    answer = mapping["answer"]
    if presented[mapping["answer_presented_index"]] != answer:
        return False
    if original[mapping["answer_original_index"]] != answer:
        return False
    return original_option(mapping, mapping["answer_presented_index"]) == answer

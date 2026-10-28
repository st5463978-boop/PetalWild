"""Choice / Noul / Score decisions from one logit per option.

The three heads are prompt modes on the same scorer. Noul rewrites yes/no
options to the live student strings. Score returns the same softmax; the
caller reads `probs`.
"""
from __future__ import annotations

import time
from typing import Callable

from hailo.contract import QTYPES, decide_from_logits

Pair = tuple[list[int], list[int]]
Encode = Callable[[str, list[str], str | None, str], list[Pair]]
ScorePair = Callable[[list[int], list[int]], float]


def normalize_qtype(qtype: str | None, options: list[str]) -> str:
    if qtype in QTYPES:
        return qtype
    labs = []
    for option in options:
        text = str(option).strip().lower()
        if ":" in text:
            text = text.split(":", 1)[0].strip()
        labs.append(text)
    if len(options) == 2 and set(labs) == {"yes", "no"}:
        return "noul"
    return "choice"


def run_decision(
    question: str,
    options: list[str],
    encode: Encode,
    score_pair: ScorePair,
    context: str | None = None,
    qtype: str | None = None,
) -> dict:
    if len(options) < 2:
        raise ValueError("decide needs at least two options")
    mode = normalize_qtype(qtype, options)
    started = time.perf_counter()
    pairs = encode(question, [str(option) for option in options], context, mode)
    if len(pairs) != len(options):
        raise ValueError(f"encoder returned {len(pairs)} pairs for {len(options)} options")
    logits = [float(score_pair(ids, mask)) for ids, mask in pairs]
    body = decide_from_logits(logits, [str(option) for option in options])
    body["qtype"] = mode
    body["latency_ms"] = (time.perf_counter() - started) * 1e3
    return body

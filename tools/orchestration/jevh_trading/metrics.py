"""Accuracy, confident-mistake count, ECE, CPU latency."""

from __future__ import annotations

import time
from typing import Sequence

import numpy as np

from .config import CONFIDENT_MISTAKE_P, HOLD_LABELS


def softmax(x: np.ndarray) -> np.ndarray:
    z = x - x.max()
    e = np.exp(z)
    return e / e.sum()


def ece(confidences: Sequence[float], correct: Sequence[bool], n_bins: int = 10) -> float:
    conf = np.asarray(confidences, dtype=np.float64)
    ok = np.asarray(correct, dtype=np.float64)
    if conf.size == 0:
        return float("nan")
    bins = np.linspace(0.0, 1.0, n_bins + 1)
    tot = 0.0
    for i in range(n_bins):
        lo, hi = bins[i], bins[i + 1]
        if i == n_bins - 1:
            m = (conf >= lo) & (conf <= hi)
        else:
            m = (conf >= lo) & (conf < hi)
        if not m.any():
            continue
        tot += float(m.mean() * abs(ok[m].mean() - conf[m].mean()) * conf.size)
    return tot / conf.size


def decision_metrics(
    pred_idx: Sequence[int],
    gold_idx: Sequence[int],
    probs: Sequence[Sequence[float]],
    labels: Sequence[Sequence[str]] | None = None,
    *,
    p_star: float = CONFIDENT_MISTAKE_P,
) -> dict:
    pred = np.asarray(pred_idx, dtype=np.int64)
    gold = np.asarray(gold_idx, dtype=np.int64)
    n = pred.size
    correct = pred == gold
    acc = float(correct.mean()) if n else float("nan")
    conf = np.array([float(p[int(i)]) for p, i in zip(probs, pred)], dtype=np.float64)
    cm = int(((~correct) & (conf >= p_star)).sum())
    hold_correct = 0
    hold_n = 0
    if labels is not None:
        for labs, g, pr in zip(labels, gold, pred):
            hold = [j for j, lab in enumerate(labs) if lab in HOLD_LABELS]
            if not hold:
                continue
            hold_n += 1
            # trivial baseline: first HOLD/RIDE/WAIT on the menu
            b = hold[0]
            hold_correct += int(b == int(g))
    baseline = float(hold_correct / hold_n) if hold_n else float("nan")
    # majority-gold baseline on this split
    if n:
        vals, counts = np.unique(gold, return_counts=True)
        _ = vals
        maj = float(counts.max() / n)
    else:
        maj = float("nan")
    return {
        "n": int(n),
        "accuracy": acc,
        "confident_mistakes": cm,
        "confident_mistake_rate": float(cm / n) if n else float("nan"),
        "ece": ece(conf, correct),
        "mean_confidence": float(conf.mean()) if n else float("nan"),
        "hold_ride_baseline_n": int(hold_n),
        "hold_ride_baseline_acc": baseline,
        "beats_hold_ride_baseline": bool(acc > baseline) if hold_n else None,
        "note_majority_index_acc_unusable": maj,
    }


def cpu_latency_ms(fn, n_warmup: int, n: int) -> dict:
    for _ in range(n_warmup):
        fn()
    times = []
    for _ in range(n):
        t0 = time.perf_counter()
        fn()
        times.append((time.perf_counter() - t0) * 1e3)
    arr = np.asarray(times, dtype=np.float64)
    return {
        "n": n,
        "mean_ms": float(arr.mean()),
        "p50_ms": float(np.percentile(arr, 50)),
        "p95_ms": float(np.percentile(arr, 95)),
        "min_ms": float(arr.min()),
        "max_ms": float(arr.max()),
    }

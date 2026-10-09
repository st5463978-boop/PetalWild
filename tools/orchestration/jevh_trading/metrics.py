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


def agreement_breakdown(
    pred_idx: Sequence[int],
    gold_idx: Sequence[int],
    probs: Sequence[Sequence[float]],
    labels: Sequence[Sequence[str]],
    *,
    varied: Sequence[bool] | None = None,
    p_star: float = CONFIDENT_MISTAKE_P,
) -> dict:
    """Agreement-with-Jev plus per-menu-size and per-action slices."""
    base = decision_metrics(pred_idx, gold_idx, probs, labels, p_star=p_star)
    by_size: dict[str, dict] = {}
    by_action: dict[str, dict] = {}
    for i, (pr, g, labs) in enumerate(zip(pred_idx, gold_idx, labels)):
        k = str(len(labs))
        slot = by_size.setdefault(k, {"n": 0, "ok": 0})
        slot["n"] += 1
        slot["ok"] += int(int(pr) == int(g))
        lab = labs[int(g)] if 0 <= int(g) < len(labs) else "?"
        act = by_action.setdefault(lab, {"n": 0, "ok": 0})
        act["n"] += 1
        act["ok"] += int(int(pr) == int(g))
    base["by_menu_size"] = {
        k: {"n": v["n"], "accuracy": v["ok"] / v["n"] if v["n"] else None}
        for k, v in sorted(by_size.items(), key=lambda kv: int(kv[0]))
    }
    base["by_action"] = {
        k: {"n": v["n"], "accuracy": v["ok"] / v["n"] if v["n"] else None}
        for k, v in sorted(by_action.items(), key=lambda kv: -kv[1]["n"])
    }
    if varied is not None:
        for name, flag in (("varied", True), ("collapsed", False)):
            idx = [i for i, v in enumerate(varied) if bool(v) is flag]
            if not idx:
                base[f"{name}_n"] = 0
                base[f"{name}_accuracy"] = None
                continue
            ok = sum(int(int(pred_idx[i]) == int(gold_idx[i])) for i in idx)
            base[f"{name}_n"] = len(idx)
            base[f"{name}_accuracy"] = ok / len(idx)
    return base


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

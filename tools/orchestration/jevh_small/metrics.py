"""Held-out accuracy, teacher baseline, confident-mistake count, ECE, latency."""
from __future__ import annotations

import math
import time
from typing import Any

import numpy as np


CONF_THRESH = 0.65


def softmax(logits: np.ndarray) -> np.ndarray:
    x = np.asarray(logits, dtype=np.float64)
    x = x - x.max()
    e = np.exp(x)
    return e / e.sum()


def ece_score(confidences: list[float], correct: list[bool], n_bins: int = 10) -> float:
    if not confidences:
        return float("nan")
    conf = np.asarray(confidences, dtype=np.float64)
    acc = np.asarray(correct, dtype=np.float64)
    bins = np.linspace(0.0, 1.0, n_bins + 1)
    ece = 0.0
    n = len(conf)
    for i in range(n_bins):
        lo, hi = bins[i], bins[i + 1]
        if i == 0:
            sel = (conf >= lo) & (conf <= hi)
        else:
            sel = (conf > lo) & (conf <= hi)
        if not np.any(sel):
            continue
        ece += (sel.sum() / n) * abs(acc[sel].mean() - conf[sel].mean())
    return float(ece)


def summarize_preds(
    gold: list[int],
    pred: list[int],
    conf: list[float],
    teacher_pred: list[int | None],
    binary: list[bool],
    thresh: float = CONF_THRESH,
) -> dict[str, Any]:
    n = len(gold)
    ok = [int(p == g) for p, g in zip(pred, gold)]
    teacher_ok = []
    teacher_n = 0
    for t, g in zip(teacher_pred, gold):
        if t is None:
            continue
        teacher_n += 1
        teacher_ok.append(int(t == g))
    conf_mist = sum(1 for o, c in zip(ok, conf) if (not o) and c >= thresh)
    yn_idx = [i for i, b in enumerate(binary) if b]
    mc_idx = [i for i, b in enumerate(binary) if not b]

    def acc_at(idxs: list[int]) -> float | None:
        if not idxs:
            return None
        return float(sum(ok[i] for i in idxs) / len(idxs))

    def teacher_acc_at(idxs: list[int]) -> float | None:
        hits = [i for i in idxs if teacher_pred[i] is not None]
        if not hits:
            return None
        return float(sum(int(teacher_pred[i] == gold[i]) for i in hits) / len(hits))

    return {
        "n": n,
        "accuracy": float(sum(ok) / n) if n else None,
        "teacher_accuracy": float(sum(teacher_ok) / teacher_n) if teacher_n else None,
        "teacher_n": teacher_n,
        "confident_mistakes": conf_mist,
        "confident_mistake_rate": float(conf_mist / n) if n else None,
        "ece": ece_score(conf, [bool(v) for v in ok]),
        "mean_confidence": float(np.mean(conf)) if conf else None,
        "yesno": {
            "n": len(yn_idx),
            "accuracy": acc_at(yn_idx),
            "teacher_accuracy": teacher_acc_at(yn_idx),
            "confident_mistakes": sum(1 for i in yn_idx if (not ok[i]) and conf[i] >= thresh),
            "ece": ece_score([conf[i] for i in yn_idx], [bool(ok[i]) for i in yn_idx]) if yn_idx else None,
        },
        "multi": {
            "n": len(mc_idx),
            "accuracy": acc_at(mc_idx),
            "teacher_accuracy": teacher_acc_at(mc_idx),
            "confident_mistakes": sum(1 for i in mc_idx if (not ok[i]) and conf[i] >= thresh),
            "ece": ece_score([conf[i] for i in mc_idx], [bool(ok[i]) for i in mc_idx]) if mc_idx else None,
        },
        "threshold": thresh,
    }


def latency_stats(ms: list[float]) -> dict[str, float]:
    a = np.asarray(ms, dtype=np.float64)
    if a.size == 0:
        return {}
    return {
        "n": int(a.size),
        "mean_ms": float(a.mean()),
        "p50_ms": float(np.percentile(a, 50)),
        "p95_ms": float(np.percentile(a, 95)),
        "min_ms": float(a.min()),
        "max_ms": float(a.max()),
    }


class Timer:
    def __enter__(self):
        self.t0 = time.perf_counter()
        return self

    def __exit__(self, *exc):
        self.ms = (time.perf_counter() - self.t0) * 1e3
        return False

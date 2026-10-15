"""Beebots indicator ports (see trading_beebots_reference.md / indicators.ts).

Inputs are oldest-first. None of this places or routes orders.
"""

from __future__ import annotations

import math
from typing import Sequence

import numpy as np

from .config import DONCHIAN_LOOKBACKS


def ema(values: np.ndarray, period: int) -> np.ndarray:
    if values.size == 0:
        return values
    k = 2.0 / (period + 1)
    out = np.empty_like(values, dtype=np.float64)
    out[0] = values[0]
    for i in range(1, values.size):
        out[i] = values[i] * k + out[i - 1] * (1.0 - k)
    return out


def rsi_wilder(closes: np.ndarray, period: int = 14) -> float | None:
    if closes.size < period + 1:
        return None
    delta = np.diff(closes.astype(np.float64))
    gain = np.where(delta > 0, delta, 0.0)
    loss = np.where(delta < 0, -delta, 0.0)
    ag = float(gain[:period].mean())
    al = float(loss[:period].mean())
    for i in range(period, delta.size):
        ag = (ag * (period - 1) + gain[i]) / period
        al = (al * (period - 1) + loss[i]) / period
    if al == 0:
        return 50.0 if ag == 0 else 100.0
    return 100.0 - 100.0 / (1.0 + ag / al)


def atr_wilder(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> float | None:
    n = close.size
    if n < period + 1:
        return None
    tr = np.empty(n - 1, dtype=np.float64)
    for i in range(1, n):
        pc = close[i - 1]
        tr[i - 1] = max(high[i] - low[i], abs(high[i] - pc), abs(low[i] - pc))
    a = float(tr[:period].mean())
    for i in range(period, tr.size):
        a = (a * (period - 1) + tr[i]) / period
    return a


def bollinger_typical(
    high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 20, k: float = 2.0
) -> dict | None:
    if close.size < period:
        return None
    tp = (high[-period:] + low[-period:] + close[-period:]) / 3.0
    mid = float(tp.mean())
    sd = float(math.sqrt(float(((tp - mid) ** 2).mean())))
    upper = mid + k * sd
    lower = mid - k * sd
    last = float(close[-1])
    pct_b = 0.5 if upper == lower else (last - lower) / (upper - lower)
    width_pct = ((upper - lower) / mid) * 100.0 if mid else 0.0
    return {"mid": mid, "upper": upper, "lower": lower, "pctB": pct_b, "widthPct": width_pct}


def pct_change(frm: float | None, to: float | None) -> float | None:
    if frm is None or to is None or not (frm > 0):
        return None
    return ((to - frm) / frm) * 100.0


def zscore(latest: float, history: Sequence[float]) -> float | None:
    if len(history) < 5:
        return None
    xs = np.asarray(history, dtype=np.float64)
    m = float(xs.mean())
    sd = float(xs.std(ddof=0))
    if sd == 0:
        return 0.0
    return (latest - m) / sd


def realised_vol_pct(closes: np.ndarray, lookback: int, bars_per_year: int) -> float | None:
    if closes.size < lookback + 1:
        return None
    xs = closes[-(lookback + 1) :].astype(np.float64)
    r = np.diff(np.log(xs))
    m = float(r.mean())
    v = float(((r - m) ** 2).sum() / (r.size - 1))
    return math.sqrt(v * bars_per_year) * 100.0


def donchian_ensemble(
    closes: np.ndarray, lookbacks: Sequence[int] = DONCHIAN_LOOKBACKS
) -> dict:
    """Zarattini/Pagani/Barbon ensemble, mirrored for shorts (indicators.ts)."""
    long_on = 0
    short_on = 0
    slices_available = 0
    long_stops: list[float] = []
    short_stops: list[float] = []
    c = closes.astype(np.float64)
    n = c.size
    for L in lookbacks:
        if n < L + 1:
            continue
        slices_available += 1
        state = "off"
        stop = 0.0
        for i in range(L, n):
            window = c[i - L : i]
            hi = float(window.max())
            lo = float(window.min())
            mid = (hi + lo) / 2.0
            px = float(c[i])
            if state == "long":
                stop = max(stop, mid)
                if px < stop:
                    state = "off"
            elif state == "short":
                stop = min(stop, mid)
                if px > stop:
                    state = "off"
            if state != "long" and px > hi:
                state = "long"
                stop = mid
            elif state != "short" and px < lo:
                state = "short"
                stop = mid
        if state == "long":
            long_on += 1
            long_stops.append(stop)
        elif state == "short":
            short_on += 1
            short_stops.append(stop)
    score = long_on - short_on
    stops = long_stops if score > 0 else short_stops if score < 0 else []
    trail = float(sum(stops) / len(stops)) if stops else None
    return {
        "score": score,
        "longOn": long_on,
        "shortOn": short_on,
        "slicesAvailable": slices_available,
        "trailStop": trail,
    }


def trend_stats_4h(c4h_high: np.ndarray, c4h_low: np.ndarray, c4h_close: np.ndarray) -> dict:
    d = donchian_ensemble(c4h_close)
    last = float(c4h_close[-1]) if c4h_close.size else None
    a = atr_wilder(c4h_high, c4h_low, c4h_close, 14)
    ten: int = 0
    if c4h_close.size >= 60 and last is not None:
        w = c4h_close[-60:]
        if last >= float(w.max()):
            ten = 1
        elif last <= float(w.min()):
            ten = -1
    atr4h_pct = (a / last) * 100.0 if a is not None and last else None
    return {
        **d,
        "atr4hPct": atr4h_pct,
        "rv90Pct": realised_vol_pct(c4h_close, 90, 6 * 365),
        "tenDayExtreme": ten,
    }


def resample_4h(ts: np.ndarray, o: np.ndarray, h: np.ndarray, l: np.ndarray, c: np.ndarray, v: np.ndarray):
    """UTC 4h buckets from 15m bars. Last bucket may be a forming bar."""
    bucket = ts // 14400
    # group in order
    ob, hb, lb, cb, vb, tb = [], [], [], [], [], []
    i = 0
    n = ts.size
    while i < n:
        b = bucket[i]
        j = i + 1
        while j < n and bucket[j] == b:
            j += 1
        ob.append(float(o[i]))
        hb.append(float(h[i:j].max()))
        lb.append(float(l[i:j].min()))
        cb.append(float(c[j - 1]))
        vb.append(float(v[i:j].sum()))
        tb.append(int(ts[j - 1]))
        i = j
    return (
        np.asarray(tb, np.int64),
        np.asarray(ob, np.float64),
        np.asarray(hb, np.float64),
        np.asarray(lb, np.float64),
        np.asarray(cb, np.float64),
        np.asarray(vb, np.float64),
    )


def utc_day_ohlc(ts: np.ndarray, o: np.ndarray, h: np.ndarray, l: np.ndarray, c: np.ndarray, i: int):
    """Day open / prev range for Larry Williams breakout at bar i (UTC days)."""
    day = int(ts[i] // 86400)
    prev = day - 1
    day_mask = (ts // 86400) == day
    prev_mask = (ts // 86400) == prev
    idx_day = np.flatnonzero(day_mask)
    idx_prev = np.flatnonzero(prev_mask)
    if idx_day.size == 0:
        return None
    day_open = float(o[idx_day[0]])
    if idx_prev.size == 0:
        return {"dayOpen": day_open, "prevRange": None, "trigger": None}
    prev_range = float(h[idx_prev].max() - l[idx_prev].min())
    return {"dayOpen": day_open, "prevRange": prev_range, "trigger": day_open + 0.5 * prev_range}

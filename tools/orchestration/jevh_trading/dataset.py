"""Rebuild beebots-style states from 15m OHLCV and label menus by forward outcome.

Labels come from realised price paths (fees + stop). Paper decisions are eval-only.
Not financial advice. Offline research.
"""

from __future__ import annotations

import json
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

import numpy as np

from .config import (
    BEE_STRATEGY,
    BIZZY_BREAKOUT_COINS,
    BREEZY_COINS,
    COINS,
    FEE_BPS,
    HOLD_GOLD_CAP,
    HOLD_LABELS,
    HORIZON_BARS,
    MAX_EVAL_EXAMPLES,
    MAX_TRAIN_EXAMPLES,
    PURGE_BARS,
    SEED,
    STRIDE_BARS,
    TRAIN_FRAC,
    WARMUP_BARS,
)
from . import indicators as ind
from .paths import find_file


@dataclass
class Option:
    label: str
    text: str
    kind: str  # hold, open, close, switch, add, wait
    coin: str | None = None
    side: str | None = None  # long/short
    size: float = 1.0


@dataclass
class Example:
    ts: int
    bar_index: int
    bee: str
    text_a: str
    options: list[Option]
    gold_index: int
    outcomes: list[float]
    split: str
    source: str
    position: dict[str, Any]
    gold_label: str = ""
    paper_choice: str | None = None

    def to_json(self) -> dict[str, Any]:
        d = asdict(self)
        return d


def _r(x: float | None, n: int = 1) -> float | None:
    if x is None or not np.isfinite(x):
        return None
    return round(float(x), n)


def load_ohlcv(path: Path) -> dict[str, np.ndarray]:
    rows = json.loads(path.read_text())
    ts = np.array([int(r["t"]) for r in rows], dtype=np.int64)
    return {
        "t": ts,
        "o": np.array([float(r["o"]) for r in rows], dtype=np.float64),
        "h": np.array([float(r["h"]) for r in rows], dtype=np.float64),
        "l": np.array([float(r["l"]) for r in rows], dtype=np.float64),
        "c": np.array([float(r["c"]) for r in rows], dtype=np.float64),
        "v": np.array([float(r["v"]) for r in rows], dtype=np.float64),
    }


def load_markets() -> dict[str, dict[str, np.ndarray]]:
    out = {}
    for coin in COINS:
        p = find_file(f"market_{coin}_15min.json")
        out[coin] = load_ohlcv(p)
    # align on BTC timestamps
    t0 = out["BTC"]["t"]
    for coin, m in out.items():
        if m["t"].size != t0.size or not np.array_equal(m["t"], t0):
            raise ValueError(f"{coin} bars are not aligned with BTC")
    return out


class CoinFeat:
    """Per-bar features for one coin, computed oldest-first prefixes."""

    def __init__(self, coin: str, m: dict[str, np.ndarray]):
        self.coin = coin
        self.t = m["t"]
        self.o, self.h, self.l, self.c, self.v = m["o"], m["h"], m["l"], m["c"], m["v"]
        n = self.c.size
        self.rsi = np.full(n, np.nan)
        self.atr = np.full(n, np.nan)
        self.pct_b = np.full(n, np.nan)
        self.ret1h = np.full(n, np.nan)
        self.ret24h = np.full(n, np.nan)
        self.ret7d = np.full(n, np.nan)
        self.vol_z = np.full(n, np.nan)
        self.score = np.zeros(n, dtype=np.int16)
        self.long_on = np.zeros(n, dtype=np.int16)
        self.short_on = np.zeros(n, dtype=np.int16)
        self.slices = np.zeros(n, dtype=np.int16)
        self.trail = np.full(n, np.nan)
        self.rv90 = np.full(n, np.nan)
        self.at10d = np.zeros(n, dtype=np.int8)
        self.atr4h_pct = np.full(n, np.nan)
        self.day_open = np.full(n, np.nan)
        self.prev_range = np.full(n, np.nan)
        self.trigger = np.full(n, np.nan)
        self._compute()

    def _compute(self) -> None:
        n = self.c.size
        t4, _o4, h4, l4, c4, _ = ind.resample_4h(self.t, self.o, self.h, self.l, self.c, self.v)
        trend_at_4h: list[dict | None] = [None] * t4.size
        # Donchian is O(lookbacks * 4h_len^2); compute once per 4h bar, not per 15m bar.
        step = 1
        for k in range(4, t4.size, step):
            trend_at_4h[k] = ind.trend_stats_4h(h4[: k + 1], l4[: k + 1], c4[: k + 1])
        last_t = None
        for k in range(t4.size):
            if trend_at_4h[k] is not None:
                last_t = trend_at_4h[k]
            else:
                trend_at_4h[k] = last_t
        idx4 = np.searchsorted(t4, self.t, side="right") - 1
        # running Wilder RSI / ATR
        if n >= 15:
            delta = np.diff(self.c)
            gain = np.where(delta > 0, delta, 0.0)
            loss = np.where(delta < 0, -delta, 0.0)
            ag = float(gain[:14].mean())
            al = float(loss[:14].mean())
            self.rsi[14] = 50.0 if al == 0 and ag == 0 else (100.0 if al == 0 else 100.0 - 100.0 / (1.0 + ag / al))
            for i in range(15, n):
                ag = (ag * 13 + gain[i - 1]) / 14
                al = (al * 13 + loss[i - 1]) / 14
                self.rsi[i] = 50.0 if al == 0 and ag == 0 else (100.0 if al == 0 else 100.0 - 100.0 / (1.0 + ag / al))
            tr = np.maximum.reduce(
                [
                    self.h[1:] - self.l[1:],
                    np.abs(self.h[1:] - self.c[:-1]),
                    np.abs(self.l[1:] - self.c[:-1]),
                ]
            )
            a = float(tr[:14].mean())
            self.atr[14] = a
            for i in range(15, n):
                a = (a * 13 + tr[i - 1]) / 14
                self.atr[i] = a
        for i in range(19, n):
            bb = ind.bollinger_typical(self.h[: i + 1], self.l[: i + 1], self.c[: i + 1], 20)
            if bb:
                self.pct_b[i] = bb["pctB"]
        if n > 4:
            self.ret1h[4:] = (self.c[4:] / self.c[:-4] - 1.0) * 100.0
        if n > 96:
            self.ret24h[96:] = (self.c[96:] / self.c[:-96] - 1.0) * 100.0
        if n > 672:
            self.ret7d[672:] = (self.c[672:] / self.c[:-672] - 1.0) * 100.0
        hv = np.convolve(self.v, np.ones(4), mode="valid")  # 1h volume ending at each bar >= 3
        for i in range(3, n):
            hist = hv[max(0, i - 3 - 167) : i - 3 + 1]
            if hist.size >= 24:
                z = ind.zscore(float(hv[i - 3]), hist.tolist())
                if z is not None:
                    self.vol_z[i] = z
        for i in range(n):
            k = int(idx4[i])
            ts = trend_at_4h[k] if k >= 0 else None
            if ts:
                self.score[i] = ts["score"]
                self.long_on[i] = ts["longOn"]
                self.short_on[i] = ts["shortOn"]
                self.slices[i] = ts["slicesAvailable"]
                if ts["trailStop"] is not None:
                    self.trail[i] = ts["trailStop"]
                if ts["rv90Pct"] is not None:
                    self.rv90[i] = ts["rv90Pct"]
                self.at10d[i] = ts["tenDayExtreme"]
                if ts["atr4hPct"] is not None:
                    self.atr4h_pct[i] = ts["atr4hPct"]
        day_id = self.t // 86400
        day_open_map: dict[int, float] = {}
        day_range_map: dict[int, float] = {}
        i0 = 0
        while i0 < n:
            d = int(day_id[i0])
            i1 = i0 + 1
            while i1 < n and int(day_id[i1]) == d:
                i1 += 1
            day_open_map[d] = float(self.o[i0])
            day_range_map[d] = float(self.h[i0:i1].max() - self.l[i0:i1].min())
            self.day_open[i0:i1] = day_open_map[d]
            prev_r = day_range_map.get(d - 1)
            if prev_r is not None:
                self.prev_range[i0:i1] = prev_r
                self.trigger[i0:i1] = day_open_map[d] + 0.5 * prev_r
            i0 = i1

    def row_breezy(self, i: int) -> list:
        atr_px = None
        if np.isfinite(self.atr4h_pct[i]):
            atr_px = self.c[i] * self.atr4h_pct[i] / 100.0
        stop_dist = None
        if np.isfinite(self.trail[i]) and atr_px:
            stop_dist = abs(self.c[i] - self.trail[i]) / atr_px
        return [
            int(self.score[i]),
            int(self.long_on[i]),
            int(self.short_on[i]),
            int(self.slices[i]),
            _r(stop_dist, 1),
            _r(self.rv90[i] if np.isfinite(self.rv90[i]) else None, 0),
            int(self.at10d[i]),
            _r(self.ret24h[i] if np.isfinite(self.ret24h[i]) else None, 1),
            None,  # fund_z unknown in OHLCV
        ]

    def row_boozy(self, i: int) -> list:
        return [
            _r(self.ret1h[i] if np.isfinite(self.ret1h[i]) else None, 1),
            _r(self.ret24h[i] if np.isfinite(self.ret24h[i]) else None, 0),
            _r(self.ret7d[i] if np.isfinite(self.ret7d[i]) else None, 0),
            _r(self.vol_z[i] if np.isfinite(self.vol_z[i]) else None, 1),
            None,
            0,  # spread unknown; majors treated as in-gate
            None,
        ]


def _fmt_row(cols: list[str], vals: list) -> str:
    bits = []
    for c, v in zip(cols, vals):
        bits.append(f"{c}={v if v is not None else 'na'}")
    return " ".join(bits)


def _text_a(bee: str, me: str, coin_lines: list[str]) -> str:
    q = BEE_STRATEGY[bee] + " Pick your next move."
    body = me + "\n" + "\n".join(coin_lines)
    return f"[choice] {q}\n{body}"


def _fee() -> float:
    return FEE_BPS / 1e4


def _atr_unit(feat: CoinFeat, i: int) -> float:
    a = feat.atr[i]
    px = feat.c[i]
    if not np.isfinite(a) or not (px > 0):
        return 1.0
    return max(a / px, 1e-6)


def sim_trade(
    feat: CoinFeat,
    i0: int,
    side: str,
    entry: float,
    stop: float | None,
    horizon: int,
    fee_entry: bool,
    fee_exit: bool,
) -> float:
    """Net return (fraction of entry) over horizon, stop on high/low of later bars."""
    i1 = min(i0 + horizon, feat.c.size - 1)
    if i1 <= i0:
        return 0.0
    exit_px = float(feat.c[i1])
    stopped = False
    for i in range(i0 + 1, i1 + 1):
        if stop is None:
            continue
        if side == "long" and feat.l[i] <= stop:
            exit_px = float(stop)
            stopped = True
            break
        if side == "short" and feat.h[i] >= stop:
            exit_px = float(stop)
            stopped = True
            break
    sgn = 1.0 if side == "long" else -1.0
    ret = sgn * (exit_px - entry) / entry
    if fee_entry:
        ret -= _fee()
    if fee_exit or stopped:
        ret -= _fee()
    _ = stopped
    return ret


def outcome_of(opt: Option, feat_map: dict[str, CoinFeat], pos: dict, i: int, horizon: int) -> float:
    """Risk-adjusted forward outcome in ATR units of the relevant coin."""

    def adj(coin: str, raw: float) -> float:
        return raw / _atr_unit(feat_map[coin], i)

    if opt.kind in ("hold", "wait"):
        if not pos.get("coin"):
            return 0.0
        f = feat_map[pos["coin"]]
        raw = sim_trade(
            f, i, pos["side"], float(pos["entry_px"]), pos.get("stop_px"), horizon, False, False
        )
        return adj(pos["coin"], raw)
    if opt.kind == "close":
        if not pos.get("coin"):
            return 0.0
        # realise now: pay exit fee, then flat
        return adj(pos["coin"], -_fee())
    if opt.kind in ("open", "switch"):
        raw = 0.0
        if opt.kind == "switch" and pos.get("coin"):
            raw -= _fee()  # close current
        f = feat_map[opt.coin]  # type: ignore[index]
        stop = _stop_for(opt, f, i, float(f.c[i]))
        raw += sim_trade(f, i, opt.side, float(f.c[i]), stop, horizon, True, True)  # type: ignore[arg-type]
        return adj(opt.coin, raw)  # type: ignore[arg-type]
    if opt.kind == "add":
        if not pos.get("coin"):
            return 0.0
        f = feat_map[pos["coin"]]
        hold = sim_trade(
            f, i, pos["side"], float(pos["entry_px"]), pos.get("stop_px"), horizon, False, False
        )
        add = sim_trade(
            f, i, pos["side"], float(f.c[i]), pos.get("stop_px"), horizon, True, True
        )
        # existing 1x + extra 0.5x
        raw = hold + 0.5 * add
        return adj(pos["coin"], raw)
    return 0.0


def _stop_for(opt: Option, f: CoinFeat, i: int, entry: float) -> float | None:
    if opt.kind not in ("open", "switch") or opt.side is None:
        return None
    if opt.label.startswith("BREAKOUT"):
        do = f.day_open[i]
        return float(do) if np.isfinite(do) else None
    if opt.label.startswith("APE_") or opt.label == "FLIP_SHORT" or (
        opt.coin == f.coin and opt.label.startswith(("LONG_", "SHORT_"))
    ):
        # boozy: 3 x ATR(1h) ~ 6 x ATR(15m); breezy: 2 x ATR(4h)
        if opt.label.startswith(("APE_", "FLIP")):
            a = f.atr[i]
            if not np.isfinite(a):
                return None
            dist = 3.0 * 2.0 * a
            return entry - dist if opt.side == "long" else entry + dist
    a4 = f.atr4h_pct[i]
    if np.isfinite(a4):
        dist = entry * (a4 / 100.0) * 2.0
        return entry - dist if opt.side == "long" else entry + dist
    a = f.atr[i]
    if not np.isfinite(a):
        return None
    dist = 2.0 * a
    return entry - dist if opt.side == "long" else entry + dist


def _gold(outcomes: list[float]) -> int:
    return int(np.argmax(np.asarray(outcomes, dtype=np.float64)))


def _pack(bee: str, i: int, ts: int, me: str, lines: list[str], opts: list[Option], pos: dict, feat_map, horizon: int, source: str, split: str) -> Example:
    outs = [outcome_of(o, feat_map, pos, i, horizon) for o in opts]
    g = _gold(outs)
    return Example(
        ts=int(ts),
        bar_index=i,
        bee=bee,
        text_a=_text_a(bee, me, lines),
        options=opts,
        gold_index=g,
        gold_label=opts[g].label,
        outcomes=outs,
        split=split,
        source=source,
        position=pos,
    )


def _zs(xs: list[float]):
    m = sum(xs) / max(len(xs), 1)
    var = sum((x - m) ** 2 for x in xs) / max(len(xs), 1)
    sd = math_sqrt(var) or 1.0

    def f(x: float) -> float:
        return (x - m) / sd

    return f


def math_sqrt(x: float) -> float:
    return float(np.sqrt(x)) if x > 0 else 0.0


def rank_boozy(feats: dict[str, CoinFeat], i: int) -> list[str]:
    pool = []
    for coin, f in feats.items():
        if not np.isfinite(f.ret24h[i]):
            continue
        r7 = f.ret7d[i] if np.isfinite(f.ret7d[i]) else f.ret24h[i]
        pool.append((coin, float(f.ret24h[i]), float(r7), float(f.vol_z[i]) if np.isfinite(f.vol_z[i]) else 0.0))
    if not pool:
        return list(COINS)
    z24 = _zs([p[1] for p in pool])
    z7 = _zs([p[2] for p in pool])
    scored = []
    for coin, r24, r7, attn in pool:
        scored.append((z7(r7) + 0.1 * z24(r24) + 0.3 * max(0.0, attn), coin))
    scored.sort(reverse=True)
    return [c for _, c in scored]


def breezy_examples(i: int, feats: dict[str, CoinFeat], split: str, rng: np.random.Generator, horizon: int) -> list[Example]:
    ts = int(feats["BTC"].t[i])
    cols = ["score", "long_on", "short_on", "slices", "stop_dist_atr", "rv90_pct", "at_10d", "r24h_pct", "fund_z"]
    lines = [f"{c} " + _fmt_row(cols, feats[c].row_breezy(i)) for c in BREEZY_COINS]
    out: list[Example] = []
    # flat menu
    opts = []
    for c in BREEZY_COINS:
        for side in ("long", "short"):
            lab = f"{side.upper()}_{c}"
            opts.append(Option(lab, f"{lab}: open {side} {c}", "open", c, side, 1.0))
    me = "me: pos=flat trades=0/3"
    out.append(_pack("breezy", i, ts, me, lines, opts, {"coin": None}, feats, horizon, "replay", split))
    # positioned variants (at most 2)
    variants = []
    for c in BREEZY_COINS:
        for side in ("long", "short"):
            look = int(rng.choice([8, 32, 64]))
            j = i - look
            if j < WARMUP_BARS:
                continue
            f = feats[c]
            entry = float(f.c[j])
            stop = _stop_for(Option(f"{side.upper()}_{c}", "", "open", c, side), f, j, entry)
            upl = (1 if side == "long" else -1) * (float(f.c[i]) - entry) / entry
            variants.append((c, side, entry, stop, look, upl))
    if variants:
        pick = rng.choice(len(variants), size=min(2, len(variants)), replace=False)
        for k in np.atleast_1d(pick):
            c, side, entry, stop, look, upl = variants[int(k)]
            pos = {"coin": c, "side": side, "entry_px": entry, "stop_px": stop, "opened_index": i - look}
            other = "ETH" if c == "BTC" else "BTC"
            oside = "long" if feats[other].score[i] >= 0 else "short"
            flip = "short" if side == "long" else "long"
            opts = [
                Option("HOLD_WINNER", f"HOLD_WINNER: keep {side} {c}", "hold", c, side),
                Option(f"{flip.upper()}_{c}", f"{flip.upper()}_{c}: flip {c}", "switch", c, flip),
                Option("SWITCH", f"SWITCH: close, go {oside} {other}", "switch", other, oside),
            ]
            if upl < 0:
                opts.append(Option("TRIM_HALF", "TRIM_HALF: take half off (treated as partial close)", "close", c, side, 0.5))
            me = f"me: pos={side} {c} upl_frac={upl:.3f} held_bars={look} trades=1/3"
            out.append(_pack("breezy", i, ts, me, lines, opts, pos, feats, horizon, "replay", split))
    return out


def boozy_examples(i: int, feats: dict[str, CoinFeat], split: str, rng: np.random.Generator, horizon: int) -> list[Example]:
    ts = int(feats["BTC"].t[i])
    cols = ["r1h_pct", "r24h_pct", "r7d_pct", "attn_z", "oi1h_pct", "spread_bp", "vol_musd"]
    ranked = rank_boozy(feats, i)
    top = ranked[:3]
    lines = [f"{c} " + _fmt_row(cols, feats[c].row_boozy(i)) for c in top]
    out: list[Example] = []
    opts = [
        Option(f"APE_{c}", f"APE_{c}: #{k+1} momentum", "open", c, "long", 0.5)
        for k, c in enumerate(top)
    ]
    me = "me: pos=flat trades=0/8 attn=volume_z"
    out.append(_pack("boozy", i, ts, me, lines, opts, {"coin": None}, feats, horizon, "replay", split))
    # one open position on the current #1, held various lengths
    if not top:
        return out
    c = top[0]
    look = int(rng.choice([8, 32, 96]))
    j = i - look
    if j < WARMUP_BARS:
        return out
    f = feats[c]
    entry = float(f.c[j])
    stop = _stop_for(Option(f"APE_{c}", "", "open", c, "long"), f, j, entry)
    pos = {"coin": c, "side": "long", "entry_px": entry, "stop_px": stop, "opened_index": j}
    upl = (float(f.c[i]) - entry) / entry
    opts = [Option("RIDE", f"RIDE: keep long {c}", "hold", c, "long")]
    if look >= 96:  # 24h * 4? 96 bars = 24h. Unlock bail/switch after 24h.
        opts.append(Option("BAIL", f"BAIL: close {c} now", "close", c, "long"))
        if len(top) > 1 and top[1] != c:
            opts.append(Option("SWITCH_COIN", f"SWITCH_COIN: close, ape {top[1]}", "switch", top[1], "long", 0.5))
        if np.isfinite(f.ret1h[i]) and f.ret1h[i] < 0:
            opts.append(Option("FLIP_SHORT", f"FLIP_SHORT: reverse {c}", "switch", c, "short", 0.5))
    atr1h = 2.0 * f.atr[i] if np.isfinite(f.atr[i]) else None
    run_atr = ((float(f.c[i]) - entry) / atr1h) if atr1h else 0.0
    if run_atr >= 1.0:
        opts.append(Option("DOUBLE_DOWN", f"DOUBLE_DOWN: add 0.5x (run {run_atr:.1f} ATR)", "add", c, "long", 0.5))
    if len(opts) < 2:
        opts.append(Option("BAIL", f"BAIL: close {c} now", "close", c, "long"))
    me = f"me: pos=long {c} upl_frac={upl:.3f} held_bars={look} trades=1/8"
    out.append(_pack("boozy", i, ts, me, lines, opts, pos, feats, horizon, "replay", split))
    return out


def bizzy_examples(i: int, feats: dict[str, CoinFeat], split: str, rng: np.random.Generator, horizon: int) -> list[Example]:
    ts = int(feats["BTC"].t[i])
    triggered = []
    lines = []
    for c in BIZZY_BREAKOUT_COINS:
        f = feats[c]
        trig = f.trigger[i] if np.isfinite(f.trigger[i]) else None
        to_pct = None if trig is None else ((trig - f.c[i]) / f.c[i]) * 100.0
        day_move = None
        if np.isfinite(f.day_open[i]) and f.day_open[i] > 0:
            day_move = ((f.c[i] / f.day_open[i]) - 1.0) * 100.0
        lines.append(
            f"{c} to_trigger_pct={_r(to_pct, 2)} day_move_pct={_r(day_move, 2)} "
            f"r1h_pct={_r(f.ret1h[i] if np.isfinite(f.ret1h[i]) else None, 1)}"
        )
        if to_pct is not None and to_pct <= 0:
            triggered.append(c)
    out: list[Example] = []
    opts: list[Option] = []
    for c in triggered:
        opts.append(Option(f"BREAKOUT_{c}", f"BREAKOUT_{c}: through trigger, go long", "open", c, "long", 1.0))
    opts.append(Option("WAIT", "WAIT: not convinced, keep waiting", "wait"))
    if len(opts) >= 2:
        me = "me: pos=flat trades=0/1 waiting_breakout"
        out.append(_pack("bizzy", i, ts, me, lines, opts, {"coin": None}, feats, horizon, "replay", split))
    if triggered:
        c = str(rng.choice(triggered))
        look = int(rng.choice([4, 16, 32]))
        j = i - look
        if j >= WARMUP_BARS:
            f = feats[c]
            entry = float(f.c[j])
            stop = float(f.day_open[i]) if np.isfinite(f.day_open[i]) else None
            pos = {"coin": c, "side": "long", "entry_px": entry, "stop_px": stop, "opened_index": j}
            upl = (float(f.c[i]) - entry) / entry
            opts = [Option("HOLD", f"HOLD: ride {c} to the day close", "hold", c, "long")]
            if upl < 0:
                opts.append(Option("CUT_LOSS", f"CUT_LOSS: breakout failing, close {c}", "close", c, "long"))
            else:
                opts.append(Option("CUT_LOSS", f"CUT_LOSS: close {c} anyway", "close", c, "long"))
            me = f"me: pos=long {c} upl_frac={upl:.3f} held_bars={look} trades=1/1"
            out.append(_pack("bizzy", i, ts, me, lines, opts, pos, feats, horizon, "replay", split))
    return out


def _assign_splits(n_bars: int, warmup: int, horizon: int, purge: int, train_frac: float) -> dict[int, str]:
    usable = list(range(warmup, n_bars - horizon))
    cut = int(len(usable) * train_frac)
    train_last = usable[cut - 1] if cut else usable[0]
    eval_first = train_last + purge
    out: dict[int, str] = {}
    for i in usable:
        if i <= train_last:
            out[i] = "train"
        elif i >= eval_first:
            out[i] = "eval"
        else:
            out[i] = "purge"
    return out


def build_replay(
    feats: dict[str, CoinFeat],
    *,
    seed: int = SEED,
    stride: int = STRIDE_BARS,
    warmup: int = WARMUP_BARS,
    horizon: int = HORIZON_BARS,
    purge: int = PURGE_BARS,
    train_frac: float = TRAIN_FRAC,
) -> list[Example]:
    n = feats["BTC"].c.size
    warmup = min(warmup, max(64, n // 3))
    horizon = min(horizon, max(4, n // 10))
    purge = min(purge, max(4, n // 10))
    splits = _assign_splits(n, warmup, horizon, purge, train_frac)
    rng = np.random.default_rng(seed)
    examples: list[Example] = []
    for i in range(warmup, n - horizon, stride):
        split = splits.get(i)
        if split not in ("train", "eval"):
            continue
        examples.extend(breezy_examples(i, feats, split, rng, horizon))
        examples.extend(boozy_examples(i, feats, split, rng, horizon))
        examples.extend(bizzy_examples(i, feats, split, rng, horizon))
    return examples


def downsample_train(examples: list[Example], *, seed: int = SEED, hold_cap: float = HOLD_GOLD_CAP, max_n: int = MAX_TRAIN_EXAMPLES) -> list[Example]:
    rng = np.random.default_rng(seed)
    train = [e for e in examples if e.split == "train"]
    hold = [e for e in train if e.gold_label in HOLD_LABELS]
    rest = [e for e in train if e.gold_label not in HOLD_LABELS]
    cap = int(len(rest) * hold_cap / max(1e-6, 1.0 - hold_cap)) if rest else len(hold)
    if len(hold) > cap:
        idx = rng.choice(len(hold), size=cap, replace=False)
        hold = [hold[int(i)] for i in idx]
    merged = rest + hold
    rng.shuffle(merged)
    if len(merged) > max_n:
        merged = merged[:max_n]
    evals = [e for e in examples if e.split == "eval"]
    if len(evals) > MAX_EVAL_EXAMPLES:
        idx = rng.choice(len(evals), size=MAX_EVAL_EXAMPLES, replace=False)
        evals = [evals[int(i)] for i in sorted(idx)]
    return merged + evals


def paper_examples() -> list[Example]:
    p = find_file("trading_paper_decisions.jsonl", required=False)
    if p is None:
        return []
    out: list[Example] = []
    with p.open() as f:
        for line in f:
            r = json.loads(line)
            menu = r.get("menu") or []
            choice = r.get("choice")
            if not isinstance(menu, list) or len(menu) < 2:
                continue
            bee_id = r.get("bee")
            state = r.get("state") or {}
            cols = (state.get("coins") or {}).get("cols") or []
            if "score" in cols:
                bee = "breezy"
            else:
                bee = "boozy"
            me = "me: " + " ".join(f"{k}={v}" for k, v in (state.get("me") or {}).items())
            lines = []
            rows = (state.get("coins") or {}).get("rows") or {}
            for coin, vals in rows.items():
                lines.append(f"{coin} " + _fmt_row(list(cols), list(vals)))
            opts = [Option(str(lab), f"{lab}: menu option", "hold" if str(lab) in HOLD_LABELS else "open") for lab in menu]
            gold = 0
            if choice in menu:
                gold = menu.index(choice)
            elif choice is None:
                continue
            out.append(
                Example(
                    ts=int(r.get("ts_ms") or 0) // 1000,
                    bar_index=-1,
                    bee=bee,
                    text_a=_text_a(bee, me, lines),
                    options=opts,
                    gold_index=gold,
                    gold_label=str(choice),
                    outcomes=[0.0] * len(opts),
                    split="paper",
                    source="paper",
                    position={"bee_id": bee_id, "raw_pos": (state.get("me") or {}).get("pos")},
                    paper_choice=str(choice) if choice is not None else None,
                )
            )
    return out


def label_distribution(examples: Iterable[Example]) -> dict[str, int]:
    return dict(Counter(e.gold_label for e in examples).most_common())


def split_counts(examples: Iterable[Example]) -> dict[str, int]:
    return dict(Counter(e.split for e in examples))


def write_jsonl(path: Path, examples: list[Example]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as f:
        for e in examples:
            f.write(json.dumps(e.to_json()) + "\n")

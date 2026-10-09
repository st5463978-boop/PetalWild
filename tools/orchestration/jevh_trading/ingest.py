"""Ingest a growing beebots decision log and turn it into a Jev-distill split.

Gold is Jev's `choice` (plus `probabilities` as soft targets).
Single-option menus are dropped from training and kept only for format checks.
Not financial advice. Offline only. Does not call any exchange or the beebots engine.
"""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any, Iterable

from .config import BEE_TAG, HOLD_LABELS, SEED
from .paths import find_file

PURGE_MS_DEFAULT = 5 * 60 * 1000  # 5 minutes
TRAIN_FRAC = 0.70
DEV_FRAC = 0.15  # of the remainder after train; eval is the rest after purge

# Rough data needed before claiming a cost-free Jev stand-in.
NEED = {
    "multi_option_unique": 2000,
    "non_hold_gold": 400,
    "per_action_gold": 50,
    "calendar_days": 14,
    "note": (
        "A 68m student can copy a collapsed HOLD_WINNER teacher from a few hundred "
        "near-duplicate ticks. Mimicking discretionary Jev (when to leave HOLD, which "
        "APE_*, when to SWITCH) wants thousands of *varied* multi-option rows, with "
        "each offered action as gold at least ~50 times, over more than one regime."
    ),
}


def _canon(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), default=str)


def state_hash(state: Any) -> str:
    return hashlib.sha1(_canon(state).encode()).hexdigest()[:16]


def bee_style(row: dict) -> str:
    menu = row.get("menu") or []
    if any(str(x).startswith("BREAKOUT") or str(x) in ("WAIT", "CUT_LOSS") for x in menu):
        return "bizzy"
    cols = ((row.get("state") or {}).get("coins") or {}).get("cols") or []
    if "score" in cols or "long_on" in cols:
        return "breezy"
    return "boozy"


# Underscores explode under the ettin BPE (upl_r → 3 tokens). Keep keys short.
_KEY = {
    "upl_r": "upl",
    "at_stop_usd": "stopUsd",
    "held_min": "held",
    "flat_min": "flat",
    "fee_left": "fee",
    "long_on": "L",
    "short_on": "S",
    "slices": "sl",
    "stop_dist_atr": "stop",
    "rv90_pct": "rv90",
    "at_10d": "at10",
    "r24h_pct": "r24",
    "r1h_pct": "r1h",
    "r7d_pct": "r7d",
    "attn_z": "attn",
    "oi1h_pct": "oi",
    "spread_bp": "spr",
    "vol_musd": "vol",
    "fund_z": "fund",
    "score": "sc",
}


def _kv(k: Any, v: Any) -> str | None:
    if v is None or v == "na":
        return None
    return f"{_KEY.get(str(k), k)}={v}"


def compact_state(state: Any) -> str:
    if not isinstance(state, dict):
        return _canon(state)
    me = state.get("me") or {}
    me_bits = [b for k, v in me.items() if (b := _kv(k, v))]
    coins = state.get("coins") or {}
    cols = list(coins.get("cols") or [])
    rows = coins.get("rows") or {}
    lines = []
    if me_bits:
        lines.append("me: " + " ".join(me_bits))
    extra = {k: v for k, v in state.items() if k not in ("me", "coins", "utc")}
    extra_bits = [b for k, v in extra.items() if (b := _kv(k, v))]
    if extra_bits:
        lines.append("meta: " + " ".join(extra_bits))
    for coin, vals in rows.items():
        seq = list(vals) if isinstance(vals, (list, tuple)) else [vals]
        bits = [b for c, v in zip(cols, seq) if (b := _kv(c, v))]
        lines.append(f"{coin} " + " ".join(bits) if bits else str(coin))
    return "\n".join(lines)


def text_a_for(row: dict) -> str:
    style = bee_style(row)
    q = BEE_TAG.get(style, style)
    ctx = compact_state(row.get("state") or {})
    return f"[choice] {q}\n{ctx}"


def align_probs(menu: list[str], probabilities: Any, choice: str) -> list[float]:
    probs = probabilities if isinstance(probabilities, dict) else {}
    out = []
    for lab in menu:
        try:
            out.append(float(probs.get(lab, 0.0) or 0.0))
        except (TypeError, ValueError):
            out.append(0.0)
    s = sum(out)
    if s <= 0:
        out = [1.0 if lab == choice else 0.0 for lab in menu]
        s = sum(out) or 1.0
    return [x / s for x in out]


def is_varied(menu: list[str], choice: str | None) -> bool:
    """Genuinely varied: more than a hold-vs-one-flip wall, or gold is not HOLD/RIDE."""
    if choice and choice not in HOLD_LABELS:
        return True
    holdish = [m for m in menu if m in HOLD_LABELS]
    if len(menu) <= 1:
        return False
    # HOLD_WINNER + LONG_BTC + SWITCH is the collapsed breezy menu in this log.
    if set(menu) <= {"HOLD_WINNER", "LONG_BTC", "SWITCH", "RIDE", "HOLD", "WAIT"}:
        return False
    return len(menu) - len(holdish) >= 2


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def discover_logs(extra: Iterable[str] | None = None, *, include_default: bool = True) -> list[Path]:
    found: list[Path] = []
    p = find_file("trading_paper_decisions.jsonl", required=False) if include_default else None
    if p:
        found.append(p)
    for raw in extra or []:
        q = Path(raw)
        if q.is_file():
            found.append(q)
    # unique, preserve order
    out, seen = [], set()
    for x in found:
        k = str(x.resolve())
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out


def parse_row(r: dict, source: str) -> dict | None:
    menu = r.get("menu")
    if not isinstance(menu, list) or not menu:
        return None
    menu = [str(x) for x in menu]
    choice = r.get("choice")
    ts = r.get("ts_ms") or r.get("ts") or 0
    try:
        ts = int(ts)
    except (TypeError, ValueError):
        ts = 0
    err = r.get("jev_error")
    rec = {
        "ts_ms": ts,
        "bee": str(r.get("bee") or ""),
        "bee_style": bee_style(r),
        "menu": menu,
        "choice": None if choice is None else str(choice),
        "probabilities": r.get("probabilities") if isinstance(r.get("probabilities"), dict) else {},
        "confidence": r.get("confidence"),
        "conviction": r.get("conviction"),
        "state": r.get("state") or {},
        "action": r.get("action"),
        "vetoed_by": r.get("vetoed_by"),
        "forced_by": r.get("forced_by"),
        "status": r.get("status"),
        "jev_error": err,
        "source": source,
        "n_options": len(menu),
        "single_option": len(menu) < 2,
        "id": r.get("id"),
    }
    rec["state_hash"] = state_hash({"bee": rec["bee"], "menu": menu, "state": rec["state"]})
    rec["varied"] = is_varied(menu, rec["choice"])
    rec["text_a"] = text_a_for(r)
    rec["option_texts"] = list(menu)
    rec["usable_train"] = (
        not rec["single_option"]
        and rec["choice"] in menu
        and not err
    )
    if rec["usable_train"]:
        rec["gold"] = menu.index(rec["choice"])
        rec["gold_label"] = rec["choice"]
        rec["probs"] = align_probs(menu, rec["probabilities"], rec["choice"])
    return rec


def ingest(
    extra_logs: Iterable[str] | None = None,
    *,
    purge_ms: int = PURGE_MS_DEFAULT,
    train_frac: float = TRAIN_FRAC,
    seed: int = SEED,
    include_default: bool = True,
) -> dict:
    _ = seed  # reserved for future shuffle of equal-timestamp rows
    logs = discover_logs(extra_logs, include_default=include_default)
    raw: list[dict] = []
    for path in logs:
        for r in load_jsonl(path):
            rec = parse_row(r, str(path))
            if rec:
                raw.append(rec)
    raw.sort(key=lambda r: (r["ts_ms"], str(r.get("id"))))

    # exact state+menu+bee dedupe, keep latest
    latest: dict[str, dict] = {}
    for rec in raw:
        latest[rec["state_hash"]] = rec
    unique = sorted(latest.values(), key=lambda r: (r["ts_ms"], str(r.get("id"))))

    format_check = [r for r in unique if r["single_option"]]
    unusable = [r for r in unique if (not r["single_option"]) and not r["usable_train"]]
    multi = [r for r in unique if r["usable_train"]]

    n = len(multi)
    i_train = int(n * train_frac)
    i_dev = int(n * (train_frac + DEV_FRAC))
    if n >= 3:
        i_train = max(1, min(i_train, n - 2))
        i_dev = max(i_train + 1, min(i_dev, n - 1))
    train, dev, rest = multi[:i_train], multi[i_train:i_dev], multi[i_dev:]
    cut_ts = 0
    if train:
        cut_ts = train[-1]["ts_ms"]
    if dev:
        cut_ts = max(cut_ts, dev[-1]["ts_ms"])
    eval_rows = [r for r in rest if r["ts_ms"] >= cut_ts + purge_ms]
    purged = [r for r in rest if r["ts_ms"] < cut_ts + purge_ms]
    if not eval_rows and rest:
        # span too short for the configured purge: keep a time-respecting tail
        eval_rows = rest
        purged = []
        purge_ms_used = 0
    else:
        purge_ms_used = purge_ms if eval_rows else 0

    for r in train:
        r["split"] = "train"
    for r in dev:
        r["split"] = "dev"
    for r in eval_rows:
        r["split"] = "eval"
    for r in purged:
        r["split"] = "purge"

    golds = Counter(r["gold_label"] for r in multi)
    varied = [r for r in multi if r["varied"]]
    span_ms = (multi[-1]["ts_ms"] - multi[0]["ts_ms"]) if multi else 0
    day_ids = {r["ts_ms"] // 86_400_000 for r in multi} if multi else set()
    per_action_n = {a: c for a, c in golds.most_common()}
    stats = {
        "logs": [str(p) for p in logs],
        "raw_rows": len(raw),
        "unique_state_menu": len(unique),
        "single_option": len(format_check),
        "unusable_multi": len(unusable),
        "multi_option_trainish": n,
        "varied_multi": len(varied),
        "collapsed_multi": n - len(varied),
        "non_hold_gold": sum(1 for r in multi if r["gold_label"] not in HOLD_LABELS),
        "gold_distribution": dict(golds.most_common()),
        "menu_size": dict(Counter(r["n_options"] for r in multi).most_common()),
        "bee": dict(Counter(r["bee"] for r in multi).most_common()),
        "bee_style": dict(Counter(r["bee_style"] for r in multi).most_common()),
        "forced": sum(1 for r in unique if r.get("forced_by")),
        "vetoed": sum(1 for r in unique if r.get("vetoed_by")),
        "span_ms": span_ms,
        "span_hours": round(span_ms / 3.6e6, 3) if span_ms else 0,
        "calendar_days": len(day_ids),
        "train": len(train),
        "dev": len(dev),
        "eval": len(eval_rows),
        "purge": len(purged),
        "purge_ms_used": purge_ms_used,
        "format_check": len(format_check),
        "gold_is": "jev_choice",
        "soft_targets": "probabilities (renormalized over menu); confidence kept as metadata",
    }
    stats["enough_to_claim"] = (
        stats["varied_multi"] >= NEED["multi_option_unique"]
        and stats["non_hold_gold"] >= NEED["non_hold_gold"]
        and stats["calendar_days"] >= NEED["calendar_days"]
        and all(c >= NEED["per_action_gold"] for c in per_action_n.values())
        and len(per_action_n) >= 4
    )
    stats["needed"] = NEED
    stats["shortfall"] = {
        "varied_multi": max(0, NEED["multi_option_unique"] - stats["varied_multi"]),
        "non_hold_gold": max(0, NEED["non_hold_gold"] - stats["non_hold_gold"]),
        "days": max(0, NEED["calendar_days"] - stats["calendar_days"]),
        "per_action_below_50": {
            a: max(0, NEED["per_action_gold"] - c) for a, c in per_action_n.items() if c < NEED["per_action_gold"]
        },
    }
    return {
        "train": train,
        "dev": dev,
        "eval": eval_rows,
        "purge": purged,
        "format_check": format_check,
        "unusable": unusable,
        "stats": stats,
    }


def write_split(bundle: dict, path: Path) -> None:
    slim = []
    for split in ("train", "dev", "eval"):
        for r in bundle[split]:
            slim.append(
                {
                    "split": split,
                    "ts_ms": r["ts_ms"],
                    "bee": r["bee"],
                    "gold_label": r["gold_label"],
                    "n_options": r["n_options"],
                    "varied": r["varied"],
                    "state_hash": r["state_hash"],
                }
            )
    path.write_text(json.dumps({"stats": bundle["stats"], "rows": slim}, indent=2))

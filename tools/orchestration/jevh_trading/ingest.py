"""Ingest a growing beebots decision log and turn it into a Jev-distill split.

Gold is Jev's `choice` (plus `probabilities` as soft targets).
Single-option menus are dropped from training and kept only for format checks.
Hyperspeed v2 logs: time-split on market_ts (last 6 snapshots + purge) and a
held-out-rules_id eval. live_engine is scored separately and never trained on
when v2 is present.

Not financial advice. Offline only. Does not call any exchange or the beebots engine.
"""

from __future__ import annotations

import gzip
import hashlib
import json
import random
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

from .config import BEE_TAG, HOLD_LABELS, SEED
from .paths import find_file

PURGE_MS_DEFAULT = 5 * 60 * 1000  # 5 minutes (legacy paper-log split)
TRAIN_FRAC = 0.70
DEV_FRAC = 0.15
EVAL_LAST_SNAPSHOTS = 6
PURGE_SNAPSHOTS = 1
TIME_DEV_SNAPSHOTS = 3
# Prefer these rules_ids as unseen-rules eval (one per style).
HOLD_RULES_PREF = {
    "breezy": "breezy-cautious",
    "boozy": "boozy-diamond",
    "bizzy": "bizzy-alts",
}

NEED = {
    "multi_option_unique": 2000,
    "non_hold_gold": 400,
    "per_action_gold": 50,
    "calendar_days": 14,
    "note": (
        "A 68m student can copy a collapsed HOLD_WINNER teacher from a few hundred "
        "near-duplicate ticks. Mimicking discretionary Jev (when to leave HOLD, which "
        "APE_*, when to SWITCH) wants thousands of *varied* multi-option rows, with "
        "each offered action as gold at least ~50 times, over more than one regime. "
        "A 13h window plus 30 minutes of one market regime is NOT that bar — scores "
        "mean 'mimics Jev in this regime', not a cost-free stand-in."
    ),
}


def _canon(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), default=str)


def state_hash(state: Any) -> str:
    return hashlib.sha1(_canon(state).encode()).hexdigest()[:16]


def bee_style(row: dict) -> str:
    if row.get("style") in ("breezy", "boozy", "bizzy"):
        return str(row["style"])
    menu = row.get("menu") or []
    if any(str(x).startswith("BREAKOUT") or str(x) in ("WAIT", "CUT_LOSS") for x in menu):
        return "bizzy"
    cols = ((row.get("state") or {}).get("coins") or {}).get("cols") or []
    if "score" in cols or "long_on" in cols:
        return "breezy"
    return "boozy"


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
    "to_trigger_pct": "trig",
    "day_move_pct": "dmove",
    "prev_range_pct": "prng",
}


def _kv(k: Any, v: Any) -> str | None:
    if v is None or v == "na":
        return None
    return f"{_KEY.get(str(k), k)}={v}"


def _clip(text: Any, n: int = 140) -> str:
    s = " ".join(str(text or "").split())
    if len(s) <= n:
        return s
    return s[: n - 1] + "…"


def _clip_ends(text: str, n: int) -> str:
    """Keep the start and the end. Long owner rules put the action at the tail."""
    if len(text) <= n:
        return text
    head = (n - 1) // 2
    tail = n - 1 - head
    return text[:head] + "…" + text[-tail:]


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


_NOT_TICKER = frozenset(
    {
        "APE",
        "LONG",
        "SHORT",
        "HOLD",
        "WINNER",
        "SWITCH",
        "COIN",
        "BREAKOUT",
        "CUT",
        "LOSS",
        "DOUBLE",
        "DOWN",
        "TRIM",
        "HALF",
        "BAIL",
        "WAIT",
        "RIDE",
        "OPEN",
        "CLOSE",
    }
)
_STYLE_COLS = {
    "breezy": ("score", "long_on", "short_on", "r24h_pct", "fund_z"),
    "boozy": ("r7d_pct", "r24h_pct", "r1h_pct", "attn_z", "vol_musd"),
    "bizzy": ("score", "r1h_pct", "oi1h_pct", "vol_musd", "r24h_pct"),
}
_MAX_COINS = 4
_RULES_CHARS = 180
_EMPTY_RULES = frozenset({"", ".", "...", "…"})


def _tickers(menu: Any, menu_detail: Any, me: Any, top1: Any) -> list[str]:
    out: list[str] = []
    pos = str((me or {}).get("pos") or "") if isinstance(me, dict) else ""
    bits = pos.replace("/", " ").split()
    if bits and bits[-1].isalpha() and bits[-1].isupper() and len(bits[-1]) >= 2:
        out.append(bits[-1])
    for lab in menu or []:
        for part in str(lab).replace("-", "_").split("_"):
            if part.isalpha() and part.isupper() and len(part) >= 2 and part not in _NOT_TICKER:
                out.append(part)
    if isinstance(menu_detail, list):
        for d in menu_detail:
            if isinstance(d, dict) and d.get("coin"):
                out.append(str(d["coin"]).upper())
    if top1:
        tok = str(top1).split()[0]
        if tok.isalpha() and tok.isupper() and len(tok) >= 2:
            out.append(tok)
    seen: set[str] = set()
    uniq: list[str] = []
    for c in out:
        if c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


def _coin_rank_key(cols: list, seq: list) -> float:
    mapping = {c: v for c, v in zip(cols, seq)}
    for k in ("score", "r7d_pct", "r24h_pct", "r1h_pct"):
        if k not in mapping or mapping[k] is None:
            continue
        try:
            return -abs(float(mapping[k]))
        except (TypeError, ValueError):
            continue
    return 0.0


def packed_state(state: Any, menu: Any = None, style: str | None = None, menu_detail: Any = None) -> str:
    """Position + the coins the menu names. seq128 keep_option keeps the prefix, so this stays short."""
    if not isinstance(state, dict):
        return _canon(state)
    me = state.get("me") or {}
    me_bits = [b for k, v in me.items() if (b := _kv(k, v))] if isinstance(me, dict) else []
    coins = state.get("coins") or {}
    cols = list(coins.get("cols") or [])
    rows = coins.get("rows") or {}
    top1 = state.get("top1")
    lines = []
    if me_bits:
        lines.append("me: " + " ".join(me_bits))
    if top1:
        lines.append(f"top1={top1}")
    want = _tickers(menu, menu_detail, me if isinstance(me, dict) else {}, top1)
    present = [str(c) for c in rows.keys()]
    ordered = [c for c in want if c in rows]
    rest = [c for c in present if c not in ordered]
    rest.sort(key=lambda c: _coin_rank_key(cols, list(rows[c]) if isinstance(rows[c], (list, tuple)) else [rows[c]]))
    ordered = (ordered + rest)[:_MAX_COINS]
    pref = _STYLE_COLS.get(style or "", ())
    use_cols = [c for c in pref if c in cols] or cols[:4]
    for coin in ordered:
        seq = list(rows[coin]) if isinstance(rows[coin], (list, tuple)) else [rows[coin]]
        mapping = {c: v for c, v in zip(cols, seq)}
        bits = [b for c in use_cols if (b := _kv(c, mapping.get(c)))]
        lines.append(f"{coin} " + " ".join(bits) if bits else str(coin))
    return "\n".join(lines)


def policy_text(strategy: Any, rules: Any) -> str:
    """Owner rules, not the shared 'You are X-bee' strategy boilerplate."""
    rules_s = " ".join(str(rules or "").split())
    if rules_s not in _EMPTY_RULES:
        return _clip_ends(rules_s, _RULES_CHARS)
    strat = " ".join(str(strategy or "").split())
    if not strat:
        return ""
    parts = [p.strip() for p in strat.replace(";", ".").split(".") if p.strip()]
    hits = [
        p
        for p in parts
        if any(k in p.lower() for k in ("only ever", "only trade", "trade only", "coins allowed", "allowed coin"))
    ]
    if not hits:
        return ""
    return _clip_ends(". ".join(hits), _RULES_CHARS)


def option_text(label: str, detail: Any) -> str:
    """SWITCH/HOLD/etc. are ambiguous without kind/coin/side from menu_detail."""
    if not isinstance(detail, dict):
        return label
    desc = str(detail.get("desc") or "").strip()
    kind = str(detail.get("kind") or "").strip()
    coin = str(detail.get("coin") or "").strip()
    side = str(detail.get("side") or "").strip()
    extra = " ".join(x for x in (kind, coin, side) if x)
    if desc and extra and desc.lower() != extra.lower():
        return f"{label}: {desc} ({extra})"
    if desc:
        return f"{label}: {desc}"
    if extra:
        return f"{label}: {extra}"
    return label


def option_texts_for(menu: list[str], menu_detail: Any) -> list[str]:
    by_lab: dict[str, dict] = {}
    if isinstance(menu_detail, list):
        for d in menu_detail:
            if isinstance(d, dict) and d.get("label") is not None:
                by_lab[str(d["label"])] = d
    elif isinstance(menu_detail, dict):
        for k, v in menu_detail.items():
            if isinstance(v, dict):
                by_lab[str(k)] = v
    return [option_text(lab, by_lab.get(lab)) for lab in menu]


def text_a_for(row: dict, ctx: dict | None = None) -> str:
    style = (ctx or {}).get("style") or row.get("style") or bee_style(row)
    rules_id = (ctx or {}).get("rules_id") or row.get("rules_id") or ""
    q = BEE_TAG.get(style, style)
    if rules_id:
        q = f"{q} {rules_id}"
    # keep_option keeps the start of text_a. Rules (what differs across bees) go
    # before state. Shared strategy boilerplate is dropped; it ate the token budget.
    lines = [f"[choice] {q}"]
    policy = policy_text((ctx or {}).get("strategy") or row.get("strategy"), (ctx or {}).get("rules") or row.get("rules"))
    if policy:
        lines.append("rules: " + policy)
    state = packed_state(row.get("state") or {}, row.get("menu") or [], style, row.get("menu_detail"))
    if state:
        lines.append(state)
    return "\n".join(lines)


PACKERS = ("v1", "option")


def _seq(v: Any) -> list:
    return list(v) if isinstance(v, (list, tuple)) else [v]


def _as_float(v: Any) -> float | None:
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _pos_coin(me: Any) -> str | None:
    pos = str((me or {}).get("pos") or "") if isinstance(me, dict) else ""
    bits = pos.replace("/", " ").split()
    if bits and bits[-1].isalpha() and bits[-1].isupper() and len(bits[-1]) >= 2:
        return bits[-1]
    return None


_ON_POSITION = frozenset({"HOLD", "RIDE", "HOLD_WINNER", "CUT_LOSS", "BAIL", "TRIM_HALF", "DOUBLE_DOWN"})


def option_coin(label: str, detail: Any, pos_coin: str | None) -> str | None:
    """The coin an option acts on: menu_detail coin, else a ticker in the label, else the open
    position for hold/close/trim/add. A bare SWITCH without menu_detail names no coin."""
    if isinstance(detail, dict) and detail.get("coin"):
        return str(detail["coin"]).upper()
    for part in reversed(str(label).replace("-", "_").split("_")):
        if part.isalpha() and part.isupper() and len(part) >= 2 and part not in _NOT_TICKER:
            return part
    kind = str(detail.get("kind") or "") if isinstance(detail, dict) else ""
    if kind in ("hold", "close", "trim", "add") or str(label) in _ON_POSITION:
        return pos_coin
    return None


def coin_line(coin: str, cols: list, rows: dict, peers: list[str]) -> str:
    """Every state column for one coin. With 3+ peers, '#k' ranks the value among them (1 = largest)."""
    seq = _seq(rows[coin])
    peer_seqs = [_seq(rows[p]) for p in peers]
    bits = []
    for i, c in enumerate(cols):
        v = seq[i] if i < len(seq) else None
        b = _kv(c, v)
        if b is None:
            continue
        x = _as_float(v)
        vals = [y for s in peer_seqs if (y := _as_float(s[i] if i < len(s) else None)) is not None]
        if x is not None and len(vals) >= 3:
            b += f"#{1 + sum(y > x for y in vals)}"
        bits.append(b)
    return f"{coin} " + " ".join(bits) if bits else str(coin)


def option_packed(row: dict, ctx: dict | None = None) -> tuple[str, list[str]]:
    """Option-centric pairs. Each option carries its own coin's full row (keep_option never trims text_b);
    text_a is header, position, rules, then the whole coin table, so truncation only eats the table tail."""
    style = (ctx or {}).get("style") or row.get("style") or bee_style(row)
    rules_id = (ctx or {}).get("rules_id") or row.get("rules_id") or ""
    q = BEE_TAG.get(style, style)
    if rules_id:
        q = f"{q} {rules_id}"
    state = row.get("state") if isinstance(row.get("state"), dict) else {}
    me = state.get("me") if isinstance(state.get("me"), dict) else {}
    coins = state.get("coins") or {}
    cols = list(coins.get("cols") or [])
    rows = {str(c): v for c, v in (coins.get("rows") or {}).items()}
    menu = [str(x) for x in row.get("menu") or []]
    det_by: dict[str, dict] = {}
    if isinstance(row.get("menu_detail"), list):
        det_by = {str(d.get("label")): d for d in row["menu_detail"] if isinstance(d, dict)}
    pos = _pos_coin(me)
    opt_coins = [option_coin(lab, det_by.get(lab), pos) for lab in menu]
    peers = list(dict.fromkeys(c for c in opt_coins if c and c in rows))

    lines = [f"[choice] {q}"]
    me_bits = [b for k, v in me.items() if (b := _kv(k, v))]
    if me_bits:
        lines.append("me: " + " ".join(me_bits))
    policy = policy_text((ctx or {}).get("strategy") or row.get("strategy"), (ctx or {}).get("rules") or row.get("rules"))
    if policy:
        lines.append("rules: " + policy)
    if state.get("top1"):
        lines.append(f"top1={state['top1']}")
    rest = sorted((c for c in rows if c not in peers), key=lambda c: _coin_rank_key(cols, _seq(rows[c])))
    lines += [coin_line(c, cols, rows, []) for c in peers + rest]
    opts = []
    for lab, coin in zip(menu, opt_coins):
        t = option_text(lab, det_by.get(lab))
        if coin and coin in rows:
            t += "\n" + coin_line(coin, cols, rows, peers)
        opts.append(t)
    return "\n".join(lines), opts


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
    if set(menu) <= {"HOLD_WINNER", "LONG_BTC", "SWITCH", "RIDE", "HOLD", "WAIT"}:
        return False
    return len(menu) - len(holdish) >= 2


def iter_jsonl(path: Path):
    name = path.name.lower()
    gz = name.endswith(".gz") or ".jsonl.gz" in name or name.endswith(".gz")
    opener = gzip.open if gz else open
    with opener(path, "rt") as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def load_jsonl(path: Path) -> list[dict]:
    return list(iter_jsonl(path))


def load_contexts(path: Path | None) -> dict[str, dict]:
    if path is None or not path.is_file():
        return {}
    out = {}
    for r in iter_jsonl(path):
        cid = r.get("context_id")
        if cid:
            out[str(cid)] = r
    return out


def discover_logs(extra: Iterable[str] | None = None, *, include_default: bool = True) -> list[Path]:
    found: list[Path] = []
    if include_default:
        v2 = find_file("trading_jev_calls_v2.jsonl.gz", required=False)
        if v2:
            found.append(v2)
        else:
            p = find_file("trading_paper_decisions.jsonl", required=False)
            if p:
                found.append(p)
    for raw in extra or []:
        q = Path(raw)
        if q.is_file():
            found.append(q)
    out, seen = [], set()
    for x in found:
        k = str(x.resolve())
        if k not in seen:
            seen.add(k)
            out.append(x)
    return out


def parse_row(r: dict, file_source: str, contexts: dict[str, dict] | None = None, packer: str = "v1") -> dict | None:
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
    cid = r.get("context_id")
    ctx = (contexts or {}).get(str(cid)) if cid else None
    style = (r.get("style") or (ctx or {}).get("style") or bee_style(r))
    if style not in ("breezy", "boozy", "bizzy"):
        style = bee_style(r)
    rules_id = r.get("rules_id") or (ctx or {}).get("rules_id") or ""
    row_source = str(r.get("source") or file_source)
    rec = {
        "ts_ms": ts,
        "market_ts": r.get("market_ts"),
        "bee": str(r.get("bee") or ""),
        "bee_style": style,
        "style": style,
        "rules_id": str(rules_id) if rules_id else "",
        "context_id": str(cid) if cid else "",
        "menu": menu,
        "choice": None if choice is None else str(choice),
        "confidence": r.get("confidence"),
        "conviction": r.get("conviction"),
        "action": r.get("action"),
        "vetoed_by": r.get("vetoed_by"),
        "forced_by": r.get("forced_by"),
        "status": r.get("status"),
        "jev_error": err,
        "file_source": file_source,
        "row_source": row_source,
        "source": row_source,
        "n_options": len(menu),
        "single_option": len(menu) < 2,
        "id": r.get("id"),
        "teacher": r.get("teacher"),
    }
    rec["state_hash"] = r.get("state_hash") or state_hash(
        {"bee": rec["bee"], "menu": menu, "state": r.get("state") or {}, "ctx": rec["context_id"], "src": row_source}
    )
    rec["varied"] = is_varied(menu, rec["choice"])
    if packer == "option":
        rec["text_a"], rec["option_texts"] = option_packed(r, ctx)
    else:
        rec["text_a"] = text_a_for(r, ctx)
        rec["option_texts"] = option_texts_for(menu, r.get("menu_detail"))
    rec["usable_train"] = not rec["single_option"] and rec["choice"] in menu and not err
    if rec["usable_train"]:
        rec["gold"] = menu.index(rec["choice"])
        rec["gold_label"] = rec["choice"]
        rec["probs"] = align_probs(menu, r.get("probabilities"), rec["choice"])
    return rec


def pick_held_rules(rows: list[dict], seed: int = SEED) -> list[str]:
    by_style: dict[str, set[str]] = defaultdict(set)
    for r in rows:
        if r.get("rules_id"):
            by_style[r.get("bee_style") or "other"].add(r["rules_id"])
    held = []
    rng = random.Random(seed)
    for style, pref in HOLD_RULES_PREF.items():
        ids = sorted(by_style.get(style) or [])
        if not ids:
            continue
        if pref in ids:
            held.append(pref)
        else:
            held.append(ids[rng.randrange(len(ids))])
    return held


def _assign_legacy(multi: list[dict], purge_ms: int, train_frac: float) -> tuple[list, list, list, list, int]:
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
        eval_rows, purged, purge_ms_used = rest, [], 0
    else:
        purge_ms_used = purge_ms if eval_rows else 0
    return train, dev, eval_rows, purged, purge_ms_used


def _assign_v2(multi: list[dict], seed: int) -> dict:
    hs = [r for r in multi if r.get("row_source") == "hyperspeed" and r.get("market_ts")]
    live = [r for r in multi if r.get("row_source") == "live_engine"]
    snaps = sorted({r["market_ts"] for r in hs})
    n_eval = min(EVAL_LAST_SNAPSHOTS, max(1, len(snaps) // 5))
    n_purge = min(PURGE_SNAPSHOTS, max(0, len(snaps) - n_eval - 4))
    n_dev = min(TIME_DEV_SNAPSHOTS, max(1, len(snaps) - n_eval - n_purge - 2))
    eval_snaps = set(snaps[-n_eval:]) if snaps else set()
    purge_snaps = set(snaps[-(n_eval + n_purge) : -n_eval]) if n_purge else set()
    remain = [s for s in snaps if s not in eval_snaps and s not in purge_snaps]
    dev_snaps = set(remain[-n_dev:]) if remain else set()
    train_snaps = set(remain[:-n_dev] if n_dev else remain)
    held_rules = pick_held_rules(hs, seed)
    held_set = set(held_rules)

    def in_snaps(rows, allowed):
        return [r for r in rows if r.get("market_ts") in allowed]

    hs_seen = [r for r in hs if r.get("rules_id") not in held_set]
    hs_unseen_rules = [r for r in hs if r.get("rules_id") in held_set]
    train = in_snaps(hs_seen, train_snaps)
    dev = in_snaps(hs_seen, dev_snaps)
    eval_time = in_snaps(hs_seen, eval_snaps)
    eval_rules = hs_unseen_rules  # any snapshot; rules never in train
    purged = in_snaps(hs, purge_snaps)
    return {
        "train": train,
        "dev": dev,
        "eval": eval_time,
        "eval_live": live,
        "eval_rules": eval_rules,
        "purge": purged,
        "held_rules": held_rules,
        "eval_snaps": sorted(eval_snaps),
        "purge_snaps": sorted(purge_snaps),
        "dev_snaps": sorted(dev_snaps),
        "train_snaps": sorted(train_snaps),
        "n_snapshots": len(snaps),
        "protocol": "hyperspeed_market_ts+held_rules+live_holdout",
    }


def ingest(
    extra_logs: Iterable[str] | None = None,
    *,
    purge_ms: int = PURGE_MS_DEFAULT,
    train_frac: float = TRAIN_FRAC,
    seed: int = SEED,
    include_default: bool = True,
    packer: str = "v1",
) -> dict:
    if packer not in PACKERS:
        raise ValueError(f"packer {packer!r} not in {PACKERS}")
    logs = discover_logs(extra_logs, include_default=include_default)
    ctx_path = find_file("trading_jev_contexts_v2.jsonl", required=False) if include_default else None
    # extra --log of contexts is unusual; still search default uploads
    if ctx_path is None:
        ctx_path = find_file("trading_jev_contexts_v2.jsonl", required=False)
    contexts = load_contexts(ctx_path)
    raw: list[dict] = []
    for path in logs:
        for r in iter_jsonl(path):
            rec = parse_row(r, str(path), contexts, packer)
            if rec:
                raw.append(rec)
    raw.sort(key=lambda r: (r["ts_ms"], str(r.get("id"))))

    latest: dict[str, dict] = {}
    for rec in raw:
        latest[f"{rec['row_source']}|{rec['state_hash']}|{rec['rules_id']}"] = rec
    unique = sorted(latest.values(), key=lambda r: (r["ts_ms"], str(r.get("id"))))

    format_check = [r for r in unique if r["single_option"]]
    unusable = [r for r in unique if (not r["single_option"]) and not r["usable_train"]]
    multi = [r for r in unique if r["usable_train"]]

    hs = [r for r in multi if r.get("row_source") == "hyperspeed" and r.get("market_ts")]
    use_v2 = len({r["market_ts"] for r in hs}) >= 8
    extra_eval: dict[str, list] = {"eval_live": [], "eval_rules": []}
    v2meta: dict = {}
    if use_v2:
        parts = _assign_v2(multi, seed)
        train, dev, eval_rows, purged = parts["train"], parts["dev"], parts["eval"], parts["purge"]
        extra_eval["eval_live"] = parts["eval_live"]
        extra_eval["eval_rules"] = parts["eval_rules"]
        v2meta = {k: parts[k] for k in ("held_rules", "eval_snaps", "purge_snaps", "dev_snaps", "train_snaps", "n_snapshots", "protocol")}
        purge_ms_used = 0
    else:
        train, dev, eval_rows, purged, purge_ms_used = _assign_legacy(multi, purge_ms, train_frac)

    for r in train:
        r["split"] = "train"
    for r in dev:
        r["split"] = "dev"
    for r in eval_rows:
        r["split"] = "eval"
    for r in extra_eval["eval_live"]:
        r["split"] = "eval_live"
    for r in extra_eval["eval_rules"]:
        r["split"] = "eval_rules"
    for r in purged:
        r["split"] = "purge"

    golds = Counter(r["gold_label"] for r in multi)
    varied = [r for r in multi if r["varied"]]
    span_ms = (multi[-1]["ts_ms"] - multi[0]["ts_ms"]) if multi else 0
    day_ids = {r["ts_ms"] // 86_400_000 for r in multi} if multi else set()
    per_action_n = {a: c for a, c in golds.most_common()}
    src_counts = Counter(r["row_source"] for r in multi)
    stats = {
        "logs": [str(p) for p in logs],
        "contexts": str(ctx_path) if ctx_path else None,
        "n_contexts": len(contexts),
        "raw_rows": len(raw),
        "unique_state_menu": len(unique),
        "single_option": len(format_check),
        "unusable_multi": len(unusable),
        "multi_option_trainish": len(multi),
        "varied_multi": len(varied),
        "collapsed_multi": len(multi) - len(varied),
        "non_hold_gold": sum(1 for r in multi if r["gold_label"] not in HOLD_LABELS),
        "gold_distribution": dict(golds.most_common()),
        "menu_size": dict(Counter(r["n_options"] for r in multi).most_common()),
        "bee": dict(Counter(r["bee"] for r in multi).most_common()),
        "bee_style": dict(Counter(r["bee_style"] for r in multi).most_common()),
        "row_source": dict(src_counts.most_common()),
        "forced": sum(1 for r in unique if r.get("forced_by")),
        "vetoed": sum(1 for r in unique if r.get("vetoed_by")),
        "span_ms": span_ms,
        "span_hours": round(span_ms / 3.6e6, 3) if span_ms else 0,
        "calendar_days": len(day_ids),
        "train": len(train),
        "dev": len(dev),
        "eval": len(eval_rows),
        "eval_live": len(extra_eval["eval_live"]),
        "eval_rules": len(extra_eval["eval_rules"]),
        "purge": len(purged),
        "purge_ms_used": purge_ms_used,
        "format_check": len(format_check),
        "gold_is": "jev_choice",
        "packer": packer,
        "soft_targets": "probabilities (renormalized over menu); confidence kept as metadata",
        "regime_note": (
            "This does NOT meet the >=14 days / multiple-regimes bar. "
            "live_engine is ~13h of one paper session; hyperspeed is 30 minutes / 30 snapshots "
            "of one market regime. Scores mean: mimics Jev in this regime, not a stand-in."
        ),
        **v2meta,
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
        "eval_live": extra_eval["eval_live"],
        "eval_rules": extra_eval["eval_rules"],
        "purge": purged,
        "format_check": format_check,
        "unusable": unusable,
        "stats": stats,
    }


def stratified_take(rows: list[dict], n: int, seed: int = SEED) -> list[dict]:
    if n <= 0 or len(rows) <= n:
        return list(rows)
    rng = random.Random(seed)
    buckets: dict[tuple, list[dict]] = defaultdict(list)
    for r in rows:
        buckets[(r.get("bee_style"), r.get("gold_label"), r.get("n_options"))].append(r)
    for b in buckets.values():
        rng.shuffle(b)
    keys = list(buckets)
    rng.shuffle(keys)
    out: list[dict] = []
    i = 0
    while len(out) < n:
        progressed = False
        for k in keys:
            if buckets[k]:
                out.append(buckets[k].pop())
                progressed = True
                if len(out) >= n:
                    break
        if not progressed:
            break
        i += 1
    out.sort(key=lambda r: (r["ts_ms"], str(r.get("id"))))
    return out


def write_split(bundle: dict, path: Path) -> None:
    slim = []
    for split in ("train", "dev", "eval", "eval_live", "eval_rules"):
        for r in bundle.get(split) or []:
            slim.append(
                {
                    "split": split,
                    "ts_ms": r["ts_ms"],
                    "market_ts": r.get("market_ts"),
                    "bee": r["bee"],
                    "bee_style": r.get("bee_style"),
                    "rules_id": r.get("rules_id"),
                    "row_source": r.get("row_source"),
                    "gold_label": r.get("gold_label"),
                    "n_options": r["n_options"],
                    "varied": r["varied"],
                    "state_hash": r["state_hash"],
                }
            )
    path.write_text(json.dumps({"stats": bundle["stats"], "n_rows": len(slim)}, indent=2))

"""How much agreement with Jev is reachable at all, and what the student input drops.

Reads the raw v2 calls (no model). Splits exactly like ingest.py. Reports:
  - Jev's own probability mass: argmax consistency, exact ties, E[max p], E[sum p^2],
    top-2 margin distribution, and what the logged `confidence` field actually is.
  - Jev re-query noise from repeated identical calls, and the agreement a perfect
    copy of Jev's mean probabilities could reach given that noise.
  - A noise-to-agreement table: how precise a student's probabilities must be.
  - Representation audit of the seq128 pair text: dropped columns, coin cap,
    rules clipping, and token truncation on a sample.

python -m jevh_trading.jev_ceiling   ->  artifacts/jev_ceiling.json

Not financial advice. Offline only.
"""

from __future__ import annotations

import argparse
import ast
import json
import random
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import numpy as np

from .config import CLS_ID, SEED, SEP_ID, SEQ_LEN
from .ingest import (
    _MAX_COINS,
    _RULES_CHARS,
    _STYLE_COLS,
    _assign_v2,
    _coin_rank_key,
    _tickers,
    align_probs,
    bee_style,
    iter_jsonl,
    load_contexts,
    option_texts_for,
    state_hash,
    text_a_for,
)
from .paths import artifacts_dir, find_file, tokenizer_path

SPLITS = ("train", "dev", "eval", "eval_rules", "eval_live")
MARGIN_EDGES = (0.0, 0.02, 0.05, 0.10, 0.20, 0.30, 0.50, 1.01)
NOISE_SIGMAS = (0.0, 0.01, 0.02, 0.03, 0.05, 0.075, 0.10, 0.15, 0.20, 0.30)


def coins_allowed(ctx: dict | None) -> list[str]:
    a = (ctx or {}).get("coins_allowed")
    if isinstance(a, str):
        try:
            a = ast.literal_eval(a)
        except (ValueError, SyntaxError):
            a = []
    return [str(x) for x in (a or [])]


def load_raw_calls(path: Path | None = None, contexts: dict[str, dict] | None = None) -> dict:
    """Raw calls with state kept, deduped and split the same way as ingest()."""
    path = path or find_file("trading_jev_calls_v2.jsonl.gz")
    if contexts is None:
        contexts = load_contexts(find_file("trading_jev_contexts_v2.jsonl", required=False))
    raw: list[dict] = []
    for r in iter_jsonl(path):
        menu = r.get("menu")
        if not isinstance(menu, list) or not menu:
            continue
        menu = [str(x) for x in menu]
        cid = str(r.get("context_id") or "")
        ctx = contexts.get(cid) if cid else None
        style = r.get("style") or (ctx or {}).get("style") or bee_style(r)
        if style not in ("breezy", "boozy", "bizzy"):
            style = bee_style(r)
        src = str(r.get("source") or path.name)
        choice = None if r.get("choice") is None else str(r.get("choice"))
        usable = len(menu) >= 2 and choice in menu and not r.get("jev_error")
        rules_id = str(r.get("rules_id") or (ctx or {}).get("rules_id") or "")
        sh = r.get("state_hash") or state_hash(
            {"bee": str(r.get("bee") or ""), "menu": menu, "state": r.get("state") or {}, "ctx": cid, "src": src}
        )
        try:
            ts = int(r.get("ts_ms") or 0)
        except (TypeError, ValueError):
            ts = 0
        rec = {"id": r.get("id"), "ts_ms": ts, "row_source": src, "state_hash": sh, "rules_id": rules_id, "usable": usable}
        if usable:
            rec.update(
                {
                    "bee": str(r.get("bee") or ""),
                    "bee_style": style,
                    "style": style,
                    "context_id": cid,
                    "market_ts": r.get("market_ts"),
                    "menu": menu,
                    "menu_detail": r.get("menu_detail"),
                    "n_options": len(menu),
                    "gold": menu.index(choice),
                    "gold_label": choice,
                    "p": align_probs(menu, r.get("probabilities"), choice),
                    "p_raw_sum": float(sum(float((r.get("probabilities") or {}).get(m) or 0) for m in menu)),
                    "confidence": r.get("confidence"),
                    "state": r.get("state") or {},
                    "input_tokens": r.get("input_tokens"),
                    "logger_state_hash": r.get("state_hash"),
                }
            )
        raw.append(rec)
    raw.sort(key=lambda x: (x["ts_ms"], str(x.get("id"))))
    latest: dict[str, dict] = {}
    for rec in raw:
        latest[f"{rec['row_source']}|{rec['state_hash']}|{rec['rules_id']}"] = rec
    multi = sorted((r for r in latest.values() if r["usable"]), key=lambda x: (x["ts_ms"], str(x.get("id"))))
    parts = _assign_v2(multi, SEED)
    for name in SPLITS + ("purge",):
        for r in parts[name]:
            r["split"] = name
    return {"raw": [r for r in raw if r["usable"]], "multi": multi, "parts": parts, "contexts": contexts}


def _sorted_p(p: list[float]) -> np.ndarray:
    return np.sort(np.asarray(p, dtype=np.float64))[::-1]


def margin_of(p: list[float]) -> float:
    s = _sorted_p(p)
    return float(s[0] - s[1]) if s.size > 1 else 1.0


def margin_bins(margins: np.ndarray) -> dict:
    out = {}
    for lo, hi in zip(MARGIN_EDGES[:-1], MARGIN_EDGES[1:]):
        m = (margins >= lo) & (margins < hi)
        out[f"[{lo:.2f},{min(hi, 1.0):.2f})"] = float(m.mean()) if margins.size else None
    return out


def jev_mass_stats(rows: list[dict]) -> dict:
    """What Jev's own probabilities say about reachable agreement."""
    if not rows:
        return {"n": 0}
    pmax, psq, ties, tie_first, argmax_ok, conf_err, margins = [], [], 0, 0, 0, [], []
    confs = []
    for r in rows:
        p = np.asarray(r["p"], dtype=np.float64)
        mx = p.max()
        top = np.flatnonzero(np.abs(p - mx) < 1e-9)
        if len(top) > 1:
            ties += 1
            tie_first += int(r["gold"] == int(top[0]))
        argmax_ok += int(r["gold"] in set(top.tolist()))
        pmax.append(mx)
        psq.append(float((p**2).sum()))
        m = margin_of(r["p"])
        margins.append(m)
        if r.get("confidence") is not None:
            try:
                c = float(r["confidence"])
                confs.append((c, m, mx))
            except (TypeError, ValueError):
                pass
    margins_a = np.asarray(margins)
    conf_a = np.asarray(confs) if confs else np.zeros((0, 3))
    out = {
        "n": len(rows),
        "choice_is_argmax_p": argmax_ok / len(rows),
        "exact_ties_at_max": ties / len(rows),
        "tie_break_first_in_menu": (tie_first / ties) if ties else None,
        "E_max_p_sampling_ceiling": float(np.mean(pmax)),
        "E_sum_p2_two_samples_agree": float(np.mean(psq)),
        "mean_top2_margin": float(margins_a.mean()),
        "margin_quantiles_10_25_50_75_90": [float(x) for x in np.percentile(margins_a, [10, 25, 50, 75, 90])],
        "margin_bins_share": margin_bins(margins_a),
        "share_margin_lt_0.10": float((margins_a < 0.10).mean()),
        "share_margin_lt_0.20": float((margins_a < 0.20).mean()),
    }
    if conf_a.shape[0] > 10:
        out["confidence_field"] = {
            "mean": float(conf_a[:, 0].mean()),
            "corr_with_top2_margin": float(np.corrcoef(conf_a[:, 0], conf_a[:, 1])[0, 1]),
            "corr_with_max_p": float(np.corrcoef(conf_a[:, 0], conf_a[:, 2])[0, 1]),
            "mean_abs_diff_vs_margin": float(np.abs(conf_a[:, 0] - conf_a[:, 1]).mean()),
            "note": "Jev's `confidence` tracks the top-2 margin, not the top probability.",
        }
    by_k: dict[str, list[float]] = defaultdict(list)
    for r, m in zip(rows, margins):
        by_k[str(len(r["menu"]))].append(m)
    out["median_margin_by_menu_size"] = {k: float(np.median(v)) for k, v in sorted(by_k.items())}
    return out


def requery_noise(raw_rows: list[dict]) -> dict:
    """Repeated identical calls (same bee, context, logged state_hash, menu) before dedupe."""
    groups: dict[tuple, list[dict]] = defaultdict(list)
    for r in raw_rows:
        if not r.get("logger_state_hash"):
            continue
        key = (r["row_source"], r["bee"], r["context_id"], r["logger_state_hash"], tuple(r["menu"]))
        groups[key].append(r)
    out = {}
    for src in sorted({k[0] for k in groups}):
        gs = [g for k, g in groups.items() if k[0] == src and len(g) >= 2]
        pairs = flips = same = 0
        maxdiff, sds, gaps = [], [], []
        for g in gs:
            P = np.asarray([x["p"] for x in g], dtype=np.float64)
            sds.append(float(P.std(axis=0, ddof=1).mean()))
            for i in range(len(g)):
                for j in range(i + 1, len(g)):
                    pairs += 1
                    flips += int(g[i]["gold"] != g[j]["gold"])
                    same += int(np.allclose(P[i], P[j], atol=1e-9))
                    maxdiff.append(float(np.abs(P[i] - P[j]).max()))
            ts = sorted(x["ts_ms"] for x in g)
            gaps += [(b - a) / 1000.0 for a, b in zip(ts, ts[1:])]
        if not gs:
            continue
        md = np.asarray(maxdiff)
        out[src] = {
            "groups": len(gs),
            "pairs": pairs,
            "choice_flips": flips,
            "choice_agreement": 1.0 - flips / max(pairs, 1),
            "identical_probability_vectors": same / max(pairs, 1),
            "per_option_sd_mean": float(np.mean(sds)),
            "max_abs_dp_mean": float(md.mean()),
            "max_abs_dp_median": float(np.median(md)),
            "max_abs_dp_p90": float(np.percentile(md, 90)),
            "repeat_gap_s_median": float(np.median(gaps)) if gaps else None,
        }
    return out


def noise_agreement(rows: list[dict], sigmas=NOISE_SIGMAS, n_draws: int = 16, seed: int = SEED) -> list[dict]:
    """Agreement with the logged choice if probabilities carry iid N(0, sigma^2) error per option.

    sigma = Jev's own re-query noise gives the ceiling for a student that knows Jev's mean
    probabilities exactly. Larger sigma stands in for a student's estimation error
    (combine in quadrature with Jev's noise). Exact ties in the 2-dp logged
    probabilities count against the student at about 50%, as in the data.
    """
    rng = np.random.default_rng(seed)
    by_k: dict[int, list[int]] = defaultdict(list)
    for i, r in enumerate(rows):
        by_k[len(r["p"])].append(i)
    table = []
    for sigma in sigmas:
        hit = hit_self = hit_top2 = 0.0
        n = 0
        for k, idx in by_k.items():
            P = np.asarray([rows[i]["p"] for i in idx], dtype=np.float64)
            G = np.asarray([rows[i]["gold"] for i in idx])
            draws = n_draws if sigma > 0 else 1
            for _ in range(draws):
                e1 = rng.normal(0.0, sigma, P.shape) if sigma > 0 else 0.0
                e2 = rng.normal(0.0, sigma, P.shape) if sigma > 0 else 0.0
                s1 = P + e1
                a1 = s1.argmax(1)
                a2 = (P + e2).argmax(1)
                hit += float((a1 == G).sum())
                hit_self += float((a1 == a2).sum())
                top2 = np.argsort(-s1, axis=1)[:, :2]
                hit_top2 += float((top2 == G[:, None]).any(1).sum())
            n += len(idx) * draws
        table.append(
            {
                "sigma": sigma,
                "agree_with_logged_choice": hit / n,
                "two_noisy_copies_agree": hit_self / n,
                "top2_contains_logged_choice": hit_top2 / n,
            }
        )
    return table


def sigma_for(table: list[dict], target: float) -> float | None:
    """Largest sigma in the table whose agreement still reaches target (linear interp)."""
    pts = [(t["sigma"], t["agree_with_logged_choice"]) for t in table]
    best = None
    for (s0, a0), (s1, a1) in zip(pts, pts[1:]):
        if a0 >= target > a1 and a0 != a1:
            best = s0 + (a0 - target) * (s1 - s0) / (a0 - a1)
    if best is None and pts and pts[-1][1] >= target:
        best = pts[-1][0]
    return None if best is None else float(best)


def _packed_coins(row: dict) -> tuple[list[str], list[str]]:
    """Coins and columns the seq128 packer writes (before token truncation)."""
    state = row.get("state") or {}
    coins = state.get("coins") or {}
    cols = list(coins.get("cols") or [])
    rows = coins.get("rows") or {}
    me = state.get("me") or {}
    want = _tickers(row["menu"], row.get("menu_detail"), me if isinstance(me, dict) else {}, state.get("top1"))
    ordered = [c for c in want if c in rows]
    rest = [c for c in rows if c not in ordered]
    rest.sort(key=lambda c: _coin_rank_key(cols, list(rows[c]) if isinstance(rows[c], (list, tuple)) else [rows[c]]))
    ordered = (ordered + rest)[:_MAX_COINS]
    pref = _STYLE_COLS.get(row.get("bee_style") or "", ())
    use_cols = [c for c in pref if c in cols] or cols[:4]
    return ordered, use_cols


def menu_coins(row: dict) -> list[str]:
    out = []
    for d in row.get("menu_detail") or []:
        if isinstance(d, dict) and d.get("coin") and d.get("kind") in ("open", "switch"):
            out.append(str(d["coin"]).upper())
    if not out:
        for lab in row["menu"]:
            bits = str(lab).split("_")
            if len(bits) == 2 and bits[0] in ("APE", "LONG", "SHORT", "BREAKOUT"):
                out.append(bits[1])
    return list(dict.fromkeys(out))


def representation_audit(rows: list[dict], contexts: dict[str, dict], sample_n: int = 3000, seed: int = SEED) -> dict:
    by_style: dict[str, dict] = {}
    for style in ("breezy", "boozy", "bizzy"):
        rs = [r for r in rows if r.get("bee_style") == style]
        if not rs:
            continue
        cols_c = Counter(tuple((r["state"].get("coins") or {}).get("cols") or []) for r in rs)
        cols = list(cols_c.most_common(1)[0][0])
        kept_c = Counter()
        drop_menu_coin = 0
        n_coins = Counter()
        for r in rs:
            ordered, use_cols = _packed_coins(r)
            kept_c[tuple(use_cols)] += 1
            mc = menu_coins(r)
            if any(c not in ordered for c in mc if c in ((r["state"].get("coins") or {}).get("rows") or {})):
                drop_menu_coin += 1
            n_coins[len((r["state"].get("coins") or {}).get("rows") or {})] += 1
        kept = list(kept_c.most_common(1)[0][0])
        by_style[style] = {
            "n": len(rs),
            "state_cols": cols,
            "packer_keeps_cols": kept,
            "packer_drops_cols": [c for c in cols if c not in kept],
            "coins_per_row": dict(sorted(n_coins.items())),
            "share_rows_with_a_menu_coin_dropped_by_coin_cap": drop_menu_coin / len(rs),
        }
    rules_chars = {}
    for c in contexts.values():
        rid = c.get("rules_id")
        n = len(" ".join(str(c.get("rules") or "").split()))
        rules_chars[rid] = max(rules_chars.get(rid, 0), n)
    jev_tokens = [int(r["input_tokens"]) for r in rows if r.get("input_tokens")]
    audit = {
        "by_style": by_style,
        "rules_chars_by_rules_id": dict(sorted(rules_chars.items(), key=lambda kv: -kv[1])),
        "rules_clip_chars": _RULES_CHARS,
        "rules_ids_clipped": sorted(k for k, v in rules_chars.items() if v > _RULES_CHARS),
        "jev_prompt_input_tokens": (
            {
                "n": len(jev_tokens),
                "median": float(np.median(jev_tokens)),
                "p10": float(np.percentile(jev_tokens, 10)),
                "p90": float(np.percentile(jev_tokens, 90)),
            }
            if jev_tokens
            else None
        ),
        "student_tokens_per_pair": SEQ_LEN,
        "menu_filtered_to_coins_allowed": _allowed_check(rows, contexts),
    }
    audit["token_truncation_sample"] = _truncation_sample(rows, contexts, sample_n, seed)
    return audit


def _allowed_check(rows: list[dict], contexts: dict[str, dict]) -> dict:
    n = inside = 0
    for r in rows:
        allowed = coins_allowed(contexts.get(r.get("context_id") or ""))
        if not allowed:
            continue
        mc = menu_coins(r)
        if not mc:
            continue
        n += 1
        inside += int(all(c in allowed for c in mc))
    return {"rows_with_allowlist": n, "share_menu_coins_all_allowed": inside / n if n else None}


class LineTok:
    """Token counts of text_a lines, to see which lines a seq128 pair keeps."""

    def __init__(self) -> None:
        from tokenizers import Tokenizer

        self.tok = Tokenizer.from_file(str(tokenizer_path()))
        self.tok.no_truncation()
        self.tok.no_padding()
        self._cache: dict[str, int] = {}

    def core_len(self, text: str) -> int:
        hit = self._cache.get(text)
        if hit is not None:
            return hit
        ids = self.tok.encode(text).ids
        if ids and ids[0] == CLS_ID:
            ids = ids[1:]
        if ids and ids[-1] == SEP_ID:
            ids = ids[:-1]
        if len(self._cache) < 500_000:
            self._cache[text] = len(ids)
        return len(ids)


def pair_view(row: dict, ctx: dict | None, lt: LineTok) -> dict:
    """Mirror encode.StudentTok: a pair that overflows keeps the option and a text_a prefix."""
    text_a = text_a_for(row, ctx)
    opts = option_texts_for(row["menu"], row.get("menu_detail"))
    lines = text_a.split("\n")
    lens = [lt.core_len(x) + (1 if i < len(lines) - 1 else 0) for i, x in enumerate(lines)]
    cum = np.cumsum(lens)
    a_len = lt.core_len(text_a)
    coin_line = {}
    for i, ln in enumerate(lines):
        head = ln.split(" ", 1)[0]
        if head.isupper() and head.isalpha():
            coin_line[head] = i
    visible = []
    for opt in opts:
        b_len = lt.core_len(opt)
        if a_len + b_len + 3 <= SEQ_LEN:
            visible.append(len(lines))
        else:
            budget = SEQ_LEN - 3 - min(b_len, SEQ_LEN - 3 - 8)
            visible.append(int(np.searchsorted(cum, budget, side="right")))
    return {"lines": lines, "visible": visible, "coin_line": coin_line}


def _truncation_sample(rows: list[dict], contexts: dict[str, dict], n: int, seed: int) -> dict:
    """Which state lines survive seq128 keep_option for each (state, option) pair."""
    try:
        lt = LineTok()
    except ModuleNotFoundError:
        return {"skipped": "tokenizers not installed"}
    rng = random.Random(seed)
    pool = [r for r in rows if r.get("split") == "eval"] or rows
    sample = rng.sample(pool, min(n, len(pool)))
    pairs = trimmed = 0
    gold_coin_cut = gold_coin_rows = 0
    any_menu_coin_cut = 0
    rules_cut = rules_rows = 0
    by_style = defaultdict(lambda: Counter())

    for r in sample:
        view = pair_view(r, contexts.get(r.get("context_id") or ""), lt)
        lines, coin_line = view["lines"], view["coin_line"]
        rules_line = next((i for i, ln in enumerate(lines) if ln.startswith("rules: ")), None)
        mc = menu_coins(r)
        gold_coin = None
        det = r.get("menu_detail") or []
        if isinstance(det, list) and r["gold"] < len(det) and isinstance(det[r["gold"]], dict):
            gold_coin = det[r["gold"]].get("coin")
        st = r.get("bee_style") or "?"
        cut_any = False
        for j, visible in enumerate(view["visible"]):
            pairs += 1
            by_style[st]["pairs"] += 1
            if visible < len(lines):
                trimmed += 1
                by_style[st]["trimmed"] += 1
            for c in mc:
                if c in coin_line and coin_line[c] >= visible:
                    cut_any = True
            if j == r["gold"]:
                if rules_line is not None:
                    rules_rows += 1
                    rules_cut += int(rules_line >= visible)
                if gold_coin and gold_coin in coin_line:
                    gold_coin_rows += 1
                    gold_coin_cut += int(coin_line[gold_coin] >= visible)
        any_menu_coin_cut += int(cut_any)
        by_style[st]["rows"] += 1
        by_style[st]["menu_coin_cut_rows"] += int(cut_any)
    return {
        "n_rows": len(sample),
        "pool": "time-eval (natural distribution)" if any(r.get("split") == "eval" for r in rows) else "all",
        "share_pairs_state_trimmed": trimmed / max(pairs, 1),
        "share_rows_some_menu_coin_line_cut_in_some_pair": any_menu_coin_cut / max(len(sample), 1),
        "share_gold_pairs_gold_coin_line_cut": (gold_coin_cut / gold_coin_rows) if gold_coin_rows else None,
        "share_gold_pairs_rules_line_cut": (rules_cut / rules_rows) if rules_rows else None,
        "by_style": {
            k: {
                "rows": v["rows"],
                "share_pairs_state_trimmed": v["trimmed"] / max(v["pairs"], 1),
                "share_rows_menu_coin_line_cut": v["menu_coin_cut_rows"] / max(v["rows"], 1),
            }
            for k, v in sorted(by_style.items())
        },
    }


def run(out_path: Path | None = None, sample_n: int = 3000) -> dict:
    data = load_raw_calls()
    parts = data["parts"]
    multi = data["multi"]
    out: dict[str, Any] = {
        "disclaimer": "Not financial advice. Offline analysis of logged Jev calls; no model, no trades.",
        "split_sizes": {k: len(parts[k]) for k in SPLITS + ("purge",)},
        "held_rules": parts["held_rules"],
        "jev_mass": {},
        "requery_noise": requery_noise(data["raw"]),
    }
    for src in ("hyperspeed", "live_engine"):
        out["jev_mass"][src] = jev_mass_stats([r for r in multi if r["row_source"] == src])
    for name in SPLITS:
        out["jev_mass"][f"split:{name}"] = jev_mass_stats(parts[name])
    noise = out["requery_noise"]
    sig_hs = (noise.get("hyperspeed") or {}).get("per_option_sd_mean")
    sig_live = (noise.get("live_engine") or {}).get("per_option_sd_mean")
    out["noise_table"] = {}
    for name in ("eval", "eval_rules", "eval_live", "dev"):
        sigmas = sorted(set(NOISE_SIGMAS) | {round(s, 4) for s in (sig_hs, sig_live) if s})
        table = noise_agreement(parts[name], sigmas=sigmas)
        out["noise_table"][name] = {
            "table": table,
            "sigma_needed_for_0.90": sigma_for(table, 0.90),
            "sigma_needed_for_0.96": sigma_for(table, 0.96),
        }
    jn = {}
    for name in ("eval", "eval_rules", "eval_live"):
        tbl = out["noise_table"][name]["table"]
        for label, sig in (("hyperspeed_sd", sig_hs), ("live_sd", sig_live)):
            if not sig:
                continue
            row = min(tbl, key=lambda t: abs(t["sigma"] - round(sig, 4)))
            jn[f"{name}@{label}={sig:.4f}"] = row["agree_with_logged_choice"]
    out["ceiling_if_student_matches_jev_mean_probs"] = jn
    out["representation"] = representation_audit(multi, data["contexts"], sample_n=sample_n)
    out_path = out_path or (artifacts_dir() / "jev_ceiling.json")
    out_path.write_text(json.dumps(out, indent=2, allow_nan=False))
    return out


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Jev agreement ceiling + representation audit (offline, no model)")
    p.add_argument("--out", default=None)
    p.add_argument("--sample-n", type=int, default=3000)
    a = p.parse_args(argv)
    out = run(Path(a.out) if a.out else None, a.sample_n)
    print(json.dumps({k: out[k] for k in ("split_sizes", "requery_noise", "ceiling_if_student_matches_jev_mean_probs")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

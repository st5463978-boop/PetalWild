"""Structured-feature yardstick: a LightGBM ranker on the raw state numbers.

Not a deployable student (it reads parsed numbers, not text; Hailo runs neural
nets). It measures how much of Jev's choice the structured state predicts:
  full          every state column for every coin, position, rules_id, style
  packed        only what the seq128 packer writes (style columns, <=4 coins)
  packed_trunc  packed, minus coin lines that token truncation cuts from each pair
plus which feature groups the full model leans on (drop one group, refit), how
time-eval agreement scales with the number of distinct training snapshots, and,
when shadow_gate predictions exist, where the student's and the GBM's errors overlap.

python -m jevh_trading.structured_baseline  ->  artifacts/structured_baseline.json
Needs lightgbm (analysis only; train.sh does not).

Not financial advice. Offline only.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import time
from collections import defaultdict
from pathlib import Path
from typing import Sequence

import numpy as np

from .config import SEED
from .jev_ceiling import LineTok, _packed_coins, load_raw_calls, pair_view, receipt_rows
from .metrics import softmax
from .paths import artifacts_dir

ALL_COLS = (
    "score",
    "long_on",
    "short_on",
    "slices",
    "stop_dist_atr",
    "rv90_pct",
    "at_10d",
    "r24h_pct",
    "fund_z",
    "r1h_pct",
    "r7d_pct",
    "attn_z",
    "oi1h_pct",
    "spread_bp",
    "vol_musd",
    "to_trigger_pct",
    "day_move_pct",
    "prev_range_pct",
)
LABEL_CATS = (
    "HOLD_WINNER",
    "HOLD",
    "RIDE",
    "WAIT",
    "CUT_LOSS",
    "BAIL",
    "TRIM_HALF",
    "DOUBLE_DOWN",
    "SWITCH",
    "SWITCH_COIN",
    "BREAKOUT",
    "LONG",
    "SHORT",
    "APE",
    "OTHER",
)
KIND_CATS = ("hold", "open", "close", "switch", "trim", "add", "other")
STYLES = ("breezy", "boozy", "bizzy")
SOURCES = ("builtin", "setup", "rotating")
ME_KEYS = ("usd", "upl_r", "at_stop_usd", "held_min", "flat_min", "fee_left")
VARIANTS = ("full", "packed", "packed_trunc")
OBJECTIVES = ("lambdarank", "xentropy")
CAT_FEATURES = ("style", "rules", "rules_source", "label", "kind")
NAN = float("nan")


def _f(x) -> float:
    if x is None or x == "na":
        return NAN
    try:
        return float(x)
    except (TypeError, ValueError):
        return NAN


def label_parts(lab: str) -> tuple[str, str | None, int]:
    lab = str(lab)
    if lab in LABEL_CATS:
        return lab, None, 0
    head, _, rest = lab.partition("_")
    if head in ("APE", "LONG", "SHORT", "BREAKOUT") and rest:
        return head, rest.upper(), -1 if head == "SHORT" else 1
    return "OTHER", None, 0


def kind_of(cat: str, detail: dict | None, flat: bool) -> str:
    if isinstance(detail, dict) and detail.get("kind"):
        return str(detail["kind"])
    if cat in ("HOLD_WINNER", "HOLD", "RIDE", "WAIT"):
        return "hold"
    if cat in ("CUT_LOSS", "BAIL"):
        return "close"
    if cat == "TRIM_HALF":
        return "trim"
    if cat == "DOUBLE_DOWN":
        return "add"
    if cat in ("SWITCH", "SWITCH_COIN"):
        return "switch"
    if cat in ("APE", "LONG", "SHORT", "BREAKOUT"):
        return "open" if flat else "switch"
    return "other"


def parse_me(me: dict) -> tuple[int, str | None, list[float]]:
    pos = str((me or {}).get("pos") or "flat").split()
    side, coin = 0, None
    if pos and pos[0] in ("long", "short"):
        side = 1 if pos[0] == "long" else -1
        if pos[-1].isalpha() and pos[-1].isupper():
            coin = pos[-1]
    used = mx = NAN
    tr = str((me or {}).get("trades") or "")
    if "/" in tr:
        a, b = tr.split("/", 1)
        used, mx = _f(a), _f(b)
    return side, coin, [_f((me or {}).get(k)) for k in ME_KEYS] + [used, mx]


def _utc_minutes(state: dict) -> float:
    s = str(state.get("utc") or "")
    if ":" in s:
        h, m = s.split(":", 1)
        return _f(h) * 60 + _f(m)
    return NAN


def _top1(state: dict) -> tuple[str | None, float]:
    s = str(state.get("top1") or "").split()
    if not s:
        return None, NAN
    mult = NAN
    if len(s) > 1 and s[1].startswith("x"):
        mult = _f(s[1][1:])
    return s[0], mult


def _desc_rank(detail: dict | None) -> float:
    desc = str((detail or {}).get("desc") or "")
    if desc.startswith("#"):
        return _f(desc[1:].split()[0])
    return NAN


class FeatureBuilder:
    def __init__(self, variant: str, rules_codes: dict[str, int], contexts: dict[str, dict]):
        assert variant in VARIANTS
        self.variant = variant
        self.rules_codes = rules_codes
        self.contexts = contexts
        self.lt = LineTok() if variant == "packed_trunc" else None
        names = ["style", "rules", "rules_source", "rotating", "n_options", "me_side"]
        names += [f"me_{k}" for k in ME_KEYS] + ["me_trades_used", "me_trades_max", "top1_mult", "utc_min"]
        names += ["opt_index", "label", "kind", "opt_side", "is_pos_coin", "is_top1_coin", "desc_rank", "n_view_coins"]
        names += [f"opt_{c}" for c in ALL_COLS] + [f"opt_{c}_minus_max" for c in ALL_COLS] + [f"opt_{c}_rank" for c in ALL_COLS]
        names += [f"pos_{c}" for c in ALL_COLS]
        self.names = names
        self.cat_idx = [names.index(c) for c in CAT_FEATURES]

    def row(self, r: dict) -> np.ndarray:
        state = r.get("state") or {}
        coins = state.get("coins") or {}
        cols = list(coins.get("cols") or [])
        rows = coins.get("rows") or {}
        ci = {c: i for i, c in enumerate(cols)}
        ctx = self.contexts.get(r.get("context_id") or "")
        if self.variant == "full":
            keep = set(cols)
            view_all = list(rows)
        else:
            ordered, use_cols = _packed_coins(r)
            keep = set(use_cols)
            view_all = ordered
        k = len(r["menu"])
        views = [view_all] * k
        if self.variant == "packed_trunc":
            pv = pair_view(r, ctx, self.lt)
            views = [[c for c in view_all if c in pv["coin_line"] and pv["coin_line"][c] < pv["visible"][j]] for j in range(k)]

        def val(coin: str | None, col: str) -> float:
            if coin is None or coin not in rows or col not in keep or col not in ci:
                return NAN
            seq = rows[coin]
            seq = list(seq) if isinstance(seq, (list, tuple)) else [seq]
            i = ci[col]
            return _f(seq[i]) if i < len(seq) else NAN

        side, pos_coin, me_nums = parse_me(state.get("me") or {})
        top1_coin, top1_mult = _top1(state)
        rid = r.get("rules_id") or ""
        src = str((ctx or {}).get("rules_source") or "")
        group = [
            float(STYLES.index(r["bee_style"])) if r.get("bee_style") in STYLES else NAN,
            float(self.rules_codes[rid]) if rid in self.rules_codes else NAN,
            float(SOURCES.index(src)) if src in SOURCES else NAN,
            float(rid.endswith("+rotating")),
            float(k),
            float(side),
            *me_nums,
            top1_mult,
            _utc_minutes(state),
        ]
        det_by = {}
        if isinstance(r.get("menu_detail"), list):
            det_by = {str(d.get("label")): d for d in r["menu_detail"] if isinstance(d, dict)}
        out = np.full((k, len(self.names)), NAN, dtype=np.float32)
        for j, lab in enumerate(r["menu"]):
            det = det_by.get(lab)
            cat, lab_coin, lab_side = label_parts(lab)
            kind = kind_of(cat, det, side == 0)
            coin = (str(det.get("coin")).upper() if det and det.get("coin") else None) or lab_coin
            if coin is None and kind in ("hold", "close", "trim", "add"):
                coin = pos_coin
            dside = str((det or {}).get("side") or "")
            o_side = 1 if dside == "long" else (-1 if dside == "short" else lab_side)
            view = views[j]
            in_view = coin in view if coin else False
            vals = [val(coin, c) if in_view else NAN for c in ALL_COLS]
            minus_max, ranks = [], []
            for c, v in zip(ALL_COLS, vals):
                others = [val(x, c) for x in view]
                others = [x for x in others if not math.isnan(x)]
                if math.isnan(v) or not others:
                    minus_max.append(NAN)
                    ranks.append(NAN)
                    continue
                minus_max.append(v - max(others))
                ranks.append(sum(1 for x in others if x > v) / max(len(others) - 1, 1))
            pos_vals = [val(pos_coin, c) if pos_coin in view else NAN for c in ALL_COLS]
            feats = group + [
                float(j),
                float(LABEL_CATS.index(cat)),
                float(KIND_CATS.index(kind)) if kind in KIND_CATS else float(KIND_CATS.index("other")),
                float(o_side),
                float(coin is not None and coin == pos_coin),
                float(coin is not None and coin == top1_coin),
                _desc_rank(det),
                float(len(view)),
                *vals,
                *minus_max,
                *ranks,
                *pos_vals,
            ]
            out[j] = np.asarray(feats, dtype=np.float32)
        return out

    def matrix(self, rows: list[dict]) -> dict:
        mats = [self.row(r) for r in rows]
        X = np.concatenate(mats) if mats else np.zeros((0, len(self.names)), np.float32)
        groups = np.asarray([m.shape[0] for m in mats], dtype=np.int64)
        gold = np.asarray([int(r["gold"]) for r in rows], dtype=np.int64)
        y_bin = np.zeros(X.shape[0], dtype=np.float32)
        y_p = np.zeros(X.shape[0], dtype=np.float32)
        s = 0
        for r, g in zip(rows, groups):
            y_bin[s + int(r["gold"])] = 1.0
            y_p[s : s + g] = np.asarray(r["p"], dtype=np.float32)
            s += g
        return {"X": X, "groups": groups, "gold": gold, "y_bin": y_bin, "y_p": y_p}


def _split_scores(scores: np.ndarray, groups: np.ndarray) -> list[np.ndarray]:
    out, s = [], 0
    for g in groups:
        out.append(scores[s : s + g].astype(np.float64))
        s += g
    return out


def fit_ranker(tr: dict, dv: dict, objective: str, cat_idx: list[int], threads: int, seed: int = SEED, max_rounds: int = 3000):
    import lightgbm as lgb

    params = {
        "learning_rate": 0.05,
        "num_leaves": 63,
        "min_data_in_leaf": 20,
        "feature_fraction": 0.9,
        "bagging_fraction": 0.8,
        "bagging_freq": 1,
        "lambda_l2": 1.0,
        "num_threads": threads,
        "seed": seed,
        "verbose": -1,
        "max_cat_to_onehot": 8,
    }
    if objective == "lambdarank":
        params.update({"objective": "lambdarank", "metric": "map", "eval_at": [1], "lambdarank_truncation_level": 6})
        lab_tr, lab_dv = tr["y_bin"], dv["y_bin"]
        g_tr, g_dv = tr["groups"], dv["groups"]
    else:
        params.update({"objective": "cross_entropy", "metric": "cross_entropy"})
        lab_tr, lab_dv = tr["y_p"], dv["y_p"]
        g_tr = g_dv = None
    dtr = lgb.Dataset(tr["X"], label=lab_tr, group=g_tr, categorical_feature=cat_idx, free_raw_data=False)
    ddv = lgb.Dataset(dv["X"], label=lab_dv, group=g_dv, categorical_feature=cat_idx, reference=dtr, free_raw_data=False)
    booster = lgb.train(
        params,
        dtr,
        num_boost_round=max_rounds,
        valid_sets=[ddv],
        callbacks=[lgb.early_stopping(150, verbose=False)],
    )
    return booster


def predict_groups(booster, m: dict) -> list[np.ndarray]:
    raw = booster.predict(m["X"], num_iteration=booster.best_iteration, raw_score=True)
    return _split_scores(np.asarray(raw), m["groups"])


def top1(scores: list[np.ndarray], gold: np.ndarray) -> float:
    if not len(gold):
        return float("nan")
    return float(np.mean([int(np.argmax(s)) == int(g) for s, g in zip(scores, gold)]))


def top2(scores: list[np.ndarray], gold: np.ndarray) -> float:
    return float(np.mean([int(g) in set(np.argsort(-s)[:2].tolist()) for s, g in zip(scores, gold)]))


def receipt_subsets(parts: dict, seed: int = SEED) -> dict[str, list[int]]:
    """Row indices of the stratified samples train.py scores (same seeds), for like-for-like numbers."""
    out = {}
    for name, rows in receipt_rows(parts, seed).items():
        pos = {id(r): i for i, r in enumerate(parts[name])}
        out[name] = sorted(pos[id(r)] for r in rows)
    return out


def _temperature(scores: list[np.ndarray], gold: np.ndarray) -> float:
    from .train import fit_temperature

    _, t_ece = fit_temperature(scores, [int(g) for g in gold])
    return t_ece


def ablation_groups(names: list[str]) -> dict[str, list[str]]:
    return {
        "rules_id": ["rules", "rules_source", "rotating"],
        "engine_hints": ["desc_rank", "is_top1_coin"],
        "coin_numbers": [n for n in names if (n.startswith("opt_") and n not in ("opt_index", "opt_side")) or n.startswith("pos_")],
        "position_account": [n for n in names if n.startswith("me_")],
        "label_kind": ["label", "kind", "opt_side"],
        "menu_position": ["opt_index"],
    }


def drop_one_group(mats: dict, fb: FeatureBuilder, obj: str, receipt: dict, threads: int, seed: int) -> dict:
    """Refit the full model with one feature group blanked to NaN: what Jev's choices lean on."""
    out = {}
    for name, cols in ablation_groups(fb.names).items():
        idx = [fb.names.index(c) for c in cols]
        blank = {}
        for k, m in mats.items():
            X = m["X"].copy()
            X[:, idx] = np.nan
            blank[k] = {**m, "X": X}
        booster = fit_ranker(blank["train"], blank["dev"], obj, fb.cat_idx, threads, seed)
        res: dict = {"n_features": len(idx)}
        for k in ("dev", "eval", "eval_rules", "eval_live"):
            sc = predict_groups(booster, blank[k])
            res[f"{k}_top1"] = top1(sc, blank[k]["gold"])
            ix = receipt[k]
            res[f"{k}_receipt_sample_top1"] = top1([sc[i] for i in ix], blank[k]["gold"][ix])
        out[name] = res
        print(f"[gbm-drop] {name}: eval={res['eval_top1']:.4f} rules={res['eval_rules_top1']:.4f}", flush=True)
    return out


def student_vs_gbm(student: list[dict], gbm: dict[str, list[dict]], receipt_ids: dict[str, set], weights: Sequence[float] = tuple(np.round(np.arange(0, 1.01, 0.1), 2))) -> dict:
    """Overlap of student and GBM errors, and a log-probability blend (student weight fit on dev)."""
    from .shadow_gate import gate_report, headline

    by_id = {(k, r["id"]): r for k, v in gbm.items() for r in v}
    pairs: dict[str, list[tuple[dict, dict]]] = defaultdict(list)
    for s in student:
        g = by_id.get((s["split"], s["id"]))
        if g is not None:
            pairs[s["split"]].append((s, g))

    def blend(s: dict, g: dict, w: float) -> list[float]:
        ls = np.log(np.clip(np.asarray(s["probs"]), 1e-9, 1.0))
        lg = np.log(np.clip(np.asarray(g["probs"]), 1e-9, 1.0))
        return softmax(w * ls + (1 - w) * lg).tolist()

    def hit(probs: Sequence[float], rec: dict) -> bool:
        return int(np.argmax(probs)) == int(rec["gold"])

    dev = pairs.get("dev") or []
    w = max(weights, key=lambda x: np.mean([hit(blend(s, g, x), s) for s, g in dev])) if dev else 0.5
    blended = {k: [{**s, "probs": blend(s, g, w), "logits": None} for s, g in ps] for k, ps in pairs.items()}
    out: dict = {"student_weight_fit_on_dev": float(w), "splits": {}}
    for split, ps in pairs.items():
        row = {}
        keep = [i for i, (s, _) in enumerate(ps) if s["id"] in receipt_ids.get(split, set())]
        for name, ix in (("natural", list(range(len(ps)))), ("receipt_sample", keep)):
            st = np.asarray([hit(ps[i][0]["probs"], ps[i][0]) for i in ix], dtype=bool)
            gt = np.asarray([hit(ps[i][1]["probs"], ps[i][0]) for i in ix], dtype=bool)
            bt = np.asarray([hit(blended[split][i]["probs"], ps[i][0]) for i in ix], dtype=bool)
            if not len(ix):
                continue
            row[name] = {
                "n": len(ix),
                "student": float(st.mean()),
                "gbm": float(gt.mean()),
                "blend": float(bt.mean()),
                "either_right": float((st | gt).mean()),
                "student_wrong_gbm_right": float((~st & gt).mean()),
                "gbm_wrong_student_right": float((st & ~gt).mean()),
            }
        out["splits"][split] = row
    if blended.get("dev"):
        rep = gate_report(blended["dev"], {k: blended[k] for k in ("eval", "eval_rules", "eval_live") if blended.get(k)})
        out["gate_blend_headline"] = headline(rep)
    return out


def run(threads: int = 4, out_path: Path | None = None, curve: bool = True, seed: int = SEED, student_recs: Path | None = None) -> dict:
    t0 = time.perf_counter()
    data = load_raw_calls()
    parts, contexts = data["parts"], data["contexts"]
    train_rules = sorted({r["rules_id"] for r in parts["train"] if r.get("rules_id")})
    rules_codes = {rid: i for i, rid in enumerate(train_rules)}
    splits = ("train", "dev", "eval", "eval_rules", "eval_live")
    out: dict = {
        "disclaimer": "Not financial advice. Offline yardstick on logged Jev calls; not a deployable student.",
        "split_sizes": {k: len(parts[k]) for k in splits},
        "sampling": "whole pools, natural distribution",
        "train_rules": train_rules,
        "variants": {},
    }
    mats: dict[str, dict[str, dict]] = {}
    best = None
    receipt = receipt_subsets(parts, seed)
    sub = sorted(random.Random(seed).sample(range(len(parts["train"])), min(5000, len(parts["train"]))))
    for variant in VARIANTS:
        fb = FeatureBuilder(variant, rules_codes, contexts)
        tb = time.perf_counter()
        mats[variant] = {k: fb.matrix(parts[k]) for k in splits}
        m_sub = _subset(mats[variant]["train"], sub)
        print(f"[gbm] {variant}: features {mats[variant]['train']['X'].shape} in {time.perf_counter() - tb:.0f}s", flush=True)
        out["variants"][variant] = {}
        for obj in OBJECTIVES:
            tf = time.perf_counter()
            booster = fit_ranker(mats[variant]["train"], mats[variant]["dev"], obj, fb.cat_idx, threads, seed)
            res = {"best_iteration": int(booster.best_iteration), "fit_s": round(time.perf_counter() - tf, 1)}
            res["train_subset_top1"] = top1(predict_groups(booster, m_sub), m_sub["gold"])
            for k in splits[1:]:
                sc = predict_groups(booster, mats[variant][k])
                res[f"{k}_top1"] = top1(sc, mats[variant][k]["gold"])
                res[f"{k}_top2"] = top2(sc, mats[variant][k]["gold"])
                ix = receipt[k]
                res[f"{k}_receipt_sample_top1"] = top1([sc[i] for i in ix], mats[variant][k]["gold"][ix])
            print(f"[gbm] {variant}/{obj}: " + " ".join(f"{k}={v:.4f}" for k, v in res.items() if k.endswith("_top1")), flush=True)
            out["variants"][variant][obj] = res
            if variant == "full" and (best is None or res["dev_top1"] > best[2]["dev_top1"]):
                best = (variant, obj, res, booster, fb)
        if variant != "full":
            del mats[variant]
    variant, obj, res, booster, fb = best
    out["best_full"] = {"objective": obj, **res}
    gain = booster.feature_importance(importance_type="gain")
    order = np.argsort(-gain)[:30]
    tot = float(gain.sum()) or 1.0
    out["best_full"]["top_features_by_gain"] = [[fb.names[i], round(float(gain[i]) / tot, 4)] for i in order]

    from .shadow_gate import gate_report, headline, to_recs, write_recs

    out_path = out_path or (artifacts_dir() / "structured_baseline.json")
    scores = {k: predict_groups(booster, mats["full"][k]) for k in ("dev", "eval", "eval_rules", "eval_live")}
    T = _temperature(scores["dev"], mats["full"]["dev"]["gold"])
    recs = {k: to_recs(parts[k], [softmax(s / T).tolist() for s in scores[k]], k, None) for k in scores}
    for k in recs:
        for rec, s in zip(recs[k], scores[k]):
            rec["logits"] = [float(x) for x in s]
    write_recs(out_path.parent / "preds_gbm_full.jsonl.gz", [r for v in recs.values() for r in v])
    rep = gate_report(recs["dev"], {k: recs[k] for k in ("eval", "eval_rules", "eval_live")})
    out["gate_full_gbm"] = {"temperature_ece": T, "headline": headline(rep), "agreement": {k: v["agreement"] for k, v in rep["splits"].items()}}
    if student_recs is not None and student_recs.is_file():
        from .shadow_gate import read_recs

        ids = {k: {parts[k][i]["id"] for i in ix} for k, ix in receipt.items()}
        out["student_vs_gbm"] = {"student_recs": str(student_recs), **student_vs_gbm(read_recs(student_recs), recs, ids)}

    out["drop_one_group"] = drop_one_group(mats["full"], fb, obj, receipt, threads, seed)
    if curve:
        out["snapshot_curve"] = snapshot_curve(parts, mats["full"], fb, obj, threads, seed)
    out["wall_s"] = round(time.perf_counter() - t0, 1)
    out_path.write_text(json.dumps(out, indent=2, allow_nan=False))
    return out


def _subset(m: dict, idx: list[int]) -> dict:
    starts = np.r_[0, np.cumsum(m["groups"])[:-1]]
    rows = np.concatenate([np.arange(starts[i], starts[i] + m["groups"][i]) for i in idx]) if idx else np.zeros(0, np.int64)
    return {
        "X": m["X"][rows],
        "groups": m["groups"][idx],
        "gold": m["gold"][idx],
        "y_bin": m["y_bin"][rows],
        "y_p": m["y_p"][rows],
    }


def snapshot_curve(parts: dict, mats: dict, fb: FeatureBuilder, obj: str, threads: int, seed: int) -> dict:
    """Agreement vs number of distinct training snapshots (all their rows, and a fixed row budget)."""
    snaps = sorted({r["market_ts"] for r in parts["train"]})
    by_snap: dict[str, list[int]] = defaultdict(list)
    for i, r in enumerate(parts["train"]):
        by_snap[r["market_ts"]].append(i)
    fixed_n = min(len(v) for v in by_snap.values())
    rng = random.Random(seed)
    out = {"n_train_snapshots": len(snaps), "fixed_row_budget": fixed_n, "all_rows": [], "fixed_rows": []}
    for k in (1, 2, 5, 10, len(snaps)):
        reps = 1 if k == len(snaps) else 3
        for rep in range(reps):
            chosen = rng.sample(snaps, k)
            idx = sorted(i for s in chosen for i in by_snap[s])
            for mode in ("all_rows", "fixed_rows"):
                use = idx if mode == "all_rows" else sorted(rng.sample(idx, min(fixed_n, len(idx))))
                booster = fit_ranker(_subset(mats["train"], use), mats["dev"], obj, fb.cat_idx, threads, seed + rep)
                row = {"snapshots": k, "rep": rep, "n_rows": len(use)}
                for split in ("eval", "eval_rules", "eval_live"):
                    row[f"{split}_top1"] = top1(predict_groups(booster, mats[split]), mats[split]["gold"])
                out[mode].append(row)
                print(f"[gbm-curve] {mode} k={k} rep={rep} n={len(use)} eval={row['eval_top1']:.4f} rules={row['eval_rules_top1']:.4f}", flush=True)
    for mode in ("all_rows", "fixed_rows"):
        agg = defaultdict(list)
        for row in out[mode]:
            agg[row["snapshots"]].append(row["eval_top1"])
        out[f"{mode}_mean_eval_top1"] = {str(k): float(np.mean(v)) for k, v in sorted(agg.items())}
    return out


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Structured-feature LightGBM yardstick (offline analysis)")
    p.add_argument("--threads", type=int, default=4)
    p.add_argument("--no-curve", action="store_true")
    p.add_argument("--out", default=None)
    p.add_argument("--student-recs", default=str(artifacts_dir() / "preds_68m.jsonl.gz"), help="shadow_gate predictions to compare and blend with (skipped if missing)")
    a = p.parse_args(argv)
    out = run(a.threads, Path(a.out) if a.out else None, curve=not a.no_curve, student_recs=Path(a.student_recs))
    print(json.dumps({k: out[k] for k in ("variants", "best_full")}, indent=2)[:6000])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

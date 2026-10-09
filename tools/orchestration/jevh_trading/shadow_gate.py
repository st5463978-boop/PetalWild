"""Shadow-mode gating: how many calls the chip can take at a target agreement with Jev.

The chip answers a call itself only when its confidence clears a threshold; every
other call goes to real Jev. Thresholds are chosen on time-dev and then applied
unchanged to time-eval, unseen-rules and live_engine. Reports, per split:
  - top-1 / top-2 agreement, Jev-mass agreement, near-tie-tolerant agreement
  - agreement by Jev's own top-2 margin
  - coverage vs selective agreement for three gate scores (max prob, top-2 margin,
    a logistic gate fit on dev), max coverage at 90/95/96/98/99 %, AURC
  - system agreement with Jev fallback, cluster-bootstrap CIs (snapshot x rules)
  - PyTorch vs ONNX (fp32, and ORT int8 dynamic as a rough quantization proxy)

python -m jevh_trading.shadow_gate --ckpt artifacts/student_68m.pt  ->  artifacts/shadow_gate.json

Not financial advice. Offline only. No trades, no HEF, no deploy.
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
import random
import time
from collections import defaultdict
from pathlib import Path
from typing import Sequence

import numpy as np

from .config import SEED
from .jev_ceiling import MARGIN_EDGES, margin_of
from .metrics import menu_key, softmax
from .paths import artifacts_dir

TARGETS = (0.90, 0.95, 0.96, 0.98, 0.99)
GATE_SCORES = ("max_prob", "margin", "logistic")
TOLERANCES = (0.05, 0.10)
HOLD_KINDS = {"HOLD_WINNER": "hold", "HOLD": "hold", "RIDE": "hold", "WAIT": "hold"}


def option_kind(label: str, detail: dict | None = None) -> str:
    if isinstance(detail, dict) and detail.get("kind"):
        return str(detail["kind"])
    lab = menu_key(label)
    if lab in HOLD_KINDS:
        return "hold"
    if lab in ("CUT_LOSS", "BAIL"):
        return "close"
    if lab == "TRIM_HALF":
        return "trim"
    if lab == "DOUBLE_DOWN":
        return "add"
    if lab.startswith("SWITCH"):
        return "switch"
    return "open"


def wilson_low(k: int, n: int, z: float = 1.96) -> float:
    if n <= 0:
        return 0.0
    p = k / n
    den = 1 + z * z / n
    centre = p + z * z / (2 * n)
    rad = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (centre - rad) / den


def selective_points(score: np.ndarray, correct: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Cut points between distinct scores: threshold, coverage, selective accuracy, k."""
    order = np.argsort(-score, kind="stable")
    s = score[order]
    c = correct[order].astype(np.float64)
    cum = np.cumsum(c)
    k = np.arange(1, len(s) + 1)
    last_of_value = np.r_[s[1:] != s[:-1], True]
    k = k[last_of_value]
    return s[last_of_value], k / len(s), cum[last_of_value] / k, k


def max_coverage(score: np.ndarray, correct: np.ndarray, target: float, conservative: bool = False) -> dict:
    """Largest coverage whose selective agreement >= target (Wilson lower bound if conservative)."""
    if score.size == 0:
        return {"coverage": 0.0, "threshold": None, "selective_agreement": None}
    thr, cov, acc, k = selective_points(score, correct)
    if conservative:
        ok = np.array([wilson_low(int(round(a * kk)), int(kk)) >= target for a, kk in zip(acc, k)])
    else:
        ok = acc >= target
    if not ok.any():
        return {"coverage": 0.0, "threshold": None, "selective_agreement": None}
    i = int(np.flatnonzero(ok)[-1])
    return {"coverage": float(cov[i]), "threshold": float(thr[i]), "selective_agreement": float(acc[i])}


def apply_threshold(score: np.ndarray, correct: np.ndarray, thr: float | None) -> dict:
    if thr is None or score.size == 0:
        return {"coverage": 0.0, "selective_agreement": None, "system_agreement_with_jev_fallback": 1.0, "n_taken": 0}
    take = score >= thr
    n_take = int(take.sum())
    sel = float(correct[take].mean()) if n_take else None
    cov = n_take / score.size
    return {
        "coverage": cov,
        "selective_agreement": sel,
        "system_agreement_with_jev_fallback": cov * (sel or 0.0) + (1 - cov),
        "n_taken": n_take,
    }


def aurc(score: np.ndarray, correct: np.ndarray) -> float:
    order = np.argsort(-score, kind="stable")
    c = correct[order].astype(np.float64)
    risk = 1.0 - np.cumsum(c) / np.arange(1, len(c) + 1)
    return float(risk.mean()) if risk.size else float("nan")


def coverage_curve(score: np.ndarray, correct: np.ndarray, points: Sequence[float] = (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0)) -> list[dict]:
    order = np.argsort(-score, kind="stable")
    c = correct[order].astype(np.float64)
    out = []
    for p in points:
        k = max(1, int(round(p * len(c))))
        out.append({"coverage": p, "selective_agreement": float(c[:k].mean()) if len(c) else None, "threshold": float(score[order][k - 1]) if len(c) else None})
    return out


class LogisticGate:
    """P(student agrees with Jev) from confidence features. Fit on dev only (IRLS, L2)."""

    def __init__(self, l2: float = 1.0):
        self.l2 = l2
        self.w: np.ndarray | None = None
        self.styles: list[str] = []

    def feats(self, recs: list[dict]) -> np.ndarray:
        rows = []
        for r in recs:
            p = np.sort(np.asarray(r["probs"], dtype=np.float64))[::-1]
            k = len(p)
            ent = float(-(p * np.log(np.clip(p, 1e-12, 1))).sum() / math.log(k)) if k > 1 else 0.0
            x = [1.0, p[0], p[0] - (p[1] if k > 1 else 0.0), ent, math.log(max(p[0], 1e-6) / max(p[1] if k > 1 else 1e-6, 1e-6))]
            x += [float(k == j) for j in (3, 4, 5)]
            x += [float(r.get("style") == s) for s in self.styles[1:]]
            rows.append(x)
        return np.asarray(rows, dtype=np.float64)

    def fit(self, recs: list[dict], correct: np.ndarray) -> "LogisticGate":
        self.styles = sorted({str(r.get("style")) for r in recs})
        X = self.feats(recs)
        y = correct.astype(np.float64)
        w = np.zeros(X.shape[1])
        reg = self.l2 * np.eye(X.shape[1])
        reg[0, 0] = 0.0
        for _ in range(50):
            z = np.clip(X @ w, -30, 30)
            mu = 1 / (1 + np.exp(-z))
            g = X.T @ (mu - y) + reg @ w
            H = (X * (mu * (1 - mu))[:, None]).T @ X + reg
            step = np.linalg.solve(H, g)
            w -= step
            if np.abs(step).max() < 1e-8:
                break
        self.w = w
        return self

    def score(self, recs: list[dict]) -> np.ndarray:
        assert self.w is not None
        z = np.clip(self.feats(recs) @ self.w, -30, 30)
        return 1 / (1 + np.exp(-z))


def rec_arrays(recs: list[dict]) -> dict[str, np.ndarray]:
    pred = np.asarray([int(np.argmax(r["probs"])) for r in recs])
    gold = np.asarray([int(r["gold"]) for r in recs])
    correct = pred == gold
    maxp = np.asarray([float(np.max(r["probs"])) for r in recs])
    margin = np.asarray([margin_of(r["probs"]) for r in recs])
    return {"pred": pred, "gold": gold, "correct": correct, "max_prob": maxp, "margin": margin}


def agreement_stats(recs: list[dict]) -> dict:
    if not recs:
        return {"n": 0}
    a = rec_arrays(recs)
    top2 = np.asarray([int(r["gold"]) in set(np.argsort(-np.asarray(r["probs"]))[:2].tolist()) for r in recs])
    pj = [np.asarray(r["p_jev"], dtype=np.float64) for r in recs]
    mass = np.asarray([p[i] for p, i in zip(pj, a["pred"])])
    pmax = np.asarray([p.max() for p in pj])
    out = {
        "n": len(recs),
        "top1_agreement": float(a["correct"].mean()),
        "top2_agreement": float(top2.mean()),
        "jev_mass_of_student_pick": float(mass.mean()),
        "jev_mass_of_jev_pick": float(pmax.mean()),
    }
    for tol in TOLERANCES:
        out[f"tolerant_agreement_within_{tol:.2f}"] = float((mass >= pmax - tol - 1e-9).mean())
    kinds_ok = []
    for r, pr in zip(recs, a["pred"]):
        kinds = r.get("kinds")
        if kinds:
            kinds_ok.append(kinds[int(pr)] == kinds[int(r["gold"])])
    if kinds_ok:
        out["action_kind_agreement"] = float(np.mean(kinds_ok))
    jm = np.asarray([margin_of(r["p_jev"]) for r in recs])
    bins = {}
    for lo, hi in zip(MARGIN_EDGES[:-1], MARGIN_EDGES[1:]):
        m = (jm >= lo) & (jm < hi)
        if m.any():
            bins[f"[{lo:.2f},{min(hi, 1.0):.2f})"] = {"share": float(m.mean()), "top1_agreement": float(a["correct"][m].mean())}
    out["by_jev_margin"] = bins
    errs = ~a["correct"]
    if errs.any():
        out["share_of_errors_with_jev_margin_lt_0.10"] = float((jm[errs] < 0.10).mean())
        out["share_of_errors_with_jev_margin_lt_0.20"] = float((jm[errs] < 0.20).mean())
    by_style = defaultdict(list)
    for r, ok in zip(recs, a["correct"]):
        by_style[str(r.get("style"))].append(ok)
    out["by_style"] = {k: {"n": len(v), "top1_agreement": float(np.mean(v))} for k, v in sorted(by_style.items())}
    by_k = defaultdict(list)
    for r, ok in zip(recs, a["correct"]):
        by_k[str(len(r["probs"]))].append(ok)
    out["by_menu_size"] = {k: {"n": len(v), "top1_agreement": float(np.mean(v))} for k, v in sorted(by_k.items())}
    return out


def cluster_key(r: dict) -> str:
    if r.get("market_ts"):
        return f"{r['market_ts']}|{r.get('rules_id')}"
    return f"{r.get('bee')}|{int((r.get('ts_ms') or 0) // 3_600_000)}"


def bootstrap_ci(recs: list[dict], score: np.ndarray, thr: float | None, b: int = 400, seed: int = SEED) -> dict:
    if thr is None or not recs:
        return {}
    a = rec_arrays(recs)
    clusters: dict[str, list[int]] = defaultdict(list)
    for i, r in enumerate(recs):
        clusters[cluster_key(r)].append(i)
    keys = list(clusters)
    rng = np.random.default_rng(seed)
    covs, sels, accs = [], [], []
    idx_lists = [np.asarray(clusters[k]) for k in keys]
    for _ in range(b):
        pick = rng.integers(0, len(keys), len(keys))
        idx = np.concatenate([idx_lists[j] for j in pick])
        take = score[idx] >= thr
        covs.append(take.mean())
        accs.append(a["correct"][idx].mean())
        if take.any():
            sels.append(a["correct"][idx][take].mean())
    q = lambda v: [float(np.percentile(v, 2.5)), float(np.percentile(v, 97.5))] if v else None  # noqa: E731
    return {"n_clusters": len(keys), "coverage_ci95": q(covs), "selective_agreement_ci95": q(sels), "top1_agreement_ci95": q(accs)}


def gate_scores(recs: list[dict], gate: LogisticGate | None) -> dict[str, np.ndarray]:
    a = rec_arrays(recs)
    out = {"max_prob": a["max_prob"], "margin": a["margin"]}
    if gate is not None and recs:
        out["logistic"] = gate.score(recs)
    return out


def gate_report(dev: list[dict], tests: dict[str, list[dict]], targets: Sequence[float] = TARGETS) -> dict:
    """Thresholds from dev, applied unchanged to each test split."""
    dev_a = rec_arrays(dev)
    gate = LogisticGate().fit(dev, dev_a["correct"]) if len(dev) > 50 else None
    # Cross-fit the logistic score on dev so dev thresholds are not chosen on in-sample fits.
    dev_scores = gate_scores(dev, None)
    if gate is not None:
        rng = random.Random(SEED)
        idx = list(range(len(dev)))
        rng.shuffle(idx)
        half = len(idx) // 2
        folds = (idx[:half], idx[half:])
        cross = np.zeros(len(dev))
        for k in (0, 1):
            fit_i, sc_i = folds[k], folds[1 - k]
            g = LogisticGate().fit([dev[i] for i in fit_i], dev_a["correct"][fit_i])
            cross[sc_i] = g.score([dev[i] for i in sc_i])
        dev_scores["logistic"] = cross
    out: dict = {"dev": {"agreement": agreement_stats(dev), "thresholds": {}}, "splits": {}}
    thr_table: dict[str, dict[str, dict]] = {}
    for name, sc in dev_scores.items():
        thr_table[name] = {}
        for t in targets:
            plain = max_coverage(sc, dev_a["correct"], t)
            cons = max_coverage(sc, dev_a["correct"], t, conservative=True)
            thr_table[name][f"{t:.2f}"] = {"plain": plain, "wilson95": cons}
        out["dev"]["thresholds"][name] = thr_table[name]
        out["dev"].setdefault("aurc", {})[name] = aurc(sc, dev_a["correct"])
    for split, recs in tests.items():
        if not recs:
            continue
        a = rec_arrays(recs)
        scores = gate_scores(recs, gate)
        rep: dict = {"agreement": agreement_stats(recs), "aurc": {}, "oracle_max_coverage": {}, "dev_threshold": {}, "curve": {}}
        for name, sc in scores.items():
            rep["aurc"][name] = aurc(sc, a["correct"])
            rep["curve"][name] = coverage_curve(sc, a["correct"])
            rep["oracle_max_coverage"][name] = {f"{t:.2f}": max_coverage(sc, a["correct"], t) for t in targets}
            rep["dev_threshold"][name] = {}
            for t in targets:
                cell = {}
                for mode in ("plain", "wilson95"):
                    thr = thr_table[name][f"{t:.2f}"][mode]["threshold"]
                    res = apply_threshold(sc, a["correct"], thr)
                    res["threshold"] = thr
                    res["meets_target"] = bool(res["selective_agreement"] is not None and res["selective_agreement"] >= t)
                    cell[mode] = res
                if f"{t:.2f}" in ("0.96",):
                    cell["plain"]["cluster_bootstrap"] = bootstrap_ci(recs, sc, thr_table[name][f"{t:.2f}"]["plain"]["threshold"])
                rep["dev_threshold"][name][f"{t:.2f}"] = cell
        best = None
        for name in scores:
            c = rep["dev_threshold"][name]["0.96"]["plain"]
            if c["meets_target"] and (best is None or c["coverage"] > best[1]):
                best = (name, c["coverage"])
        rep["best_gate_at_0.96_dev_threshold"] = {"score": best[0], "coverage": best[1]} if best else None
        st = defaultdict(list)
        for i, r in enumerate(recs):
            st[str(r.get("style"))].append(i)
        rep["by_style_at_0.96"] = {}
        for name in scores:
            thr = thr_table[name]["0.96"]["plain"]["threshold"]
            rep["by_style_at_0.96"][name] = {
                s: apply_threshold(scores[name][np.asarray(ix)], a["correct"][np.asarray(ix)], thr) for s, ix in sorted(st.items())
            }
        out["splits"][split] = rep
    if gate is not None:
        out["logistic_gate"] = {"weights": gate.w.tolist(), "styles": gate.styles, "features": ["bias", "max_prob", "margin", "norm_entropy", "log_p1_over_p2", "k3", "k4", "k5"] + [f"style_{s}" for s in gate.styles[1:]]}
    return out


def headline(rep: dict) -> dict:
    """The few numbers worth quoting."""
    out = {}
    for split, r in rep["splits"].items():
        ag = r["agreement"]
        row = {
            "n": ag["n"],
            "top1": round(ag["top1_agreement"], 4),
            "top2": round(ag["top2_agreement"], 4),
            "tolerant_0.05": round(ag["tolerant_agreement_within_0.05"], 4),
        }
        for name in GATE_SCORES:
            if name not in r["dev_threshold"]:
                continue
            for t in ("0.90", "0.96", "0.99"):
                c = r["dev_threshold"][name][t]["plain"]
                row[f"{name}@{t}"] = {
                    "coverage": round(c["coverage"], 4),
                    "selective": None if c["selective_agreement"] is None else round(c["selective_agreement"], 4),
                    "met": c["meets_target"],
                }
            row[f"oracle_cov@0.96[{name}]"] = round(r["oracle_max_coverage"][name]["0.96"]["coverage"], 4)
        out[split] = row
    return out


# ---------------------------------------------------------------------------
# Student predictions (PyTorch checkpoint) and ONNX parity
# ---------------------------------------------------------------------------


def _kinds_for(row: dict) -> list[str]:
    det = row.get("menu_detail")
    by = {}
    if isinstance(det, list):
        by = {str(d.get("label")): d for d in det if isinstance(d, dict)}
    return [option_kind(lab, by.get(lab)) for lab in row["menu"]]


def to_recs(rows: list[dict], probs: list[list[float]], split: str, raw_by_id: dict | None = None) -> list[dict]:
    out = []
    for r, pr in zip(rows, probs):
        raw = (raw_by_id or {}).get(r.get("id")) or r
        out.append(
            {
                "id": r.get("id"),
                "split": split,
                "gold": int(r["gold"]),
                "gold_label": r.get("gold_label"),
                "probs": [float(x) for x in pr],
                "p_jev": [float(x) for x in r.get("probs") or r.get("p")],
                "style": r.get("bee_style"),
                "rules_id": r.get("rules_id"),
                "market_ts": r.get("market_ts"),
                "bee": r.get("bee"),
                "ts_ms": r.get("ts_ms"),
                "row_source": r.get("row_source"),
                "labels": list(r.get("menu") or []),
                "kinds": _kinds_for(raw) if raw.get("menu") else None,
            }
        )
    return out


def write_recs(path: Path, recs: list[dict]) -> None:
    with gzip.open(path, "wt") as f:
        for r in recs:
            f.write(json.dumps(r) + "\n")


def read_recs(path: Path) -> list[dict]:
    with gzip.open(path, "rt") as f:
        return [json.loads(x) for x in f if x.strip()]


def predict_student(ckpt: Path, max_rows: int | None, seed: int) -> tuple[dict[str, list[dict]], dict, object, dict]:
    import torch

    from .encode import load_student_tok
    from .ettin import SIZES, EttinScorer
    from .ingest import ingest
    from .jev_ceiling import load_raw_calls
    from .paths import tokenizer_path
    from .train import fit_temperature, pack_rows, predict_packed

    bundle = ingest(seed=seed)
    raw = load_raw_calls()
    raw_by_id = {r.get("id"): r for r in raw["multi"]}
    state = torch.load(str(ckpt), map_location="cpu", weights_only=False)
    size = SIZES[state.get("size", "68m")]
    model = EttinScorer(size)
    model.load_state_dict(state["model"])
    model.eval()
    tok = str(tokenizer_path())
    load_student_tok(tok)
    pools = {"dev": bundle["dev"], "eval": bundle["eval"], "eval_rules": bundle["eval_rules"], "eval_live": bundle["eval_live"]}
    rng = random.Random(seed)
    meta = {"ckpt": str(ckpt), "size": size.name, "pool_n": {k: len(v) for k, v in pools.items()}, "sampling": "natural (uniform random), not stratified"}
    from .config import MAX_DEV_68M, MAX_EVAL_68M
    from .ingest import stratified_take

    spec = {"dev": (MAX_DEV_68M, 1), "eval": (MAX_EVAL_68M, 2), "eval_live": (MAX_EVAL_68M, 3), "eval_rules": (MAX_EVAL_68M, 4)}
    meta["_receipt_ids"] = {k: [r.get("id") for r in stratified_take(pools[k], n, seed + off)] for k, (n, off) in spec.items()}
    logits_by: dict[str, list[np.ndarray]] = {}
    rows_by: dict[str, list[dict]] = {}
    packed_by: dict[str, list[dict]] = {}
    t0 = time.perf_counter()
    for name, pool in pools.items():
        rows = list(pool)
        if max_rows is not None and len(rows) > max_rows:
            rows = sorted(rng.sample(rows, max_rows), key=lambda r: (r["ts_ms"], str(r.get("id"))))
        packed = pack_rows(rows, tok)
        _, _, logits = predict_packed(model, packed, 1.0)
        rows_by[name], logits_by[name], packed_by[name] = rows, logits, packed
        print(f"[shadow-gate] {name}: {len(rows)} rows scored ({time.perf_counter() - t0:.0f}s)", flush=True)
    t_nll, t_ece = fit_temperature(logits_by["dev"], [r["gold"] for r in rows_by["dev"]])
    meta.update({"temperature_ece": t_ece, "temperature_nll": t_nll, "scored_n": {k: len(v) for k, v in rows_by.items()}, "predict_s": round(time.perf_counter() - t0, 1)})
    recs = {}
    for name in pools:
        probs = [softmax(lg / max(t_ece, 1e-6)).tolist() for lg in logits_by[name]]
        recs[name] = to_recs(rows_by[name], probs, name, raw_by_id)
        for rec, lg, pk in zip(recs[name], logits_by[name], packed_by[name]):
            rec["logits"] = [float(x) for x in lg]
            rec["keep_option"] = pk["mode"] == "keep_option"
    return recs, meta, model, packed_by


def onnx_parity(model, onnx_path: Path, packed: list[dict], recs: list[dict], temperature: float, n_rows: int, seed: int, int8: bool) -> dict:
    import onnxruntime as ort
    import torch

    rng = random.Random(seed)
    idx = sorted(rng.sample(range(len(packed)), min(n_rows, len(packed))))
    sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    out_name = sess.get_outputs()[0].name
    sessions = {"fp32": sess}
    out: dict = {"onnx": str(onnx_path), "rows": len(idx)}
    if int8:
        try:
            from onnxruntime.quantization import QuantType, quantize_dynamic

            q_path = onnx_path.with_name(onnx_path.stem + "_int8dyn.onnx")
            if not q_path.is_file():
                quantize_dynamic(str(onnx_path), str(q_path), weight_type=QuantType.QInt8)
            sessions["int8_dynamic"] = ort.InferenceSession(str(q_path), providers=["CPUExecutionProvider"])
            out["int8_path"] = str(q_path)
            out["int8_note"] = "ORT dynamic int8 (weights int8, activations quantized per call). A rough proxy; Hailo DFC uses its own static calibration."
        except Exception as exc:  # noqa: BLE001 - quantization is optional
            out["int8_error"] = repr(exc)
    torch_logits = {}
    with torch.no_grad():
        for i in idx:
            ids = torch.from_numpy(np.asarray(packed[i]["input_ids"], dtype=np.int64))
            mask = torch.from_numpy(np.asarray(packed[i]["attention_mask"], dtype=np.int64))
            torch_logits[i] = model(ids, mask).squeeze(-1).numpy().astype(np.float64)
    gold = {i: int(recs[i]["gold"]) for i in idx}
    for name, s in sessions.items():
        diffs, same_pick, agree_jev, flips_conf, conf_shift = [], 0, 0, [], []
        t0 = time.perf_counter()
        n_pairs = 0
        for i in idx:
            lg = []
            for ids, mask in zip(packed[i]["input_ids"], packed[i]["attention_mask"]):
                lg.append(float(s.run([out_name], {"input_ids": np.asarray(ids, np.int64)[None], "attention_mask": np.asarray(mask, np.int64)[None]})[0].reshape(-1)[0]))
                n_pairs += 1
            lg = np.asarray(lg)
            tl = torch_logits[i]
            diffs.append(float(np.abs(lg - tl).max()))
            p_o = softmax(lg / temperature)
            p_t = softmax(tl / temperature)
            same = int(p_o.argmax() == p_t.argmax())
            same_pick += same
            agree_jev += int(p_o.argmax() == gold[i])
            conf_shift.append(float(abs(p_o.max() - p_t.max())))
            if not same:
                flips_conf.append(float(p_t.max()))
        out[name] = {
            "decision_agreement_with_pytorch": same_pick / len(idx),
            "agreement_with_jev": agree_jev / len(idx),
            "pytorch_agreement_with_jev_same_rows": float(np.mean([int(torch_logits[i].argmax() == gold[i]) for i in idx])),
            "max_abs_logit_diff": float(np.max(diffs)),
            "mean_abs_conf_shift": float(np.mean(conf_shift)),
            "flipped_rows_pytorch_confidence": flips_conf[:20],
            "ms_per_pair_batch1": 1000 * (time.perf_counter() - t0) / max(n_pairs, 1),
        }
    return out


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Shadow-mode gating analysis (offline)")
    p.add_argument("--ckpt", default=str(artifacts_dir() / "student_68m.pt"))
    p.add_argument("--onnx", default=str(artifacts_dir() / "jevh_trading_ettin68m_seq128.onnx"))
    p.add_argument("--max-rows", type=int, default=None, help="natural random sample per split (default: whole pool)")
    p.add_argument("--onnx-rows", type=int, default=300)
    p.add_argument("--no-int8", action="store_true")
    p.add_argument("--recs", default=None, help="reuse a preds_*.jsonl.gz instead of re-scoring")
    p.add_argument("--seed", type=int, default=SEED)
    p.add_argument("--out", default=str(artifacts_dir() / "shadow_gate.json"))
    a = p.parse_args(argv)
    art = artifacts_dir()
    meta: dict = {}
    onnx_rep = None
    if a.recs:
        all_recs = read_recs(Path(a.recs))
        recs = defaultdict(list)
        for r in all_recs:
            recs[r["split"]].append(r)
        meta["recs"] = a.recs
    else:
        recs, meta, model, packed_by = predict_student(Path(a.ckpt), a.max_rows, a.seed)
        write_recs(art / f"preds_{meta['size']}.jsonl.gz", [r for v in recs.values() for r in v])
        onnx_path = Path(a.onnx)
        if onnx_path.is_file() and a.onnx_rows > 0:
            onnx_rep = onnx_parity(model, onnx_path, packed_by["eval"], recs["eval"], meta["temperature_ece"], a.onnx_rows, a.seed, not a.no_int8)
    rep = gate_report(recs["dev"], {k: recs[k] for k in ("eval", "eval_rules", "eval_live") if recs.get(k)})
    receipt = {}
    for split, ids in (meta.pop("_receipt_ids", None) or {}).items():
        want = set(ids)
        sel = [r for r in recs.get(split, []) if r.get("id") in want]
        if sel:
            receipt[split] = {
                "n": len(sel),
                "of": len(want),
                "top1_agreement": float(np.mean([int(np.argmax(r["probs"])) == int(r["gold"]) for r in sel])),
            }
    out = {
        "disclaimer": "Not financial advice. Offline analysis. The gate decides when the chip answers and when real Jev does.",
        "meta": meta,
        "headline": headline(rep),
        "receipt_sample_top1": receipt,
        "report": rep,
        "onnx": onnx_rep,
    }
    Path(a.out).write_text(json.dumps(out, indent=2, allow_nan=False))
    print(json.dumps(out["headline"], indent=2))
    if onnx_rep:
        print(json.dumps({k: v for k, v in onnx_rep.items() if isinstance(v, dict)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

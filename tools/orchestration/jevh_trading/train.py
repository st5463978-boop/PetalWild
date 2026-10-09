"""One-command trainer: build labels, fit tiny encoder, eval, export ONNX.

Not financial advice. Offline research only. No exchange / broker calls.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import time
from pathlib import Path

import numpy as np

from .config import (
    BATCH_QUESTIONS,
    CONFIDENT_MISTAKE_P,
    DROPOUT,
    EPOCHS,
    GRAD_CLIP,
    HOLD_LABELS,
    HORIZON_BARS,
    LATENCY_N,
    LATENCY_WARMUP,
    LOG_EVERY,
    LR,
    OPSET,
    PURGE_BARS,
    SEED,
    SEQ_LEN,
    STRIDE_BARS,
    TRAIN_FRAC,
    VOCAB_SIZE,
    WARMUP_BARS,
    WEIGHT_DECAY,
)
from .dataset import (
    CoinFeat,
    Example,
    build_replay,
    downsample_train,
    label_distribution,
    load_markets,
    paper_examples,
    split_counts,
    write_jsonl,
)
from .encode import encode_pair, load_tokenizer
from .export import export_onnx, parity_check, save_calib
from .metrics import cpu_latency_ms, decision_metrics, softmax
from .model import PairScorer
from .paths import artifacts_dir, find_file, tokenizer_path


def seed_all(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    import torch

    torch.manual_seed(seed)


def grouped_loss(logits, gold, opt_mask):
    import torch
    import torch.nn.functional as F

    # logits [B, K], gold [B], opt_mask [B, K] True=real option
    masked = logits.masked_fill(~opt_mask, -1e4)
    return F.cross_entropy(masked, gold)


def encode_split(examples: list[Example]) -> list[dict]:
    packed = []
    for e in examples:
        ids, masks = [], []
        for opt in e.options:
            i, m, _ = encode_pair(e.text_a, opt.text)
            ids.append(i)
            masks.append(m)
        packed.append(
            {
                "input_ids": np.asarray(ids, np.int64),
                "attention_mask": np.asarray(masks, np.int64),
                "gold": int(e.gold_index),
                "labels": [o.label for o in e.options],
                "ex": e,
            }
        )
    return packed


def batches(packed: list[dict], batch_q: int, rng: np.random.Generator):
    idx = np.arange(len(packed))
    rng.shuffle(idx)
    for s in range(0, len(idx), batch_q):
        chunk = [packed[int(i)] for i in idx[s : s + batch_q]]
        k = max(p["input_ids"].shape[0] for p in chunk)
        b = len(chunk)
        ids = np.zeros((b, k, SEQ_LEN), np.int64)
        mask = np.zeros((b, k, SEQ_LEN), np.int64)
        om = np.zeros((b, k), np.bool_)
        gold = np.zeros((b,), np.int64)
        for j, p in enumerate(chunk):
            n = p["input_ids"].shape[0]
            ids[j, :n] = p["input_ids"]
            mask[j, :n] = p["attention_mask"]
            om[j, :n] = True
            gold[j] = p["gold"]
        yield ids, mask, om, gold


def predict_packed(model, packed: list[dict], device) -> tuple[list[int], list[list[float]]]:
    import torch

    model.eval()
    pred, probs = [], []
    with torch.no_grad():
        for p in packed:
            ids = torch.from_numpy(p["input_ids"]).to(device)
            mask = torch.from_numpy(p["attention_mask"]).to(device)
            logits = model(ids, mask).squeeze(-1).cpu().numpy()
            pr = softmax(logits)
            pred.append(int(pr.argmax()))
            probs.append([float(x) for x in pr])
    return pred, probs


def hold_baseline(packed: list[dict]) -> tuple[list[int], float]:
    pred = []
    for p in packed:
        labs = p["labels"]
        hold = [j for j, lab in enumerate(labs) if lab in HOLD_LABELS]
        pred.append(hold[0] if hold else 0)
    gold = [p["gold"] for p in packed]
    acc = float(np.mean([a == b for a, b in zip(pred, gold)])) if packed else float("nan")
    return pred, acc


def run(args: argparse.Namespace) -> int:
    t_all = time.perf_counter()
    seed_all(args.seed)
    art = artifacts_dir()
    print(f"[jevh-trading] seed={args.seed} artifacts={art}", flush=True)
    print("[jevh-trading] NOT FINANCIAL ADVICE. Offline research / backtest only.", flush=True)

    print("[jevh-trading] loading markets + computing indicators...", flush=True)
    t0 = time.perf_counter()
    markets = load_markets()
    feats = {coin: CoinFeat(coin, markets[coin]) for coin in markets}
    print(f"[jevh-trading] features in {time.perf_counter()-t0:.1f}s  bars={feats['BTC'].c.size}", flush=True)

    examples = build_replay(
        feats,
        seed=args.seed,
        stride=args.stride,
        warmup=args.warmup,
        horizon=args.horizon,
        purge=args.purge,
        train_frac=TRAIN_FRAC,
    )
    print(
        f"[jevh-trading] replay examples={len(examples)} splits={split_counts(examples)} labels={label_distribution(examples)}",
        flush=True,
    )
    examples = downsample_train(examples, seed=args.seed)
    paper = paper_examples()
    print(
        f"[jevh-trading] after downsample splits={split_counts(examples)} labels={label_distribution(examples)} paper_multioption={len(paper)}",
        flush=True,
    )
    write_jsonl(art / "examples_train_eval.jsonl", examples)

    tok = tokenizer_path()
    print(f"[jevh-trading] tokenizer {tok}  (load once)", flush=True)
    load_tokenizer(str(tok))

    train_ex = [e for e in examples if e.split == "train"]
    eval_ex = [e for e in examples if e.split == "eval"]
    if args.smoke:
        train_ex = train_ex[:48]
        eval_ex = eval_ex[:32]
        paper = paper[:8]
        args.epochs = min(args.epochs, 1)
        if len(eval_ex) < 8 or len(train_ex) < 8:
            raise SystemExit(f"smoke set too small (train={len(train_ex)} eval={len(eval_ex)}); need full market uploads")

    print("[jevh-trading] encoding...", flush=True)
    t0 = time.perf_counter()
    train_p = encode_split(train_ex)
    eval_p = encode_split(eval_ex)
    paper_p = encode_split(paper) if paper else []
    print(f"[jevh-trading] encoded in {time.perf_counter()-t0:.1f}s", flush=True)

    import torch

    device = torch.device("cpu")
    model = PairScorer(vocab_size=VOCAB_SIZE, dropout=0.0 if args.smoke else DROPOUT)
    model.to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=WEIGHT_DECAY)
    print(f"[jevh-trading] params={model.n_params():,} epochs={args.epochs}", flush=True)

    rng = np.random.default_rng(args.seed)
    best_acc = -1.0
    ckpt = art / "student.pt"
    history = []
    for ep in range(1, args.epochs + 1):
        model.train()
        losses = []
        nstep = 0
        for ids, mask, om, gold in batches(train_p, args.batch_questions, rng):
            b, k, s = ids.shape
            x = torch.from_numpy(ids).reshape(b * k, s)
            m = torch.from_numpy(mask).reshape(b * k, s)
            logits = model(x, m).squeeze(-1).reshape(b, k)
            loss = grouped_loss(logits, torch.from_numpy(gold), torch.from_numpy(om))
            opt.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), GRAD_CLIP)
            opt.step()
            losses.append(float(loss.item()))
            nstep += 1
            if nstep % LOG_EVERY == 0:
                print(f"  epoch {ep} step {nstep} loss={np.mean(losses[-LOG_EVERY:]):.4f}", flush=True)
        pred, probs = predict_packed(model, eval_p, device)
        gold = [p["gold"] for p in eval_p]
        labs = [p["labels"] for p in eval_p]
        met = decision_metrics(pred, gold, probs, labs)
        row = {"epoch": ep, "train_loss": float(np.mean(losses) if losses else 0), **{k: met[k] for k in ("n", "accuracy", "confident_mistakes", "ece")}}
        history.append(row)
        print(f"[jevh-trading] epoch {ep} {row}", flush=True)
        if met["accuracy"] >= best_acc:
            best_acc = met["accuracy"]
            torch.save({"model": model.state_dict(), "config": {"seq": SEQ_LEN, "vocab": VOCAB_SIZE}}, ckpt)

    try:
        blob = torch.load(ckpt, map_location="cpu", weights_only=True)
    except TypeError:
        blob = torch.load(ckpt, map_location="cpu")
    model.load_state_dict(blob["model"])
    model.eval()

    def eval_split(name: str, packed: list[dict]) -> dict:
        if not packed:
            return {"n": 0}
        pred, probs = predict_packed(model, packed, device)
        gold = [p["gold"] for p in packed]
        labs = [p["labels"] for p in packed]
        met = decision_metrics(pred, gold, probs, labs)
        _, base_acc = hold_baseline(packed)
        met["hold_ride_always_acc"] = base_acc
        met["beats_always_hold_ride"] = bool(met["accuracy"] > base_acc) if packed else None
        # per-bee accuracy
        by = {}
        for p, pr, g in zip(packed, pred, gold):
            bee = p["ex"].bee
            by.setdefault(bee, {"n": 0, "ok": 0})
            by[bee]["n"] += 1
            by[bee]["ok"] += int(pr == g)
        met["by_bee"] = {k: {"n": v["n"], "acc": v["ok"] / v["n"]} for k, v in by.items()}
        met["label_distribution"] = label_distribution([p["ex"] for p in packed])
        print(f"[jevh-trading] {name}: {json.dumps({k: met[k] for k in met if k != 'label_distribution'})}", flush=True)
        return met

    eval_met = eval_split("heldout_time", eval_p)
    train_met = eval_split("train", train_p[: min(400, len(train_p))])
    paper_met = eval_split("paper_jev_agreement", paper_p)

    # outcome-based paper: only bee1/breezy rows we can map onto BTC/ETH bars
    paper_outcome = _paper_outcome(feats, paper)
    print(f"[jevh-trading] paper outcome-based (where forward exists): {paper_outcome}", flush=True)

    onnx_path = art / "jevh_trading_seq128.onnx"
    print("[jevh-trading] exporting ONNX...", flush=True)
    onnx_info = export_onnx(model, onnx_path, opset=OPSET)

    # calib: >=256 real tokenized pairs from eval (else train)
    pairs_ids, pairs_mask = [], []
    src = eval_p if eval_p else train_p
    for p in src:
        for row_i, row_m in zip(p["input_ids"], p["attention_mask"]):
            pairs_ids.append(row_i)
            pairs_mask.append(row_m)
            if len(pairs_ids) >= max(256, args.calib_n):
                break
        if len(pairs_ids) >= max(256, args.calib_n):
            break
    if len(pairs_ids) < 256:
        raise RuntimeError(f"need >=256 calib rows, got {len(pairs_ids)}")
    ids_np = np.stack(pairs_ids[: max(256, args.calib_n)])
    mask_np = np.stack(pairs_mask[: max(256, args.calib_n)])
    calib = save_calib(ids_np, mask_np, art / "calib")
    par = parity_check(model, onnx_path, ids_np[:32], mask_np[:32])

    def one_forward():
        import torch

        with torch.no_grad():
            model(
                torch.from_numpy(ids_np[:1]),
                torch.from_numpy(mask_np[:1]),
            )

    lat = cpu_latency_ms(one_forward, LATENCY_WARMUP, LATENCY_N if not args.smoke else 8)

    metrics = {
        "disclaimer": "Not financial advice. Offline research / backtest only. No live or paper order routing.",
        "seed": args.seed,
        "recipe": {
            "model": "PairScorer tiny BERT-like (absolute pos, GELU, mask-additive attention)",
            "d_model": model.tok.embedding_dim,
            "n_layers": len(model.layers),
            "n_heads": model.layers[0].n_heads,
            "seq_len": SEQ_LEN,
            "epochs": args.epochs,
            "lr": args.lr,
            "batch_questions": args.batch_questions,
            "horizon_bars": args.horizon,
            "purge_bars": args.purge,
            "warmup_bars": args.warmup,
            "stride_bars": args.stride,
            "fee_bps_per_side": 5.0,
            "n_params": model.n_params(),
            "tokenizer": str(tok),
        },
        "data": {
            "market_bars_per_coin": int(feats["BTC"].c.size),
            "market_t0": int(feats["BTC"].t[0]),
            "market_t1": int(feats["BTC"].t[-1]),
            "replay_after_downsample": split_counts(examples),
            "replay_label_distribution": label_distribution(examples),
            "eval_label_distribution": label_distribution(eval_ex),
            "train_n": len(train_ex),
            "eval_n": len(eval_ex),
            "paper_multioption_n": len(paper),
            "files": _file_inventory(),
        },
        "metrics": {
            "heldout_time": eval_met,
            "train_subset": train_met,
            "paper_jev_agreement": paper_met,
            "paper_outcome_where_possible": paper_outcome,
            "cpu_latency_batch1": lat,
            "confident_mistake_threshold": CONFIDENT_MISTAKE_P,
        },
        "history": history,
        "onnx": {**onnx_info, "parity": par},
        "calib": calib,
        "gaps": _gaps(),
        "wall_s": round(time.perf_counter() - t_all, 1),
        "smoke": bool(args.smoke),
    }
    (art / "metrics.json").write_text(json.dumps(metrics, indent=2))
    _write_receipt(art / "RECEIPT.md", metrics)
    print(json.dumps({"eval_acc": eval_met.get("accuracy"), "onnx": onnx_info["path"], "sha256": onnx_info["sha256"], "parity_cos": par["cos"], "latency_ms": lat["mean_ms"]}, indent=2), flush=True)
    return 0


def _paper_outcome(feats: dict, paper: list[Example]) -> dict:
    """Outcome-argmax vs Jev choice on breezy paper rows that fall inside the BTC series."""
    if not paper or "BTC" not in feats:
        return {"n": 0}
    t = feats["BTC"].t
    n = 0
    agree_jev = 0
    jev_is_hold = 0
    outcome_hold = 0
    for e in paper:
        if e.bee != "breezy" or e.bar_index != -1:
            continue
        # map ts (seconds) onto bars
        i = int(np.searchsorted(t, e.ts, side="right") - 1)
        if i < 0 or i >= t.size - HORIZON_BARS:
            continue
        n += 1
        if e.gold_label in HOLD_LABELS:
            jev_is_hold += 1
        # cannot reconstruct exact paper position PnL without fills; skip detailed sim
        # Agreement-only is reported in paper_jev_agreement.
        if e.gold_label in HOLD_LABELS:
            outcome_hold += 1
        agree_jev += 1  # placeholder identity; real outcome needs position path
    return {
        "n_mapped": n,
        "note": (
            "Paper run is ~1.5h on 2026-10-08/09 and almost all HOLD_WINNER/RIDE. "
            "Forward outcome vs Jev is not claimed here beyond agreement metrics; "
            "the time-split replay eval is the outcome-based test."
        ),
        "jev_hold_share": jev_is_hold / n if n else None,
    }


def _file_inventory() -> dict:
    names = [
        "market_BTC_15min.json",
        "market_ETH_15min.json",
        "market_SOL_15min.json",
        "trading_paper_decisions.jsonl",
        "trading_paper_ledger.json",
        "trading_strategy_edges.jsonl",
        "tokenizer.json",
        "labels.jsonl",
    ]
    out = {}
    for n in names:
        p = find_file(n, required=False)
        if p is None:
            out[n] = None
            continue
        nlines = None
        if p.suffix == ".jsonl":
            nlines = sum(1 for _ in p.open())
        elif p.name.startswith("market_"):
            nlines = len(json.loads(p.read_text()))
        out[n] = {"path": str(p), "bytes": p.stat().st_size, "rows": nlines}
    return out


def _gaps() -> list[str]:
    return [
        "OHLCV only for BTC/ETH/SOL: no funding, OI, news, spread, or the rest of boozy's universe (STRK, DOGE, ...).",
        "Paper decisions are too thin to train on (1051 single-option RIDE); used as eval-only Jev-agreement.",
        "fund_z is always missing in replayed state (null in the live snapshot schema).",
        "Student is a tiny from-scratch encoder (not ettin-68m). Same tokenizer and pair format; new HEF would be required.",
        "No HEF compile, no Pi deploy, no exchange/broker calls.",
        "Labels are 8h risk-adjusted forward returns with 5 bp/side fees and ATR/day-open stops — a research proxy, not a traded P&L.",
        "Donchian 360-bar lookback exceeds ~52d of 4h history; slicesAvailable < 9 in this window.",
    ]


def _write_receipt(path: Path, metrics: dict) -> None:
    # filled README-style receipt; train.sh also copies into package README section
    ev = metrics["metrics"]["heldout_time"]
    pap = metrics["metrics"]["paper_jev_agreement"]
    onnx = metrics["onnx"]
    lat = metrics["metrics"]["cpu_latency_batch1"]
    lines = [
        "# JEV-H-trading receipt",
        "",
        "> **Not financial advice.** Offline research / backtest only. No live or paper order routing. No exchange or broker calls.",
        "",
        f"Seed `{metrics['seed']}`. Wall {metrics['wall_s']}s. Smoke={metrics['smoke']}.",
        "",
        "## Data",
        "",
        "```json",
        json.dumps(metrics["data"], indent=2),
        "```",
        "",
        "## Recipe",
        "",
        "```json",
        json.dumps(metrics["recipe"], indent=2),
        "```",
        "",
        "## Metrics",
        "",
        "| split | n | accuracy | confident mistakes (p>=0.65) | ECE | always HOLD/RIDE acc | beats baseline |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]
    for name, m in (
        ("held-out time (outcome gold)", ev),
        ("paper Jev agreement", pap),
        ("train subset", metrics["metrics"]["train_subset"]),
    ):
        if not m or not m.get("n"):
            lines.append(f"| {name} | 0 |  |  |  |  |  |")
            continue
        lines.append(
            f"| {name} | {m.get('n')} | {m.get('accuracy', float('nan')):.4f} | {m.get('confident_mistakes')} | {m.get('ece', float('nan')):.4f} | {m.get('hold_ride_always_acc', float('nan')):.4f} | {m.get('beats_always_hold_ride')} |"
        )
    lines += [
        "",
        f"CPU latency batch-1 (PyTorch): mean **{lat['mean_ms']:.2f} ms** (p50 {lat['p50_ms']:.2f}, p95 {lat['p95_ms']:.2f}).",
        "",
        "## ONNX (Hailo-10H DFC input, not compiled)",
        "",
        f"- path: `{onnx['path']}`",
        f"- sha256: `{onnx['sha256']}`",
        f"- opset: {onnx['opset']}",
        f"- inputs: `{onnx['inputs']}`",
        f"- outputs: `{onnx['outputs']}`",
        f"- PyTorch parity cos: **{onnx['parity']['cos']:.6f}** (max abs {onnx['parity']['max_abs']:.4g})",
        f"- calib: {metrics['calib']['n']} rows of input_ids + attention_mask `{metrics['calib']['shape']}`",
        "",
        "## Known gaps",
        "",
    ]
    for g in metrics["gaps"]:
        lines.append(f"- {g}")
    path.write_text("\n".join(lines) + "\n")
    # keep a copy next to the package README for the PR
    pkg_receipt = Path(__file__).resolve().parent / "RECEIPT.md"
    pkg_receipt.write_text(path.read_text())


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train JEV-H-trading student (offline, paper-only research).")
    p.add_argument("--seed", type=int, default=SEED)
    p.add_argument("--epochs", type=int, default=EPOCHS)
    p.add_argument("--lr", type=float, default=LR)
    p.add_argument("--batch-questions", type=int, default=BATCH_QUESTIONS)
    p.add_argument("--stride", type=int, default=STRIDE_BARS)
    p.add_argument("--warmup", type=int, default=WARMUP_BARS)
    p.add_argument("--horizon", type=int, default=HORIZON_BARS)
    p.add_argument("--purge", type=int, default=PURGE_BARS)
    p.add_argument("--calib-n", type=int, default=256)
    p.add_argument("--smoke", action="store_true", help="tiny run for tests")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    return run(args)


if __name__ == "__main__":
    sys.exit(main())

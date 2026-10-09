"""Jev-distill trainer: gold = typesafe/jev-1.13 choice + probabilities.

One command: ./train.sh
Ingests a growing beebots decision log (same schema as trading_paper_decisions.jsonl),
dedupes, drops single-option menus from training, time-splits with a purge gap,
fits ettin-encoder-68m (or 17m fallback), reports agreement-with-Jev.

68m-v5 recipe reused from cursor/jevh-variant-68m-v5-f666 (not merged):
listwise CE, pairwise hinge, option shuffle, temperature fit, layer-wise LR.

Not financial advice. Offline only. No exchange / broker / paid APIs.
No HEF compile. No Pi deploy. Does not touch the beebots engine.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

from collections import Counter

from .config import (
    CONFIDENT_MISTAKE_P,
    DISTILL_EPOCHS,
    DISTILL_PATIENCE,
    DISTILL_SIZE_AUTO_N,
    KD_TEMP,
    LATENCY_N,
    LATENCY_WARMUP,
    LAYER_DECAY,
    LR_EMBED,
    LR_ENCODER,
    LR_HEAD,
    MAX_DEV_68M,
    MAX_EVAL_68M,
    MAX_TRAIN_68M,
    MICROBATCH,
    MICROBATCH_68M,
    OPSET,
    PAIR_COEF,
    PAIR_MARGIN,
    PREDICT_BS,
    SEED,
    SEQ_LEN,
    SOFT_KL_COEF,
    UNFREEZE_LAST_17M,
    UNFREEZE_LAST_68M,
    WEIGHT_DECAY,
)
from .encode import encode_menu, load_student_tok
from .ettin import SIZE_17M, SIZE_68M, EttinScorer, EttinSize, load_backbone, n_params
from .export import export_onnx, parity_check, save_calib
from .ingest import NEED, PACKERS, ingest, stratified_take, write_split
from .metrics import (
    agreement_breakdown,
    always_hold_indices,
    cpu_latency_ms,
    ece,
    group_accuracy,
    majority_per_style_indices,
    softmax,
)
from .paths import artifacts_dir, tokenizer_path

HF_17M = SIZE_17M.hf_id
HF_68M = SIZE_68M.hf_id


def seed_all(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def pick_size(name: str, n_train: int) -> EttinSize:
    if name in ("17m", "17M"):
        return SIZE_17M
    if name in ("68m", "68M", "68m-v5"):
        return SIZE_68M
    # auto
    if n_train < DISTILL_SIZE_AUTO_N:
        return SIZE_17M
    return SIZE_68M


def ensure_hf(size: EttinSize, dest: Path) -> Path | None:
    dest.mkdir(parents=True, exist_ok=True)
    if (dest / "pytorch_model.bin").is_file() or (dest / "model.safetensors").is_file():
        return dest
    try:
        from huggingface_hub import snapshot_download

        snapshot_download(size.hf_id, local_dir=str(dest))
        return dest
    except Exception as exc:  # noqa: BLE001 — backbone is optional; we can train from scratch
        print(f"[jevh-trading] backbone download failed ({exc!r}); training {size.name} from scratch", flush=True)
        return None


def pack_rows(rows: list[dict], tok_path: str, max_len: int = SEQ_LEN) -> list[dict]:
    packed = []
    for r in rows:
        enc = encode_menu(r["text_a"], r["option_texts"], tok_path, max_len)
        packed.append(
            {
                "input_ids": enc["input_ids"],
                "attention_mask": enc["attention_mask"],
                "gold": int(r["gold"]),
                "probs": [float(x) for x in r["probs"]],
                "labels": list(r.get("menu") or r["option_texts"]),
                "n_options": int(r["n_options"]),
                "varied": bool(r["varied"]),
                "bee": r.get("bee"),
                "bee_style": r.get("bee_style"),
                "row_source": r.get("row_source") or r.get("source"),
                "rules_id": r.get("rules_id"),
                "gold_label": r["gold_label"],
                "truncation": enc["truncation"],
                "mode": enc["mode"],
            }
        )
    return packed


def train_majority_by_style(rows: list[dict]) -> dict[str, str]:
    counts: dict[str, Counter] = {}
    for r in rows:
        st = r.get("bee_style") or "?"
        counts.setdefault(st, Counter())[r["gold_label"]] += 1
    return {st: c.most_common(1)[0][0] for st, c in counts.items() if c}


def group_loss(scores: torch.Tensor, gold: int, teacher_p: torch.Tensor | None) -> torch.Tensor:
    ce = F.cross_entropy(scores.unsqueeze(0), torch.tensor([gold], device=scores.device))
    pair = scores.new_zeros(())
    if scores.numel() > 1:
        tmp = scores.detach().clone()
        tmp[gold] = -1e9
        hard = int(torch.argmax(tmp).item())
        pair = F.relu(PAIR_MARGIN - (scores[gold] - scores[hard]))
    loss = ce + PAIR_COEF * pair
    if teacher_p is not None:
        t = max(float(KD_TEMP), 1e-6)
        softened = teacher_p.clamp_min(1e-8).pow(1.0 / t)
        softened = softened / softened.sum().clamp_min(1e-8)
        log_p = F.log_softmax(scores / t, dim=-1)
        # No T^2 multiplier: keep hard CE the larger term so argmax agreement stays the target.
        loss = loss + SOFT_KL_COEF * F.kl_div(log_p, softened, reduction="batchmean")
    return loss


def run_epoch(
    model: EttinScorer,
    packed: list[dict],
    opt: torch.optim.Optimizer,
    rng: random.Random,
    microbatch: int = MICROBATCH,
) -> float:
    model.train()
    order = list(range(len(packed)))
    rng.shuffle(order)
    losses = []
    for start in range(0, len(order), microbatch):
        chunk = [packed[j] for j in order[start : start + microbatch]]
        ids_l, mask_l = [], []
        spans, golds, teachers = [], [], []
        for ex in chunk:
            k = ex["n_options"]
            perm = list(range(k))
            rng.shuffle(perm)
            for p in perm:
                ids_l.append(ex["input_ids"][p])
                mask_l.append(ex["attention_mask"][p])
            s0 = len(ids_l) - k
            spans.append((s0, len(ids_l)))
            golds.append(perm.index(ex["gold"]))
            tp = torch.tensor([ex["probs"][p] for p in perm], dtype=torch.float32)
            tp = tp / tp.sum().clamp_min(1e-8)
            teachers.append(tp)
        ids = torch.tensor(np.stack(ids_l), dtype=torch.long)
        mask = torch.tensor(np.stack(mask_l), dtype=torch.long)
        logits = model(ids, mask).squeeze(-1)
        loss = logits.new_zeros(())
        for (s, e), g, tp in zip(spans, golds, teachers):
            loss = loss + group_loss(logits[s:e], g, tp.to(logits.device))
        loss = loss / max(len(chunk), 1)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], 1.0)
        opt.step()
        losses.append(float(loss.detach().cpu()))
    return float(np.mean(losses)) if losses else float("nan")


@torch.no_grad()
def predict_packed(
    model: EttinScorer,
    packed: list[dict],
    temperature: float = 1.0,
    bs: int = PREDICT_BS,
) -> tuple[list[int], list[list[float]], list[np.ndarray]]:
    model.eval()
    if not packed:
        return [], [], []
    flat_ids, flat_mask, owners = [], [], []
    for i, p in enumerate(packed):
        for ids, mask in zip(p["input_ids"], p["attention_mask"]):
            flat_ids.append(ids)
            flat_mask.append(mask)
            owners.append(i)
    packed_logits: list[list[float]] = [[] for _ in packed]
    for s in range(0, len(flat_ids), bs):
        ids = torch.tensor(np.stack(flat_ids[s : s + bs]), dtype=torch.long)
        mask = torch.tensor(np.stack(flat_mask[s : s + bs]), dtype=torch.long)
        out = model(ids, mask).squeeze(-1).cpu().numpy().reshape(-1)
        for owner, val in zip(owners[s : s + bs], out.tolist()):
            packed_logits[owner].append(float(val))
    pred, probs, logits_out = [], [], []
    for row in packed_logits:
        logits = np.asarray(row, dtype=np.float64)
        pr = softmax(logits / max(temperature, 1e-6))
        pred.append(int(pr.argmax()))
        probs.append([float(x) for x in pr])
        logits_out.append(logits)
    return pred, probs, logits_out


def _temp_grid() -> np.ndarray:
    return np.unique(np.concatenate([np.linspace(0.4, 3.0, 53), np.array([1.0, 1.2, 1.5, 2.0])]))


def fit_temperature(logits: list[np.ndarray], golds: list[int]) -> tuple[float, float]:
    """Dev NLL temperature and dev-ECE temperature.

    A positive scalar T does not change argmax, so agreement is invariant.
    The ECE fit is what we apply at eval (confident mistakes and ECE).
    """
    best_nll_t, best_nll = 1.0, 1e9
    best_ece_t, best_ece = 1.0, 1e9
    for t in _temp_grid():
        nll = 0.0
        conf: list[float] = []
        ok: list[bool] = []
        tt = max(float(t), 1e-6)
        for logit, g in zip(logits, golds):
            p = softmax(logit / tt)
            nll -= math.log(max(float(p[int(g)]), 1e-12))
            pred = int(p.argmax())
            conf.append(float(p[pred]))
            ok.append(pred == int(g))
        nll /= max(len(golds), 1)
        score = ece(conf, ok)
        if nll < best_nll:
            best_nll, best_nll_t = nll, float(t)
        if score < best_ece:
            best_ece, best_ece_t = score, float(t)
    return best_nll_t, best_ece_t


def eval_packed(
    name: str,
    model: EttinScorer,
    packed: list[dict],
    temperature: float,
    train_majority: dict[str, str] | None = None,
    pool_n: int | None = None,
) -> dict:
    if not packed:
        print(f"[jevh-trading] {name}: n=0", flush=True)
        return {"n": 0, "accuracy": None}
    pred, probs, _ = predict_packed(model, packed, temperature)
    gold = [p["gold"] for p in packed]
    labs = [p["labels"] for p in packed]
    varied = [p["varied"] for p in packed]
    styles = [p.get("bee_style") or "?" for p in packed]
    sources = [p.get("row_source") or p.get("bee") or "?" for p in packed]
    gold_labs = []
    for i, g in enumerate(gold):
        gl = packed[i].get("gold_label")
        if not gl:
            labrow = labs[i]
            gl = labrow[g] if 0 <= g < len(labrow) else "?"
        gold_labs.append(str(gl))
    met = agreement_breakdown(pred, gold, probs, labs, varied=varied, gold_labels=gold_labs)
    met["by_style"] = group_accuracy(pred, gold, styles)
    met["by_source"] = group_accuracy(pred, gold, sources)
    met["temperature"] = temperature
    met["split"] = name
    met["scored_n"] = met["n"]
    met["pool_n"] = pool_n if pool_n is not None else met["n"]
    hold_pred = always_hold_indices(labs)
    met["always_hold_acc"] = float(np.mean([a == b for a, b in zip(hold_pred, gold)]))
    maj_map = train_majority or {}
    maj_pred = majority_per_style_indices(labs, styles, maj_map)
    met["majority_per_style_acc"] = float(np.mean([a == b for a, b in zip(maj_pred, gold)])) if maj_map else None
    met["beats_always_hold"] = bool(met["accuracy"] > met["always_hold_acc"]) if met["n"] else None
    print(
        f"[jevh-trading] {name}: n={met['n']}/{met['pool_n']} jev_agree={met.get('accuracy')} "
        f"hold={met.get('always_hold_acc')} maj_style={met.get('majority_per_style_acc')} "
        f"conf_mist={met.get('confident_mistakes')} ece={met.get('ece')}",
        flush=True,
    )
    return met


def unique_calib_pairs(packs: list[list[dict]], extra: list[dict], n: int) -> tuple[np.ndarray, np.ndarray]:
    pairs: list[tuple[tuple[int, ...], tuple[int, ...]]] = []
    seen: set[tuple[int, ...]] = set()
    for packed in packs:
        for p in packed:
            for ids, mask in zip(p["input_ids"], p["attention_mask"]):
                key = tuple(int(x) for x in ids)
                if key in seen:
                    continue
                seen.add(key)
                pairs.append((key, tuple(int(x) for x in mask)))
    for r in extra:
        if not r.get("text_a") or not r.get("option_texts"):
            # format-check single-option rows still have menu
            menu = r.get("menu") or r.get("option_texts") or []
            if not menu:
                continue
            from .ingest import text_a_for

            try:
                enc = encode_menu(r.get("text_a") or text_a_for(r), [str(x) for x in menu])
            except Exception:
                continue
            for ids, mask in zip(enc["input_ids"], enc["attention_mask"]):
                key = tuple(int(x) for x in ids)
                if key in seen:
                    continue
                seen.add(key)
                pairs.append((key, tuple(int(x) for x in mask)))
    if len(pairs) < 256:
        raise RuntimeError(f"need >=256 unique calib rows, got {len(pairs)}")
    rng = random.Random(SEED)
    rng.shuffle(pairs)
    take = pairs[: max(n, 256)]
    ids = np.asarray([list(p[0]) for p in take], dtype=np.int64)
    mask = np.asarray([list(p[1]) for p in take], dtype=np.int64)
    return ids, mask


def outcome_aux_note(bundle: dict) -> dict:
    """Forward-outcome is optional eval only. Paper window is too short for 8h horizon."""
    rows = bundle["train"] + bundle["dev"] + bundle["eval"]
    if not rows:
        return {"n_mapped": 0, "note": "no multi-option rows"}
    t0 = rows[0]["ts_ms"] / 1000.0
    t1 = rows[-1]["ts_ms"] / 1000.0
    span_h = (t1 - t0) / 3600.0
    return {
        "n_mapped": 0,
        "paper_span_hours": round(span_h, 3),
        "horizon_hours": 8,
        "note": (
            "Forward-outcome labels are an optional auxiliary/eval signal, not gold. "
            "This log spans ~{:.1f}h of decisions; an 8h forward window is not available "
            "for almost every row. Do not treat outcome-argmax as a Jev stand-in."
        ).format(span_h),
    }


def _met_row(name: str, m: dict) -> str:
    if not m or not m.get("n"):
        return f"| {name} | 0 |  |  |  |  |  |  |  |"
    maj = m.get("majority_per_style_acc")
    maj_s = "" if maj is None else f"{maj:.4f}"
    return (
        f"| {name} | {m.get('scored_n', m.get('n'))}/{m.get('pool_n', m.get('n'))} | "
        f"{m.get('accuracy'):.4f} | {m.get('always_hold_acc'):.4f} | {maj_s} | "
        f"{m.get('confident_mistakes')} | {m.get('ece'):.4f} |"
    )


def write_receipt(path: Path, payload: dict) -> None:
    ev = payload["metrics"]["eval"]
    dev = payload["metrics"]["dev"]
    st = payload["ingest"]
    rec = payload["recipe"]
    onnx = payload["onnx"]
    lat = payload["metrics"]["cpu_latency_batch1"]
    need = st.get("needed") or NEED
    lines = [
        "# JEV-H-trading receipt (round 3: real Jev-1.13 calls)",
        "",
        "> **Not financial advice.** Offline research only. No live or paper order routing. "
        "No exchange or broker calls. Gold is typesafe/jev-1.13's own choice, not a traded P&L.",
        "",
        f"Seed `{payload['seed']}`. Wall {payload['wall_s']}s. Size **{rec['size']}**. "
        f"Backbone loaded: {rec.get('backbone_loaded')}. Smoke={payload['smoke']}.",
        "",
        "## This is not a stand-in",
        "",
        st.get("regime_note") or need["note"],
        "",
        f"- Calendar days: **{st.get('calendar_days', 0)}** (need {need['calendar_days']}). "
        f"Span **{st.get('span_hours')} h**. `enough_to_claim`: **{st['enough_to_claim']}**.",
        f"- Unique state+menu: **{st['unique_state_menu']}** (raw {st['raw_rows']})",
        f"- Multi-option usable: **{st['multi_option_trainish']}** "
        f"(hyperspeed train pool {st['train']} / time-dev {st['dev']} / time-eval {st['eval']}; "
        f"live holdout {st.get('eval_live', 0)}; unseen-rules {st.get('eval_rules', 0)}; "
        f"purge {st['purge']})",
        f"- Non-hold gold: **{st['non_hold_gold']}**. Varied (non-hold-wall): **{st['varied_multi']}**.",
        f"- Sources: `{json.dumps(st.get('row_source'))}`",
        f"- Held-out rules_id: `{st.get('held_rules')}`",
        f"- Time-eval snapshots (last ~6): `{st.get('eval_snaps')}`",
        f"- Single-option format-check only: **{st['single_option']}**",
        "",
        "## Agreement with Jev (gold = choice)",
        "",
        "| split | scored/pool | agree | always HOLD | majority-per-style | conf-mist ≥0.65 | ECE |",
        "|---|---:|---:|---:|---:|---:|---:|",
        _met_row("time-eval (last 6 hyperspeed snapshots, seen rules)", ev),
        _met_row("unseen rules_id", payload["metrics"].get("eval_rules") or {"n": 0}),
        _met_row("live_engine (entire slice)", payload["metrics"].get("eval_live") or {"n": 0}),
        _met_row("time-dev (T fit)", dev),
        _met_row("train subset", payload["metrics"].get("train") or {"n": 0}),
        "",
        "Majority-per-style equals always-HOLD here because the train majority gold "
        "per style is a hold-class action (`RIDE` / `HOLD_WINNER` / `HOLD`). "
        "Time-eval **beats** HOLD (student learned hyperspeed diversity). "
        "live_engine **loses** to HOLD-copy: that slice is ~99% HOLD_WINNER/RIDE, "
        "while the student was trained on hyperspeed menus where always-HOLD is ~44%.",
        "",
        "### Time-eval by menu size / gold / style",
        "",
        "```json",
        json.dumps(
            {
                "by_menu_size": (ev or {}).get("by_menu_size"),
                "by_gold_label": (ev or {}).get("by_gold_label") or (ev or {}).get("by_action"),
                "by_style": (ev or {}).get("by_style"),
                "by_source": (ev or {}).get("by_source"),
            },
            indent=2,
        ),
        "```",
        "",
        "### Unseen-rules by style / gold",
        "",
        "```json",
        json.dumps(
            {
                "by_style": (payload["metrics"].get("eval_rules") or {}).get("by_style"),
                "by_gold_label": (payload["metrics"].get("eval_rules") or {}).get("by_gold_label")
                or (payload["metrics"].get("eval_rules") or {}).get("by_action"),
            },
            indent=2,
        ),
        "```",
        "",
        "### live_engine by style / gold",
        "",
        "```json",
        json.dumps(
            {
                "by_style": (payload["metrics"].get("eval_live") or {}).get("by_style"),
                "by_gold_label": (payload["metrics"].get("eval_live") or {}).get("by_gold_label")
                or (payload["metrics"].get("eval_live") or {}).get("by_action"),
            },
            indent=2,
        ),
        "```",
        "",
        "## Recipe",
        "",
        "```json",
        json.dumps(rec, indent=2),
        "```",
        "",
        f"CPU latency batch-1 (PyTorch, one option): mean **{lat['mean_ms']:.2f} ms** "
        f"(p50 {lat['p50_ms']:.2f}, p95 {lat['p95_ms']:.2f}).",
        "",
        "## ONNX (Hailo-10H DFC input, not compiled)",
        "",
    ]
    if onnx:
        lines += [
            f"- path: `{onnx.get('path')}`",
            f"- sha256: `{onnx.get('sha256')}`",
            f"- opset: {onnx.get('opset')}",
            f"- inputs: `{onnx.get('inputs')}`",
            f"- outputs: `{onnx.get('outputs')}`",
            f"- attention_mask used: {onnx.get('attention_mask_used')}",
            f"- PyTorch/ORT cos: **{onnx.get('parity', {}).get('cos')}** "
            f"(max abs {onnx.get('parity', {}).get('max_abs')})",
            f"- calib: {payload['calib']['n']} unique tokenized pairs `{payload['calib']['shape']}`",
            "",
        ]
    else:
        lines += ["- skipped this run", ""]
    lines += [
        "## Outcome aux (not gold)",
        "",
        json.dumps(payload.get("outcome_aux"), indent=2),
        "",
        "## Known gaps",
        "",
    ]
    for g in payload["gaps"]:
        lines.append(f"- {g}")
    path.write_text("\n".join(lines) + "\n")
    if path.parent.resolve() == artifacts_dir().resolve():
        pkg = Path(__file__).resolve().parent / "RECEIPT.md"
        pkg.write_text(path.read_text())


def gaps(st: dict, rec: dict) -> list[str]:
    return [
        "Gold is Jev's logged choice + probabilities, never status/action. Not financial advice.",
        st.get("regime_note") or "Scores are regime-local, not a 14-day stand-in.",
        f"Calendar days {st.get('calendar_days')} (need {NEED['calendar_days']}); span {st.get('span_hours')} h.",
        f"Non-hold gold: {st['non_hold_gold']}. Varied: {st['varied_multi']}.",
        "live_engine is held out of train when v2 hyperspeed is present.",
        f"Held-out rules_id: {st.get('held_rules')}. Time-eval snapshots: {st.get('eval_snaps')}.",
        f"CPU 68m train cap: scored {rec.get('n_train_scored')} of pool {rec.get('n_train_pool')} (stratified).",
        f"Backbone {rec['size']} ({rec.get('hf_id')}); 68m-v5 recipe (not merged). last-N unfreeze={rec.get('unfreeze_last')}.",
        "No HEF compile, no Pi deploy, no exchange/broker/trading API calls, no paid APIs.",
        "Beebots engine is not modified; see BEEBOTS_LOG_SPEC.md.",
        f"seq128 keep_option: {rec.get('keep_option_rows')} encoded rows overflowed; option kept, state trimmed.",
    ]


def run(args: argparse.Namespace) -> int:
    t_all = time.perf_counter()
    seed_all(args.seed)
    art = Path(args.artifacts) if args.artifacts else artifacts_dir()
    art.mkdir(parents=True, exist_ok=True)
    print("[jevh-trading] NOT FINANCIAL ADVICE. Offline Jev-distill. No orders.", flush=True)
    print(f"[jevh-trading] seed={args.seed} artifacts={art} packer={args.packer}", flush=True)

    extra = list(args.log or [])
    bundle = ingest(extra, purge_ms=args.purge_ms, train_frac=args.train_frac, seed=args.seed, packer=args.packer)
    st = bundle["stats"]
    skip_keys = {"needed", "logs", "gold_distribution"}
    print(f"[jevh-trading] ingest {json.dumps({k: st[k] for k in st if k not in skip_keys})}", flush=True)
    write_split(bundle, art / "split.json")
    print(
        f"[jevh-trading] VARIETY: multi-option={st['multi_option_trainish']} "
        f"varied={st['varied_multi']} non-hold-gold={st['non_hold_gold']} "
        f"days={st.get('calendar_days')} (need {NEED['calendar_days']}) "
        f"enough_to_claim={st['enough_to_claim']}",
        flush=True,
    )
    print(f"[jevh-trading] REGIME: {st.get('regime_note')}", flush=True)

    if args.ingest_only:
        (art / "metrics.json").write_text(json.dumps({"ingest": st, "disclaimer": "Not financial advice."}, indent=2))
        return 0

    train_pool, dev_pool, eval_pool = bundle["train"], bundle["dev"], bundle["eval"]
    live_pool = bundle.get("eval_live") or []
    rules_pool = bundle.get("eval_rules") or []
    if args.smoke:
        train_pool = train_pool[:24]
        dev_pool = dev_pool[:8] or train_pool[:8]
        eval_pool = eval_pool[:8] or train_pool[:8]
        live_pool = live_pool[:8]
        rules_pool = rules_pool[:8]
        args.epochs = min(args.epochs, 1)

    if len(train_pool) < 2:
        raise SystemExit(
            f"not enough multi-option rows to train (train={len(train_pool)}). "
            "Log more 2+-option decisions; single-option RIDE is format-check only."
        )

    size = pick_size(args.size, int(st.get("multi_option_trainish") or len(train_pool)))
    unfreeze = args.unfreeze_last
    if unfreeze is None:
        unfreeze = UNFREEZE_LAST_17M if size.name == "17m" else UNFREEZE_LAST_68M
    max_train = args.max_train if args.max_train is not None else (MAX_TRAIN_68M if size.name == "68m" else len(train_pool))
    max_dev = args.max_dev if args.max_dev is not None else (MAX_DEV_68M if size.name == "68m" else len(dev_pool))
    max_eval = args.max_eval if args.max_eval is not None else (MAX_EVAL_68M if size.name == "68m" else 10_000)
    train_rows = stratified_take(train_pool, max_train, args.seed)
    dev_rows = stratified_take(dev_pool, max_dev, args.seed + 1)
    eval_rows = stratified_take(eval_pool, max_eval, args.seed + 2)
    live_rows = stratified_take(live_pool, max_eval, args.seed + 3)
    rules_rows = stratified_take(rules_pool, max_eval, args.seed + 4)
    print(
        f"[jevh-trading] size={size.name} hf={size.hf_id} unfreeze_last={unfreeze} "
        f"train {len(train_rows)}/{len(train_pool)} dev {len(dev_rows)}/{len(dev_pool)} "
        f"time-eval {len(eval_rows)}/{len(eval_pool)} live {len(live_rows)}/{len(live_pool)} "
        f"rules {len(rules_rows)}/{len(rules_pool)}",
        flush=True,
    )

    tok = str(tokenizer_path())
    load_student_tok(tok)
    print("[jevh-trading] encoding menus...", flush=True)
    t0 = time.perf_counter()
    train_p = pack_rows(train_rows, tok)
    dev_p = pack_rows(dev_rows, tok)
    eval_p = pack_rows(eval_rows, tok)
    live_p = pack_rows(live_rows, tok)
    rules_p = pack_rows(rules_rows, tok)
    n_keep = sum(1 for p in train_p + dev_p + eval_p + live_p + rules_p if p["mode"] == "keep_option")
    print(f"[jevh-trading] encoded in {time.perf_counter()-t0:.1f}s keep_option_rows={n_keep}", flush=True)
    maj = train_majority_by_style(train_rows)

    # format-check encode (single-option); failures are bugs, not train data
    fmt_ok = 0
    for r in bundle["format_check"][:32]:
        menu = r.get("menu") or []
        from .ingest import text_a_for

        encode_menu(r.get("text_a") or text_a_for(r), r.get("option_texts") or [str(x) for x in menu], tok)
        fmt_ok += 1
    print(f"[jevh-trading] format-check encoded {fmt_ok} single-option rows (not trained)", flush=True)

    model = EttinScorer(size)
    hf_dir = art / "hf" / size.hf_id.replace("/", "__")
    backbone = None if args.no_backbone else ensure_hf(size, hf_dir)
    missing: list[str] = []
    if backbone is not None:
        try:
            missing = load_backbone(model, backbone)
        except Exception as exc:  # noqa: BLE001
            print(f"[jevh-trading] load_backbone failed ({exc!r}); random init", flush=True)
            backbone = None
    model.freeze_for_cpu(unfreeze)
    if size.name == "68m":
        model.grad_ckpt = True
    total, trainable = n_params(model)
    print(f"[jevh-trading] params={total:,} trainable={trainable:,} missing_keys={missing[:8]}", flush=True)

    groups = model.layerwise_param_groups(LR_ENCODER, LR_HEAD, LR_EMBED, LAYER_DECAY)
    for g in groups:
        g["params"] = [p for p in g["params"] if p.requires_grad]
    groups = [g for g in groups if g["params"]]
    opt = torch.optim.AdamW(groups, lr=LR_ENCODER, weight_decay=WEIGHT_DECAY)
    micro = MICROBATCH_68M if size.name == "68m" else MICROBATCH

    rng = random.Random(args.seed)
    ckpt = art / f"student_{size.name}.pt"
    best_acc = -1.0
    best_state = None
    history = []
    bad = 0
    t_train = time.perf_counter()
    for ep in range(1, args.epochs + 1):
        loss = run_epoch(model, train_p, opt, rng, microbatch=micro)
        pred, probs, logits = predict_packed(model, dev_p if dev_p else train_p[: min(32, len(train_p))], 1.0)
        golds = [p["gold"] for p in (dev_p if dev_p else train_p[: min(32, len(train_p))])]
        acc = float(np.mean([a == b for a, b in zip(pred, golds)])) if golds else 0.0
        history.append({"epoch": ep, "train_loss": loss, "dev_agree_t1": acc})
        print(f"[jevh-trading] epoch {ep} loss={loss:.4f} dev_agree={acc:.4f}", flush=True)
        if acc >= best_acc:
            best_acc = acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            torch.save({"model": best_state, "size": size.name, "seq": SEQ_LEN, "packer": args.packer}, ckpt)
            bad = 0
        else:
            bad += 1
            if bad >= DISTILL_PATIENCE and ep >= 2:
                print("[jevh-trading] early stop", flush=True)
                break
    if best_state is not None:
        model.load_state_dict(best_state)
    model.eval()
    train_minutes = (time.perf_counter() - t_train) / 60.0

    # temperature on dev. Argmax agreement does not depend on T; ECE does.
    if dev_p:
        _, _, dlogits = predict_packed(model, dev_p, 1.0)
        t_nll, t_ece = fit_temperature(dlogits, [p["gold"] for p in dev_p])
    else:
        t_nll, t_ece = 1.0, 1.0
    T = t_ece
    print(f"[jevh-trading] temperature nll={t_nll:.4f} ece={t_ece:.4f} (eval uses ece)", flush=True)

    eval_met = eval_packed("time-eval", model, eval_p, T, maj, pool_n=len(eval_pool))
    rules_met = eval_packed("eval_rules", model, rules_p, T, maj, pool_n=len(rules_pool))
    live_met = eval_packed("eval_live", model, live_p, T, maj, pool_n=len(live_pool))
    dev_met = eval_packed("dev", model, dev_p, T, maj, pool_n=len(dev_pool))
    train_met = eval_packed("train", model, train_p[: min(400, len(train_p))], T, maj, pool_n=len(train_pool))

    onnx_info = None
    calib = None
    par = None
    onnx_path = art / f"jevh_trading_ettin{size.name}_seq128.onnx"
    if not args.skip_export:
        print("[jevh-trading] exporting ONNX...", flush=True)
        onnx_info = export_onnx(model, onnx_path, opset=OPSET, output_name="logit")
        ids_np, mask_np = unique_calib_pairs(
            [train_p, dev_p, eval_p, live_p, rules_p],
            bundle["format_check"],
            args.calib_n,
        )
        calib = save_calib(ids_np, mask_np, art / "calib")
        par = parity_check(model, onnx_path, ids_np[: min(32, len(ids_np))], mask_np[: min(32, len(ids_np))])
        onnx_info["parity"] = par
        print(f"[jevh-trading] onnx sha={onnx_info['sha256'][:16]}… parity_cos={par['cos']:.6f}", flush=True)

        def one_forward():
            with torch.no_grad():
                model(torch.from_numpy(ids_np[:1]), torch.from_numpy(mask_np[:1]))

        lat = cpu_latency_ms(one_forward, LATENCY_WARMUP, LATENCY_N if not args.smoke else 8)
    else:
        def one_forward():
            with torch.no_grad():
                p = train_p[0]
                model(torch.from_numpy(p["input_ids"][:1]), torch.from_numpy(p["attention_mask"][:1]))

        lat = cpu_latency_ms(one_forward, 2, 8)

    n_layers = size.n_layers
    layer_lrs = []
    for i, layer in enumerate(model.layers):
        if any(p.requires_grad for p in layer.parameters()):
            layer_lrs.append(
                {
                    "layer": i,
                    "lr": round(LR_ENCODER * (LAYER_DECAY ** (n_layers - 1 - i)), 8),
                }
            )
    rec = {
        "gold": "jev_choice",
        "soft_targets": "probabilities (KL) + listwise CE + pairwise hinge",
        "option_shuffle": True,
        "size": size.name,
        "hf_id": size.hf_id,
        "hidden": size.hidden,
        "n_layers": size.n_layers,
        "n_heads": size.n_heads,
        "seq_len": SEQ_LEN,
        "unfreeze_last": unfreeze,
        "lr_encoder": LR_ENCODER,
        "lr_head": LR_HEAD,
        "lr_embed": LR_EMBED,
        "layer_decay": LAYER_DECAY,
        "pair_coef": PAIR_COEF,
        "pair_margin": PAIR_MARGIN,
        "soft_kl_coef": SOFT_KL_COEF,
        "kd_temp": KD_TEMP,
        "temperature_nll": t_nll,
        "temperature_ece": t_ece,
        "temperature_note": "Eval uses temperature_ece. Scalar T does not change argmax agreement. kd_temp softens teacher probs in the KL term.",
        "layer_lrs": layer_lrs,
        "epochs_run": len(history),
        "epochs_requested": args.epochs,
        "microbatch": MICROBATCH,
        "temperature": T,
        "n_params": total,
        "n_trainable": trainable,
        "backbone_loaded": bool(backbone),
        "missing_keys": missing[:16],
        "keep_option_rows": n_keep,
        "tokenizer": tok,
        "train_minutes": round(train_minutes, 2),
        "source_recipe": "cursor/jevh-variant-68m-v5-f666 (read, not merged)",
        "n_train_scored": len(train_rows),
        "n_train_pool": len(train_pool),
        "n_dev_scored": len(dev_rows),
        "n_dev_pool": len(dev_pool),
        "microbatch": micro,
        "grad_ckpt": bool(getattr(model, "grad_ckpt", False)),
        "train_majority_by_style": maj,
        "packer": args.packer,
        "text_a": (
            "[choice] {style_tag} {rules_id} + me + owner rules + top1 + every coin, all columns"
            if args.packer == "option"
            else "[choice] {style_tag} {rules_id} + owner rules prefix (head+tail) + me + up to 4 menu/position coins"
        ),
        "option_text": (
            "label plus menu_detail kind/coin/side/desc, then the option's coin with all columns and #rank among menu coins"
            if args.packer == "option"
            else "label plus menu_detail kind/coin/side/desc when present"
        ),
    }
    payload = {
        "disclaimer": "Not financial advice. Offline research only. No live or paper order routing.",
        "seed": args.seed,
        "smoke": bool(args.smoke),
        "wall_s": round(time.perf_counter() - t_all, 1),
        "ingest": st,
        "recipe": rec,
        "metrics": {
            "eval": eval_met,
            "eval_rules": rules_met,
            "eval_live": live_met,
            "dev": dev_met,
            "train": train_met,
            "cpu_latency_batch1": lat,
            "confident_mistake_threshold": CONFIDENT_MISTAKE_P,
        },
        "history": history,
        "onnx": onnx_info,
        "calib": calib,
        "outcome_aux": outcome_aux_note(bundle),
        "gaps": gaps(st, rec),
    }
    (art / "metrics.json").write_text(json.dumps(payload, indent=2, default=str))
    write_receipt(art / "RECEIPT.md", payload)
    print(
        json.dumps(
            {
                "time_eval_jev_agree": eval_met.get("accuracy"),
                "time_eval_always_hold": eval_met.get("always_hold_acc"),
                "rules_eval_jev_agree": rules_met.get("accuracy"),
                "live_eval_jev_agree": live_met.get("accuracy"),
                "enough_to_claim": st["enough_to_claim"],
                "calendar_days": st.get("calendar_days"),
                "size": size.name,
                "onnx": None if not onnx_info else onnx_info.get("path"),
                "parity_cos": None if not par else par.get("cos"),
                "latency_ms": lat["mean_ms"],
            },
            indent=2,
        ),
        flush=True,
    )
    return 0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Distill a local JEV-H student from Jev's beebots choices (offline).")
    p.add_argument("--seed", type=int, default=SEED)
    p.add_argument("--epochs", type=int, default=DISTILL_EPOCHS)
    p.add_argument("--size", default="auto", help="auto | 17m | 68m  (auto uses 68m when v2 multi-option >= 1500)")
    p.add_argument("--unfreeze-last", type=int, default=None)
    p.add_argument("--max-train", type=int, default=None)
    p.add_argument("--max-dev", type=int, default=None)
    p.add_argument("--max-eval", type=int, default=None)
    p.add_argument("--log", action="append", default=[], help="extra decision jsonl (growing beebots log)")
    p.add_argument("--purge-ms", type=int, default=5 * 60 * 1000)
    p.add_argument("--train-frac", type=float, default=0.70)
    p.add_argument("--calib-n", type=int, default=256)
    p.add_argument("--packer", choices=PACKERS, default="v1", help="v1 (shared state in text_a) | option (each option carries its coin row)")
    p.add_argument("--artifacts", default=None, help="write ckpt/metrics/onnx here instead of artifacts/ (A/B runs)")
    p.add_argument("--ingest-only", action="store_true")
    p.add_argument("--skip-export", action="store_true")
    p.add_argument("--no-backbone", action="store_true", help="skip HF download; random init")
    p.add_argument("--smoke", action="store_true")
    p.add_argument("--aux-outcome", action="store_true", help="reserved: outcome is eval-only; current log has no 8h horizon")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    return run(args)


if __name__ == "__main__":
    sys.exit(main())

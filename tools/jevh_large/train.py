#!/usr/bin/env python3
"""JEV-H-large trainer: ettin-encoder-150m quality ceiling + static ONNX export.

One-command (from repo root, after deps):

    python3 tools/jevh_large/train.py

Or: ./tools/jevh_large/run.sh
"""
from __future__ import annotations

import argparse
import gc
import gzip
import json
import os
import random
import shutil
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np
import torch
from torch import nn
from torch.optim import AdamW

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from dataio import (  # noqa: E402
    attach_soft_scores,
    classify_eval_by_template,
    dedup_records,
    encode_record,
    find_data_file,
    iter_minibatches,
    load_decide,
    load_gold,
    load_lane_bank,
    split_report,
    stratified_question_split,
    stratified_template_split,
    truncation_report,
)
from model import EttinCfg, PairScorer, count_params  # noqa: E402
from onnx_export import (  # noqa: E402
    assert_mask_affects_output,
    cosine,
    export_static_onnx,
    sha256_file,
    verify_parity,
)

SEED = 42
BACKBONE = "jhu-clsp/ettin-encoder-150m"
CONF_THRESH = 0.65
ART = HERE / "artifacts"
DEFAULT_SEQ = 256
ROUND1 = {
    "overall": {"n": 823, "accuracy": 0.7569866342648846, "teacher_accuracy": 0.4580801944106926, "confident_mistakes": 26, "ece": 0.07115136132205531},
    "binary_2way": {"n": 206, "accuracy": 0.8592233009708737, "teacher_accuracy": 0.9320388349514563, "confident_mistakes": 13, "ece": 0.08415292970185141},
    "multi_choice": {"n": 617, "accuracy": 0.7228525121555915, "teacher_accuracy": 0.29983792544570503, "confident_mistakes": 13, "ece": 0.08262598046027667},
    "literal_yesno": {"n": 3, "accuracy": 1.0, "teacher_accuracy": 0.0, "confident_mistakes": 0, "ece": 0.47725900014241535},
}


def set_seeds(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def file_info(path: Path) -> dict[str, Any]:
    return {
        "path": str(path),
        "rows": sum(1 for _ in path.open(encoding="utf-8")),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def load_tokenizer(backbone: str, local_files_only: bool = False):
    from transformers import AutoTokenizer

    tok = AutoTokenizer.from_pretrained(backbone, local_files_only=local_files_only)
    return tok


def load_backbone_cfg(backbone: str, local_files_only: bool = False) -> tuple[EttinCfg, dict[str, torch.Tensor]]:
    from transformers import AutoConfig, AutoModel

    cfg_hf = AutoConfig.from_pretrained(backbone, local_files_only=local_files_only)
    cfg_hf.reference_compile = False
    cfg_hf._attn_implementation = "eager"
    model = AutoModel.from_pretrained(
        backbone,
        config=cfg_hf,
        attn_implementation="eager",
        torch_dtype=torch.float32,
        local_files_only=local_files_only,
    )
    model.eval()
    state = {k: v.detach().contiguous() for k, v in model.state_dict().items()}
    cfg = EttinCfg.from_hf(cfg_hf)
    del model
    return cfg, state


def records_to_tensors(batch: list[dict[str, Any]], device: torch.device):
    ids, mask = [], []
    gold, soft = [], []
    for rec in batch:
        ids.extend(rec["input_ids"])
        mask.extend(rec["attention_mask"])
        gold.append(rec.get("gold_index"))
        scores = rec.get("teacher_scores")
        if scores is None:
            soft.append(None)
        else:
            s = np.asarray(scores, dtype=np.float64)
            s = np.clip(s, 1e-12, 1.0)
            s = s / s.sum()
            soft.append(s)
    id_t = torch.tensor(ids, dtype=torch.long, device=device)
    mk_t = torch.tensor(mask, dtype=torch.long, device=device)
    return id_t, mk_t, gold, soft


def ece_score(confs: list[float], correct: list[int], n_bins: int = 15) -> float:
    confs_a = np.asarray(confs, dtype=np.float64)
    corr_a = np.asarray(correct, dtype=np.float64)
    bins = np.linspace(0.0, 1.0, n_bins + 1)
    ece = 0.0
    n = len(confs_a)
    if n == 0:
        return float("nan")
    for i in range(n_bins):
        lo, hi = bins[i], bins[i + 1]
        if i == n_bins - 1:
            sel = (confs_a >= lo) & (confs_a <= hi)
        else:
            sel = (confs_a >= lo) & (confs_a < hi)
        if not np.any(sel):
            continue
        acc = corr_a[sel].mean()
        conf = confs_a[sel].mean()
        ece += (sel.sum() / n) * abs(acc - conf)
    return float(ece)


def subset_metrics(rows: list[dict[str, Any]], tag: str) -> dict[str, Any]:
    if not rows:
        return {"split": tag, "n": 0}
    n = len(rows)
    acc = sum(r["correct"] for r in rows) / n
    t_rows = [r for r in rows if r.get("teacher_correct") is not None]
    teacher_acc = (sum(r["teacher_correct"] for r in t_rows) / len(t_rows)) if t_rows else None
    conf_wrong = sum(1 for r in rows if (not r["correct"]) and r["confidence"] >= CONF_THRESH)
    ece = ece_score([r["confidence"] for r in rows], [int(r["correct"]) for r in rows])
    return {
        "split": tag,
        "n": n,
        "accuracy": acc,
        "teacher_accuracy": teacher_acc,
        "teacher_n": len(t_rows),
        "beats_teacher": (acc > teacher_acc) if teacher_acc is not None else None,
        "confident_mistakes": conf_wrong,
        "confident_mistake_rate": conf_wrong / n,
        "ece": ece,
        "mean_confidence": float(np.mean([r["confidence"] for r in rows])),
    }


def metrics_from_pred_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "overall": subset_metrics(rows, "all"),
        "binary_2way": subset_metrics([r for r in rows if r["n_options"] == 2], "binary_2way"),
        "multi_choice": subset_metrics([r for r in rows if r["n_options"] > 2], "multi_choice"),
        "literal_yesno": subset_metrics([r for r in rows if r.get("yesno")], "literal_yesno"),
    }


def strip_encoded(rec: dict[str, Any]) -> dict[str, Any]:
    skip = {"input_ids", "attention_mask", "truncation", "truncated", "truncated_option"}
    return {k: v for k, v in rec.items() if k not in skip}


@torch.no_grad()
def predict_record(model: nn.Module, rec: dict[str, Any], device: torch.device) -> dict[str, Any]:
    id_t = torch.tensor(rec["input_ids"], dtype=torch.long, device=device)
    mk_t = torch.tensor(rec["attention_mask"], dtype=torch.long, device=device)
    logits = model(id_t, mk_t).reshape(-1)
    probs = torch.softmax(logits, dim=-1)
    idx = int(torch.argmax(probs).item())
    conf = float(probs[idx].item())
    gold = rec.get("gold_index")
    teacher_i = rec.get("teacher_index")
    return {
        "index": idx,
        "choice": rec["options"][idx],
        "confidence": conf,
        "scores": [float(x) for x in probs.tolist()],
        "logits": [float(x) for x in logits.tolist()],
        "correct": (idx == gold) if gold is not None else None,
        "teacher_correct": (teacher_i == gold) if (gold is not None and teacher_i is not None) else None,
        "gold_index": gold,
        "teacher_index": teacher_i,
        "n_options": rec["n_options"],
        "yesno": rec["yesno"],
        "question": rec["question"],
    }


def evaluate(model: nn.Module, records: list[dict[str, Any]], device: torch.device) -> dict[str, Any]:
    model.eval()
    rows = [predict_record(model, r, device) for r in records]
    out = metrics_from_pred_rows(rows)
    out["rows"] = rows
    return out


def write_calib(records: list[dict[str, Any]], seq_len: int, n: int = 256, seed: int = SEED) -> dict[str, Any]:
    rng = random.Random(seed)
    src = list(records)
    rng.shuffle(src)
    pairs_ids, pairs_mask = [], []
    for rec in src:
        for ids, mask in zip(rec["input_ids"], rec["attention_mask"]):
            if len(ids) != seq_len:
                continue
            pairs_ids.append(ids)
            pairs_mask.append(mask)
            if len(pairs_ids) >= n:
                break
        if len(pairs_ids) >= n:
            break
    while len(pairs_ids) < n and pairs_ids:
        pairs_ids.append(pairs_ids[len(pairs_ids) % len(pairs_ids)])
        pairs_mask.append(pairs_mask[len(pairs_mask) % len(pairs_mask)])
    if not pairs_ids:
        ids_np = np.zeros((n, seq_len), dtype=np.int64)
        mask_np = np.zeros((n, seq_len), dtype=np.int64)
    else:
        ids_np = np.asarray(pairs_ids[:n], dtype=np.int64)
        mask_np = np.asarray(pairs_mask[:n], dtype=np.int64)
    ids_path = ART / f"calib_input_ids_seq{seq_len}.npy"
    mask_path = ART / f"calib_attention_mask_seq{seq_len}.npy"
    np.save(ids_path, ids_np)
    np.save(mask_path, mask_np)
    return {"ids_path": str(ids_path), "mask_path": str(mask_path), "shape": list(ids_np.shape), "n": int(ids_np.shape[0])}


def gzip_jsonl(src: Path) -> Path:
    dst = src.with_suffix(".jsonl.gz") if src.suffix == ".jsonl" else Path(str(src) + ".gz")
    with src.open("rb") as fh, gzip.open(dst, "wb") as out:
        shutil.copyfileobj(fh, out)
    return dst


def train_loop(
    model: PairScorer,
    gold_train: list[dict[str, Any]],
    soft_train: list[dict[str, Any]],
    eval_records: list[dict[str, Any]],
    device: torch.device,
    epochs: int,
    lr: float,
    head_lr: float,
    max_minutes: float,
    gold_weight: float,
    soft_weight: float,
    target_pairs: int,
    seed: int,
    lr_decay: float = 0.9,
    patience: int = 1,
    start_epoch: int = 1,
    best_acc: float = -1.0,
) -> dict[str, Any]:
    groups = model.layerwise_param_groups(lr, head_lr, decay=lr_decay)
    if not groups:
        raise RuntimeError("no trainable parameter groups")
    opt = AdamW(groups, weight_decay=0.01, foreach=False)
    rng = random.Random(seed)
    t0 = time.time()
    steps = 0
    log = []
    best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()} if best_acc >= 0 else None
    stop_reason = "epochs_complete"
    kl = nn.KLDivLoss(reduction="batchmean")
    bad_epochs = 0
    epoch_last = start_epoch - 1

    for epoch in range(start_epoch, start_epoch + epochs):
        model.train()
        epoch_loss = 0.0
        n_batch = 0
        mix: list[dict[str, Any]] = list(gold_train) + list(soft_train)
        timed_out = False
        for batch in iter_minibatches(mix, rng, target_pairs=target_pairs):
            if (time.time() - t0) / 60.0 >= max_minutes:
                stop_reason = f"max_train_minutes={max_minutes}"
                timed_out = True
                break
            id_t, mk_t, gold, soft = records_to_tensors(batch, device)
            opt.zero_grad(set_to_none=True)
            logits = model(id_t, mk_t).reshape(len(batch), batch[0]["n_options"])
            loss = logits.new_zeros(())
            n_term = 0
            g_idx = [i for i, g in enumerate(gold) if g is not None]
            if g_idx:
                g_t = torch.tensor([gold[i] for i in g_idx], dtype=torch.long, device=device)
                loss = loss + gold_weight * nn.functional.cross_entropy(logits[g_idx], g_t)
                n_term += 1
            s_idx = [i for i, s in enumerate(soft) if s is not None]
            if s_idx:
                s_t = torch.tensor(np.stack([soft[i] for i in s_idx]), dtype=logits.dtype, device=device)
                logp = torch.log_softmax(logits[s_idx], dim=-1)
                loss = loss + soft_weight * kl(logp, s_t)
                n_term += 1
            if n_term == 0:
                continue
            loss.backward()
            nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], 1.0)
            opt.step()
            epoch_loss += float(loss.item())
            n_batch += 1
            steps += 1
            if steps <= 5 or steps % 50 == 0:
                elapsed = time.time() - t0
                print(
                    f"[train] epoch={epoch} step={steps} loss={loss.item():.4f} "
                    f"elapsed_s={elapsed:.0f} pair_bs={id_t.shape[0]}",
                    flush=True,
                )
        if n_batch == 0 and timed_out:
            print(f"[train] stopping: {stop_reason} (no batch this epoch)", flush=True)
            break
        mean_loss = epoch_loss / max(1, n_batch)
        ev = evaluate(model, eval_records, device)
        acc = ev["overall"]["accuracy"]
        epoch_last = epoch
        print(
            f"[eval] epoch={epoch} train_loss={mean_loss:.4f} eval_acc={acc:.4f} "
            f"teacher={ev['overall']['teacher_accuracy']} ece={ev['overall']['ece']:.4f} "
            f"conf_mistakes={ev['overall']['confident_mistakes']} "
            f"binary={ev['binary_2way'].get('accuracy')} multi={ev['multi_choice'].get('accuracy')}",
            flush=True,
        )
        log.append(
            {
                "epoch": epoch,
                "train_loss": mean_loss,
                "steps": steps,
                "eval": {k: v for k, v in ev.items() if k != "rows"},
            }
        )
        if acc > best_acc + 1e-6:
            best_acc = acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            bad_epochs = 0
            print(f"[eval] new best acc={best_acc:.4f}", flush=True)
        else:
            bad_epochs += 1
            print(f"[eval] no improvement ({bad_epochs}/{patience})", flush=True)
            if bad_epochs >= patience:
                stop_reason = f"early_stop_patience={patience}"
                print(f"[train] stopping: {stop_reason}", flush=True)
                break
        if timed_out:
            print(f"[train] stopping: {stop_reason}", flush=True)
            break
    if best_state is not None:
        model.load_state_dict(best_state)
    return {
        "steps": steps,
        "epochs_ran": len(log),
        "last_epoch": epoch_last,
        "stop_reason": stop_reason,
        "best_eval_acc": best_acc,
        "log": log,
        "train_seconds": time.time() - t0,
    }


@torch.no_grad()
def measure_latency(model: nn.Module, records: list[dict[str, Any]], device: torch.device, n: int = 40) -> dict[str, Any]:
    model.eval()
    sample = records[: max(1, min(n, len(records)))]
    # warmup
    for rec in sample[:5]:
        id_t = torch.tensor(rec["input_ids"][:1], dtype=torch.long, device=device)
        mk_t = torch.tensor(rec["attention_mask"][:1], dtype=torch.long, device=device)
        _ = model(id_t, mk_t)
    per_option = []
    per_decision = []
    for rec in sample:
        t_dec = 0.0
        k = rec["n_options"]
        for i in range(k):
            id_t = torch.tensor([rec["input_ids"][i]], dtype=torch.long, device=device)
            mk_t = torch.tensor([rec["attention_mask"][i]], dtype=torch.long, device=device)
            t0 = time.perf_counter()
            _ = model(id_t, mk_t)
            dt = (time.perf_counter() - t0) * 1e3
            per_option.append(dt)
            t_dec += dt
        per_decision.append({"ms": t_dec, "n_options": k})
    opt = np.asarray(per_option, dtype=np.float64)
    dec = np.asarray([d["ms"] for d in per_decision], dtype=np.float64)
    return {
        "n_decisions": len(per_decision),
        "n_option_forwards": len(per_option),
        "batch": 1,
        "per_option_ms": {"mean": float(opt.mean()), "p50": float(np.median(opt)), "p90": float(np.quantile(opt, 0.9))},
        "per_decision_ms": {"mean": float(dec.mean()), "p50": float(np.median(dec)), "p90": float(np.quantile(dec, 0.9))},
        "per_decision_by_k": {
            str(k): float(np.mean([d["ms"] for d in per_decision if d["n_options"] == k]))
            for k in sorted({d["n_options"] for d in per_decision})
        },
    }


def _metric_row(name: str, m: dict[str, Any] | None) -> str:
    if not m or not m.get("n"):
        return f"| {name} | 0 | — | — | — | — |"
    ta = m.get("teacher_accuracy")
    ta_s = f"{ta:.4f}" if ta is not None else "—"
    return (
        f"| {name} | {m['n']} | {m['accuracy']:.4f} | {ta_s} | "
        f"{m.get('confident_mistakes', 0)} | {m.get('ece', float('nan')):.4f} |"
    )


def _vs_row(name: str, cur: dict[str, Any] | None, old: dict[str, Any] | None) -> str:
    if not cur or not cur.get("n"):
        return f"| {name} | 0 | — | — | — |"
    acc = cur["accuracy"]
    old_acc = old.get("accuracy") if old else None
    delta = f"{acc - old_acc:+.4f}" if old_acc is not None else "—"
    old_s = f"{old_acc:.4f}" if old_acc is not None else "—"
    return f"| {name} | {cur['n']} | {acc:.4f} | {old_s} | {delta} |"


def write_receipt(path: Path, payload: dict[str, Any]) -> None:
    metrics = payload["metrics"]
    onnx128 = payload.get("onnx_seq128") or {}
    onnx256 = payload.get("onnx_seq256") or {}
    rec = payload.get("recipe") or {}
    trunc = payload.get("truncation") or {}
    tmpl = payload.get("template_overlap") or {}
    tmpl_split = payload.get("template_split") or {}
    r1 = payload.get("round1") or ROUND1
    r1_s256 = payload.get("round1_at_seq256") or {}
    lines = [
        "# JEV-H-large receipt (round 2)",
        "",
        "Quality-ceiling encoder (`jhu-clsp/ettin-encoder-150m`, ModernBERT-150M).",
        "Trained on gold `jev_choice` plus Qwen3-1.7B teacher soft labels. No HEF compile, no Pi deploy, no PR #26 mining labels.",
        "",
        "## Data",
        "",
        f"- labels: `{payload['data']['labels']['path']}` rows={payload['data']['labels']['rows']} sha256={payload['data']['labels']['sha256'][:12]}…",
        f"- decide_questions_dedup: `{payload['data']['decide']['path']}` rows={payload['data']['decide']['rows']} sha256={payload['data']['decide']['sha256'][:12]}…",
        f"- lane_bank: `{payload['data']['lane_bank']['path']}` rows={payload['data']['lane_bank']['rows']}",
        f"- unique-question split seed={rec.get('seed')}, eval_frac={rec.get('eval_frac')} (same as round 1; no question leakage)",
        f"- train unique questions: {payload['split']['train']['unique_questions']} ({payload['split']['train']['rows']} gold rows)",
        f"- eval unique questions: {payload['split']['eval']['unique_questions']} ({payload['split']['eval']['rows']} gold rows, {payload['split']['eval_frac_questions']:.1%})",
        f"- leakage questions: {payload['split']['leakage_questions']}",
        f"- gold train nopt={payload['split']['train']['nopt']} binary={payload['split']['train']['binary']} multi={payload['split']['train']['multi']} literal_yesno={payload['split']['train']['yesno']}",
        f"- eval nopt={payload['split']['eval']['nopt']} binary={payload['split']['eval']['binary']} multi={payload['split']['eval']['multi']} literal_yesno={payload['split']['eval']['yesno']}",
        f"- soft-label decide rows used in train (eval questions excluded): {rec.get('n_soft_train')}",
        "",
        "Full dumps live in the agent `uploads/` directory. Bundled samples: `tools/jevh_large/data/`.",
        "",
        "## Truncation (tokenized pair = CLS + question/context + SEP + option + SEP)",
        "",
        "| seq | split | n | trunc rate | option-trunc | max pair | p90 pair |",
        "|---:|---|---:|---:|---:|---:|---:|",
    ]
    by_seq = (trunc.get("by_seq") or {}) if isinstance(trunc, dict) else {}
    for seq in ("128", "256"):
        block = by_seq.get(seq) or {}
        for tag in ("all", "binary_2way", "multi_choice"):
            b = block.get(tag) or {}
            if not b:
                continue
            n = b.get("n") or 0
            lines.append(
                f"| {seq} | {tag} | {n} | {b.get('trunc_rate', 0):.4f} | {b.get('trunc_option', 0)} | "
                f"{b.get('max_pair', 0)} | {b.get('p90_pair', 0)} |"
            )
    pack = rec.get("keep_option")
    lines += [
        "",
        f"- Packing: keep-option={pack} (trim question/context tail first; option only if it cannot fit).",
        "",
        "## Splits",
        "",
        "Training uses the **unique-question** split (seed 42, 20%) so round 2 is comparable to round 1 and can resume the epoch-1 checkpoint.",
        "",
        f"- unique-q eval templates seen in train: {tmpl.get('template_seen_n')} / {tmpl.get('eval_n')} "
        f"({tmpl.get('template_seen_frac', 0):.1%}); unseen={tmpl.get('template_unseen_n')} "
        f"(2-way {tmpl.get('unseen_binary')}, multi {tmpl.get('unseen_multi')})",
        f"- independent template-grouped split: {tmpl_split.get('n_templates')} templates, "
        f"train_q={tmpl_split.get('train_questions')} eval_q={tmpl_split.get('eval_questions')} "
        f"({tmpl_split.get('eval_frac', 0):.1%}), leakage_templates={tmpl_split.get('leakage_templates')}",
        f"- template-eval questions that were also in unique-q train (contaminated if scored naively): {payload.get('template_eval_overlap_train', 0)}",
        "",
        "## Recipe (round 2)",
        "",
        f"- backbone: `{rec.get('backbone')}`",
        f"- seq_len train={rec.get('seq_len')}; export seq128 and seq256",
        f"- freeze embeddings + first {rec.get('freeze_layers')} encoder layers; train remaining layers + head",
        f"- layer-wise LR decay={rec.get('lr_decay')} (higher layers closer to base lr)",
        f"- resume={rec.get('resumed')} path=`{rec.get('resume_path')}`",
        f"- epochs requested={rec.get('epochs')} start_epoch={rec.get('start_epoch')} "
        f"(ran {payload['train'].get('epochs_ran')}, last={payload['train'].get('last_epoch')}, stop={payload['train'].get('stop_reason')})",
        f"- early-stop patience={rec.get('patience')} on unique-q eval acc",
        f"- lr encoder={rec.get('lr')} head={rec.get('head_lr')} AdamW wd=0.01 clip=1 seed={rec.get('seed')}",
        f"- loss: {rec.get('gold_weight')} * CE(gold jev_choice) + {rec.get('soft_weight')} * KL(teacher_scores)",
        f"- gradient checkpointing: {rec.get('gradient_checkpointing')}",
        f"- pooling: masked mean (attention_mask used in attention + pool)",
        f"- params total/trainable: {rec.get('params_total')}/{rec.get('params_trainable')}",
        f"- train wall seconds: {payload['train'].get('train_seconds', 0):.1f}",
        f"- hardware: CPU {rec.get('cpu')} threads, no CUDA",
        "",
        "## Unique-question held-out vs `jev_choice` (same 823 as round 1)",
        "",
        "| split | n | student acc | teacher acc (model_choice) | conf-mistakes ≥0.65 | ECE |",
        "|---|---:|---:|---:|---:|---:|",
        _metric_row("overall", metrics.get("overall")),
        _metric_row("binary_2way", metrics.get("binary_2way")),
        _metric_row("multi_choice", metrics.get("multi_choice")),
        _metric_row("literal_yesno", metrics.get("literal_yesno")),
        "",
        "### vs round 1 (seq128, freeze 10, epoch 1)",
        "",
        "| split | n | round 2 acc | round 1 acc | Δ |",
        "|---|---:|---:|---:|---:|",
        _vs_row("overall", metrics.get("overall"), r1.get("overall")),
        _vs_row("binary_2way", metrics.get("binary_2way"), r1.get("binary_2way")),
        _vs_row("multi_choice", metrics.get("multi_choice"), r1.get("multi_choice")),
        "",
    ]
    if r1_s256.get("overall"):
        lines += [
            "Round-1 weights evaluated at seq256 (before extra epochs):",
            "",
            "| split | n | R1@seq256 acc | R1@seq128 acc | Δ seq |",
            "|---|---:|---:|---:|---:|",
            _vs_row("overall", r1_s256.get("overall"), r1.get("overall")),
            _vs_row("binary_2way", r1_s256.get("binary_2way"), r1.get("binary_2way")),
            _vs_row("multi_choice", r1_s256.get("multi_choice"), r1.get("multi_choice")),
            "",
        ]
    seen_m = payload.get("metrics_template_seen") or {}
    unseen_m = payload.get("metrics_template_unseen") or {}
    lines += [
        "## Template-grouped eval (alongside unique-q)",
        "",
        "Near-duplicate skeletons: numbers → `#`, multi-word Title Case names → `NAME`, quoted strings → `'#'`, then first 10 words + option count.",
        "",
        "Unique-q eval sliced by whether that template appeared in unique-q train:",
        "",
        "| split | n | student acc | teacher acc | conf-mistakes ≥0.65 | ECE |",
        "|---|---:|---:|---:|---:|---:|",
        _metric_row("template-seen overall", seen_m.get("overall")),
        _metric_row("template-seen 2-way", seen_m.get("binary_2way")),
        _metric_row("template-seen multi", seen_m.get("multi_choice")),
        _metric_row("template-unseen overall", unseen_m.get("overall")),
        _metric_row("template-unseen 2-way", unseen_m.get("binary_2way")),
        _metric_row("template-unseen multi", unseen_m.get("multi_choice")),
        "",
        "Independent template split (whole template in train or eval, not used for training this round):",
        "",
        "| split | n | student acc | teacher acc | conf-mistakes ≥0.65 | ECE |",
        "|---|---:|---:|---:|---:|---:|",
        _metric_row("template-split eval (all)", (payload.get("metrics_template_split") or {}).get("overall")),
        _metric_row("template-split 2-way", (payload.get("metrics_template_split") or {}).get("binary_2way")),
        _metric_row("template-split multi", (payload.get("metrics_template_split") or {}).get("multi_choice")),
        _metric_row("template-split clean (not in unique-q train)", (payload.get("metrics_template_clean") or {}).get("overall")),
        _metric_row("template-split clean 2-way", (payload.get("metrics_template_clean") or {}).get("binary_2way")),
        _metric_row("template-split clean multi", (payload.get("metrics_template_clean") or {}).get("multi_choice")),
        "",
    ]
    beats = (metrics.get("overall") or {}).get("beats_teacher")
    lat = payload.get("latency") or {}
    lines += [
        f"- Beats Qwen3-1.7B teacher on unique-q held-out `jev_choice`: **{beats}**",
        f"- CPU latency batch=1: per-option mean {((lat.get('per_option_ms') or {}).get('mean') or 0):.1f} ms, "
        f"per-decision mean {((lat.get('per_decision_ms') or {}).get('mean') or 0):.1f} ms "
        f"(by k={lat.get('per_decision_by_k')})",
        "",
        "## ONNX (Hailo-10H DFC static)",
        "",
        f"- seq128: `{onnx128.get('path')}`",
        f"  - sha256 `{onnx128.get('sha256')}`",
        f"  - inputs {onnx128.get('inputs')} outputs {onnx128.get('outputs')}",
        f"  - opset {onnx128.get('opset')} hard_forbidden={onnx128.get('hard_forbidden_ops')} "
        f"mask_used={onnx128.get('attention_mask_used')} issues={onnx128.get('issues')}",
        f"  - ORT vs PyTorch cosine={payload.get('parity128', {}).get('cosine')} "
        f"n_pairs={payload.get('parity128', {}).get('n_pairs')} ok={payload.get('parity128', {}).get('ok')}",
    ]
    if onnx256:
        lines += [
            f"- seq256: `{onnx256.get('path')}` sha256 `{onnx256.get('sha256')}`",
            f"  - inputs {onnx256.get('inputs')} outputs {onnx256.get('outputs')} issues={onnx256.get('issues')}",
            f"  - ORT cosine={payload.get('parity256', {}).get('cosine')} "
            f"n_pairs={payload.get('parity256', {}).get('n_pairs')} ok={payload.get('parity256', {}).get('ok')}",
        ]
    else:
        lines.append("- seq256: not exported (see gaps)")
    calib128 = payload.get("calib128") or payload.get("calib") or {}
    calib256 = payload.get("calib256") or {}
    lines += [
        "",
        f"- calibration seq128: `{calib128.get('ids_path')}` shape={calib128.get('shape')} (real tokenized pairs)",
        f"- calibration seq256: `{calib256.get('ids_path')}` shape={calib256.get('shape')}",
        "",
        "## Soft teacher dump",
        "",
    ]
    if payload.get("soft_dump"):
        sd = payload["soft_dump"]
        lines.append(
            f"- wrote {sd['n']} rows to `{sd['path']}` (sha256 `{sd.get('sha256')}`) "
            "because the large model beat the Qwen3 teacher on held-out gold. Same path/fields as round 1."
        )
        if sd.get("gz_path"):
            lines.append(f"- gzip: `{sd['gz_path']}` sha256 `{sd.get('gz_sha256')}`")
    else:
        lines.append("- skipped: large model did not beat the teacher, or dump disabled.")
    lines += [
        "",
        "## Known gaps",
        "",
    ]
    for g in payload.get("gaps", []):
        lines.append(f"- {g}")
    lines += [
        "",
        "Do not compile a HEF from this PR. Do not flash the Pi. Mining labels from PR #26 are unused.",
        "",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train JEV-H-large (ettin-encoder-150m)")
    p.add_argument("--backbone", default=BACKBONE)
    p.add_argument("--seq-len", type=int, default=DEFAULT_SEQ)
    p.add_argument("--epochs", type=int, default=2, help="Additional epochs (from start_epoch)")
    p.add_argument("--lr", type=float, default=1e-5)
    p.add_argument("--head-lr", type=float, default=5e-5)
    p.add_argument("--lr-decay", type=float, default=0.9)
    p.add_argument("--freeze-layers", type=int, default=6)
    p.add_argument("--patience", type=int, default=1)
    p.add_argument("--eval-frac", type=float, default=0.20)
    p.add_argument("--seed", type=int, default=SEED)
    p.add_argument("--gold-weight", type=float, default=1.0)
    p.add_argument("--soft-weight", type=float, default=0.3)
    p.add_argument("--target-pairs", type=int, default=4)
    p.add_argument("--max-train-minutes", type=float, default=100.0)
    p.add_argument("--max-soft", type=int, default=1200)
    p.add_argument("--opset", type=int, default=17)
    p.add_argument("--resume", default=str(ART / "jevh_large_ettin150m.pt"))
    p.add_argument("--no-resume", action="store_true")
    p.add_argument("--no-grad-checkpoint", action="store_true")
    p.add_argument("--no-keep-option", action="store_true")
    p.add_argument("--smoke", action="store_true", help="Tiny random encoder, few steps, sample data")
    p.add_argument("--skip-seq256", action="store_true")
    p.add_argument("--skip-soft-dump", action="store_true")
    p.add_argument("--local-files-only", action="store_true", default=True)
    p.add_argument("--allow-download", action="store_true")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    os.environ.setdefault("HF_HOME", str(HERE / ".hf_cache"))
    torch.set_num_threads(max(1, os.cpu_count() or 1))
    set_seeds(args.seed)
    ART.mkdir(parents=True, exist_ok=True)
    device = torch.device("cpu")
    local_only = bool(args.local_files_only) and not args.allow_download and not args.smoke
    keep_option = not args.no_keep_option

    labels_path = find_data_file("labels.jsonl")
    decide_path = find_data_file("decide_questions_dedup.jsonl")
    lane_path = find_data_file("jevh_lane_bank.jsonl")
    print(f"[data] labels={labels_path}", flush=True)
    print(f"[data] decide={decide_path}", flush=True)
    print(f"[data] lane={lane_path}", flush=True)

    gold_all = load_gold(labels_path)
    decide_all = load_decide(decide_path)
    lane_all = load_lane_bank(lane_path)
    attach_soft_scores(gold_all, decide_all)
    gold_all = dedup_records(gold_all)

    questions = [r["question"] for r in gold_all]
    nopts = [r["n_options"] for r in gold_all]
    train_q, eval_q = stratified_question_split(questions, nopts, args.seed, args.eval_frac)
    gold_train = [r for r in gold_all if r["question"] in train_q]
    gold_eval = [r for r in gold_all if r["question"] in eval_q]
    split = split_report(gold_train, gold_eval)
    assert split["leakage_questions"] == 0, split
    assert split["eval_frac_questions"] >= 0.15, split
    print(f"[split unique-q] {json.dumps(split)}", flush=True)

    tmpl_train_q, tmpl_eval_q, tmpl_split_info = stratified_template_split(gold_all, args.seed, args.eval_frac)
    gold_tmpl_eval = [r for r in gold_all if r["question"] in tmpl_eval_q]
    gold_tmpl_clean = [r for r in gold_tmpl_eval if r["question"] not in train_q]
    tmpl_overlap_train = sum(1 for r in gold_tmpl_eval if r["question"] in train_q)
    print(f"[split template] {json.dumps(tmpl_split_info)} overlap_uniqueq_train={tmpl_overlap_train}", flush=True)
    _, _, tmpl_overlap = classify_eval_by_template(gold_train, gold_eval)
    print(f"[split template-overlap unique-q eval] {json.dumps(tmpl_overlap)}", flush=True)

    soft_pool = [
        r
        for r in decide_all
        if r.get("teacher_scores") is not None and r["question"] not in eval_q
    ]
    soft_pool = dedup_records(soft_pool)
    rng = random.Random(args.seed)
    if args.smoke:
        gold_train = gold_train[:16]
        gold_eval = gold_eval[:8] or gold_train[:4]
        gold_tmpl_eval = gold_tmpl_eval[:8] or gold_eval
        gold_tmpl_clean = gold_tmpl_clean[:8] or gold_eval
        soft_pool = soft_pool[:8]
        args.epochs = 1
        args.max_train_minutes = 2
        args.max_soft = 8
        args.skip_seq256 = True
        args.seq_len = min(args.seq_len, 32)
        args.no_resume = True
    gold_keys = {(r["question"], tuple(r["options"])) for r in gold_train}
    soft_pool = [r for r in soft_pool if (r["question"], tuple(r["options"])) not in gold_keys]
    if len(soft_pool) > args.max_soft:
        soft_pool = list(soft_pool)
        rng.shuffle(soft_pool)
        soft_pool = soft_pool[: args.max_soft]

    ckpt = ART / ("smoke_ettin.pt" if args.smoke else "jevh_large_ettin150m.pt")
    r1_pt = ART / "jevh_large_ettin150m_r1.pt"
    if not args.smoke:
        real_ckpt = ART / "jevh_large_ettin150m.pt"
        if real_ckpt.is_file() and not r1_pt.is_file():
            shutil.copy2(real_ckpt, r1_pt)
            print(f"[ckpt] copied round1 weights → {r1_pt}", flush=True)
        r1_metrics_copy = ART / "round1_metrics.json"
        src_m = ART / "metrics.json"
        if src_m.is_file() and not r1_metrics_copy.is_file():
            shutil.copy2(src_m, r1_metrics_copy)

    if args.smoke:
        cfg = EttinCfg().tiny()
        model = PairScorer(cfg, args.seq_len)

        class TinyTok:
            cls_token_id = 1
            sep_token_id = 2
            pad_token_id = 0

            def encode(self, text, add_special_tokens=False):
                return [(ord(c) % 120) + 3 for c in str(text)[:200]]

            def __call__(self, a, b=None, **kwargs):
                seq = kwargs.get("max_length", args.seq_len)
                ids, mask, _ = encode_pair(self, a, b or "", seq, keep_option=keep_option)
                return {"input_ids": ids, "attention_mask": mask}

        tok = TinyTok()
        missing, unexpected = [], []
        resumed = False
        resume_path = None
    else:
        print(f"[model] loading {args.backbone}", flush=True)
        tok = load_tokenizer(args.backbone, local_files_only=local_only)
        cfg, hf_state = load_backbone_cfg(args.backbone, local_files_only=local_only)
        model = PairScorer(cfg, args.seq_len)
        missing, unexpected = model.encoder.load_hf_encoder(hf_state)
        del hf_state
        print(f"[model] missing={len(missing)} unexpected={len(unexpected)}", flush=True)
        resumed = False
        resume_path = None if args.no_resume else Path(args.resume)
        if resume_path and resume_path.is_file():
            blob = torch.load(resume_path, map_location="cpu", weights_only=False)
            src = blob["model"]
            dst = model.state_dict()
            transferred = {k: v for k, v in src.items() if k in dst and tuple(dst[k].shape) == tuple(v.shape)}
            model.load_state_dict(transferred, strict=False)
            resumed = True
            print(
                f"[resume] {resume_path} tensors={len(transferred)}/{len(dst)} "
                f"(seq-dependent buffers rebuilt for seq={args.seq_len})",
                flush=True,
            )
            del blob, src, transferred
            gc.collect()
        elif resume_path:
            print(f"[resume] missing {resume_path}; training from HF init", flush=True)

    freeze_n = 0 if args.smoke else args.freeze_layers
    frozen = model.freeze_bottom_layers(freeze_n)
    use_ckpt = (not args.smoke) and (not args.no_grad_checkpoint)
    model.encoder.gradient_checkpointing = use_ckpt
    total_p, train_p = count_params(model)
    print(
        f"[model] params total={total_p} trainable={train_p} frozen_elems={frozen} "
        f"grad_checkpoint={use_ckpt}",
        flush=True,
    )
    model.to(device)

    trunc = truncation_report(tok, gold_all if not args.smoke else gold_train + gold_eval, [128, 256, args.seq_len])
    print(f"[truncation] {json.dumps(trunc)}", flush=True)

    def _encode_all(rows: list[dict[str, Any]], tag: str, seq: int | None = None) -> list[dict[str, Any]]:
        seq = args.seq_len if seq is None else seq
        out = []
        for i, rec in enumerate(rows, 1):
            out.append(encode_record(tok, rec, seq, keep_option=keep_option))
            if i == 1 or i % 500 == 0 or i == len(rows):
                print(f"[data] encoded {tag} {i}/{len(rows)} seq={seq}", flush=True)
        return out

    print("[data] encoding pairs…", flush=True)
    gold_train = _encode_all(gold_train, "gold_train")
    gold_eval = _encode_all(gold_eval, "gold_eval")
    gold_tmpl_eval = _encode_all(gold_tmpl_eval, "gold_tmpl_eval")
    gold_tmpl_clean = _encode_all(gold_tmpl_clean, "gold_tmpl_clean")
    soft_train = _encode_all(soft_pool, "soft")
    print(
        f"[data] encoded gold_train={len(gold_train)} gold_eval={len(gold_eval)} "
        f"tmpl_eval={len(gold_tmpl_eval)} tmpl_clean={len(gold_tmpl_clean)} soft={len(soft_train)}",
        flush=True,
    )

    r1_at_seq256 = None
    best_acc = -1.0
    start_epoch = 1
    if resumed:
        print("[eval] round-1 weights at train seq (before extra epochs)", flush=True)
        r1_at_seq256 = evaluate(model, gold_eval, device)
        best_acc = float(r1_at_seq256["overall"]["accuracy"])
        start_epoch = 2
        print(
            f"[eval] R1@seq{args.seq_len} acc={best_acc:.4f} "
            f"binary={r1_at_seq256['binary_2way'].get('accuracy')} "
            f"multi={r1_at_seq256['multi_choice'].get('accuracy')}",
            flush=True,
        )

    train_info = train_loop(
        model,
        gold_train,
        soft_train,
        gold_eval,
        device,
        epochs=args.epochs,
        lr=args.lr if not args.smoke else 1e-3,
        head_lr=args.head_lr if not args.smoke else 1e-3,
        max_minutes=args.max_train_minutes,
        gold_weight=args.gold_weight,
        soft_weight=args.soft_weight,
        target_pairs=4 if args.smoke else args.target_pairs,
        seed=args.seed,
        lr_decay=args.lr_decay,
        patience=args.patience,
        start_epoch=start_epoch,
        best_acc=best_acc,
    )

    metrics = evaluate(model, gold_eval, device)
    print("[metrics unique-q]", json.dumps({k: metrics[k] for k in metrics if k != "rows"}, indent=2), flush=True)

    seen_recs, unseen_recs, tmpl_overlap = classify_eval_by_template(gold_train, gold_eval)
    pred_by_q = {r["question"]: r for r in metrics["rows"]}
    seen_pred = [pred_by_q[r["question"]] for r in seen_recs if r["question"] in pred_by_q]
    unseen_pred = [pred_by_q[r["question"]] for r in unseen_recs if r["question"] in pred_by_q]
    metrics_seen = metrics_from_pred_rows(seen_pred)
    metrics_unseen = metrics_from_pred_rows(unseen_pred)
    print("[metrics template-seen]", json.dumps(metrics_seen, indent=2), flush=True)
    print("[metrics template-unseen]", json.dumps(metrics_unseen, indent=2), flush=True)

    metrics_tmpl = evaluate(model, gold_tmpl_eval, device) if gold_tmpl_eval else metrics_from_pred_rows([])
    metrics_tmpl_clean = evaluate(model, gold_tmpl_clean, device) if gold_tmpl_clean else metrics_from_pred_rows([])
    print("[metrics template-split]", json.dumps({k: metrics_tmpl[k] for k in metrics_tmpl if k != "rows"}, indent=2), flush=True)
    print("[metrics template-clean]", json.dumps({k: metrics_tmpl_clean[k] for k in metrics_tmpl_clean if k != "rows"}, indent=2), flush=True)

    torch.save(
        {
            "model": model.state_dict(),
            "cfg": model.cfg.__dict__,
            "seq_len": args.seq_len,
            "backbone": args.backbone,
            "round": 2,
            "metrics": {k: metrics[k] for k in metrics if k != "rows"},
        },
        ckpt,
    )

    mask_check = assert_mask_affects_output(model, args.seq_len)
    print("[mask]", mask_check, flush=True)
    if not mask_check["ok"]:
        print("WARNING: attention_mask did not change the logit", flush=True)

    def _export_seq(seq: int, tagged_eval: list[dict[str, Any]], max_pairs: int) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
        try:
            mexp = model.as_export(seq)
            path = ART / (f"smoke_seq{seq}.onnx" if args.smoke else f"jevh_large_ettin150m_seq{seq}.onnx")
            info = export_static_onnx(mexp, path, seq, opset=args.opset)
            print(
                f"[onnx{seq}]",
                {k: info[k] for k in ("path", "sha256", "issues", "attention_mask_used", "inputs", "outputs")},
                flush=True,
            )
            sample = tagged_eval
            if sample and sample[0].get("input_ids") and len(sample[0]["input_ids"][0]) != seq:
                sample = [
                    encode_record(tok, strip_encoded(r), seq, keep_option=keep_option) for r in tagged_eval[: max(32, min(len(tagged_eval), 80))]
                ]
            parity = verify_parity(mexp, path, sample, max_pairs=max_pairs)
            print(f"[parity{seq}]", parity, flush=True)
            del mexp
            gc.collect()
            return info, parity
        except Exception as exc:  # noqa: BLE001
            print(f"[onnx{seq}] failed: {type(exc).__name__}: {exc}", flush=True)
            return None, None

    info128 = parity128 = info256 = parity256 = None
    export_eval = gold_eval[:80] if args.smoke else gold_eval
    if args.seq_len == 128:
        info128, parity128 = _export_seq(128, export_eval, 16 if args.smoke else 128)
    elif not args.smoke:
        recs128 = _encode_all([strip_encoded(r) for r in gold_eval[:80]], "parity128", seq=128)
        info128, parity128 = _export_seq(128, recs128, 128)
    else:
        info128, parity128 = _export_seq(args.seq_len, export_eval, 16)

    if not args.skip_seq256:
        recs256 = gold_eval if args.seq_len == 256 else _encode_all([strip_encoded(r) for r in gold_eval[:80]], "parity256", seq=256)
        info256, parity256 = _export_seq(256, recs256[:80] if args.smoke else recs256, 16 if args.smoke else 64)

    calib256 = write_calib(gold_train + soft_train, args.seq_len, n=256, seed=args.seed)
    if args.seq_len != 128 and not args.smoke:
        recs128_cal = _encode_all([strip_encoded(r) for r in (gold_train + soft_train)[:120]], "calib128", seq=128)
        calib128 = write_calib(recs128_cal, 128, n=256, seed=args.seed)
    else:
        calib128 = calib256 if args.seq_len == 128 else write_calib(gold_train + soft_train, args.seq_len, n=256, seed=args.seed)
    print("[calib128]", calib128, flush=True)
    print("[calib256]", calib256, flush=True)

    latency = measure_latency(model, gold_eval, device, n=8 if args.smoke else 40)
    print("[latency]", latency, flush=True)

    beats = bool(metrics["overall"].get("beats_teacher"))
    soft_dump = None
    if beats and not args.skip_soft_dump and not args.smoke:
        dump_path = ART / "jevh_large_soft_on_decide_questions_dedup.jsonl"
        n_dump = 0
        with dump_path.open("w", encoding="utf-8") as fh:
            for raw in decide_all:
                rec = encode_record(tok, raw, args.seq_len, keep_option=keep_option)
                pred = predict_record(model, rec, device)
                fh.write(
                    json.dumps(
                        {
                            "question": raw["question"],
                            "context": raw.get("context"),
                            "options": raw["options"],
                            "qtype": raw["qtype"],
                            "teacher_choice": raw.get("teacher_choice"),
                            "teacher_scores": raw.get("teacher_scores"),
                            "large_choice": pred["choice"],
                            "large_index": pred["index"],
                            "large_scores": pred["scores"],
                            "large_confidence": pred["confidence"],
                            "large_logits": pred["logits"],
                            "backbone": args.backbone,
                            "seq_len": args.seq_len,
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                )
                n_dump += 1
                if n_dump % 500 == 0:
                    print(f"[soft-dump] {n_dump}/{len(decide_all)}", flush=True)
        gz_path = gzip_jsonl(dump_path)
        soft_dump = {
            "path": str(dump_path),
            "n": n_dump,
            "sha256": sha256_file(dump_path),
            "gz_path": str(gz_path),
            "gz_sha256": sha256_file(gz_path),
        }

    trunc128 = ((trunc.get("by_seq") or {}).get("128") or {}).get("all") or {}
    gaps = [
        "Gold labels are biased toward teacher-unsure / teacher-disagreement cases; they are not a uniform /decide sample.",
        "Most 2-way items are long binary choices (not literal yes/no). Literal yes/no in labels is tiny.",
        f"seq128 gold trunc_rate={trunc128.get('trunc_rate')} max_pair={trunc128.get('max_pair')} (2-way gap vs teacher is not seq128 clipping on gold).",
        "Unique-q eval still leaks near-duplicate templates; template-unseen is the honest generalization slice.",
        "Independent template split is reported but was not the training split (resume needed the round-1 unique-q partition).",
        f"Embeddings + first {freeze_n} encoder layers frozen; layer-wise LR on the rest. Not a full 150M fine-tune.",
        "No HEF compile (no DFC). No Pi deploy. Teacher soft labels are not gold. Large-model dump is not gold either.",
        "PR #26 mining corpus was not mixed in.",
        "ONNX is batch=1 static; multi-option decisions run one pair at a time for Hailo.",
    ]
    if not beats:
        gaps.append("Did not beat Qwen3 teacher on held-out jev_choice; soft dump on decide_questions skipped.")
    if info256 is None:
        gaps.append("seq256 ONNX not produced or failed; seq128 is the Hailo candidate.")
    if not (parity128 or {}).get("ok"):
        gaps.append(f"ONNX seq128 parity cosine below 0.999: {parity128}")
    if info256 is not None and not (parity256 or {}).get("ok"):
        gaps.append(f"ONNX seq256 parity cosine below 0.999: {parity256}")
    if not mask_check.get("ok"):
        gaps.append("attention_mask ablation did not change logits; graph may not use the mask.")

    def _drop_rows(m: dict[str, Any] | None) -> dict[str, Any] | None:
        if not m:
            return m
        return {k: v for k, v in m.items() if k != "rows"}

    payload = {
        "round": 2,
        "data": {
            "labels": file_info(labels_path),
            "decide": file_info(decide_path),
            "lane_bank": file_info(lane_path),
            "lane_n": len(lane_all),
        },
        "split": split,
        "template_split": tmpl_split_info,
        "template_overlap": tmpl_overlap,
        "template_eval_overlap_train": tmpl_overlap_train,
        "truncation": trunc,
        "recipe": {
            "backbone": args.backbone,
            "seq_len": args.seq_len,
            "export_seq256": bool(info256),
            "freeze_layers": freeze_n,
            "epochs": args.epochs,
            "start_epoch": start_epoch,
            "patience": args.patience,
            "lr": args.lr,
            "head_lr": args.head_lr,
            "lr_decay": args.lr_decay,
            "gold_weight": args.gold_weight,
            "soft_weight": args.soft_weight,
            "keep_option": keep_option,
            "gradient_checkpointing": use_ckpt,
            "resumed": resumed,
            "resume_path": str(resume_path) if resume_path else None,
            "seed": args.seed,
            "eval_frac": args.eval_frac,
            "params_total": total_p,
            "params_trainable": train_p,
            "n_soft_train": len(soft_train),
            "cpu": os.cpu_count(),
            "smoke": args.smoke,
        },
        "train": train_info,
        "round1": ROUND1,
        "round1_at_seq256": _drop_rows(r1_at_seq256),
        "metrics": _drop_rows(metrics),
        "metrics_template_seen": metrics_seen,
        "metrics_template_unseen": metrics_unseen,
        "metrics_template_split": _drop_rows(metrics_tmpl),
        "metrics_template_clean": _drop_rows(metrics_tmpl_clean),
        "latency": latency,
        "onnx_seq128": info128,
        "onnx_seq256": info256,
        "parity128": parity128,
        "parity256": parity256,
        "mask_check": mask_check,
        "calib128": calib128,
        "calib256": calib256,
        "calib": calib128,
        "soft_dump": soft_dump,
        "gaps": gaps,
        "ckpt": str(ckpt),
        "ckpt_r1": str(r1_pt),
    }
    metrics_path = ART / ("smoke_metrics.json" if args.smoke else "metrics.json")
    metrics_path.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
    if args.smoke:
        write_receipt(ART / "smoke_RECEIPT.md", payload)
        print(f"[done] smoke receipt {ART / 'smoke_RECEIPT.md'}", flush=True)
    else:
        write_receipt(HERE / "RECEIPT.md", payload)
        write_receipt(ART / "RECEIPT.md", payload)
        print(f"[done] receipt {HERE / 'RECEIPT.md'}", flush=True)
    print(
        f"[done] beats_teacher={beats} unique-q acc={metrics['overall']['accuracy']:.4f} "
        f"unseen={metrics_unseen.get('overall', {}).get('accuracy')} r1={ROUND1['overall']['accuracy']:.4f}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

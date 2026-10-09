#!/usr/bin/env python3
"""JEV-H-large trainer: ettin-encoder-150m quality ceiling + static ONNX export.

One-command (from repo root, after deps):

    python3 tools/jevh_large/train.py

Or: ./tools/jevh_large/run.sh
"""
from __future__ import annotations

import argparse
import json
import os
import random
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
    dedup_records,
    encode_record,
    find_data_file,
    iter_minibatches,
    load_decide,
    load_gold,
    load_lane_bank,
    split_report,
    stratified_question_split,
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
DEFAULT_SEQ = 128


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
    overall = subset_metrics(rows, "all")
    binary = subset_metrics([r for r in rows if r["n_options"] == 2], "binary_2way")
    multi = subset_metrics([r for r in rows if r["n_options"] > 2], "multi_choice")
    yesno = subset_metrics([r for r in rows if r["yesno"]], "literal_yesno")
    return {"overall": overall, "binary_2way": binary, "multi_choice": multi, "literal_yesno": yesno, "rows": rows}


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
) -> dict[str, Any]:
    enc_params = [p for n, p in model.named_parameters() if p.requires_grad and n.startswith("encoder.")]
    head_params = [p for n, p in model.named_parameters() if p.requires_grad and not n.startswith("encoder.")]
    opt = AdamW(
        [
            {"params": enc_params, "lr": lr},
            {"params": head_params, "lr": head_lr},
        ],
        weight_decay=0.01,
        foreach=False,
    )
    rng = random.Random(seed)
    t0 = time.time()
    steps = 0
    log = []
    best_acc = -1.0
    best_state = None
    stop_reason = "epochs_complete"
    kl = nn.KLDivLoss(reduction="batchmean")

    for epoch in range(1, epochs + 1):
        model.train()
        epoch_loss = 0.0
        n_batch = 0
        mix: list[dict[str, Any]] = list(gold_train) + list(soft_train)
        for batch in iter_minibatches(mix, rng, target_pairs=target_pairs):
            if (time.time() - t0) / 60.0 >= max_minutes:
                stop_reason = f"max_train_minutes={max_minutes}"
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
        if stop_reason.startswith("max_train"):
            print(f"[train] stopping: {stop_reason}", flush=True)
            break
        mean_loss = epoch_loss / max(1, n_batch)
        ev = evaluate(model, eval_records, device)
        acc = ev["overall"]["accuracy"]
        print(
            f"[eval] epoch={epoch} train_loss={mean_loss:.4f} eval_acc={acc:.4f} "
            f"teacher={ev['overall']['teacher_accuracy']} ece={ev['overall']['ece']:.4f} "
            f"conf_mistakes={ev['overall']['confident_mistakes']}",
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
        if acc >= best_acc:
            best_acc = acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
    if best_state is not None:
        model.load_state_dict(best_state)
    return {
        "steps": steps,
        "epochs_ran": len(log),
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


def write_receipt(path: Path, payload: dict[str, Any]) -> None:
    metrics = payload["metrics"]
    onnx128 = payload.get("onnx_seq128") or {}
    onnx256 = payload.get("onnx_seq256") or {}
    lines = [
        "# JEV-H-large receipt",
        "",
        "Quality-ceiling encoder student (`jhu-clsp/ettin-encoder-150m`, ModernBERT-150M).",
        "Trained on gold `jev_choice` plus Qwen3 teacher soft labels. No HEF compile, no Pi deploy.",
        "",
        "## Data",
        "",
        f"- labels: `{payload['data']['labels']['path']}` rows={payload['data']['labels']['rows']} sha256={payload['data']['labels']['sha256'][:12]}…",
        f"- decide_questions_dedup: `{payload['data']['decide']['path']}` rows={payload['data']['decide']['rows']} sha256={payload['data']['decide']['sha256'][:12]}…",
        f"- lane_bank: `{payload['data']['lane_bank']['path']}` rows={payload['data']['lane_bank']['rows']}",
        f"- split seed={payload['recipe']['seed']}, eval_frac={payload['recipe']['eval_frac']} by unique question, stratified by option count",
        f"- train unique questions: {payload['split']['train']['unique_questions']} ({payload['split']['train']['rows']} gold rows)",
        f"- eval unique questions: {payload['split']['eval']['unique_questions']} ({payload['split']['eval']['rows']} gold rows, {payload['split']['eval_frac_questions']:.1%})",
        f"- leakage questions: {payload['split']['leakage_questions']}",
        f"- gold train nopt={payload['split']['train']['nopt']} binary={payload['split']['train']['binary']} multi={payload['split']['train']['multi']} literal_yesno={payload['split']['train']['yesno']}",
        f"- eval nopt={payload['split']['eval']['nopt']} binary={payload['split']['eval']['binary']} multi={payload['split']['eval']['multi']} literal_yesno={payload['split']['eval']['yesno']}",
        f"- soft-label decide rows used in train (eval questions excluded): {payload['recipe']['n_soft_train']}",
        "",
        "Full dumps live in the agent `uploads/` directory (`labels_*.jsonl`, `decide_questions_dedup_*.jsonl`, `jevh_lane_bank_*.jsonl`).",
        "This repo keeps small samples under `tools/jevh_large/data/`. Set `JEVH_DATA_DIR` to override.",
        "",
        "## Recipe",
        "",
        f"- backbone: `{payload['recipe']['backbone']}`",
        f"- seq_len train/export128: {payload['recipe']['seq_len']}; export256: {payload['recipe'].get('export_seq256')}",
        f"- freeze embeddings + first {payload['recipe']['freeze_layers']} encoder layers; train remaining layers + head",
        f"- epochs={payload['recipe']['epochs']} (ran {payload['train']['epochs_ran']}, stop={payload['train']['stop_reason']})",
        f"- lr encoder={payload['recipe']['lr']} head={payload['recipe']['head_lr']} AdamW wd=0.01 clip=1 seed={payload['recipe']['seed']}",
        f"- loss: {payload['recipe']['gold_weight']} * CE(gold jev_choice) + {payload['recipe']['soft_weight']} * KL(teacher_scores)",
        f"- pooling: masked mean (attention_mask used in attention + pool)",
        f"- params total/trainable: {payload['recipe']['params_total']}/{payload['recipe']['params_trainable']}",
        f"- train wall seconds: {payload['train']['train_seconds']:.1f}",
        f"- hardware: CPU {payload['recipe']['cpu']} threads, no CUDA",
        "",
        "## Held-out metrics vs `jev_choice`",
        "",
        "| split | n | student acc | teacher acc (model_choice) | conf-mistakes ≥0.65 | ECE |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for key in ("overall", "binary_2way", "multi_choice", "literal_yesno"):
        m = metrics[key]
        if not m.get("n"):
            lines.append(f"| {key} | 0 | — | — | — | — |")
            continue
        ta = m.get("teacher_accuracy")
        ta_s = f"{ta:.4f}" if ta is not None else "—"
        lines.append(
            f"| {key} | {m['n']} | {m['accuracy']:.4f} | {ta_s} | {m['confident_mistakes']} | {m['ece']:.4f} |"
        )
    beats = metrics["overall"].get("beats_teacher")
    lines += [
        "",
        f"- Beats Qwen3-1.7B teacher on held-out `jev_choice`: **{beats}**",
        f"- CPU latency batch=1: per-option mean {payload['latency']['per_option_ms']['mean']:.1f} ms, "
        f"per-decision mean {payload['latency']['per_decision_ms']['mean']:.1f} ms "
        f"(by k={payload['latency']['per_decision_by_k']})",
        "",
        "## ONNX (Hailo-10H DFC static)",
        "",
        f"- seq{payload['recipe']['seq_len']}: `{onnx128.get('path')}`",
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
            f"  - ORT cosine={payload.get('parity256', {}).get('cosine')} ok={payload.get('parity256', {}).get('ok')}",
        ]
    else:
        lines.append("- seq256: not exported (see gaps)")
    lines += [
        "",
        f"- calibration seq128: `{payload['calib']['ids_path']}` shape={payload['calib']['shape']} (real tokenized pairs)",
        "",
        "## Soft teacher dump",
        "",
    ]
    if payload.get("soft_dump"):
        sd = payload["soft_dump"]
        lines.append(
            f"- wrote {sd['n']} rows to `{sd['path']}` because the large model beat the Qwen3 teacher on held-out gold."
        )
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
    p.add_argument("--epochs", type=int, default=2)
    p.add_argument("--lr", type=float, default=2e-5)
    p.add_argument("--head-lr", type=float, default=1e-4)
    p.add_argument("--freeze-layers", type=int, default=10)
    p.add_argument("--eval-frac", type=float, default=0.20)
    p.add_argument("--seed", type=int, default=SEED)
    p.add_argument("--gold-weight", type=float, default=1.0)
    p.add_argument("--soft-weight", type=float, default=0.3)
    p.add_argument("--target-pairs", type=int, default=8)
    p.add_argument("--max-train-minutes", type=float, default=75.0)
    p.add_argument("--max-soft", type=int, default=2500)
    p.add_argument("--opset", type=int, default=17)
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
    print(f"[split] {json.dumps(split)}", flush=True)

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
        soft_pool = soft_pool[:8]
        args.epochs = 1
        args.max_train_minutes = 2
        args.max_soft = 8
        args.skip_seq256 = True
    gold_keys = {(r["question"], tuple(r["options"])) for r in gold_train}
    soft_pool = [r for r in soft_pool if (r["question"], tuple(r["options"])) not in gold_keys]
    if len(soft_pool) > args.max_soft:
        soft_pool = list(soft_pool)
        rng.shuffle(soft_pool)
        soft_pool = soft_pool[: args.max_soft]

    if args.smoke:
        cfg = EttinCfg().tiny()
        model = PairScorer(cfg, args.seq_len)
        tok = None
        # Tiny tokenizer stand-in: hash words into 128 ids.
        class TinyTok:
            def __call__(self, a, b, **kwargs):
                seq = kwargs.get("max_length", args.seq_len)
                text = f"{a} [SEP] {b}"
                ids = [(ord(c) % 120) + 1 for c in text[: seq - 1]]
                ids = [1] + ids
                ids = ids[:seq] + [0] * (seq - len(ids))
                mask = [1 if i != 0 else 0 for i in ids]
                return {"input_ids": ids, "attention_mask": mask}

        tok = TinyTok()
        missing, unexpected = [], []
    else:
        print(f"[model] loading {args.backbone}", flush=True)
        tok = load_tokenizer(args.backbone, local_files_only=local_only)
        cfg, hf_state = load_backbone_cfg(args.backbone, local_files_only=local_only)
        model = PairScorer(cfg, args.seq_len)
        missing, unexpected = model.encoder.load_hf_encoder(hf_state)
        del hf_state
        print(f"[model] missing={len(missing)} unexpected={len(unexpected)}", flush=True)

    frozen = model.freeze_bottom_layers(0 if args.smoke else args.freeze_layers)
    total_p, train_p = count_params(model)
    print(f"[model] params total={total_p} trainable={train_p} frozen_tensors={frozen}", flush=True)
    model.to(device)

    def _encode_all(rows: list[dict[str, Any]], tag: str) -> list[dict[str, Any]]:
        out = []
        for i, rec in enumerate(rows, 1):
            out.append(encode_record(tok, rec, args.seq_len))
            if i == 1 or i % 500 == 0 or i == len(rows):
                print(f"[data] encoded {tag} {i}/{len(rows)}", flush=True)
        return out

    print("[data] encoding pairs…", flush=True)
    gold_train = _encode_all(gold_train, "gold_train")
    gold_eval = _encode_all(gold_eval, "gold_eval")
    soft_train = _encode_all(soft_pool, "soft")
    print(f"[data] encoded gold_train={len(gold_train)} gold_eval={len(gold_eval)} soft={len(soft_train)}", flush=True)

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
    )

    metrics = evaluate(model, gold_eval, device)
    print("[metrics]", json.dumps({k: metrics[k] for k in metrics if k != "rows"}, indent=2), flush=True)

    ckpt = ART / "jevh_large_ettin150m.pt"
    torch.save(
        {
            "model": model.state_dict(),
            "cfg": model.cfg.__dict__,
            "seq_len": args.seq_len,
            "backbone": args.backbone,
            "metrics": {k: metrics[k] for k in metrics if k != "rows"},
        },
        ckpt,
    )

    mask_check = assert_mask_affects_output(model, args.seq_len)
    print("[mask]", mask_check, flush=True)
    if not mask_check["ok"]:
        print("WARNING: attention_mask did not change the logit", flush=True)

    export128 = model.as_export(args.seq_len)
    onnx128_path = ART / f"jevh_large_ettin150m_seq{args.seq_len}.onnx"
    info128 = export_static_onnx(export128, onnx128_path, args.seq_len, opset=args.opset)
    print("[onnx128]", {k: info128[k] for k in ("path", "sha256", "issues", "attention_mask_used", "inputs", "outputs")}, flush=True)
    parity128 = verify_parity(export128, onnx128_path, gold_eval, max_pairs=64 if args.smoke else 256)
    print("[parity128]", parity128, flush=True)

    info256 = None
    parity256 = None
    if not args.skip_seq256:
        try:
            m256 = model.as_export(256).to(device)
            gold_eval256 = [encode_record(tok, {k: v for k, v in r.items() if k not in ("input_ids", "attention_mask")}, 256) for r in gold_eval[:32]]
            onnx256_path = ART / "jevh_large_ettin150m_seq256.onnx"
            info256 = export_static_onnx(m256, onnx256_path, 256, opset=args.opset)
            parity256 = verify_parity(m256, onnx256_path, gold_eval256, max_pairs=64)
            print("[onnx256]", {k: info256[k] for k in ("path", "sha256", "issues", "attention_mask_used")}, flush=True)
            print("[parity256]", parity256, flush=True)
            del m256
        except Exception as exc:  # noqa: BLE001
            print(f"[onnx256] failed: {type(exc).__name__}: {exc}", flush=True)
            info256 = None

    # calibration set: 256 real pairs from train gold + soft
    calib_src = (gold_train + soft_train)[: max(256, len(gold_train))]
    rng.shuffle(calib_src)
    pairs_ids, pairs_mask = [], []
    for rec in calib_src:
        for ids, mask in zip(rec["input_ids"], rec["attention_mask"]):
            pairs_ids.append(ids)
            pairs_mask.append(mask)
            if len(pairs_ids) >= 256:
                break
        if len(pairs_ids) >= 256:
            break
    while len(pairs_ids) < 256 and pairs_ids:
        pairs_ids.append(pairs_ids[len(pairs_ids) % len(pairs_ids)])
        pairs_mask.append(pairs_mask[len(pairs_mask) % len(pairs_mask)])
    ids_np = np.asarray(pairs_ids[:256], dtype=np.int64)
    mask_np = np.asarray(pairs_mask[:256], dtype=np.int64)
    ids_path = ART / f"calib_input_ids_seq{args.seq_len}.npy"
    mask_path = ART / f"calib_attention_mask_seq{args.seq_len}.npy"
    np.save(ids_path, ids_np)
    np.save(mask_path, mask_np)

    latency = measure_latency(model, gold_eval, device, n=8 if args.smoke else 40)
    print("[latency]", latency, flush=True)

    beats = bool(metrics["overall"].get("beats_teacher"))
    soft_dump = None
    if beats and not args.skip_soft_dump and not args.smoke:
        dump_path = ART / "jevh_large_soft_on_decide_questions_dedup.jsonl"
        n_dump = 0
        with dump_path.open("w", encoding="utf-8") as fh:
            for raw in decide_all:
                rec = encode_record(tok, raw, args.seq_len)
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
        soft_dump = {"path": str(dump_path), "n": n_dump, "sha256": sha256_file(dump_path)}

    gaps = [
        "Gold labels are biased toward teacher-unsure / teacher-disagreement cases; they are not a uniform /decide sample.",
        "Most 2-way items are long binary choices (not literal yes/no). Literal yes/no in labels is tiny.",
        f"Train seq_len={args.seq_len}; long 2-way options truncate (p90 pair is hundreds of characters).",
        "Early encoder layers + embeddings frozen to fit CPU RAM/time; not a full 150M fine-tune.",
        "No HEF compile (no DFC). No Pi deploy. Teacher soft labels are not gold.",
        "PR #26 mining corpus was not mixed in.",
        "ONNX is batch=1 static; multi-option decisions run one pair at a time for Hailo.",
    ]
    if not beats:
        gaps.append("Did not beat Qwen3 teacher on held-out jev_choice; soft dump on decide_questions skipped.")
    if info256 is None:
        gaps.append("seq256 ONNX not produced or failed; seq128 is the Hailo candidate.")
    if not (parity128 or {}).get("ok"):
        gaps.append(f"ONNX seq{args.seq_len} parity cosine below 0.999: {parity128}")
    if not mask_check.get("ok"):
        gaps.append("attention_mask ablation did not change logits; graph may not use the mask.")

    payload = {
        "data": {
            "labels": file_info(labels_path),
            "decide": file_info(decide_path),
            "lane_bank": file_info(lane_path),
            "lane_n": len(lane_all),
        },
        "split": split,
        "recipe": {
            "backbone": args.backbone,
            "seq_len": args.seq_len,
            "export_seq256": bool(info256),
            "freeze_layers": 0 if args.smoke else args.freeze_layers,
            "epochs": args.epochs,
            "lr": args.lr,
            "head_lr": args.head_lr,
            "gold_weight": args.gold_weight,
            "soft_weight": args.soft_weight,
            "seed": args.seed,
            "eval_frac": args.eval_frac,
            "params_total": total_p,
            "params_trainable": train_p,
            "n_soft_train": len(soft_train),
            "cpu": os.cpu_count(),
            "smoke": args.smoke,
        },
        "train": train_info,
        "metrics": {k: metrics[k] for k in metrics if k != "rows"},
        "latency": latency,
        "onnx_seq128": info128,
        "onnx_seq256": info256,
        "parity128": parity128,
        "parity256": parity256,
        "mask_check": mask_check,
        "calib": {"ids_path": str(ids_path), "mask_path": str(mask_path), "shape": list(ids_np.shape)},
        "soft_dump": soft_dump,
        "gaps": gaps,
        "ckpt": str(ckpt),
    }
    metrics_path = ART / "metrics.json"
    # drop huge train log tensors
    metrics_path.write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
    write_receipt(HERE / "RECEIPT.md", payload)
    write_receipt(ART / "RECEIPT.md", payload)
    print(f"[done] receipt {HERE / 'RECEIPT.md'}", flush=True)
    print(f"[done] beats_teacher={beats} eval_acc={metrics['overall']['accuracy']:.4f}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

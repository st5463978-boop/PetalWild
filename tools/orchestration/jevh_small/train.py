#!/usr/bin/env python3
"""Train JEV-H-small (ettin-encoder-17m student), eval, export static ONNX.

One command (from this directory, after deps):

    python3 train.py

Or: ./run.sh
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys
import time
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import numpy as np
import torch
from torch.nn import functional as F

from data import (
    EVAL_FRAC,
    SEED,
    dump_split,
    load_labels,
    load_lane_bank,
    load_soft_decide,
    load_decide_index,
    resolve_paths,
    split_by_question,
    subsample,
)
from encode import SEQ_LEN, StudentTok
from export import export_onnx, save_calib, sha256_file, verify_ort_parity
from metrics import CONF_THRESH, Timer, latency_stats, softmax, summarize_preds
from model import ETTIN17, ETTIN68, OptionScorer, ettin_param_count, load_pretrained, write_config

HF_REPO = "jhu-clsp/ettin-encoder-17m"
DEFAULT_EPOCHS = 3
DEFAULT_BATCH = 4
SOFT_WEIGHT = 0.4
SOFT_EXTRA = 1200
LR = 3e-5
HEAD_LR = 1e-3
WD = 0.01
WARMUP_FRAC = 0.06
CLIP = 1.0
HF_WEIGHT_CANDIDATES = ("model.safetensors", "pytorch_model.bin")


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train JEV-H-small ettin-17m student")
    p.add_argument("--data-dir", default=os.environ.get("JEVH_DATA_DIR") or "")
    p.add_argument("--labels", default="")
    p.add_argument("--decide", default="")
    p.add_argument("--lane", default="")
    p.add_argument("--tokenizer", default="")
    p.add_argument("--out", default=str(HERE / "artifacts"))
    p.add_argument("--epochs", type=int, default=DEFAULT_EPOCHS)
    p.add_argument("--batch", type=int, default=DEFAULT_BATCH)
    p.add_argument("--seed", type=int, default=SEED)
    p.add_argument("--eval-frac", type=float, default=EVAL_FRAC)
    p.add_argument("--soft-weight", type=float, default=SOFT_WEIGHT)
    p.add_argument("--soft-extra", type=int, default=SOFT_EXTRA)
    p.add_argument("--lr", type=float, default=LR)
    p.add_argument("--head-lr", type=float, default=HEAD_LR)
    p.add_argument("--opset", type=int, default=17)
    p.add_argument("--quick", action="store_true", help="tiny run for smoke (scale-down)")
    p.add_argument("--skip-train", action="store_true")
    p.add_argument("--weights", default="", help="path to ettin 17m checkpoint (otherwise HF download)")
    p.add_argument("--hf-repo", default=HF_REPO)
    p.add_argument("--hf-revision", default="")
    p.add_argument("--latency-n", type=int, default=64)
    return p.parse_args()


def download_backbone(repo: str, out_dir: Path, revision: str | None) -> tuple[Path, dict[str, Any]]:
    from huggingface_hub import hf_hub_download, model_info

    out_dir.mkdir(parents=True, exist_ok=True)
    info = model_info(repo, revision=revision or None)
    sha = info.sha
    meta = {"repo": repo, "revision": sha, "siblings": [s.rfilename for s in info.siblings]}
    weight_name = next((n for n in HF_WEIGHT_CANDIDATES if n in meta["siblings"]), None)
    if weight_name is None:
        raise FileNotFoundError(f"no weights in {repo}: {meta['siblings'][:20]}")
    cfg = hf_hub_download(repo, "config.json", revision=sha, cache_dir=str(out_dir / "hf_cache"))
    wt = hf_hub_download(repo, weight_name, revision=sha, cache_dir=str(out_dir / "hf_cache"))
    meta["config_path"] = cfg
    meta["weight_path"] = wt
    meta["weight_name"] = weight_name
    return Path(wt), meta


def batches(items: list, size: int):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def encode_batch(tok: StudentTok, examples, torch):
    ids, masks, n_opts, golds, teacher = [], [], [], [], []
    for ex in examples:
        i, m, _, _ = tok.encode_question(ex.question, ex.options, ex.context)
        ids.extend(i)
        masks.extend(m)
        n_opts.append(len(ex.options))
        golds.append(-1 if ex.gold_index is None else int(ex.gold_index))
        teacher.append(ex.teacher_scores)
    return (
        torch.tensor(ids, dtype=torch.long),
        torch.tensor(masks, dtype=torch.float32),
        n_opts,
        golds,
        teacher,
    )


def grouped_loss(logits, n_opts, golds, teacher, soft_weight, torch, F):
    loss = logits.new_zeros(())
    n_hard = 0
    n_soft = 0
    off = 0
    for n, g, ts in zip(n_opts, golds, teacher):
        lg = logits[off : off + n]
        off += n
        if g >= 0:
            loss = loss + F.cross_entropy(lg.unsqueeze(0), torch.tensor([g], device=lg.device))
            n_hard += 1
        if ts is not None and n == len(ts):
            logp = F.log_softmax(lg.float(), dim=0)
            tgt = torch.tensor(ts, dtype=logp.dtype, device=lg.device)
            loss = loss + soft_weight * F.kl_div(logp, tgt, reduction="sum")
            n_soft += 1
    denom = max(n_hard + n_soft, 1)
    return loss / denom, n_hard, n_soft


def lr_at(step: int, total: int, warmup: int, base: float) -> float:
    if step < warmup:
        return base * float(step + 1) / max(warmup, 1)
    t = (step - warmup) / max(total - warmup, 1)
    return base * 0.5 * (1.0 + math.cos(math.pi * min(t, 1.0)))


def predict_example(model, tok, ex):
    ids, masks, _, _ = tok.encode_question(ex.question, ex.options, ex.context)
    ids_t = torch.tensor(ids, dtype=torch.long)
    mask_t = torch.tensor(masks, dtype=torch.float32)
    with torch.no_grad():
        logits = model(ids_t, mask_t).cpu().numpy().astype(np.float64)
    probs = softmax(logits)
    idx = int(probs.argmax())
    return logits, probs, idx, float(probs[idx])


def eval_split(model, tok, examples, latency_n: int) -> dict[str, Any]:
    model.eval()
    gold, pred, conf, teacher, binary = [], [], [], [], []
    all_logits = []
    lat_ms = []
    lat_seq_ms = []
    for i, ex in enumerate(examples):
        if ex.gold_index is None:
            continue
        with Timer() as t_pack:
            logits, probs, idx, c = predict_example(model, tok, ex)
        gold.append(int(ex.gold_index))
        pred.append(idx)
        conf.append(c)
        teacher.append(ex.teacher_index)
        binary.append(bool(ex.is_binary()))
        all_logits.append(np.asarray(logits, dtype=np.float64))
        if i < latency_n:
            lat_ms.append(t_pack.ms)
            with Timer() as t_seq:
                ids, masks, _, _ = tok.encode_question(ex.question, ex.options, ex.context)
                parts = []
                with torch.no_grad():
                    for row_i, row_m in zip(ids, masks):
                        li = torch.tensor([row_i], dtype=torch.long)
                        lm = torch.tensor([row_m], dtype=torch.float32)
                        parts.append(float(model(li, lm).cpu().item()))
                _ = softmax(np.asarray(parts, dtype=np.float64))
            lat_seq_ms.append(t_seq.ms)
    metrics = summarize_preds(gold, pred, conf, teacher, binary, CONF_THRESH)
    metrics["latency_packed_options"] = latency_stats(lat_ms)
    metrics["latency_batch1_per_option"] = latency_stats(lat_seq_ms)
    metrics["latency_note"] = (
        "latency_batch1_per_option is Hailo-style: each option scored at batch=1, seq=128; "
        "one decision = all options sequential. packed_options forwards K options together on CPU."
    )
    return metrics, all_logits, gold, pred, conf


def write_receipt(path: Path, payload: dict[str, Any]) -> None:
    m = payload["metrics"]
    yn, mc = m["yesno"], m["multi"]
    onnx = payload["onnx"]
    lines = [
        "# JEV-H-small receipt (ettin-encoder-17m)",
        "",
        "Speed/size floor student for PetalWild JEV-H. Distils a 17M Ettin encoder into a",
        "multiple-choice / yes-no scorer. **No HEF compile. No Pi deploy. No paid APIs.**",
        "",
        "## Backbone choice",
        "",
        "- **Picked: `jhu-clsp/ettin-encoder-17m`** (17M, hidden 256, 7 layers, 4 heads, intermediate 384).",
        "- Same ModernBERT/Ettin family as the live 68m Hailo student, same 50,368 BPE tokenizer,",
        "  same pair encoding (`[qtype] question` as text_a, option as text_b, seq 128, CLS head).",
        "- 17M is the published Ettin XXS / mobile-edge checkpoint and sits at the bottom of the",
        "  requested 17–30M band. `ettin-encoder-32m` would be the next size up if this floor is too weak.",
        f"- Encoder params (formula): 17m ≈ {ettin_param_count(ETTIN17):,}; 68m ≈ {ettin_param_count(ETTIN68):,}.",
        "- Live 68m host weights were 104 MB (not attached here); 17m encoder+head ONNX is ~encoder fp32 size.",
        "",
        "## Data",
        "",
        f"- labels: `{payload['paths']['labels']}` — {payload['counts']['label_rows']} rows, "
        f"{payload['counts']['label_questions']} unique questions. Gold = `jev_choice`.",
        "  Biased toward hard cases (teacher unsure or disagreed).",
        f"- decide_questions_dedup: `{payload['paths']['decide']}` — {payload['counts']['decide_rows']} rows, "
        f"{payload['counts']['decide_teacher']} with teacher soft scores. **Not gold.**",
        f"- lane bank: `{payload['paths']['lane']}` — {payload['counts']['lane_rows']} unlabeled game questions "
        "(calibration only).",
        f"- tokenizer: `{payload['paths']['tokenizer']}` (live student tokenizer.json).",
        "- Full files live in the Cloud Agent upload bundle (hashed names) or `$JEVH_DATA_DIR`.",
        "  Samples (not full data) are in `data/`. Do not treat decide rows as gold.",
        "- Mining / teacher-swarm corpora from PR #26 were **not** used.",
        "",
        "## Split (unique question, no leakage)",
        "",
        f"- seed {payload['split']['seed']}, eval fraction {payload['split']['eval_frac']:.4f} "
        f"({payload['split']['n_eval_questions']} / {payload['split']['n_unique_questions']} questions).",
        f"- train rows {payload['split']['n_train_rows']} (2-way {payload['split']['train_yesno_rows']}, "
        f"multi {payload['split']['train_multi_rows']}).",
        f"- eval rows {payload['split']['n_eval_rows']} (2-way {payload['split']['eval_yesno_rows']}, "
        f"multi {payload['split']['eval_multi_rows']}).",
        f"- option-count strata: `{json.dumps(payload['split']['by_option_count'])}`.",
        "- 2-way is reported as yes/no (matches the label card's 1,111 2-way count). Strict noul (literal yes/no) is rarer.",
        "",
        "## Recipe",
        "",
        f"- backbone `{payload['hf']['repo']}` revision `{payload['hf'].get('revision')}`.",
        f"- freeze token embeddings; fine-tune 7 encoder layers + GELU CLS head (Linear→GELU→LN→Linear→1).",
        f"- hard CE on `jev_choice` + KL to Qwen3 teacher scores (λ={payload['recipe']['soft_weight']}).",
        f"- extra unlabeled teacher rows: {payload['recipe']['soft_extra_used']} (capped, eval questions excluded).",
        f"- AdamW encoder lr {payload['recipe']['lr']}, head lr {payload['recipe']['head_lr']}, wd {WD}, clip {CLIP}.",
        f"- epochs {payload['recipe']['epochs']}, batch {payload['recipe']['batch']} questions, seed {payload['recipe']['seed']}.",
        f"- device: CPU (`{payload['recipe']['device']}`), threads {payload['recipe']['threads']}.",
        f"- scaled down: {payload['recipe']['scaled_down']}. {payload['recipe'].get('scale_note', '')}",
        "",
        "## Metrics (held-out labels, gold = jev_choice)",
        "",
        "| split | n | student acc | teacher acc (model_choice) | confident mistakes (≥0.65) | ECE |",
        "|---|---:|---:|---:|---:|---:|",
        _row("all", m),
        _row("yes/no (2-way)", yn),
        _row("multi-choice", mc),
        "",
        f"- mean student confidence {m.get('mean_confidence')}.",
        f"- CPU latency per decision, batch=1 per option: {m.get('latency_batch1_per_option')}.",
        f"- CPU latency packed options: {m.get('latency_packed_options')}.",
        "",
        "## ONNX (Hailo-10H DFC, no compile here)",
        "",
        f"- path: `{onnx.get('path')}`",
        f"- sha256: `{onnx.get('sha256')}`",
        f"- opset {onnx.get('opset')}, nodes {onnx.get('n_nodes')}, bytes {onnx.get('bytes')}.",
        f"- inputs: `{onnx.get('inputs')}`",
        f"- outputs: `{onnx.get('outputs')}`",
        f"- attention_mask used in graph: {onnx.get('attention_mask_used')}",
        f"- forbidden ops (Loop/If/NonZero): `{onnx.get('forbidden_ops')}`",
        f"- PyTorch vs ORT cosine: {payload['parity'].get('cosine')} (need ≥ 0.999), ok={payload['parity'].get('ok')}.",
        f"- calib: n={payload['calib'].get('n')} `artifacts/calib/input_ids.npy` + `attention_mask.npy`.",
        "",
        "## Size / latency trade-off vs 68m",
        "",
        payload["tradeoff"],
        "",
        "## Known gaps",
        "",
    ]
    for g in payload["gaps"]:
        lines.append(f"- {g}")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def _row(name: str, d: dict[str, Any]) -> str:
    def fmt(x):
        if x is None:
            return "—"
        if isinstance(x, float):
            return f"{x:.4f}"
        return str(x)

    return (
        f"| {name} | {fmt(d.get('n'))} | {fmt(d.get('accuracy'))} | "
        f"{fmt(d.get('teacher_accuracy'))} | {fmt(d.get('confident_mistakes'))} | {fmt(d.get('ece'))} |"
    )


def main() -> int:
    args = parse_args()
    if args.data_dir == "":
        args.data_dir = None
    for a in ("labels", "decide", "lane", "tokenizer"):
        if getattr(args, a) == "":
            setattr(args, a, None)

    threads = int(os.environ.get("OMP_NUM_THREADS") or os.cpu_count() or 4)
    torch.set_num_threads(threads)
    set_seed(args.seed)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    paths = resolve_paths(args)
    tok = StudentTok(str(paths["tokenizer"]), SEQ_LEN)
    decide_idx = load_decide_index(paths["decide"])
    labels = load_labels(paths["labels"], decide_idx)
    if args.quick:
        labels = labels[:400]
        args.epochs = min(args.epochs, 1)
        args.soft_extra = min(args.soft_extra, 64)
        args.latency_n = min(args.latency_n, 8)
    train, eval_, split_meta = split_by_question(labels, eval_frac=args.eval_frac, seed=args.seed)
    if split_meta["eval_frac"] < 0.15:
        raise SystemExit(f"eval fraction {split_meta['eval_frac']} < 0.15")
    dump_split(out / "split.json", train, eval_, split_meta)
    eval_q = {e.question for e in eval_}
    extra_soft = load_soft_decide(paths["decide"], exclude_questions=eval_q)
    extra_soft = subsample(extra_soft, args.soft_extra, args.seed)
    lane = load_lane_bank(paths["lane"])
    decide_rows = sum(1 for _ in open(paths["decide"], encoding="utf-8"))
    decide_teacher = sum(1 for r in decide_idx.values() if r.get("teacher_scores"))

    recipe = {
        "epochs": args.epochs,
        "batch": args.batch,
        "seed": args.seed,
        "lr": args.lr,
        "head_lr": args.head_lr,
        "soft_weight": args.soft_weight,
        "soft_extra_used": len(extra_soft),
        "device": "cpu",
        "threads": threads,
        "scaled_down": bool(args.quick),
        "scale_note": "quick smoke subset" if args.quick else "full CPU recipe as above",
        "freeze_embeddings": True,
        "seq_len": SEQ_LEN,
        "opset": args.opset,
    }

    hf_meta: dict[str, Any] = {"repo": args.hf_repo, "revision": args.hf_revision or "main"}
    model = OptionScorer(ETTIN17, SEQ_LEN)
    if not args.skip_train:
        if args.weights:
            wpath = Path(args.weights)
            load_info = load_pretrained(model, wpath)
            hf_meta["weight_path"] = str(wpath)
        else:
            wpath, hf_meta = download_backbone(args.hf_repo, out, args.hf_revision or None)
            load_info = load_pretrained(model, wpath)
        (out / "weight_load.json").write_text(json.dumps({**hf_meta, **load_info}, indent=2, default=str), encoding="utf-8")
        if load_info.get("missing", 99) > 4:
            print("WARN missing encoder keys", load_info, flush=True)
        model.freeze_embeddings()
        print(
            f"[jevh-small] params {model.n_params():,} trainable {model.n_params(True):,} "
            f"train {len(train)} eval {len(eval_)} soft {len(extra_soft)}",
            flush=True,
        )
        opt_params = [
            {"params": [p for n, p in model.named_parameters() if p.requires_grad and n.startswith("encoder.")], "lr": args.lr},
            {"params": [p for n, p in model.named_parameters() if p.requires_grad and not n.startswith("encoder.")], "lr": args.head_lr},
        ]
        opt = torch.optim.AdamW(opt_params, weight_decay=WD)
        mix = list(train) + list(extra_soft)
        steps_per = max(1, math.ceil(len(mix) / args.batch))
        total_steps = steps_per * args.epochs
        warmup = max(1, int(total_steps * WARMUP_FRAC))
        t0 = time.time()
        model.train()
        step = 0
        log = []
        for epoch in range(args.epochs):
            rng = random.Random(args.seed + epoch)
            order = list(mix)
            rng.shuffle(order)
            running = 0.0
            nseen = 0
            for chunk in batches(order, args.batch):
                opt.zero_grad(set_to_none=True)
                ids, masks, n_opts, golds, teacher = encode_batch(tok, chunk, torch)
                logits = model(ids, masks)
                loss, n_hard, n_soft = grouped_loss(logits, n_opts, golds, teacher, args.soft_weight, torch, F)
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), CLIP)
                enc_lr = lr_at(step, total_steps, warmup, args.lr)
                head_lr = lr_at(step, total_steps, warmup, args.head_lr)
                for i, g in enumerate(opt.param_groups):
                    g["lr"] = enc_lr if i == 0 else head_lr
                opt.step()
                running += float(loss.item())
                nseen += 1
                step += 1
                if step % 20 == 0 or nseen == 1:
                    print(
                        f"[jevh-small] epoch {epoch+1}/{args.epochs} step {step}/{total_steps} "
                        f"loss {loss.item():.4f} hard {n_hard} soft {n_soft}",
                        flush=True,
                    )
            log.append({"epoch": epoch + 1, "mean_loss": running / max(nseen, 1), "steps": nseen})
        recipe["train_seconds"] = round(time.time() - t0, 1)
        recipe["train_log"] = log
        ckpt = out / "jevh_small_ettin17m.pt"
        torch.save(
            {
                "model": model.state_dict(),
                "cfg": ETTIN17,
                "seq_len": SEQ_LEN,
                "recipe": recipe,
                "hf": hf_meta,
            },
            ckpt,
        )
        recipe["ckpt"] = str(ckpt)
    else:
        ckpt = out / "jevh_small_ettin17m.pt"
        blob = torch.load(str(ckpt), map_location="cpu", weights_only=False)
        model.load_state_dict(blob["model"])

    write_config(out / "config.json", {"n_params": model.n_params()})
    model.eval()
    metrics, eval_logits, gold, pred, conf = eval_split(model, tok, eval_, args.latency_n)
    (out / "metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print("[jevh-small] eval", json.dumps({k: metrics[k] for k in ("n", "accuracy", "teacher_accuracy", "confident_mistakes", "ece")}), flush=True)

    onnx_path = out / "jevh_small_ettin17m_seq128.onnx"
    onnx_info = export_onnx(model, onnx_path, opset=args.opset)
    (out / "onnx_meta.json").write_text(json.dumps(onnx_info, indent=2), encoding="utf-8")

    # parity on eval option rows (flatten)
    pair_ids, pair_masks = [], []
    for ex in eval_[: max(32, min(len(eval_), 128))]:
        ids, masks, _, _ = tok.encode_question(ex.question, ex.options, ex.context)
        pair_ids.extend(ids)
        pair_masks.extend(masks)
    pair_ids = np.asarray(pair_ids[:512], dtype=np.int64)
    pair_masks = np.asarray(pair_masks[:512], dtype=np.float32)
    parity = verify_ort_parity(model, onnx_path, pair_ids, pair_masks, min_cos=0.999)
    (out / "onnx_parity.json").write_text(json.dumps(parity, indent=2), encoding="utf-8")
    if not parity["ok"]:
        print("WARN ONNX parity failed", parity, flush=True)

    calib_ids, calib_masks = [], []
    calib_src = list(train) + list(lane) + list(extra_soft)
    rng = random.Random(args.seed)
    rng.shuffle(calib_src)
    for ex in calib_src:
        ids, masks, _, _ = tok.encode_question(ex.question, ex.options, ex.context)
        calib_ids.extend(ids)
        calib_masks.extend(masks)
        if len(calib_ids) >= 256:
            break
    if len(calib_ids) < 256:
        raise SystemExit(f"only {len(calib_ids)} calib rows")
    calib_ids = np.asarray(calib_ids[:512], dtype=np.int64)
    calib_masks = np.asarray(calib_masks[:512], dtype=np.int64)
    calib_info = save_calib(
        out / "calib",
        calib_ids,
        calib_masks,
        {"drawn_from": "train labels + lane bank + extra teacher rows", "excluded": "held-out eval questions"},
    )

    n_params = model.n_params()
    p17 = ettin_param_count(ETTIN17)
    p68 = ettin_param_count(ETTIN68)
    lat = metrics.get("latency_batch1_per_option") or {}
    tradeoff = (
        f"Student has {n_params:,} parameters (encoder formula ~{p17:,} plus a small CLS head). "
        f"Ettin-68m encoder formula ~{p68:,} params (~{p68 / max(p17,1):.1f}×). "
        f"Transformer-body FLOPs scale roughly (19/7)×(512/256)×(768/384) ≈ 11× for FFN; "
        f"the live 68m NPU decision was ~55 ms wall on Hailo-10H (reference service). "
        f"This 17m CPU batch-1 decision is mean {lat.get('mean_ms')} ms on {threads} threads "
        f"(not comparable to NPU, but the HEF should be much smaller/faster than 68m). "
        f"68m CPU accuracy was not re-measured (host_weights_v4_ettin68m.npz not attached)."
    )
    gaps = [
        "Labels are hard-case biased (written when the teacher was unsure or disagreed), so held-out accuracy is not in-the-wild decide accuracy.",
        "Teacher (Qwen3-1.7B model_choice) is a baseline on the same rows, not gold.",
        "No 68m student was re-run; size/latency comparison is from the Ettin card + the live :8771 reference (~55 ms NPU).",
        "ONNX is batch=1 seq=128 per option; softmax over options stays on the host (variable 2–6 options).",
        "No Hailo DFC compile, no HEF, no Pi flash.",
        "Local attention window at seq=128 is ±64; global every 3rd layer. Mask is additive -1e4, not -inf.",
        "PR #26 mining failures were not mixed into train (owned by the other agent).",
    ]
    if args.quick:
        gaps.insert(0, "This run used --quick (subset / 1 epoch). Metrics are smoke-only.")
    if onnx_info.get("forbidden_ops"):
        gaps.append(f"ONNX still contains forbidden ops: {onnx_info['forbidden_ops']}")
    if not onnx_info.get("attention_mask_used"):
        gaps.append("attention_mask was not detected as a used graph input — DFC compile would repeat the Laya no-mask failure.")
    if not parity.get("ok"):
        gaps.append(f"ONNX parity cosine {parity.get('cosine')} < 0.999.")

    payload = {
        "paths": {k: str(v) for k, v in paths.items()},
        "counts": {
            "label_rows": len(labels),
            "label_questions": len({e.question for e in labels}),
            "decide_rows": decide_rows,
            "decide_teacher": decide_teacher,
            "lane_rows": len(lane),
        },
        "split": split_meta,
        "recipe": recipe,
        "hf": hf_meta,
        "metrics": metrics,
        "onnx": onnx_info,
        "parity": parity,
        "calib": calib_info,
        "tradeoff": tradeoff,
        "gaps": gaps,
        "n_params": n_params,
    }
    (out / "receipt.json").write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
    write_receipt(out / "RECEIPT.md", payload)
    print("[jevh-small] wrote", out / "RECEIPT.md", flush=True)
    print("[jevh-small] ONNX", onnx_info.get("sha256"), "parity", parity.get("cosine"), flush=True)
    return 0 if parity.get("ok") and not onnx_info.get("forbidden_ops") and onnx_info.get("attention_mask_used") else 2


if __name__ == "__main__":
    raise SystemExit(main())

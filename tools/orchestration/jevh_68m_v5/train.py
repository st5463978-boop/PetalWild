#!/usr/bin/env python3
"""JEV-H-68m-v5 trainer: ettin-encoder-68m, listwise CE + hard-neg pair, static ONNX.

One command: ./run.sh
Gold is jev_choice on labels.jsonl. Teacher / decide rows are never gold.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import time
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch
from huggingface_hub import snapshot_download
from torch import nn
from torch.nn import functional as F

from data import (
    CONF_DISAGREE,
    SEED,
    attach_student_preds,
    examples_from_decide,
    examples_from_labels,
    load_paths,
    n_options_bucket,
    read_jsonl,
    stratified_question_split,
    tokenize_example,
)
from encode import SEQ_LEN, StudentTok, gold_index
from model import Ettin68mScorer, load_backbone

HERE = Path(__file__).resolve().parent
ART = HERE / "artifacts"
HF_ID = "jhu-clsp/ettin-encoder-68m"
PAIR_COEF = 0.4
PAIR_MARGIN = 0.5
KD_COEF = 0.2
UNFREEZE_LAST = 6
LR_ENCODER = 2e-5
LR_HEAD = 1e-4
WEIGHT_DECAY = 0.01
MICROBATCH = 8
EPOCHS = 2
CLIP = 1.0
CONF_THR = 0.65
OPSET = 17
FORBIDDEN_OPS = {"Loop", "If", "NonZero", "Optional", "SequenceAt", "NonMaxSuppression"}


def seed_all(seed: int = SEED) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ensure_hf(dest: Path) -> Path:
    dest.mkdir(parents=True, exist_ok=True)
    if (dest / "pytorch_model.bin").is_file():
        return dest
    snapshot_download(HF_ID, local_dir=str(dest))
    return dest


def ece_score(conf: np.ndarray, correct: np.ndarray, n_bins: int = 15) -> float:
    bins = np.linspace(0.0, 1.0, n_bins + 1)
    total = 0.0
    n = len(conf)
    if n == 0:
        return float("nan")
    for i in range(n_bins):
        lo, hi = bins[i], bins[i + 1]
        if i == 0:
            m = (conf >= lo) & (conf <= hi)
        else:
            m = (conf > lo) & (conf <= hi)
        if not np.any(m):
            continue
        total += (m.sum() / n) * abs(conf[m].mean() - correct[m].mean())
    return float(total)


def softmax_np(x: np.ndarray, t: float = 1.0) -> np.ndarray:
    z = x.astype(np.float64) / max(t, 1e-6)
    z = z - z.max()
    e = np.exp(z)
    return e / e.sum()


@torch.no_grad()
def predict_logits(model: Ettin68mScorer, examples: list[dict], device: torch.device, bs: int = 32) -> list[np.ndarray]:
    model.eval()
    out: list[np.ndarray] = [None] * len(examples)  # type: ignore[list-item]
    flat_ids, flat_mask, owners = [], [], []
    for i, ex in enumerate(examples):
        for ids, mask in zip(ex["input_ids"], ex["attention_mask"]):
            flat_ids.append(ids)
            flat_mask.append(mask)
            owners.append(i)
    logits_flat = []
    for i in range(0, len(flat_ids), bs):
        ids = torch.tensor(flat_ids[i : i + bs], dtype=torch.long, device=device)
        mask = torch.tensor(flat_mask[i : i + bs], dtype=torch.long, device=device)
        logits_flat.append(model(ids, mask).squeeze(-1).cpu())
    packed = torch.cat(logits_flat, dim=0).numpy()
    buckets: dict[int, list[float]] = defaultdict(list)
    for owner, val in zip(owners, packed.tolist()):
        buckets[owner].append(val)
    return [np.asarray(buckets[i], dtype=np.float64) for i in range(len(examples))]


def fit_temperature(logits: list[np.ndarray], golds: list[int]) -> float:
    best_t, best_nll = 1.0, 1e9
    for t in np.concatenate([np.linspace(0.3, 3.0, 28), np.array([1.0])]):
        nll = 0.0
        for logit, g in zip(logits, golds):
            p = softmax_np(logit, float(t))
            nll -= math.log(max(p[g], 1e-12))
        nll /= max(len(golds), 1)
        if nll < best_nll:
            best_nll, best_t = nll, float(t)
    return best_t


def metrics_table(examples: list[dict], logits: list[np.ndarray], temperature: float) -> dict:
    preds, golds, confs, correct = [], [], [], []
    yn_c = yn_n = mc_c = mc_n = 0
    teacher_c = teacher_n = 0
    student_c = student_n = 0
    conf_mist = 0
    teacher_conf_mist = 0
    student_conf_mist = 0
    by_n: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for ex, logit in zip(examples, logits):
        p = softmax_np(logit, temperature)
        pred = int(p.argmax())
        conf = float(p[pred])
        gold = int(ex["gold"])
        hit = int(pred == gold)
        preds.append(pred)
        golds.append(gold)
        confs.append(conf)
        correct.append(hit)
        if not hit and conf >= CONF_THR:
            conf_mist += 1
        key = "yesno" if ex["n_options"] == 2 else "multi"
        if key == "yesno":
            yn_c += hit
            yn_n += 1
        else:
            mc_c += hit
            mc_n += 1
        b = n_options_bucket(ex["n_options"])
        by_n[b][0] += hit
        by_n[b][1] += 1
        if ex.get("teacher_index") is not None:
            teacher_n += 1
            th = int(ex["teacher_index"] == gold)
            teacher_c += th
            tconf = ex.get("teacher_confidence")
            if not th and tconf is not None and float(tconf) >= CONF_THR:
                teacher_conf_mist += 1
        if ex.get("student_index") is not None:
            student_n += 1
            sh = int(ex["student_index"] == gold)
            student_c += sh
            sconf = ex.get("student_confidence")
            if not sh and sconf is not None and float(sconf) >= CONF_THR:
                student_conf_mist += 1
    confs_a = np.asarray(confs)
    corr_a = np.asarray(correct, dtype=np.float64)
    acc = float(corr_a.mean()) if len(corr_a) else float("nan")
    return {
        "n": len(examples),
        "accuracy": acc,
        "yesno_n": yn_n,
        "yesno_accuracy": (yn_c / yn_n) if yn_n else None,
        "multi_n": mc_n,
        "multi_accuracy": (mc_c / mc_n) if mc_n else None,
        "by_n_options": {k: {"n": v[1], "accuracy": v[0] / v[1] if v[1] else None} for k, v in sorted(by_n.items())},
        "confident_mistakes": conf_mist,
        "confident_mistake_rate": conf_mist / len(examples) if examples else None,
        "ece": ece_score(confs_a, corr_a),
        "teacher_n": teacher_n,
        "teacher_accuracy": (teacher_c / teacher_n) if teacher_n else None,
        "teacher_confident_mistakes": teacher_conf_mist,
        "student_overlap_n": student_n,
        "student_accuracy": (student_c / student_n) if student_n else None,
        "student_confident_mistakes": student_conf_mist,
        "temperature": temperature,
        "mean_confidence": float(confs_a.mean()) if len(confs_a) else None,
    }


def group_loss(scores: torch.Tensor, gold: int, hard_neg: int | None, weight: float) -> torch.Tensor:
    ce = F.cross_entropy(scores.unsqueeze(0), torch.tensor([gold], device=scores.device))
    pair = scores.new_zeros(())
    if hard_neg is not None and hard_neg != gold:
        pair = F.relu(PAIR_MARGIN - (scores[gold] - scores[hard_neg]))
    online = int(torch.argmax(scores.detach()).item())
    if online == gold and scores.numel() > 1:
        tmp = scores.detach().clone()
        tmp[gold] = -1e9
        online = int(torch.argmax(tmp).item())
    if online != gold:
        pair = pair + F.relu(PAIR_MARGIN - (scores[gold] - scores[online]))
    return weight * (ce + PAIR_COEF * pair)


def kd_loss(scores: torch.Tensor, teacher_p: torch.Tensor) -> torch.Tensor:
    log_p = F.log_softmax(scores, dim=-1)
    return F.kl_div(log_p, teacher_p, reduction="batchmean")


def run_epoch(
    model: Ettin68mScorer,
    gold_ex: list[dict],
    kd_ex: list[dict],
    opt: torch.optim.Optimizer,
    device: torch.device,
    rng: random.Random,
) -> float:
    model.train()
    order = list(range(len(gold_ex)))
    rng.shuffle(order)
    kd_i = 0
    kd_order = list(range(len(kd_ex)))
    rng.shuffle(kd_order)
    losses = []
    for start in range(0, len(order), MICROBATCH):
        chunk = [gold_ex[j] for j in order[start : start + MICROBATCH]]
        ids_l, mask_l = [], []
        spans = []
        golds = []
        hards = []
        weights = []
        for ex in chunk:
            k = ex["n_options"]
            perm = list(range(k))
            rng.shuffle(perm)
            for p in perm:
                ids_l.append(ex["input_ids"][p])
                mask_l.append(ex["attention_mask"][p])
            s0 = len(ids_l) - k
            spans.append((s0, len(ids_l)))
            inv = [perm.index(i) for i in range(k)]
            golds.append(perm.index(ex["gold"]))
            ti = ex.get("teacher_index")
            hards.append(perm.index(ti) if ex.get("disagree") and ti is not None else None)
            weights.append(float(ex["weight"]))
        kd_spans = []
        kd_probs = []
        if kd_ex:
            take = min(MICROBATCH // 2, len(kd_ex))
            for _ in range(take):
                ex = kd_ex[kd_order[kd_i % len(kd_order)]]
                kd_i += 1
                k = ex["n_options"]
                perm = list(range(k))
                rng.shuffle(perm)
                for p in perm:
                    ids_l.append(ex["input_ids"][p])
                    mask_l.append(ex["attention_mask"][p])
                s0 = len(ids_l) - k
                kd_spans.append((s0, len(ids_l)))
                tp = torch.tensor([ex["teacher_scores"][p] for p in perm], dtype=torch.float32)
                tp = tp / tp.sum().clamp_min(1e-8)
                kd_probs.append(tp)
        ids = torch.tensor(ids_l, dtype=torch.long, device=device)
        mask = torch.tensor(mask_l, dtype=torch.long, device=device)
        logits = model(ids, mask).squeeze(-1)
        loss = logits.new_zeros(())
        for (s, e), g, h, w in zip(spans, golds, hards, weights):
            loss = loss + group_loss(logits[s:e], g, h, w)
        loss = loss / max(len(chunk), 1)
        if kd_spans:
            kl = logits.new_zeros(())
            for (s, e), tp in zip(kd_spans, kd_probs):
                kl = kl + kd_loss(logits[s:e], tp.to(device))
            loss = loss + KD_COEF * (kl / len(kd_spans))
        opt.zero_grad(set_to_none=True)
        loss.backward()
        nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad], CLIP)
        opt.step()
        losses.append(float(loss.detach().cpu()))
    return float(np.mean(losses)) if losses else float("nan")


def export_onnx(model: Ettin68mScorer, path: Path, device: torch.device) -> None:
    model.eval()
    ids = torch.zeros(1, SEQ_LEN, dtype=torch.long, device=device)
    mask = torch.ones(1, SEQ_LEN, dtype=torch.long, device=device)
    ids[0, 0] = 50281
    path.parent.mkdir(parents=True, exist_ok=True)
    kwargs = dict(
        input_names=["input_ids", "attention_mask"],
        output_names=["logits"],
        opset_version=OPSET,
        do_constant_folding=True,
    )
    try:
        torch.onnx.export(model, (ids, mask), str(path), dynamo=False, **kwargs)
    except TypeError:
        torch.onnx.export(model, (ids, mask), str(path), **kwargs)


def inspect_onnx(path: Path) -> dict:
    import onnx

    m = onnx.load(str(path))
    onnx.checker.check_model(m)
    ops = sorted({n.op_type for n in m.graph.node})
    bad = sorted(set(ops) & FORBIDDEN_OPS)
    dyn = []
    for vi in list(m.graph.input) + list(m.graph.output):
        dims = []
        for d in vi.type.tensor_type.shape.dim:
            if d.dim_param:
                dyn.append(f"{vi.name}:{d.dim_param}")
            dims.append(d.dim_value if d.dim_value else d.dim_param or "?")
        # store
    inputs = []
    for vi in m.graph.input:
        shape = [d.dim_value or (d.dim_param or -1) for d in vi.type.tensor_type.shape.dim]
        inputs.append({"name": vi.name, "shape": shape, "elem": vi.type.tensor_type.elem_type})
    outputs = []
    for vi in m.graph.output:
        shape = [d.dim_value or (d.dim_param or -1) for d in vi.type.tensor_type.shape.dim]
        outputs.append({"name": vi.name, "shape": shape, "elem": vi.type.tensor_type.elem_type})
    consumed = {i for n in m.graph.node for i in n.input}
    return {
        "ir_version": m.ir_version,
        "opset": [op.version for op in m.opset_import],
        "ops": ops,
        "forbidden": bad,
        "dynamic_dims": dyn,
        "inputs": inputs,
        "outputs": outputs,
        "attention_mask_is_input": any(i["name"] == "attention_mask" for i in inputs),
        "input_ids_is_input": any(i["name"] == "input_ids" for i in inputs),
        "attention_mask_used": "attention_mask" in consumed,
    }


def onnx_matches_pytorch(model: Ettin68mScorer, onnx_path: Path, examples: list[dict], device: torch.device) -> float:
    import onnxruntime as ort

    sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    pt_all, ort_all = [], []
    model.eval()
    n = 0
    with torch.no_grad():
        for ex in examples:
            for ids, mask in zip(ex["input_ids"], ex["attention_mask"]):
                t_ids = torch.tensor([ids], dtype=torch.long, device=device)
                t_mask = torch.tensor([mask], dtype=torch.long, device=device)
                pt = model(t_ids, t_mask).squeeze(-1).cpu().numpy().reshape(-1)
                rt = sess.run(None, {"input_ids": np.asarray(ids, np.int64)[None], "attention_mask": np.asarray(mask, np.int64)[None]})[0].reshape(-1)
                pt_all.append(pt)
                ort_all.append(rt)
                n += 1
                if n >= 512:
                    break
            if n >= 512:
                break
    a = np.concatenate(pt_all).astype(np.float64)
    b = np.concatenate(ort_all).astype(np.float64)
    denom = (np.linalg.norm(a) * np.linalg.norm(b)) or 1.0
    return float(np.dot(a, b) / denom)


def write_calib(examples: list[dict], lane_rows: list[dict], tok: StudentTok, path_ids: Path, path_mask: Path, n: int = 256) -> int:
    pairs: list[tuple[list[int], list[int]]] = []
    for ex in examples:
        for ids, mask in zip(ex["input_ids"], ex["attention_mask"]):
            pairs.append((ids, mask))
            if len(pairs) >= n * 4:
                break
        if len(pairs) >= n * 4:
            break
    from encode import build_input

    for r in lane_rows:
        opts = [str(o) for o in (r.get("options") or [])]
        q = str(r.get("question") or "")
        if len(opts) < 2 or not q:
            continue
        _, text_a, stexts, _ = build_input(q, opts, r.get("context"))
        ids, masks, _ = tok.encode(text_a, stexts)
        for a, b in zip(ids, masks):
            pairs.append((a, b))
    rng = random.Random(SEED)
    rng.shuffle(pairs)
    # prefer a mix of short and long real masks
    pairs = pairs[: max(n, 256)]
    if len(pairs) < 256:
        raise RuntimeError(f"need >=256 calib rows, got {len(pairs)}")
    ids = np.asarray([p[0] for p in pairs[: max(n, 256)]], dtype=np.int64)
    mask = np.asarray([p[1] for p in pairs[: max(n, 256)]], dtype=np.int64)
    np.save(path_ids, ids)
    np.save(path_mask, mask)
    return int(ids.shape[0])


def latency_ms(model: Ettin68mScorer, examples: list[dict], device: torch.device, n: int = 40) -> dict:
    model.eval()
    times = []
    with torch.no_grad():
        for ex in examples[:n]:
            ids = torch.tensor(ex["input_ids"][:1], dtype=torch.long, device=device)
            mask = torch.tensor(ex["attention_mask"][:1], dtype=torch.long, device=device)
            _ = model(ids, mask)
        for ex in examples[:n]:
            k = ex["n_options"]
            t0 = time.perf_counter()
            for j in range(k):
                ids = torch.tensor([ex["input_ids"][j]], dtype=torch.long, device=device)
                mask = torch.tensor([ex["attention_mask"][j]], dtype=torch.long, device=device)
                _ = model(ids, mask)
            times.append((time.perf_counter() - t0) * 1e3)
    arr = np.asarray(times)
    per_opt = []
    with torch.no_grad():
        for ex in examples[:n]:
            t0 = time.perf_counter()
            ids = torch.tensor([ex["input_ids"][0]], dtype=torch.long, device=device)
            mask = torch.tensor([ex["attention_mask"][0]], dtype=torch.long, device=device)
            _ = model(ids, mask)
            per_opt.append((time.perf_counter() - t0) * 1e3)
    po = np.asarray(per_opt)
    return {
        "n": int(len(arr)),
        "decision_ms_mean": float(arr.mean()),
        "decision_ms_p50": float(np.median(arr)),
        "decision_ms_p90": float(np.percentile(arr, 90)),
        "option_batch1_ms_mean": float(po.mean()),
        "option_batch1_ms_p50": float(np.median(po)),
        "note": "batch=1 per option, then softmax over options (matches Hailo option loop)",
    }


def write_receipt(path: Path, payload: dict) -> None:
    m = payload["eval_calibrated"]
    t = payload["eval_teacher"]
    lines = [
        "# JEV-H-68m-v5 receipt",
        "",
        "Direct successor to the live ettin68m student (seq128, `[qtype] question` + option text).",
        "No HEF compile. No Pi deploy. No paid APIs.",
        "",
        "## Data",
        "",
        f"- labels: `{payload['paths']['labels']}` ({payload['counts']['label_rows']} rows, {payload['counts']['unique_questions']} unique questions)",
        f"- decide (soft labels, never gold): `{payload['paths']['decide']}` ({payload['counts']['decide_rows']} rows, {payload['counts']['kd_rows']} KD train rows)",
        f"- lane bank: `{payload['paths']['lane']}` ({payload['counts']['lane_rows']} rows)",
        f"- tokenizer: `{payload['paths']['tokenizer']}`",
        f"- split seed {payload['seed']}, by unique question, stratified by option count",
        f"- train questions {payload['counts']['train_q']} / rows {payload['counts']['train_rows']}",
        f"- dev questions {payload['counts']['dev_q']} / rows {payload['counts']['dev_rows']}",
        f"- eval questions {payload['counts']['eval_q']} / rows {payload['counts']['eval_rows']} ({payload['counts']['eval_q_frac']:.1%} of unique questions)",
        f"- eval yes/no (2-way) rows {m['yesno_n']}, multi-choice rows {m['multi_n']}",
        f"- confident teacher-vs-JEV disagreements in labels: {payload['counts']['conf_disagree']} (train weight 3.0)",
        "",
        "## Recipe",
        "",
        f"- backbone `{HF_ID}` (ModernBERT, hidden 512, 19 layers, local window 128, RoPE θ 160000)",
        f"- CLS GELU head (Linear 512→512 no bias + GELU + LN + Linear 512→1), live-compatible pair scoring",
        f"- seq_len {SEQ_LEN}, seed {payload['seed']}",
        f"- freeze embeddings + first {19 - payload['unfreeze_last']} layers; train last {payload['unfreeze_last']} + final LN + head",
        f"- listwise CE over options + pairwise hinge (margin {PAIR_MARGIN}, coef {PAIR_COEF}) vs teacher-wrong and online hard neg",
        f"- option order shuffled every use",
        f"- KD (KL to teacher softmax) on decide rows whose questions are outside eval/dev, coef {KD_COEF}",
        f"- AdamW encoder lr {LR_ENCODER}, head lr {LR_HEAD}, wd {WEIGHT_DECAY}, clip {CLIP}, microbatch {MICROBATCH} questions",
        f"- epochs run: {payload['epochs_run']}, train minutes: {payload['train_minutes']:.1f}",
        f"- temperature fit on dev NLL: T={m['temperature']:.4f}",
        "",
        "## Held-out eval (gold = jev_choice)",
        "",
        "| split | n | acc vs jev_choice | teacher acc | current student acc (overlap) | conf-mistakes (≥0.65) | ECE |",
        "|---|---:|---:|---:|---:|---:|---:|",
        (
            f"| eval T={m['temperature']:.3f} | {m['n']} | {m['accuracy']:.4f} | "
            f"{_fmt(m['teacher_accuracy'])} | {_fmt(m['student_accuracy'])} "
            f"(n={m['student_overlap_n']}) | {m['confident_mistakes']} | {m['ece']:.4f} |"
        ),
        (
            f"| eval T=1 | {payload['eval_raw']['n']} | {payload['eval_raw']['accuracy']:.4f} | "
            f"{_fmt(payload['eval_raw']['teacher_accuracy'])} | {_fmt(payload['eval_raw']['student_accuracy'])} "
            f"| {payload['eval_raw']['confident_mistakes']} | {payload['eval_raw']['ece']:.4f} |"
        ),
        (
            f"| eval yes/no (2-way) | {m['yesno_n']} | {_fmt(m['yesno_accuracy'])} |  |  |  |  |"
        ),
        (
            f"| eval multi-choice | {m['multi_n']} | {_fmt(m['multi_accuracy'])} |  |  |  |  |"
        ),
        (
            f"| teacher baseline (same eval rows) | {m['teacher_n']} | {_fmt(m['teacher_accuracy'])} | — | — | {m['teacher_confident_mistakes']} | — |"
        ),
        "",
        f"Dev (for T fit only): n={payload['dev']['n']} acc={payload['dev']['accuracy']:.4f} ECE={payload['dev']['ece']:.4f}.",
        "",
        "## CPU latency (batch 1)",
        "",
        json.dumps(payload["latency"], indent=2),
        "",
        "## ONNX (Hailo-10H DFC, no compile here)",
        "",
        f"- path: `{payload['onnx']['path']}`",
        f"- sha256: `{payload['onnx']['sha256']}`",
        f"- size_bytes: {payload['onnx']['size']}",
        f"- opset: {payload['onnx']['inspect']['opset']}",
        f"- inputs: {payload['onnx']['inspect']['inputs']}",
        f"- outputs: {payload['onnx']['inspect']['outputs']}",
        f"- forbidden ops: {payload['onnx']['inspect']['forbidden'] or 'none'}",
        f"- PyTorch vs ORT cosine on eval logits: {payload['onnx']['cosine']:.6f} (need ≥ 0.999)",
        "",
        f"Calibration set: `{payload['calib']['ids']}` + `{payload['calib']['mask']}` "
        f"shape {payload['calib']['shape']} (real tokenized pairs, seed {payload['seed']}).",
        "",
        "## Known gaps",
        "",
    ]
    for g in payload["gaps"]:
        lines.append(f"- {g}")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def _fmt(x) -> str:
    if x is None:
        return "—"
    return f"{x:.4f}"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--epochs", type=int, default=EPOCHS)
    ap.add_argument("--unfreeze-last", type=int, default=UNFREEZE_LAST)
    ap.add_argument("--max-train-minutes", type=float, default=float(os.environ.get("JEVH_MAX_TRAIN_MINUTES", "70")))
    ap.add_argument("--skip-train", action="store_true")
    args = ap.parse_args()
    seed_all(args.seed)
    ART.mkdir(parents=True, exist_ok=True)
    torch.set_num_threads(int(os.environ.get("JEVH_THREADS", "4")))
    device = torch.device("cpu")

    paths = load_paths()
    labels = read_jsonl(paths["labels"])
    decide = read_jsonl(paths["decide"]) if paths["decide"] else []
    lane = read_jsonl(paths["lane"]) if paths["lane"] else []
    tok = StudentTok(str(paths["tokenizer"]), SEQ_LEN)

    gold = examples_from_labels(labels)
    uniq = sorted({ex["question"] for ex in gold})
    n_opts = {}
    for ex in gold:
        n_opts.setdefault(ex["question"], ex["n_options"])
    split_map = stratified_question_split(uniq, n_opts, seed=args.seed)
    (ART / "split.json").write_text(json.dumps(split_map, indent=0), encoding="utf-8")
    eval_dev_q = {q for q, s in split_map.items() if s != "train"}
    for ex in gold:
        ex["split"] = split_map[ex["question"]]
    attach_student_preds(gold, decide)
    print("tokenizing labels...", flush=True)
    gold = [tokenize_example(tok, ex) for ex in gold]
    splits = {k: [ex for ex in gold if ex["split"] == k] for k in ("train", "dev", "eval")}
    kd = examples_from_decide(decide, eval_dev_q)
    # drop KD on gold-disagree train questions so teacher errors are not distilled
    disagree_q = {ex["question"] for ex in splits["train"] if ex.get("conf_disagree")}
    kd = [ex for ex in kd if ex["question"] not in disagree_q]
    print(f"tokenizing {len(kd)} KD rows...", flush=True)
    kd = [tokenize_example(tok, ex) for ex in kd]

    n_q = len(uniq)
    counts = {
        "label_rows": len(labels),
        "unique_questions": n_q,
        "decide_rows": len(decide),
        "lane_rows": len(lane),
        "kd_rows": len(kd),
        "train_q": sum(1 for s in split_map.values() if s == "train"),
        "dev_q": sum(1 for s in split_map.values() if s == "dev"),
        "eval_q": sum(1 for s in split_map.values() if s == "eval"),
        "train_rows": len(splits["train"]),
        "dev_rows": len(splits["dev"]),
        "eval_rows": len(splits["eval"]),
        "eval_q_frac": sum(1 for s in split_map.values() if s == "eval") / max(n_q, 1),
        "conf_disagree": sum(1 for ex in gold if ex.get("conf_disagree")),
        "yesno_eval": sum(1 for ex in splits["eval"] if ex["n_options"] == 2),
        "multi_eval": sum(1 for ex in splits["eval"] if ex["n_options"] != 2),
    }
    print(json.dumps(counts, indent=2), flush=True)
    if counts["eval_q_frac"] < 0.15:
        raise SystemExit(f"eval unique-question fraction {counts['eval_q_frac']:.3f} < 0.15")

    hf_dir = ensure_hf(ART / "hf" / "ettin-encoder-68m")
    model = Ettin68mScorer(SEQ_LEN)
    missing = load_backbone(model, hf_dir)
    print("load missing (ok if only head_out):", missing[:8], flush=True)
    model.freeze_for_cpu(args.unfreeze_last)
    model.to(device)
    n_train_p = sum(p.numel() for p in model.parameters() if p.requires_grad)
    n_all_p = sum(p.numel() for p in model.parameters())
    print(f"params {n_all_p/1e6:.1f}M, trainable {n_train_p/1e6:.1f}M", flush=True)

    enc_params, head_params = [], []
    for name, p in model.named_parameters():
        if not p.requires_grad:
            continue
        (head_params if name.startswith("head_") else enc_params).append(p)
    opt = torch.optim.AdamW(
        [
            {"params": enc_params, "lr": LR_ENCODER},
            {"params": head_params, "lr": LR_HEAD},
        ],
        weight_decay=WEIGHT_DECAY,
    )
    ckpt = ART / "jevh_68m_v5.pt"
    rng = random.Random(args.seed)
    t_train0 = time.time()
    epochs_run = 0
    best_dev = -1.0
    gaps = []
    if not args.skip_train:
        for epoch in range(1, args.epochs + 1):
            if (time.time() - t_train0) / 60.0 >= args.max_train_minutes:
                gaps.append(f"Stopped before epoch {epoch}: hit --max-train-minutes={args.max_train_minutes}")
                break
            loss = run_epoch(model, splits["train"], kd, opt, device, rng)
            epochs_run = epoch
            dev_logits = predict_logits(model, splits["dev"], device)
            dev_acc = float(np.mean([int(np.argmax(lo) == ex["gold"]) for lo, ex in zip(dev_logits, splits["dev"])]))
            print(f"epoch {epoch} loss={loss:.4f} dev_acc={dev_acc:.4f}", flush=True)
            if dev_acc >= best_dev:
                best_dev = dev_acc
                torch.save({"model": model.state_dict(), "epoch": epoch, "dev_acc": dev_acc, "seed": args.seed}, ckpt)
            if (time.time() - t_train0) / 60.0 >= args.max_train_minutes:
                gaps.append(f"Stopped after epoch {epoch}: hit --max-train-minutes={args.max_train_minutes}")
                break
        if ckpt.is_file():
            blob = torch.load(ckpt, map_location="cpu", weights_only=False)
            model.load_state_dict(blob["model"])
    else:
        if ckpt.is_file():
            blob = torch.load(ckpt, map_location="cpu", weights_only=False)
            model.load_state_dict(blob["model"])
        epochs_run = 0
        gaps.append("Training skipped (--skip-train).")
    train_minutes = (time.time() - t_train0) / 60.0

    print("eval...", flush=True)
    dev_logits = predict_logits(model, splits["dev"], device)
    T = fit_temperature(dev_logits, [ex["gold"] for ex in splits["dev"]])
    eval_logits = predict_logits(model, splits["eval"], device)
    eval_cal = metrics_table(splits["eval"], eval_logits, T)
    eval_raw = metrics_table(splits["eval"], eval_logits, 1.0)
    dev_m = metrics_table(splits["dev"], dev_logits, T)
    print("eval calibrated", json.dumps(eval_cal, indent=2), flush=True)

    lat = latency_ms(model, splits["eval"], device)
    print("latency", lat, flush=True)

    onnx_path = ART / "jevh_68m_v5_seq128.onnx"
    print("export onnx...", flush=True)
    export_onnx(model, onnx_path, device)
    inspect = inspect_onnx(onnx_path)
    if inspect["forbidden"]:
        gaps.append(f"ONNX still contains forbidden ops: {inspect['forbidden']}")
    if inspect["dynamic_dims"]:
        gaps.append(f"ONNX has dynamic dims: {inspect['dynamic_dims']}")
    cos = onnx_matches_pytorch(model, onnx_path, splits["eval"], device)
    print(f"onnx cosine={cos:.6f} inspect={inspect}", flush=True)
    if cos < 0.999:
        gaps.append(f"ONNX cosine {cos:.6f} < 0.999")

    calib_ids = ART / "calib_input_ids.npy"
    calib_mask = ART / "calib_attention_mask.npy"
    n_cal = write_calib(splits["train"] + splits["dev"], lane, tok, calib_ids, calib_mask, n=256)

    decide_is_sample = paths["decide"] is not None and "sample" in paths["decide"].name
    if decide_is_sample:
        gaps.append("Full decide_questions_dedup.jsonl was not found; KD used the bundled sample only.")
    gaps.append("Labels are biased to teacher-unsure or teacher-JEV disagreement cases.")
    gaps.append("No HEF compile (no DFC). No deploy. Current-student comparison only on decide overlap rows.")
    if epochs_run < args.epochs:
        gaps.append(f"Requested {args.epochs} epochs, ran {epochs_run}.")
    gaps.append("Encoder embeddings and early layers frozen for the CPU budget; a full unfreeze would need more RAM/time.")

    payload = {
        "seed": args.seed,
        "unfreeze_last": args.unfreeze_last,
        "epochs_run": epochs_run,
        "train_minutes": train_minutes,
        "paths": {k: (str(v) if v else None) for k, v in paths.items()},
        "counts": counts,
        "eval_calibrated": eval_cal,
        "eval_raw": eval_raw,
        "eval_teacher": {"accuracy": eval_cal["teacher_accuracy"], "n": eval_cal["teacher_n"]},
        "dev": dev_m,
        "latency": lat,
        "onnx": {
            "path": str(onnx_path),
            "sha256": sha256_file(onnx_path),
            "size": onnx_path.stat().st_size,
            "inspect": inspect,
            "cosine": cos,
        },
        "calib": {
            "ids": str(calib_ids),
            "mask": str(calib_mask),
            "shape": [n_cal, SEQ_LEN],
        },
        "gaps": gaps,
        "params_m": n_all_p / 1e6,
        "trainable_m": n_train_p / 1e6,
    }
    (ART / "metrics.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    write_receipt(HERE / "RECEIPT.md", payload)
    print("wrote", HERE / "RECEIPT.md", flush=True)


if __name__ == "__main__":
    main()

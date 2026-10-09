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
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import torch
from huggingface_hub import snapshot_download
from torch import nn
from torch.nn import functional as F

from data import (
    CONF_DISAGREE,
    SEED,
    attach_large_to_gold,
    attach_student_preds,
    examples_from_decide,
    examples_from_labels,
    load_large_index,
    load_paths,
    n_options_bucket,
    read_jsonl,
    stratified_question_split,
    template_grouped_split,
    template_key,
    tokenize_example,
    truncation_report,
)
from encode import SEQ_LEN, StudentTok, gold_index
from model import Ettin68mScorer, load_backbone

HERE = Path(__file__).resolve().parent
ART = HERE / "artifacts"
HF_ID = "jhu-clsp/ettin-encoder-68m"
PAIR_COEF = 0.4
PAIR_MARGIN = 0.5
KD_COEF = 0.25
UNFREEZE_LAST = -1
LR_ENCODER = 2e-5
LR_HEAD = 8e-5
LR_EMBED = 5e-6
LAYER_DECAY = 0.9
WEIGHT_DECAY = 0.01
MICROBATCH = 8
GRAD_ACCUM = 2
EPOCHS = 6
PATIENCE = 2
CLIP = 1.0
CONF_THR = 0.65
OPSET = 17
FORBIDDEN_OPS = {"Loop", "If", "NonZero", "Optional", "SequenceAt", "NonMaxSuppression"}
ROUND1 = {
    "accuracy": 0.7640625,
    "yesno_accuracy": 0.8628571428571429,
    "multi_accuracy": 0.7268817204301076,
    "teacher_accuracy": 0.46875,
    "student_accuracy": 0.6578947368421053,
    "overlap_model_accuracy": 0.7280701754385965,
    "confident_mistakes": 18,
    "ece": 0.03163120673868383,
    "temperature": 1.3,
    "n": 640,
    "student_overlap_n": 114,
}
ROUND2A = {
    "n": 640,
    "accuracy": 0.7625,
    "yesno_accuracy": 0.8628571428571429,
    "multi_accuracy": 0.7247311827956989,
    "teacher_accuracy": 0.46875,
    "student_accuracy": 0.6578947368421053,
    "overlap_model_accuracy": 0.7105263157894737,
    "confident_mistakes": 25,
    "ece": 0.040330729549041835,
    "student_overlap_n": 114,
    "template_n": 809,
    "template_accuracy": 0.9023485784919654,
    "template_yesno": 0.8434343434343434,
    "template_multi": 0.9214402618657938,
}


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
    overlap_model_c = 0
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
            overlap_model_c += hit
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
        "overlap_model_accuracy": (overlap_model_c / student_n) if student_n else None,
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
        gold_kd_spans: list[tuple[int, int]] = []
        gold_kd_probs: list[list[float]] = []
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
            ti = ex.get("teacher_index")
            hards.append(perm.index(ti) if ex.get("disagree") and ti is not None else None)
            weights.append(float(ex["weight"]))
            bsc = ex.get("blend_scores") or ex.get("large_scores")
            if bsc and ex.get("large_index") == ex["gold"]:
                gold_kd_spans.append((s0, s0 + k))
                gold_kd_probs.append([float(bsc[p]) for p in perm])
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
        if gold_kd_spans:
            gkl = logits.new_zeros(())
            for (s, e), raw_p in zip(gold_kd_spans, gold_kd_probs):
                tp = torch.tensor(raw_p, dtype=torch.float32, device=device)
                tp = tp / tp.sum().clamp_min(1e-8)
                gkl = gkl + kd_loss(logits[s:e], tp)
            loss = loss + 0.15 * (gkl / len(gold_kd_spans))
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
    elem_names = {1: "float32", 6: "int32", 7: "int64"}
    for item in inputs + outputs:
        item["dtype"] = elem_names.get(item["elem"], str(item["elem"]))
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
        ids, masks, _, _ = tok.encode(text_a, stexts)
        for a, b in zip(ids, masks):
            pairs.append((a, b))
    rng = random.Random(SEED)
    rng.shuffle(pairs)
    uniq: list[tuple[list[int], list[int]]] = []
    seen: set[tuple[int, ...]] = set()
    for ids_row, mask_row in pairs:
        key = tuple(ids_row)
        if key in seen:
            continue
        seen.add(key)
        uniq.append((ids_row, mask_row))
        if len(uniq) >= max(n, 256):
            break
    if len(uniq) < 256:
        raise RuntimeError(f"need >=256 unique calib rows, got {len(uniq)}")
    ids = np.asarray([p[0] for p in uniq], dtype=np.int64)
    mask = np.asarray([p[1] for p in uniq], dtype=np.int64)
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


def _row(name: str, m: dict) -> str:
    return (
        f"| {name} | {m['n']} | {_fmt(m['accuracy'])} | {_fmt(m.get('yesno_accuracy'))} | "
        f"{_fmt(m.get('multi_accuracy'))} | {_fmt(m.get('teacher_accuracy'))} | "
        f"live {_fmt(m.get('student_accuracy'))} / v5 {_fmt(m.get('overlap_model_accuracy'))} "
        f"(n={m.get('student_overlap_n')}) | {m.get('confident_mistakes')} | {_fmt(m.get('ece'))} |"
    )


def write_receipt(path: Path, payload: dict) -> None:
    t_eval = payload["template_eval"]
    q_eval = payload["question_eval"]
    r1 = payload["round1"]
    lines = [
        "# JEV-H-68m-v5 receipt (round 2)",
        "",
        "Direct successor to the live ettin68m student (seq128, `[qtype] question` + option text).",
        "No HEF compile. No Pi deploy. No paid APIs. Trained on the template-grouped split (honest).",
        "",
        "## Data",
        "",
        f"- labels: `{payload['paths']['labels']}` ({payload['counts']['label_rows']} rows, {payload['counts']['unique_questions']} unique questions, {payload['counts']['n_templates']} templates)",
        f"- decide (soft labels, never gold): `{payload['paths']['decide']}` ({payload['counts']['decide_rows']} rows, {payload['counts']['kd_rows']} KD train rows)",
        f"- JEV-H-large soft labels: `{payload['paths'].get('large_soft')}` ({payload['counts'].get('large_rows', 0)} rows; from `cursor/jevh-variant-large-819a`, not merged)",
        f"- KD blend: large 0.65/Qwen 0.35 on argmax-agree, large 0.80/Qwen 0.20 on disagree. `jev_choice` stays gold.",
        f"- lane bank: `{payload['paths']['lane']}` ({payload['counts']['lane_rows']} rows)",
        f"- tokenizer: `{payload['paths']['tokenizer']}`",
        f"- split seed {payload['seed']}",
        f"- **template-grouped** (train): questions {payload['counts']['train_q']} / rows {payload['counts']['train_rows']}; dev {payload['counts']['dev_q']}/{payload['counts']['dev_rows']}; eval {payload['counts']['eval_q']}/{payload['counts']['eval_rows']} ({payload['counts']['eval_q_frac']:.1%} of unique questions, {payload['counts']['eval_templates']} templates; largest train family {payload['counts'].get('max_train_template_q')} q, largest eval family {payload['counts'].get('max_eval_template_q')} q)",
        f"- unique-question split (round-1 protocol, eval-only): {payload['counts']['qsplit_eval_q']} questions / {payload['counts']['qsplit_eval_rows']} rows; leaked into template-train: {payload['counts']['qsplit_eval_leaked']}",
        f"- eval 2-way (template) {t_eval['yesno_n']}, multi {t_eval['multi_n']}",
        f"- confident teacher-vs-JEV disagreements: {payload['counts']['conf_disagree']} (train weight 3.0)",
        "",
        "## Truncation (seq128)",
        "",
        json.dumps(payload["truncation"], indent=2),
        "",
        "Smarter truncation (`keep_option`): if a pair would exceed 128, keep option tokens and trim question/context. Labels never overflowed 128; decide had a handful of 2-way overflows.",
        "",
        "## Recipe (round 2 vs round 1)",
        "",
        f"- backbone `{HF_ID}`, CLS GELU head, seq_len {SEQ_LEN}, seed {payload['seed']}",
        "- **full encoder unfrozen** including embeddings (round 1: last 6 layers + head)",
        f"- layer-wise LR decay {LAYER_DECAY}: last layer {LR_ENCODER}, embeddings {LR_EMBED}, head {LR_HEAD}",
        f"- init from round-1 checkpoint: {payload.get('init_ckpt')}",
        f"- listwise CE + pairwise hinge (margin {PAIR_MARGIN}, coef {PAIR_COEF}); option shuffle",
        f"- KD from blended large+Qwen on decide rows outside template eval/dev, coef {KD_COEF}; extra KL on gold rows where large agrees with jev_choice",
        f"- AdamW wd {WEIGHT_DECAY}, clip {CLIP}, microbatch {MICROBATCH}, grad checkpointing on",
        f"- early stopping patience {PATIENCE} on unique-q-dev acc (min 3 epochs); epochs run {payload['epochs_run']} / requested {payload.get('epochs_requested')}; train minutes {payload['train_minutes']:.1f}",
        f"- temperature: template-dev T={t_eval['temperature']:.4f}; unique-q-dev T={q_eval['temperature']:.4f}",
        f"- trainable {payload['trainable_m']:.1f}M / {payload['params_m']:.1f}M",
        "",
        "## Held-out eval (gold = jev_choice)",
        "",
        "| split | n | acc | 2-way | multi | teacher | live student / v5 overlap | conf-mist ≥0.65 | ECE |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
        _row(f"template eval T={t_eval['temperature']:.2f} (honest)", t_eval),
        _row(f"unique-q eval T={q_eval['temperature']:.2f}, same rows as round 1", q_eval),
        _row("unique-q eval T=1.3 (round-1 temperature)", payload.get("question_eval_t13") or q_eval),
        _row("unique-q eval, rows not in template-train", payload.get("question_eval_clean") or {"n": 0, "accuracy": None}),
        (
            f"| round 1 unique-q T=1.3 (frozen) | {r1['n']} | {r1['accuracy']:.4f} | "
            f"{r1['yesno_accuracy']:.4f} | {r1['multi_accuracy']:.4f} | {r1['teacher_accuracy']:.4f} | "
            f"live {r1['student_accuracy']:.4f} / v5 {r1['overlap_model_accuracy']:.4f} "
            f"(n={r1['student_overlap_n']}) | {r1['confident_mistakes']} | {r1['ece']:.4f} |"
        ),
        (
            f"| round 2a unique-q (template-dev early stop) | {ROUND2A['n']} | {ROUND2A['accuracy']:.4f} | "
            f"{ROUND2A['yesno_accuracy']:.4f} | {ROUND2A['multi_accuracy']:.4f} | {ROUND2A['teacher_accuracy']:.4f} | "
            f"live {ROUND2A['student_accuracy']:.4f} / v5 {ROUND2A['overlap_model_accuracy']:.4f} "
            f"(n={ROUND2A['student_overlap_n']}) | {ROUND2A['confident_mistakes']} | {ROUND2A['ece']:.4f} |"
        ),
        _row("template-dev (T fit)", payload["dev"]),
        _row("unique-q-dev (early stop / T fit)", payload.get("uniqueq_dev") or payload["dev"]),
        "",
        f"Round-2 minus round-1 unique-q acc: {_fmt(q_eval['accuracy'] - r1['accuracy'])} (same 640 rows; {payload['counts']['qsplit_eval_leaked']} of those questions were in template-train).",
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
        f"- attention_mask used: {payload['onnx']['inspect'].get('attention_mask_used')}",
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
    if isinstance(x, float):
        return f"{x:.4f}"
    return str(x)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--epochs", type=int, default=EPOCHS)
    ap.add_argument("--unfreeze-last", type=int, default=UNFREEZE_LAST)
    ap.add_argument("--max-train-minutes", type=float, default=float(os.environ.get("JEVH_MAX_TRAIN_MINUTES", "90")))
    ap.add_argument("--patience", type=int, default=PATIENCE)
    ap.add_argument("--init-ckpt", type=str, default=str(ART / "jevh_68m_v5.pt"))
    ap.add_argument("--no-init-ckpt", action="store_true")
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
    large_rows = read_jsonl(paths["large_soft"]) if paths.get("large_soft") else []
    large_index = load_large_index(large_rows)
    tok = StudentTok(str(paths["tokenizer"]), SEQ_LEN)

    gold = examples_from_labels(labels)
    attach_student_preds(gold, decide)
    attach_large_to_gold(gold, large_index)
    uniq = sorted({ex["question"] for ex in gold})
    n_opts = {}
    templates = {}
    for ex in gold:
        n_opts.setdefault(ex["question"], ex["n_options"])
        templates.setdefault(ex["question"], ex["template"])
    q_split = stratified_question_split(uniq, n_opts, seed=args.seed)
    t_split = template_grouped_split(uniq, n_opts, templates, seed=args.seed)
    (ART / "split.json").write_text(json.dumps({"question": q_split, "template": t_split}, indent=0), encoding="utf-8")
    (ART / "split_template.json").write_text(json.dumps(t_split, indent=0), encoding="utf-8")

    leaked = sum(1 for q, s in q_split.items() if s == "eval" and t_split.get(q) == "train")
    for ex in gold:
        ex["split"] = t_split[ex["question"]]
        ex["q_split"] = q_split[ex["question"]]
    print("tokenizing labels...", flush=True)
    gold = [tokenize_example(tok, ex) for ex in gold]
    trunc = truncation_report(gold)
    print("truncation", json.dumps(trunc), flush=True)
    splits = {k: [ex for ex in gold if ex["split"] == k] for k in ("train", "dev", "eval")}
    q_eval_ex = [ex for ex in gold if ex["q_split"] == "eval"]
    q_dev_ex = [ex for ex in gold if ex["q_split"] == "dev"]
    q_eval_clean = [ex for ex in q_eval_ex if ex["split"] != "train"]
    eval_dev_q = {q for q, s in t_split.items() if s != "train"}
    eval_dev_templates = {templates[q] for q in eval_dev_q}
    kd = examples_from_decide(decide, eval_dev_q, large_index, eval_dev_templates)
    disagree_q = {ex["question"] for ex in splits["train"] if ex.get("conf_disagree")}
    kd = [ex for ex in kd if ex["question"] not in disagree_q]
    print(f"tokenizing {len(kd)} KD rows...", flush=True)
    kd = [tokenize_example(tok, ex) for ex in kd]
    trunc_kd = truncation_report(kd)

    n_q = len(uniq)
    n_tmpl = len(set(templates.values()))
    counts = {
        "label_rows": len(labels),
        "unique_questions": n_q,
        "n_templates": n_tmpl,
        "decide_rows": len(decide),
        "large_rows": len(large_rows),
        "lane_rows": len(lane),
        "kd_rows": len(kd),
        "train_q": sum(1 for s in t_split.values() if s == "train"),
        "dev_q": sum(1 for s in t_split.values() if s == "dev"),
        "eval_q": sum(1 for s in t_split.values() if s == "eval"),
        "eval_templates": len({templates[q] for q, s in t_split.items() if s == "eval"}),
        "train_rows": len(splits["train"]),
        "dev_rows": len(splits["dev"]),
        "eval_rows": len(splits["eval"]),
        "eval_q_frac": sum(1 for s in t_split.values() if s == "eval") / max(n_q, 1),
        "qsplit_eval_q": sum(1 for s in q_split.values() if s == "eval"),
        "qsplit_eval_rows": len(q_eval_ex),
        "qsplit_eval_leaked": leaked,
        "qsplit_eval_clean_rows": len(q_eval_clean),
        "qsplit_dev_rows": len(q_dev_ex),
        "conf_disagree": sum(1 for ex in gold if ex.get("conf_disagree")),
        "yesno_eval": sum(1 for ex in splits["eval"] if ex["n_options"] == 2),
        "multi_eval": sum(1 for ex in splits["eval"] if ex["n_options"] != 2),
        "kd_blend": dict(Counter(ex.get("blend") for ex in kd)),
        "max_train_template_q": max(Counter(templates[q] for q, s in t_split.items() if s == "train").values(), default=0),
        "max_eval_template_q": max(Counter(templates[q] for q, s in t_split.items() if s == "eval").values(), default=0),
    }
    print(json.dumps(counts, indent=2), flush=True)
    if counts["eval_q_frac"] < 0.15:
        raise SystemExit(f"template eval unique-question fraction {counts['eval_q_frac']:.3f} < 0.15")
    # no template in two splits
    tmpl_sets = {"train": set(), "dev": set(), "eval": set()}
    for q, s in t_split.items():
        tmpl_sets[s].add(templates[q])
    leak_t = (tmpl_sets["train"] & tmpl_sets["eval"]) | (tmpl_sets["dev"] & tmpl_sets["eval"]) | (tmpl_sets["train"] & tmpl_sets["dev"])
    if leak_t:
        raise SystemExit(f"template leakage across splits: {len(leak_t)}")

    hf_dir = ensure_hf(ART / "hf" / "ettin-encoder-68m")
    model = Ettin68mScorer(SEQ_LEN)
    missing = load_backbone(model, hf_dir)
    print("load missing (ok if only head_out):", missing[:8], flush=True)
    init_ckpt = None
    if not args.no_init_ckpt and args.init_ckpt and Path(args.init_ckpt).is_file():
        blob0 = torch.load(args.init_ckpt, map_location="cpu", weights_only=False)
        model.load_state_dict(blob0["model"], strict=False)
        init_ckpt = args.init_ckpt
        print(f"init from {init_ckpt} (round-1)", flush=True)
    model.freeze_for_cpu(args.unfreeze_last)
    model.grad_ckpt = True
    model.to(device)
    n_train_p = sum(p.numel() for p in model.parameters() if p.requires_grad)
    n_all_p = sum(p.numel() for p in model.parameters())
    print(f"params {n_all_p/1e6:.1f}M, trainable {n_train_p/1e6:.1f}M", flush=True)

    opt = torch.optim.AdamW(
        model.layerwise_param_groups(LR_ENCODER, LR_HEAD, LR_EMBED, LAYER_DECAY),
        weight_decay=WEIGHT_DECAY,
    )
    ckpt = ART / "jevh_68m_v5_r2.pt"
    rng = random.Random(args.seed)
    t_train0 = time.time()
    epochs_run = 0
    best_dev = -1.0
    stale = 0
    epoch_log = []
    gaps = []
    if not args.skip_train:
        for epoch in range(1, args.epochs + 1):
            if (time.time() - t_train0) / 60.0 >= args.max_train_minutes:
                gaps.append(f"Stopped before epoch {epoch}: hit --max-train-minutes={args.max_train_minutes}")
                break
            loss = run_epoch(model, splits["train"], kd, opt, device, rng)
            epochs_run = epoch
            t_dev_logits = predict_logits(model, splits["dev"], device)
            t_dev_acc = float(np.mean([int(np.argmax(lo) == ex["gold"]) for lo, ex in zip(t_dev_logits, splits["dev"])]))
            q_dev_logits = predict_logits(model, q_dev_ex, device)
            q_dev_acc = float(np.mean([int(np.argmax(lo) == ex["gold"]) for lo, ex in zip(q_dev_logits, q_dev_ex)]))
            rec = {
                "epoch": epoch,
                "loss": loss,
                "template_dev_acc": t_dev_acc,
                "uniqueq_dev_acc": q_dev_acc,
                "minutes": (time.time() - t_train0) / 60.0,
            }
            epoch_log.append(rec)
            print(
                f"epoch {epoch} loss={loss:.4f} template_dev_acc={t_dev_acc:.4f} uniqueq_dev_acc={q_dev_acc:.4f}",
                flush=True,
            )
            # Select on unique-q-dev (harder, comparable to round-1). Template-dev
            # saturates on one-off templates and stopped round-2a before modulo moved.
            torch.save(
                {
                    "model": model.state_dict(),
                    "epoch": epoch,
                    "template_dev_acc": t_dev_acc,
                    "uniqueq_dev_acc": q_dev_acc,
                    "seed": args.seed,
                    "train_minutes": rec["minutes"],
                },
                ART / f"jevh_68m_v5_r2_ep{epoch}.pt",
            )
            if q_dev_acc > best_dev + 1e-4:
                best_dev = q_dev_acc
                stale = 0
                torch.save(
                    {
                        "model": model.state_dict(),
                        "epoch": epoch,
                        "dev_acc": q_dev_acc,
                        "template_dev_acc": t_dev_acc,
                        "uniqueq_dev_acc": q_dev_acc,
                        "seed": args.seed,
                        "train_minutes": rec["minutes"],
                    },
                    ckpt,
                )
            else:
                stale += 1
                # do not stop before epoch 3: template-dev was already 0.96 at epoch 1
                if epoch >= 3 and stale >= args.patience:
                    gaps.append(
                        f"Early stop at epoch {epoch}: unique-q-dev acc {q_dev_acc:.4f} vs best {best_dev:.4f}"
                    )
                    break
            if (time.time() - t_train0) / 60.0 >= args.max_train_minutes:
                gaps.append(f"Stopped after epoch {epoch}: hit --max-train-minutes={args.max_train_minutes}")
                break
        if ckpt.is_file():
            blob = torch.load(ckpt, map_location="cpu", weights_only=False)
            model.load_state_dict(blob["model"])
        train_minutes = (time.time() - t_train0) / 60.0
    else:
        load_path = ckpt if ckpt.is_file() else Path(args.init_ckpt)
        if load_path.is_file():
            blob = torch.load(load_path, map_location="cpu", weights_only=False)
            model.load_state_dict(blob["model"])
            epochs_run = int(blob.get("epoch") or 0)
            train_minutes = float(blob.get("train_minutes") or 0.0)
        else:
            epochs_run = 0
            train_minutes = 0.0
            gaps.append("Training skipped and no checkpoint was found.")

    model.grad_ckpt = False
    print("eval...", flush=True)
    t_dev_logits = predict_logits(model, splits["dev"], device)
    q_dev_logits = predict_logits(model, q_dev_ex, device)
    T_t = fit_temperature(t_dev_logits, [ex["gold"] for ex in splits["dev"]])
    T_q = fit_temperature(q_dev_logits, [ex["gold"] for ex in q_dev_ex])
    t_logits = predict_logits(model, splits["eval"], device)
    q_logits = predict_logits(model, q_eval_ex, device)
    t_eval = metrics_table(splits["eval"], t_logits, T_t)
    q_eval = metrics_table(q_eval_ex, q_logits, T_q)
    q_eval_t13 = metrics_table(q_eval_ex, q_logits, 1.3)
    q_clean = metrics_table(q_eval_clean, predict_logits(model, q_eval_clean, device), T_q) if q_eval_clean else {"n": 0}
    eval_raw = metrics_table(splits["eval"], t_logits, 1.0)
    dev_m = metrics_table(splits["dev"], t_dev_logits, T_t)
    q_dev_m = metrics_table(q_dev_ex, q_dev_logits, T_q)
    print("template eval", json.dumps(t_eval, indent=2), flush=True)
    print("question eval (r1 rows)", json.dumps(q_eval, indent=2), flush=True)
    print("question eval clean (not in template-train)", json.dumps(q_clean, indent=2), flush=True)

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

    if paths.get("decide") is not None and "sample" in paths["decide"].name:
        gaps.append("Full decide_questions_dedup.jsonl was not found; KD used the bundled sample only.")
    if not large_rows:
        gaps.append("JEV-H-large soft file missing; KD used Qwen3 scores only.")
    gaps.append("Labels are biased to teacher-unsure or teacher-JEV disagreement cases.")
    gaps.append("No HEF compile (no DFC). No deploy. Current-student comparison only on decide overlap rows.")
    if epochs_run < args.epochs:
        gaps.append(f"Requested {args.epochs} epochs, ran {epochs_run}.")
    gaps.append("Unique-question eval reuses round-1 rows; some of those questions can sit in template-train (see qsplit_eval_leaked). Template eval is the honest number.")

    payload = {
        "seed": args.seed,
        "unfreeze_last": args.unfreeze_last,
        "epochs_run": epochs_run,
        "epochs_requested": args.epochs,
        "train_minutes": train_minutes,
        "init_ckpt": init_ckpt,
        "paths": {k: (str(v) if v else None) for k, v in paths.items()},
        "counts": counts,
        "truncation": {"labels": trunc, "kd": trunc_kd},
        "template_eval": t_eval,
        "question_eval": q_eval,
        "question_eval_t13": q_eval_t13,
        "question_eval_clean": q_clean,
        "eval_calibrated": t_eval,
        "eval_raw": eval_raw,
        "eval_teacher": {"accuracy": t_eval["teacher_accuracy"], "n": t_eval["teacher_n"]},
        "dev": dev_m,
        "uniqueq_dev": q_dev_m,
        "epoch_log": epoch_log,
        "round1": ROUND1,
        "round2a": ROUND2A,
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

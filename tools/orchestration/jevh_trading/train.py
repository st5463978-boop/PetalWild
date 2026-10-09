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

from .config import (
    CONFIDENT_MISTAKE_P,
    DISTILL_EPOCHS,
    DISTILL_PATIENCE,
    DISTILL_SIZE_AUTO_N,
    HOLD_LABELS,
    LATENCY_N,
    LATENCY_WARMUP,
    LAYER_DECAY,
    LR_EMBED,
    LR_ENCODER,
    LR_HEAD,
    MICROBATCH,
    OPSET,
    PAIR_COEF,
    PAIR_MARGIN,
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
from .ingest import NEED, ingest, write_split
from .metrics import agreement_breakdown, cpu_latency_ms, softmax
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


def pack_rows(rows: list[dict], tok_path: str) -> list[dict]:
    packed = []
    for r in rows:
        enc = encode_menu(r["text_a"], r["option_texts"], tok_path)
        packed.append(
            {
                "input_ids": enc["input_ids"],
                "attention_mask": enc["attention_mask"],
                "gold": int(r["gold"]),
                "probs": [float(x) for x in r["probs"]],
                "labels": list(r["option_texts"]),
                "n_options": int(r["n_options"]),
                "varied": bool(r["varied"]),
                "bee": r.get("bee"),
                "bee_style": r.get("bee_style"),
                "gold_label": r["gold_label"],
                "truncation": enc["truncation"],
                "mode": enc["mode"],
                "row": r,
            }
        )
    return packed


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
        log_p = F.log_softmax(scores, dim=-1)
        loss = loss + SOFT_KL_COEF * F.kl_div(log_p, teacher_p, reduction="batchmean")
    return loss


def run_epoch(model: EttinScorer, packed: list[dict], opt: torch.optim.Optimizer, rng: random.Random) -> float:
    model.train()
    order = list(range(len(packed)))
    rng.shuffle(order)
    losses = []
    for start in range(0, len(order), MICROBATCH):
        chunk = [packed[j] for j in order[start : start + MICROBATCH]]
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
def predict_packed(model: EttinScorer, packed: list[dict], temperature: float = 1.0) -> tuple[list[int], list[list[float]], list[np.ndarray]]:
    model.eval()
    pred, probs, logits_out = [], [], []
    for p in packed:
        ids = torch.from_numpy(p["input_ids"])
        mask = torch.from_numpy(p["attention_mask"])
        logits = model(ids, mask).squeeze(-1).cpu().numpy().astype(np.float64)
        pr = softmax(logits / max(temperature, 1e-6))
        pred.append(int(pr.argmax()))
        probs.append([float(x) for x in pr])
        logits_out.append(logits)
    return pred, probs, logits_out


def fit_temperature(logits: list[np.ndarray], golds: list[int]) -> float:
    best_t, best_nll = 1.0, 1e9
    for t in np.concatenate([np.linspace(0.3, 3.0, 28), np.array([1.0])]):
        nll = 0.0
        for logit, g in zip(logits, golds):
            p = softmax(logit / max(float(t), 1e-6))
            nll -= math.log(max(float(p[g]), 1e-12))
        nll /= max(len(golds), 1)
        if nll < best_nll:
            best_nll, best_t = nll, float(t)
    return best_t


def eval_packed(name: str, model: EttinScorer, packed: list[dict], temperature: float) -> dict:
    if not packed:
        print(f"[jevh-trading] {name}: n=0", flush=True)
        return {"n": 0, "accuracy": None}
    pred, probs, _ = predict_packed(model, packed, temperature)
    gold = [p["gold"] for p in packed]
    labs = [p["labels"] for p in packed]
    varied = [p["varied"] for p in packed]
    met = agreement_breakdown(pred, gold, probs, labs, varied=varied)
    met["temperature"] = temperature
    met["split"] = name
    # majority-gold-label baseline (always pick HOLD_WINNER if offered, else first HOLD_*)
    hold_pred = []
    for p in packed:
        labs_p = p["labels"]
        hold = [j for j, lab in enumerate(labs_p) if lab in HOLD_LABELS]
        hold_pred.append(hold[0] if hold else 0)
    met["always_hold_acc"] = float(np.mean([a == b for a, b in zip(hold_pred, gold)]))
    print(
        f"[jevh-trading] {name}: n={met['n']} jev_agree={met.get('accuracy')} "
        f"varied={met.get('varied_n')}/{met.get('varied_accuracy')} "
        f"conf_mist={met.get('confident_mistakes')} ece={met.get('ece')} "
        f"hold_copy={met.get('always_hold_acc')}",
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


def write_receipt(path: Path, payload: dict) -> None:
    ev = payload["metrics"]["eval"]
    dev = payload["metrics"]["dev"]
    st = payload["ingest"]
    rec = payload["recipe"]
    onnx = payload["onnx"]
    lat = payload["metrics"]["cpu_latency_batch1"]
    need = st.get("needed") or NEED
    lines = [
        "# JEV-H-trading receipt (round 2: Jev distill)",
        "",
        "> **Not financial advice.** Offline research only. No live or paper order routing. "
        "No exchange or broker calls. Gold is typesafe/jev-1.13's own choice, not a traded P&L.",
        "",
        f"Seed `{payload['seed']}`. Wall {payload['wall_s']}s. Size **{rec['size']}**. "
        f"Backbone loaded: {rec.get('backbone_loaded')}. Smoke={payload['smoke']}.",
        "",
        "## Honest data verdict",
        "",
        f"- Unique state+menu rows: **{st['unique_state_menu']}** (raw {st['raw_rows']})",
        f"- Multi-option usable for train/dev/eval: **{st['multi_option_trainish']}** "
        f"(train {st['train']} / dev {st['dev']} / eval {st['eval']}, purge {st['purge']} @ {st['purge_ms_used']} ms)",
        f"- Single-option (format-check only, dropped from train): **{st['single_option']}**",
        f"- Genuinely varied multi-option: **{st['varied_multi']}** "
        f"(need ~{need['multi_option_unique']}; shortfall {st['shortfall']['varied_multi']})",
        f"- Non-hold gold: **{st['non_hold_gold']}** "
        f"(need ~{need['non_hold_gold']}; shortfall {st['shortfall']['non_hold_gold']})",
        f"- Calendar days: **{st.get('calendar_days', 0)}** (need {need['calendar_days']})",
        f"- Gold distribution: `{json.dumps(st['gold_distribution'])}`",
        f"- Enough to claim a cost-free Jev stand-in: **{st['enough_to_claim']}**",
        "",
        need["note"],
        "",
        "## Agreement with Jev (gold = choice)",
        "",
        "| split | n | agree | varied n/acc | collapsed n/acc | conf-mist ≥0.65 | ECE | always HOLD/RIDE |",
        "|---|---:|---:|---|---|---:|---:|---:|",
    ]

    def row(name: str, m: dict) -> str:
        if not m or not m.get("n"):
            return f"| {name} | 0 |  |  |  |  |  |  |"
        return (
            f"| {name} | {m.get('n')} | {m.get('accuracy'):.4f} | "
            f"{m.get('varied_n')}/{m.get('varied_accuracy')} | "
            f"{m.get('collapsed_n')}/{m.get('collapsed_accuracy')} | "
            f"{m.get('confident_mistakes')} | {m.get('ece'):.4f} | "
            f"{m.get('always_hold_acc'):.4f} |"
        )

    lines += [
        row("time-split eval", ev),
        row("time-split dev (T fit)", dev),
        row("train", payload["metrics"].get("train") or {"n": 0}),
        "",
        "### Per menu size (eval)",
        "",
        "```json",
        json.dumps((ev or {}).get("by_menu_size"), indent=2),
        "```",
        "",
        "### Per action (eval, gold label)",
        "",
        "```json",
        json.dumps((ev or {}).get("by_action"), indent=2),
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
    pkg = Path(__file__).resolve().parent / "RECEIPT.md"
    pkg.write_text(path.read_text())


def gaps(st: dict, rec: dict) -> list[str]:
    return [
        "Gold is Jev's logged choice + probabilities, not forward PnL. Not financial advice.",
        f"Genuinely varied multi-option rows: {st['varied_multi']} (need ~{NEED['multi_option_unique']}).",
        f"Non-hold gold: {st['non_hold_gold']} (need ~{NEED['non_hold_gold']}).",
        "Single-option RIDE menus are format-check only and never enter the train loss.",
        "Collapsed HOLD_WINNER+LONG_BTC+SWITCH ticks dominate; a student can copy HOLD without mimicking discretionary Jev.",
        f"Backbone {rec['size']} ({rec.get('hf_id')}); recipe from 68m-v5, not merged. 17m is the thin-data/CPU fallback.",
        "No HEF compile, no Pi deploy, no exchange/broker/trading API calls, no paid APIs.",
        "Beebots engine is not modified; see BEEBOTS_LOG_SPEC.md for the log schema.",
        "Forced/vetoed execution is metadata; gold stays Jev's choice even when the engine overrode the fill.",
        f"seq128 keep_option: {rec.get('keep_option_rows')} encoded rows overflowed; option tokens are kept and state is trimmed from the end.",
    ]


def run(args: argparse.Namespace) -> int:
    t_all = time.perf_counter()
    seed_all(args.seed)
    art = artifacts_dir()
    print("[jevh-trading] NOT FINANCIAL ADVICE. Offline Jev-distill. No orders.", flush=True)
    print(f"[jevh-trading] seed={args.seed} artifacts={art}", flush=True)

    extra = list(args.log or [])
    bundle = ingest(extra, purge_ms=args.purge_ms, train_frac=args.train_frac, seed=args.seed)
    st = bundle["stats"]
    print(f"[jevh-trading] ingest {json.dumps({k: st[k] for k in st if k not in ('needed', 'logs')})}", flush=True)
    write_split(bundle, art / "split.json")
    print(
        f"[jevh-trading] VARIETY: multi-option={st['multi_option_trainish']} "
        f"varied={st['varied_multi']} (need ~{NEED['multi_option_unique']}) "
        f"non-hold-gold={st['non_hold_gold']} (need ~{NEED['non_hold_gold']}) "
        f"days={st.get('calendar_days')} (need {NEED['calendar_days']}) "
        f"enough_to_claim={st['enough_to_claim']}",
        flush=True,
    )

    if args.ingest_only:
        (art / "metrics.json").write_text(json.dumps({"ingest": st, "disclaimer": "Not financial advice."}, indent=2))
        return 0

    train_rows, dev_rows, eval_rows = bundle["train"], bundle["dev"], bundle["eval"]
    if args.smoke:
        train_rows = train_rows[:24]
        dev_rows = dev_rows[:8] or train_rows[:8]
        eval_rows = eval_rows[:8] or train_rows[:8]
        args.epochs = min(args.epochs, 1)

    if len(train_rows) < 2:
        raise SystemExit(
            f"not enough multi-option rows to train (train={len(train_rows)}). "
            "Log more 2+-option decisions; single-option RIDE is format-check only."
        )

    size = pick_size(args.size, len(train_rows))
    unfreeze = args.unfreeze_last
    if unfreeze is None:
        unfreeze = UNFREEZE_LAST_17M if size.name == "17m" else UNFREEZE_LAST_68M
    print(f"[jevh-trading] size={size.name} hf={size.hf_id} n_train={len(train_rows)} unfreeze_last={unfreeze}", flush=True)

    tok = str(tokenizer_path())
    load_student_tok(tok)
    print("[jevh-trading] encoding menus...", flush=True)
    t0 = time.perf_counter()
    train_p = pack_rows(train_rows, tok)
    dev_p = pack_rows(dev_rows, tok)
    eval_p = pack_rows(eval_rows, tok)
    n_keep = sum(1 for p in train_p + dev_p + eval_p if p["mode"] == "keep_option")
    print(f"[jevh-trading] encoded in {time.perf_counter()-t0:.1f}s keep_option_rows={n_keep}", flush=True)

    # format-check encode (single-option); failures are bugs, not train data
    fmt_ok = 0
    for r in bundle["format_check"][:32]:
        menu = r.get("menu") or []
        from .ingest import text_a_for

        encode_menu(text_a_for(r), [str(x) for x in menu], tok)
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
    total, trainable = n_params(model)
    print(f"[jevh-trading] params={total:,} trainable={trainable:,} missing_keys={missing[:8]}", flush=True)

    groups = model.layerwise_param_groups(LR_ENCODER, LR_HEAD, LR_EMBED, LAYER_DECAY)
    for g in groups:
        g["params"] = [p for p in g["params"] if p.requires_grad]
    groups = [g for g in groups if g["params"]]
    opt = torch.optim.AdamW(groups, lr=LR_ENCODER, weight_decay=WEIGHT_DECAY)

    rng = random.Random(args.seed)
    ckpt = art / f"student_{size.name}.pt"
    best_acc = -1.0
    best_state = None
    history = []
    bad = 0
    t_train = time.perf_counter()
    for ep in range(1, args.epochs + 1):
        loss = run_epoch(model, train_p, opt, rng)
        pred, probs, logits = predict_packed(model, dev_p if dev_p else train_p[: min(32, len(train_p))], 1.0)
        golds = [p["gold"] for p in (dev_p if dev_p else train_p[: min(32, len(train_p))])]
        acc = float(np.mean([a == b for a, b in zip(pred, golds)])) if golds else 0.0
        history.append({"epoch": ep, "train_loss": loss, "dev_agree_t1": acc})
        print(f"[jevh-trading] epoch {ep} loss={loss:.4f} dev_agree={acc:.4f}", flush=True)
        if acc >= best_acc:
            best_acc = acc
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            torch.save({"model": best_state, "size": size.name, "seq": SEQ_LEN}, ckpt)
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

    # temperature on dev
    if dev_p:
        _, _, dlogits = predict_packed(model, dev_p, 1.0)
        T = fit_temperature(dlogits, [p["gold"] for p in dev_p])
    else:
        T = 1.0
    print(f"[jevh-trading] temperature={T:.4f}", flush=True)

    eval_met = eval_packed("eval", model, eval_p, T)
    dev_met = eval_packed("dev", model, dev_p, T)
    train_met = eval_packed("train", model, train_p[: min(200, len(train_p))], T)

    onnx_info = None
    calib = None
    par = None
    onnx_path = art / f"jevh_trading_ettin{size.name}_seq128.onnx"
    if not args.skip_export:
        print("[jevh-trading] exporting ONNX...", flush=True)
        onnx_info = export_onnx(model, onnx_path, opset=OPSET, output_name="logit")
        ids_np, mask_np = unique_calib_pairs(
            [train_p, dev_p, eval_p],
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
                "eval_jev_agree": eval_met.get("accuracy"),
                "varied_multi": st["varied_multi"],
                "need_varied": NEED["multi_option_unique"],
                "enough_to_claim": st["enough_to_claim"],
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
    p.add_argument("--size", default="auto", help="auto | 17m | 68m  (auto uses 17m when n_train < 1500)")
    p.add_argument("--unfreeze-last", type=int, default=None)
    p.add_argument("--log", action="append", default=[], help="extra decision jsonl (growing beebots log)")
    p.add_argument("--purge-ms", type=int, default=5 * 60 * 1000)
    p.add_argument("--train-frac", type=float, default=0.70)
    p.add_argument("--calib-n", type=int, default=256)
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

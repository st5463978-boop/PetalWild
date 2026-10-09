# JEV-H-large (ettin-encoder-150m)

Quality-ceiling encoder for PetalWild `/decide`. A ~150M ModernBERT (`jhu-clsp/ettin-encoder-150m`) scores each `(question, option)` pair and softmaxes over options. Gold is `jev_choice` from review labels; Qwen3-1.7B teacher scores from real `/decide` logs are extra soft labels.

This is **not** the live Hailo student (ettin68m HEF `352c0f6d…`). It is a CPU trainer + static ONNX export. No HEF compile. No Pi deploy. It does not use PR #26 mining labels.

## One command

From the repo root:

```bash
./tools/jevh_large/run.sh
```

That creates `tools/jevh_large/.venv`, installs [requirements.txt](requirements.txt) (CPU torch from the PyTorch CPU index), trains with seed 42, writes metrics, seq128 and seq256 static ONNX, and 256-row calibration sets.

Round 2 (same branch): resume the epoch-1 checkpoint, train at **seq256** with keep-option packing, unfreeze more layers + layer-wise LR, extra epochs with early stopping, and report a **template-grouped** eval alongside the unique-question split.

Smoke (tiny random encoder, bundled samples, seconds):

```bash
./tools/jevh_large/run.sh --smoke
```

Fast checks (split leakage + tiny static ONNX):

```bash
./tools/jevh_large/.venv/bin/python tools/jevh_large/test_jevh_large.py
```

## Data

Loader searches, in order: `$JEVH_DATA_DIR`, the agent `uploads/` directory, repo `uploads/`, then [data/](data/) samples.

| File | Full dump (not committed; > samples) | Rows |
|---|---|---|
| `labels.jsonl` / `labels_*.jsonl` | agent `uploads/labels_c563.jsonl` (~2.6 MB) | 4,220 review labels, 4,108 unique questions. Gold = `jev_choice`. |
| `decide_questions_dedup.jsonl` | `uploads/decide_questions_dedup_e594.jsonl` (~5.4 MB) | 9,402 real `/decide` requests. Teacher scores on 6,942. **Not gold.** |
| `jevh_lane_bank.jsonl` | `uploads/jevh_lane_bank_128a.jsonl` | 197 hard game questions (calib / unlabeled). |

A 20% held-out split is by **unique question** (no leakage), stratified by option count. Eval is reported for 2-way vs multi-choice (and a tiny literal yes/no slice). Soft decide rows whose question is in eval are dropped.

Input format matches the live JEV-H service: `text_a = "[qtype] question"` (+ context when present); yes/no (`noul`) options expand to `yes: that is true given the state` / `no: that is not true given the state`.

## Recipe (round 2 default, CPU)

- Backbone: `jhu-clsp/ettin-encoder-150m` (22 layers, hidden 768, GeGLU, alternating local/global attention).
- Static padded encoder (no HF unpadding / NonZero). `attention_mask` is an input and is used in attention **and** masked-mean pooling.
- Train/eval at **seq256**. Packing keeps the option: trim question/context tail first.
- Freeze embeddings + first **6** encoder layers; train layers 6–21 + head with **layer-wise LR decay 0.9**.
- Resume round-1 epoch-1 weights (`--resume artifacts/jevh_large_ettin150m.pt`); extra epochs with early stopping on unique-q eval (`--patience 1`).
- AdamW, seed 42, `1.0 * CE(gold) + 0.3 * KL(teacher_scores)`, `--max-train-minutes 100`.
- Head: GELU-erf + LayerNorm + scalar logit per option.
- Eval: unique-question split (same as round 1) **and** template-grouped (normalize numbers/names/quotes; no template in both train and eval).

Round 1 (seq128, freeze 10) is kept as `artifacts/jevh_large_ettin150m_r1.pt` when round 2 starts. If wall time is tight, `run.sh --epochs 1 --freeze-layers 10 --max-soft 800`.

## Round 2 (CPU, seed 42, seq256)

Same unique-question eval (823). Resume epoch-1, freeze 6, layer-wise LR, one extra epoch (100 min cap). Gold truncation at seq128 is **0%** (max pair 113). Unique-q eval is 89.8% template-seen.

| split | n | round 2 | round 1 | teacher | Δ vs R1 |
|---|---:|---:|---:|---:|---:|
| unique-q overall | 823 | **0.7655** | 0.7570 | 0.4581 | +0.85 pp |
| unique-q 2-way | 206 | 0.8641 | 0.8592 | **0.9320** | +0.49 pp |
| unique-q multi | 617 | **0.7326** | 0.7229 | 0.2998 | +0.97 pp |
| template-unseen overall | 84 | 0.6071 | — | **0.6190** | honest slice |
| template-unseen 2-way | 54 | 0.5370 | — | **0.7778** | |
| template-unseen multi | 30 | **0.7333** | — | 0.3333 | |

Conf-mistakes 23 (was 26). ECE 0.077. CPU batch-1 seq256: **105 ms / option**, ~223 ms / decision. Soft dump on 9,402 decide rows regenerated (`seq_len=256`). Full tables and ONNX sha256: [RECEIPT.md](RECEIPT.md).

## Round 1 (for comparison)

Held-out **823** unique questions. Best checkpoint: epoch 1 at seq128, freeze 10.

| split | n | student acc | Qwen3 teacher acc | conf-mistakes ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|
| overall | 823 | **0.757** | 0.458 | 26 | 0.071 |
| 2-way | 206 | 0.859 | 0.932 | 13 | 0.084 |
| multi-choice | 617 | **0.723** | 0.300 | 13 | 0.083 |

CPU batch-1 seq128: **62 ms / option**, ~132 ms / decision.

## Artifacts

Under `tools/jevh_large/artifacts/` (ONNX/checkpoints ~570 MB are gitignored; recreate with `run.sh`):

- `jevh_large_ettin150m_seq128.onnx` — batch 1, seq 128, `input_ids` + `attention_mask` → `logits` `[1,1]`
- `jevh_large_ettin150m_seq256.onnx` — same, seq 256
- `calib_input_ids_seq128.npy`, `calib_attention_mask_seq128.npy` — 256 real pairs
- `calib_input_ids_seq256.npy`, `calib_attention_mask_seq256.npy` — 256 real pairs
- `jevh_large_soft_on_decide_questions_dedup.jsonl.gz` — large-model soft labels on decide traffic (round 2, seq256)
- `metrics.json`, `RECEIPT.md`

## Hailo notes

ONNX is opset 17, fully static shapes, no `Loop` / `If` / `NonZero`, no dynamic `Reshape`. Do **not** compile a HEF here (no DFC machine on this agent). The previous Laya HEF omitted `attention_mask` and calibrated on noise (21.7% parity); this export keeps the mask in the graph.

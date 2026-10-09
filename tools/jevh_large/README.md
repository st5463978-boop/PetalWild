# JEV-H-large (ettin-encoder-150m)

Quality-ceiling encoder for PetalWild `/decide`. A ~150M ModernBERT (`jhu-clsp/ettin-encoder-150m`) scores each `(question, option)` pair and softmaxes over options. Gold is `jev_choice` from review labels; Qwen3-1.7B teacher scores from real `/decide` logs are extra soft labels.

This is **not** the live Hailo student (ettin68m HEF `352c0f6d…`). It is a CPU trainer + static ONNX export. No HEF compile. No Pi deploy. It does not use PR #26 mining labels.

## One command

From the repo root:

```bash
./tools/jevh_large/run.sh
```

That creates `tools/jevh_large/.venv`, installs [requirements.txt](requirements.txt) (CPU torch from the PyTorch CPU index), trains with seed 42, writes metrics, seq128 ONNX (seq256 if it fits), and a 256-row calibration set.

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

## Recipe (default, CPU)

- Backbone: `jhu-clsp/ettin-encoder-150m` (22 layers, hidden 768, GeGLU, alternating local/global attention).
- Static padded encoder (no HF unpadding / NonZero). `attention_mask` is an input and is used in attention **and** masked-mean pooling.
- Freeze embeddings + first 10 encoder layers; train layers 10–21 + head (CPU RAM).
- 2 epochs, AdamW, seed 42, `1.0 * CE(gold) + 0.3 * KL(teacher_scores)`.
- `--max-train-minutes 75` stops training early but still evals and exports.
- Head: GELU-erf + LayerNorm + scalar logit per option.

If wall time is tight, `run.sh --epochs 1 --freeze-layers 14 --max-soft 1000`.

## This run (CPU, seed 42)

Held-out **823** unique questions (20%, no leakage). Best checkpoint: epoch 1 (epoch 2 hit the 75-minute cap).

| split | n | student acc | Qwen3 teacher acc | conf-mistakes ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|
| overall | 823 | **0.757** | 0.458 | 26 | 0.071 |
| 2-way | 206 | 0.859 | 0.932 | 13 | 0.084 |
| multi-choice | 617 | **0.723** | 0.300 | 13 | 0.083 |

Beats the teacher overall, so soft labels on all 9,402 decide rows were exported. CPU batch-1: **62 ms / option**, ~132 ms / decision. Details, ONNX sha256, and gaps: [RECEIPT.md](RECEIPT.md).

## Artifacts

Under `tools/jevh_large/artifacts/` (ONNX/checkpoints ~570 MB are gitignored; recreate with `run.sh`):

- `jevh_large_ettin150m_seq128.onnx` — batch 1, seq 128, `input_ids` + `attention_mask` → `logits` `[1,1]`
- `jevh_large_ettin150m_seq256.onnx` — same, seq 256
- `calib_input_ids_seq128.npy`, `calib_attention_mask_seq128.npy` — 256 real pairs
- `jevh_large_soft_on_decide_questions_dedup.jsonl.gz` — large-model soft labels on decide traffic
- `metrics.json`, `RECEIPT.md`

## Hailo notes

ONNX is opset 17, fully static shapes, no `Loop` / `If` / `NonZero`, no dynamic `Reshape`. Do **not** compile a HEF here (no DFC machine on this agent). The previous Laya HEF omitted `attention_mask` and calibrated on noise (21.7% parity); this export keeps the mask in the graph.

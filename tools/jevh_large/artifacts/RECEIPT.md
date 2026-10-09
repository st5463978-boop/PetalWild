# JEV-H-large receipt (round 2)

Quality-ceiling encoder (`jhu-clsp/ettin-encoder-150m`, ModernBERT-150M).
Trained on gold `jev_choice` plus Qwen3-1.7B teacher soft labels. No HEF compile, no Pi deploy, no PR #26 mining labels.

## Data

| file | rows | sha256 | where |
|---|---:|---|---|
| `labels_c563.jsonl` | 4,220 (4,108 unique questions) | `b2cb4b2621a32307e2d8fb29abfbcf389de72aadc0dbe673f8e1438587bd4430` | agent `uploads/` (~2.6 MB, not committed) |
| `decide_questions_dedup_e594.jsonl` | 9,402 (teacher scores on 6,942) | `5c61b3aa54c2368c933c7b08ff2341a7707b2216385d7b89d70b03f87f7934f5` | agent `uploads/` (~5.4 MB, not committed) |
| `jevh_lane_bank_128a.jsonl` | 197 | `be0268a783f1225f0e5cf92179c1248a93054af0f8d209b1a691b262c5207e09` | agent `uploads/` |
| bundled samples | 38 / 24 / 12 | — | `tools/jevh_large/data/sample_*.jsonl` |

**Unique-question split** (same as round 1, so resume is comparable): seed **42**, **20.0%** held-out, stratified by option count, leakage **0**.

- train: 3,285 questions / 3,287 gold rows (2-way 823, 3-way 4, 4-way 2,460; literal yes/no 9)
- eval: 823 questions / 823 gold rows (2-way 206, 3-way 1, 4-way 615, 6-way 1; literal yes/no 3)
- soft decide rows in train (eval questions excluded, gold pairs de-duplicated, cap 1,200): 1,200

**Template-grouped split** (reported, not used for training this round): 509 templates after normalizing numbers → `#`, multi-word Title Case names → `NAME`, quoted strings → `'#'`, then `(n_options, first 10 words)`. Whole template in train or eval, leakage **0**. Train 3,284 questions / eval 824 (20.1%). Three XL families (≥100 questions) stay in train.

Unique-q eval vs train templates: **739 / 823 (89.8%) template-seen**, 84 template-unseen (54 2-way, 30 multi). Independent template-eval overlaps unique-q train on 641 questions — those scores are contaminated; the honest slice is unique-q **template-unseen**.

Labels are biased toward teacher-unsure / teacher-disagreement cases. `jev_choice` is gold. Decide teacher scores are **not** gold.

## Truncation

Tokenized pair = `[CLS] question/context [SEP] option [SEP]`. Keep-option packing trims the question/context tail first.

| seq | split | n | trunc rate | option-trunc | max pair | p90 pair |
|---:|---|---:|---:|---:|---:|---:|
| 128 | all | 4,110 | **0.000** | 0 | 113 | 71 |
| 128 | 2-way | 1,029 | **0.000** | 0 | 113 | 76 |
| 128 | multi | 3,081 | **0.000** | 0 | 75 | 53 |
| 256 | all | 4,110 | **0.000** | 0 | 113 | 71 |
| 256 | 2-way | 1,029 | **0.000** | 0 | 113 | 76 |
| 256 | multi | 3,081 | **0.000** | 0 | 75 | 53 |

Gold never hits seq128. Round-1 weights at seq256 score **identically** to seq128 (75.70 / 85.92 / 72.29). The 2-way gap vs the teacher is **not** clipping.

On `decide_questions_dedup` (9,402): 3 pairs exceed 128 tokens (max 137); **0** exceed 256.

## Recipe (round 2)

- backbone: `jhu-clsp/ettin-encoder-150m` (22 layers, hidden 768, 12 heads, GeGLU)
- static padded encoder (no HF unpadding). Masked-mean pool. GELU-erf head → scalar logit / option, softmax over options
- train/eval **seq256**, keep-option packing
- freeze embeddings + first **6** encoder layers (was 10); train layers 6–21 + head
- params 149,605,633 total / **80,832,769** trainable (was 60,772,609)
- resume round-1 epoch-1 weights; extra epoch 2 with layer-wise LR decay **0.9**
- AdamW lr encoder 1e-5 / head 5e-5, wd 0.01, grad clip 1, seed 42, gradient checkpointing
- loss: `1.0 * CE(gold)` + `0.3 * KL(teacher_scores)`
- 2 extra epochs requested, patience 1; stopped at `--max-train-minutes 100` after epoch 2 eval (new best). Train wall 6,590 s
- hardware: 4-thread CPU, no CUDA

Reproduce: `./tools/jevh_large/run.sh` (pinned CPU torch + transformers 4.51.3). Round-1 checkpoint is copied to `artifacts/jevh_large_ettin150m_r1.pt` (gitignored).

## Unique-question held-out vs `jev_choice` (same 823 as round 1)

| split | n | student acc | teacher acc (`model_choice`) | conf-mistakes ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|
| overall | 823 | **0.7655** | 0.4581 | 23 | 0.0769 |
| binary (2-way) | 206 | 0.8641 | **0.9320** | 17 | 0.1014 |
| multi-choice (3+) | 617 | **0.7326** | 0.2998 | 6 | 0.0896 |
| literal yes/no | 3 | 0.0000 | 0.0000 | 0 | 0.5563 |

### vs round 1

| split | n | round 2 | round 1 | Δ |
|---|---:|---:|---:|---:|
| overall | 823 | **0.7655** | 0.7570 | **+0.85 pp** |
| 2-way | 206 | 0.8641 | 0.8592 | +0.49 pp |
| multi | 617 | **0.7326** | 0.7229 | **+0.97 pp** |
| conf-mistakes | 823 | 23 | 26 | −3 |
| ECE | 823 | 0.0769 | 0.0712 | +0.006 |
| R1 weights @ seq256 | 823 | 0.7570 | 0.7570 | 0 (seq alone does nothing) |

Beats Qwen3-1.7B teacher on unique-q `jev_choice`: **yes** (overall +30.7 pp). Literal yes/no n=3 is noise (round 1 was 3/3).

CPU latency, batch=1 (PyTorch fp32, seq256, 40 eval decisions):

- per-option mean **105.1 ms** (p50 104.3, p90 107.9) — was 62.1 ms at seq128
- per-decision mean **223.4 ms** (2-way 210 ms, 3-way 322 ms, 6-way 631 ms)

## Template-grouped eval (alongside unique-q)

Unique-q eval sliced by whether that template appeared in unique-q train:

| split | n | student acc | teacher acc | conf-mistakes ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|
| template-seen overall | 739 | **0.7835** | 0.4398 | 5 | 0.0808 |
| template-seen 2-way | 152 | 0.9803 | **0.9868** | 2 | 0.0729 |
| template-seen multi | 587 | **0.7325** | 0.2981 | 3 | 0.0879 |
| **template-unseen overall** | 84 | 0.6071 | **0.6190** | 18 | 0.1425 |
| template-unseen 2-way | 54 | 0.5370 | **0.7778** | 15 | 0.2078 |
| template-unseen multi | 30 | **0.7333** | 0.3333 | 3 | 0.1495 |

The unique-q 2-way score (86.4%) is almost all template leakage: seen 2-way is **98.0%**, unseen 2-way is **53.7%** vs teacher 77.8%. Unseen multi still beats the teacher (73.3% vs 33.3%). Honest overall generalization on this slice: **60.7%**, slightly under the teacher (61.9%).

Independent template-split eval of this unique-q-trained model (not a retrained split):

| split | n | student acc | teacher acc | note |
|---|---:|---:|---:|---|
| template-split eval (all) | 824 | 0.9600 | 0.7427 | 641/824 also in unique-q **train** — contaminated |
| template-split clean | 183 | 0.9235 | 0.7158 | not in unique-q train, but still same templates as those 641 |
| template-split clean 2-way | 90 | 0.8778 | 0.9333 | |
| template-split clean multi | 93 | **0.9677** | 0.5054 | |

Treat **template-unseen unique-q** as the honest number; the independent split numbers above still leak near-duplicates through unique-q training.

## ONNX (Hailo-10H DFC static)

Exported then `onnxsim` (opset 17). No `Loop` / `If` / `NonZero`. `attention_mask` is an input and reaches Softmax (attention) and ReduceSum (pool). Mixed-mask ablation changes the logit (δ=0.054).

| | seq128 | seq256 |
|---|---|---|
| path | `tools/jevh_large/artifacts/jevh_large_ettin150m_seq128.onnx` (gitignored, ~571 MB) | `…_seq256.onnx` |
| sha256 | `7b099b0a84e8a11b7a1b1a75033f0e5cf2d0dd03e04dcfdbe7b359cd123a46e0` | `f8835d1e2ee69ffd32fb06c99e83a93d8c64fa971bd38e4fbbbb4ae7b8ab0343` |
| inputs | `input_ids` int64 `[1,128]`, `attention_mask` int64 `[1,128]` | same, `[1,256]` |
| output | `logits` float32 `[1,1]` | `logits` float32 `[1,1]` |
| ORT vs PyTorch cosine | **1.000000** (n=128) | **1.000000** (n=64) |

Do **not** compile a HEF from this PR.

Calibration (real tokenized pairs from train, 256 rows):

- `tools/jevh_large/artifacts/calib_input_ids_seq128.npy` shape `[256, 128]` int64 (242 unique rows)
- `tools/jevh_large/artifacts/calib_attention_mask_seq128.npy` shape `[256, 128]` int64
- `tools/jevh_large/artifacts/calib_input_ids_seq256.npy` shape `[256, 256]` int64 (256 unique)
- `tools/jevh_large/artifacts/calib_attention_mask_seq256.npy` shape `[256, 256]` int64

## Soft teacher dump

Wrote 9,402 rows because the large model beat Qwen3 on unique-q held-out gold. Same path/fields as round 1; `seq_len=256`. Uncompressed jsonl ~6.7 MB (gitignored); committed gzip:

- `tools/jevh_large/artifacts/jevh_large_soft_on_decide_questions_dedup.jsonl.gz` (9,402 rows, 1.2 MB, sha256 `7b40ffaa5700aa2341501e79e2f5cf7fffa313c20466b792632225894edd5d3b`)

Fields: `question`, `context`, `options`, `qtype`, `teacher_*`, `large_choice`, `large_scores`, `large_confidence`, `large_logits`, `backbone`, `seq_len`.

## Known gaps

- Gold labels are biased toward teacher-unsure / teacher-disagreement cases; they are not a uniform `/decide` sample.
- seq128 gold trunc_rate=0; the 2-way gap vs teacher is template leakage + hard binary items, not clipping.
- Unique-q eval is 89.8% template-seen. Template-unseen (n=84) is the honest generalization slice and does **not** beat the teacher overall (60.7% vs 61.9%), though unseen multi still does (73.3% vs 33.3%).
- Independent template split was not the training split (resume needed the round-1 unique-q partition); its eval scores leak through unique-q train.
- Embeddings + first 6 encoder layers frozen. Not a full 150M fine-tune. One extra epoch at seq256; wall cap 100 min.
- Literal yes/no n=3 is too small to score.
- No HEF compile (no DFC). No Pi deploy. Teacher soft labels and the large-model dump are not gold.
- PR #26 mining corpus was not mixed in.
- ONNX is batch=1 static; multi-option decisions run one pair at a time for Hailo.

Do not compile a HEF from this PR. Do not flash the Pi. Mining labels from PR #26 are unused.

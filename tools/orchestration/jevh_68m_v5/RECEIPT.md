# JEV-H-68m-v5 receipt

Direct successor to the live ettin68m student (seq128, `[qtype] question` + option text).
No HEF compile. No Pi deploy. No paid APIs.

## Data

- labels: `/home/ubuntu/.cursor/projects/workspace/uploads/labels_6f4e.jsonl` (4220 rows, 4108 unique questions). Bundled copy: `data/labels.jsonl`.
- decide (soft labels, never gold): `/home/ubuntu/.cursor/projects/workspace/uploads/decide_questions_dedup_cc6a.jsonl` (9402 rows, 4162 KD train rows). Not committed (~5.4 MB); sample fallback is `data/decide_questions.sample.jsonl`.
- lane bank: `/home/ubuntu/.cursor/projects/workspace/uploads/jevh_lane_bank_d8df.jsonl` (197 rows). Bundled copy: `data/lane_bank.jsonl`.
- tokenizer: `/home/ubuntu/.cursor/projects/workspace/uploads/jevh_student_tokenizer_fe24.json`. Bundled copy: `data/tokenizer.json`.
- split seed 42, by unique question, stratified by option count (`artifacts/split.json`)
- train questions 2873 / rows 2955
- dev questions 617 / rows 625
- eval questions 618 / rows 640 (**15.04%** of unique questions)
- eval yes/no (2-way) rows 175, multi-choice rows 465
- confident teacher-vs-JEV disagreements in labels: 2228 (train weight 3.0)

## Recipe

- backbone `jhu-clsp/ettin-encoder-68m` (ModernBERT, hidden 512, 19 layers, local window 128, RoPE θ 160000)
- CLS GELU head (Linear 512→512 no bias + GELU + LN + Linear 512→1), live-compatible pair scoring
- seq_len 128, seed 42
- freeze embeddings + first 13 layers; train last 6 + final LN + head (68.4M params, 13.6M trainable)
- listwise CE over options + pairwise hinge (margin 0.5, coef 0.4) vs teacher-wrong and online hard neg
- option order shuffled every use
- KD (KL to teacher softmax) on decide rows whose questions are outside eval/dev, coef 0.2; confident-disagreement questions excluded from KD
- AdamW encoder lr 2e-5, head lr 1e-4, wd 0.01, clip 1.0, microbatch 8 questions
- epochs run: **2**, train wall: **25.3 min** on 4-core CPU
- temperature fit on dev NLL: T=1.3000

## Held-out eval (gold = `jev_choice`)

| split | n | acc vs jev_choice | teacher acc | current student (overlap) | conf-mistakes (≥0.65) | ECE |
|---|---:|---:|---:|---:|---:|---:|
| eval T=1.300 | 640 | **0.7641** | 0.4688 | live 0.6579 / v5 0.7281 (n=114) | **18** | 0.0316 |
| eval T=1 | 640 | 0.7641 | 0.4688 | live 0.6579 | 21 | 0.0285 |
| eval yes/no (2-way) | 175 | **0.8629** | — | — | — | — |
| eval multi-choice | 465 | **0.7269** | — | — | — | — |
| teacher baseline (same 640 rows) | 640 | 0.4688 | — | — | 191 | — |

Dev (T fit only, not model selection leak into the table above except picking the ckpt): n=625 acc=0.7440 ECE=0.0331.

Option-count slices on eval: 2-way 175 @ 0.8629, 3-way 1 @ 1.0, 4-way 461 @ 0.7310, 6-way 3 @ 0.0.

## CPU latency (batch 1)

Measured on this VM (4× Xeon, fp32), one option at a time then softmax over the question's options:

| | mean | p50 | p90 |
|---|---:|---:|---:|
| per option (batch=1) | 44.5 ms | 44.5 ms | — |
| per decision (all options) | 103.0 ms | 88.6 ms | 96.9 ms |

## ONNX (Hailo-10H DFC, no compile here)

- path: `tools/orchestration/jevh_68m_v5/artifacts/jevh_68m_v5_seq128.onnx` (gitignored, 277,144,914 bytes)
- sha256: `a7c37638d7bcf6586e70046671e9c997783abf9e3dc8cd77b17755faf8e933da`
- opset: 17
- inputs:
  - `input_ids`: int64 `[1, 128]`
  - `attention_mask`: int64 `[1, 128]` (consumed as an additive attention bias; confirmed in graph)
- output: `logits` float32 `[1, 1]` (one option score; softmax is across options outside the graph, matching the live service)
- forbidden ops (Loop / If / NonZero): none
- static shapes only; Reshape/Slice are compile-time constants
- PyTorch vs onnxruntime cosine on eval logits: **1.000000** (need ≥ 0.999)

Calibration set (256 unique real tokenized pairs, seed 42):

- `artifacts/calib_input_ids.npy` shape `[256, 128]` int64
- `artifacts/calib_attention_mask.npy` shape `[256, 128]` int64

Reproduce: `./tools/orchestration/jevh_68m_v5/run.sh`

## Known gaps

- Labels were only written when the teacher was unsure or disagreed with JEV, so this eval is biased toward hard cases. Teacher acc 0.47 on this set is that bias, not the teacher's overall quality.
- Current-student comparison is only the 114 eval rows that also appear in `decide_questions_dedup` with `student_choice`.
- 6-way eval has n=3 and is not meaningful.
- Encoder embeddings and the first 13 layers were frozen for the CPU/RAM budget. A full unfreeze might move the multi-choice number.
- ONNX (~277 MB) is not committed; sha256 is the handle. No HEF compile (no DFC machine). No Pi deploy.
- Temperature 1.3 trims confident mistakes (21 → 18) with a small ECE trade vs T=1.

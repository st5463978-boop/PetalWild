# JEV-H-large receipt

Quality-ceiling encoder (`jhu-clsp/ettin-encoder-150m`, ModernBERT-150M).
Trained on gold `jev_choice` plus Qwen3-1.7B teacher soft labels. No HEF compile, no Pi deploy, no PR #26 mining labels.

## Data

| file | rows | sha256 | where |
|---|---:|---|---|
| `labels_c563.jsonl` | 4,220 (4,108 unique questions) | `b2cb4b2621a32307e2d8fb29abfbcf389de72aadc0dbe673f8e1438587bd4430` | agent `uploads/` (~2.6 MB, not committed) |
| `decide_questions_dedup_e594.jsonl` | 9,402 (teacher scores on 6,942) | `5c61b3aa54c2368c933c7b08ff2341a7707b2216385d7b89d70b03f87f7934f5` | agent `uploads/` (~5.4 MB, not committed) |
| `jevh_lane_bank_128a.jsonl` | 197 | `be0268a783f1225f0e5cf92179c1248a93054af0f8d209b1a691b262c5207e09` | agent `uploads/` |
| bundled samples | 38 / 24 / 12 | — | `tools/jevh_large/data/sample_*.jsonl` |

Split: seed **42**, **20.0%** held-out by unique question, stratified by option count, leakage **0**.

- train: 3,285 questions / 3,287 gold rows (2-way 823, 3-way 4, 4-way 2,460; literal yes/no 9)
- eval: 823 questions / 823 gold rows (2-way 206, 3-way 1, 4-way 615, 6-way 1; literal yes/no 3)
- soft decide rows in train (eval questions excluded, gold pairs de-duplicated, cap 2,500): 2,500

Labels are biased toward teacher-unsure / teacher-disagreement cases. `jev_choice` is gold. Decide teacher scores are **not** gold.

## Recipe

- backbone: `jhu-clsp/ettin-encoder-150m` (22 layers, hidden 768, 12 heads, GeGLU)
- static padded encoder (no HF unpadding). Masked-mean pool. GELU-erf head → scalar logit / option, softmax over options
- freeze embeddings + first 10 encoder layers; train layers 10–21 + head
- params 149,605,633 total / 60,772,609 trainable
- seq_len train **128**; export 128 and 256
- 2 epochs requested; stopped at `--max-train-minutes 75` mid-epoch 2 (3,947 steps). Best checkpoint is **epoch 1**
- AdamW lr encoder 2e-5 / head 1e-4, wd 0.01, grad clip 1, seed 42
- loss: `1.0 * CE(gold)` + `0.3 * KL(teacher_scores)`
- hardware: 4-thread CPU, no CUDA; train wall 4,501 s

Reproduce: `./tools/jevh_large/run.sh` (pinned CPU torch + transformers 4.51.3).

## Held-out metrics vs `jev_choice`

| split | n | student acc | teacher acc (`model_choice`) | conf-mistakes ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|
| overall | 823 | **0.7570** | 0.4581 | 26 | 0.0712 |
| binary (2-way) | 206 | 0.8592 | **0.9320** | 13 | 0.0842 |
| multi-choice (3+) | 617 | **0.7229** | 0.2998 | 13 | 0.0826 |
| literal yes/no | 3 | 1.0000 | 0.0000 | 0 | 0.4773 |

Beats Qwen3-1.7B teacher on held-out `jev_choice`: **yes** (overall +30 pp). The gain is on 4-way items; 2-way long options still trail the teacher (seq128 truncation).

CPU latency, batch=1 (PyTorch fp32, 40 eval decisions):

- per-option mean **62.1 ms** (p50 62.0, p90 63.4)
- per-decision mean **132.0 ms** (2-way 124 ms, 3-way 184 ms, 6-way 370 ms)

## ONNX (Hailo-10H DFC static)

Exported then `onnxsim` (opset 17). No `Loop` / `If` / `NonZero` / `Shape`. Remaining `Reshape` ops use constant `[1, seq, …]` initializers. `attention_mask` is an input and reaches Softmax (attention) and ReduceSum (pool). Mixed-mask ablation changes the logit.

| | seq128 | seq256 |
|---|---|---|
| path | `tools/jevh_large/artifacts/jevh_large_ettin150m_seq128.onnx` (gitignored, ~571 MB) | `…_seq256.onnx` (gitignored, ~571 MB) |
| sha256 | `37f175952cd6e6d8b2ba28ac14afc500a96f56ed9f7c12e12e060cf1c7928de3` | `d58365169d4a6ccf8b1cefa5b5cea4a604a9da578fb885d8b25fc3263b972ca7` |
| inputs | `input_ids` int64 `[1,128]`, `attention_mask` int64 `[1,128]` | same, `[1,256]` |
| output | `logits` float32 `[1,1]` | `logits` float32 `[1,1]` |
| ORT vs PyTorch cosine | **1.000000** (n=32 after sim; 256 pairs before sim) | **1.000000** (n=64) |

Reproduce the files with `./tools/jevh_large/run.sh`. Do **not** compile a HEF from this PR.

Calibration (real tokenized pairs from train, 256 unique rows):

- `tools/jevh_large/artifacts/calib_input_ids_seq128.npy` shape `[256, 128]` int64
- `tools/jevh_large/artifacts/calib_attention_mask_seq128.npy` shape `[256, 128]` int64

## Soft teacher dump

Wrote 9,402 rows because the large model beat Qwen3 on held-out gold. Uncompressed jsonl is ~6.7 MB (gitignored); committed gzip:

- `tools/jevh_large/artifacts/jevh_large_soft_on_decide_questions_dedup.jsonl.gz` (9,402 rows, 1.2 MB, sha256 `b415edca8f6b78116f252f3abc104eda801b698116bf2182859ec264bb664bb0`)

Fields: `question`, `context`, `options`, `qtype`, `teacher_*`, `large_choice`, `large_scores`, `large_confidence`, `large_logits`.

## Known gaps

- Gold set is hard-case biased; overall teacher acc 45.8% on this eval is not Qwen3's accuracy on easy /decide traffic.
- 2-way eval is mostly long binary strings, not literal yes/no (literal n=3). Student 85.9% vs teacher 93.2% there; seq128 truncates those options.
- Epoch 2 did not finish (75-minute cap); kept epoch-1 weights. Embeddings + first 10 layers frozen — not a full 150M fine-tune.
- Soft dump is a distillation artifact, not gold.
- ONNX / `.pt` are ~570 MB and gitignored; sha256 above is the Hailo candidate.
- No HEF compile (no DFC). No Pi deploy. PR #26 mining corpus unused.

# JEV-H-small receipt (ettin-encoder-17m)

Speed/size floor student for PetalWild JEV-H. Distils a 17M Ettin encoder into a
multiple-choice / yes-no scorer. **No HEF compile. No Pi deploy. No paid APIs.**

## Backbone choice

- **Picked: `jhu-clsp/ettin-encoder-17m`** (17M, hidden 256, 7 layers, 4 heads, intermediate 384).
- Same ModernBERT/Ettin family as the live 68m Hailo student, same 50,368 BPE tokenizer,
  same pair encoding (`[qtype] question` as text_a, option as text_b, seq 128, CLS head).
- 17M is the published Ettin XXS / mobile-edge checkpoint and sits at the bottom of the
  requested 17–30M band. `ettin-encoder-32m` would be the next size up if this floor is too weak.
- Encoder params (formula): 17m ≈ 16,797,184; 68m ≈ 68,144,128.
- Live 68m host weights were 104 MB (not attached here); 17m encoder+head ONNX is ~encoder fp32 size.

## Data

- labels: `labels_bc1e.jsonl` — 4220 rows, 4108 unique questions. Gold = `jev_choice`.
  Biased toward hard cases (teacher unsure or disagreed).
- decide_questions_dedup: `decide_questions_dedup_c6f4.jsonl` — 9402 rows, 6940 with teacher soft scores. **Not gold.**
- lane bank: `jevh_lane_bank_69ec.jsonl` — 197 unlabeled game questions (calibration only).
- tokenizer: `jevh_student_tokenizer_f28e.json` (live student tokenizer.json).
- Full files live in the Cloud Agent upload bundle (hashed names) or `$JEVH_DATA_DIR`.
  Samples (not full data) are in `data/`. Do not treat decide rows as gold.
- Mining / teacher-swarm corpora from PR #26 were **not** used.

## Split (unique question, no leakage)

- seed 42, eval fraction 0.1502 (617 / 4108 questions).
- train rows 3592 (2-way 949, multi 2643).
- eval rows 628 (2-way 162, multi 466).
- option-count strata: `{"2": {"n_questions": 1029, "n_eval": 154, "n_train": 875}, "3": {"n_questions": 5, "n_eval": 1, "n_train": 4}, "4": {"n_questions": 3073, "n_eval": 461, "n_train": 2612}, "6plus": {"n_questions": 1, "n_eval": 1, "n_train": 0}}`.
- 2-way is reported as yes/no (matches the label card's 1,111 2-way count). Strict noul (literal yes/no) is rarer.

## Recipe

- backbone `jhu-clsp/ettin-encoder-17m` revision `987607455c61e7a5bbc85f7758e0512ea6d0ae4c`.
- freeze token embeddings; fine-tune 7 encoder layers + GELU CLS head (Linear→GELU→LN→Linear→1).
- hard CE on `jev_choice` + KL to Qwen3 teacher scores (λ=0.4).
- extra unlabeled teacher rows: 1200 (capped, eval questions excluded).
- AdamW encoder lr 3e-05, head lr 0.001, wd 0.01, clip 1.0.
- epochs 3, batch 8 questions, seed 42.
- device: CPU (`cpu`), threads 4.
- scaled down: False. full CPU recipe as above

## Metrics (held-out labels, gold = jev_choice)

| split | n | student acc | teacher acc (model_choice) | confident mistakes (≥0.65) | ECE |
|---|---:|---:|---:|---:|---:|
| all | 628 | 0.9554 | 0.4618 | 12 | 0.1785 |
| yes/no (2-way) | 162 | 0.8642 | 0.9383 | 10 | 0.0462 |
| multi-choice | 466 | 0.9871 | 0.2961 | 2 | 0.2494 |

- mean student confidence 0.7845.
- CPU latency per decision, batch=1 per option: n=64 mean 13.7 ms (p50 10.8, p95 22.1, min 10.0, max 32.3).
- CPU latency packed options: n=64 mean 9.3 ms (p50 8.2, p95 12.1, min 7.8, max 19.4).

## ONNX (Hailo-10H DFC, no compile here)

- path: `artifacts/jevh_small_ettin17m_seq128.onnx` (not committed; ~68.9 MB, reproduce with `python train.py`)
- sha256: `5bc20e976e2b4e16b607553c5d11cebe46712f2277f67d1e616d71ce482fce7b`
- opset 17, nodes 610, bytes 68934506.
- inputs: `input_ids [1, 128] int64, attention_mask [1, 128] float32`
- outputs: `logit [1] float32`
- attention_mask used in graph: True
- forbidden ops (Loop/If/NonZero): `[]`
- Shape ops remaining: 0 (0 wanted for DFC); dynamic Reshape: `[]`.
- PyTorch vs ORT cosine: 0.9999999999994112 (need ≥ 0.999), ok=True.
- calib: n=256 `artifacts/calib/input_ids.npy` + `attention_mask.npy`.

## Size / latency trade-off vs 68m

Student has 16,864,001 parameters (encoder formula ~16,797,184 plus a small CLS head). Ettin-68m encoder formula ~68,144,128 params (~4.1×). Transformer-body FLOPs scale roughly (19/7)×(512/256)×(768/384) ≈ 11× for FFN; the live 68m NPU decision was ~55 ms wall on Hailo-10H (reference service). This 17m CPU batch-1 decision is n=64 mean 13.7 ms (p50 10.8, p95 22.1, min 10.0, max 32.3) on 4 threads (not comparable to NPU, but the HEF should be much smaller/faster than 68m). 68m CPU accuracy was not re-measured (host_weights_v4_ettin68m.npz not attached).

## Known gaps

- Labels are hard-case biased (written when the teacher was unsure or disagreed), so held-out accuracy is not in-the-wild decide accuracy.
- Teacher (Qwen3-1.7B model_choice) is a baseline on the same rows, not gold.
- No 68m student was re-run; size/latency comparison is from the Ettin card + the live :8771 reference (~55 ms NPU).
- ONNX is batch=1 seq=128 per option; softmax over options stays on the host (variable 2–6 options).
- No Hailo DFC compile, no HEF, no Pi flash.
- Local attention window at seq=128 is ±64; global every 3rd layer. Mask is additive -1e4, not -inf.
- PR #26 mining failures were not mixed into train (owned by the other agent).

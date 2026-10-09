# JEV-H-68m-v5 receipt (round 2)

Direct successor to the live ettin68m student (seq128, `[qtype] question` + option text).
No HEF compile. No Pi deploy. No paid APIs. Trained on the template-grouped split (honest).

## Data

- labels: `/home/ubuntu/.cursor/projects/workspace/uploads/labels_6f4e.jsonl` (4220 rows, 4108 unique questions, 503 templates)
- decide (soft labels, never gold): `/home/ubuntu/.cursor/projects/workspace/uploads/decide_questions_dedup_cc6a.jsonl` (9402 rows, 5442 KD train rows)
- JEV-H-large soft labels: `/workspace/tools/orchestration/jevh_68m_v5/data/external/jevh_large_soft_on_decide_questions_dedup.jsonl.gz` (9402 rows; from `cursor/jevh-variant-large-819a`, not merged)
- KD blend: large 0.65/Qwen 0.35 on argmax-agree, large 0.80/Qwen 0.20 on disagree. `jev_choice` stays gold.
- lane bank: `/home/ubuntu/.cursor/projects/workspace/uploads/jevh_lane_bank_d8df.jsonl` (197 rows)
- tokenizer: `/home/ubuntu/.cursor/projects/workspace/uploads/jevh_student_tokenizer_fe24.json`
- split seed 42
- **template-grouped** (train): questions 2578 / rows 2616; dev 766/795; eval 764/809 (18.6% of unique questions, 269 templates; largest train family 1245 q, largest eval family 305 q)
- unique-question split (round-1 protocol, eval-only): 618 questions / 640 rows; leaked into template-train: 390
- eval 2-way (template) 198, multi 611
- confident teacher-vs-JEV disagreements: 2228 (train weight 3.0)

## Truncation (seq128)

{
  "labels": {
    "pairs": 14634,
    "pairs_true_len_gt_128": 0,
    "pair_overflow_rate": 0.0,
    "trimmed_question_pairs": 0,
    "trimmed_option_pairs": 0,
    "two_way_rows": 1111,
    "two_way_rows_overflow": 0,
    "two_way_overflow_rate": 0.0
  },
  "kd": {
    "pairs": 11858,
    "pairs_true_len_gt_128": 1,
    "pair_overflow_rate": 8.433125316242199e-05,
    "trimmed_question_pairs": 1,
    "trimmed_option_pairs": 0,
    "two_way_rows": 4948,
    "two_way_rows_overflow": 1,
    "two_way_overflow_rate": 0.0002021018593371059
  }
}

Smarter truncation (`keep_option`): if a pair would exceed 128, keep option tokens and trim question/context. Labels never overflowed 128; decide had a handful of 2-way overflows.

## Recipe (round 2 vs round 1)

- backbone `jhu-clsp/ettin-encoder-68m`, CLS GELU head, seq_len 128, seed 42
- **full encoder unfrozen** including embeddings (round 1: last 6 layers + head)
- layer-wise LR decay 0.9: last layer 2e-05, embeddings 5e-06, head 8e-05
- init from round-1 checkpoint: /workspace/tools/orchestration/jevh_68m_v5/artifacts/jevh_68m_v5.pt
- listwise CE + pairwise hinge (margin 0.5, coef 0.4); option shuffle
- KD from blended large+Qwen on decide rows outside template eval/dev, coef 0.25; extra KL on gold rows where large agrees with jev_choice
- AdamW wd 0.01, clip 1.0, microbatch 8, grad checkpointing on
- early stopping patience 2 on unique-q-dev acc (min 3 epochs); epochs run 3 / requested 6; train minutes 106.0
- temperature: template-dev T=0.5000; unique-q-dev T=0.7000
- trainable 68.4M / 68.4M

## Held-out eval (gold = jev_choice)

| split | n | acc | 2-way | multi | teacher | live student / v5 overlap | conf-mist ≥0.65 | ECE |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| template eval T=0.50 (honest) | 809 | 0.8863 | 0.8030 | 0.9133 | 0.6032 | live 0.5414 / v5 0.8854 (n=157) | 41 | 0.0290 |
| unique-q eval T=0.70, same rows as round 1 | 640 | 0.8000 | 0.8400 | 0.7849 | 0.4688 | live 0.6579 / v5 0.7193 (n=114) | 25 | 0.0503 |
| unique-q eval T=1.3 (round-1 temperature) | 640 | 0.8000 | 0.8400 | 0.7849 | 0.4688 | live 0.6579 / v5 0.7193 (n=114) | 14 | 0.0796 |
| unique-q eval, rows not in template-train | 245 | 0.8735 | 0.6102 | 0.9570 | 0.5306 | live 0.7317 / v5 0.8049 (n=41) | 18 | 0.0573 |
| round 1 unique-q T=1.3 (frozen) | 640 | 0.7641 | 0.8629 | 0.7269 | 0.4688 | live 0.6579 / v5 0.7281 (n=114) | 18 | 0.0316 |
| round 2a unique-q (template-dev early stop) | 640 | 0.7625 | 0.8629 | 0.7247 | 0.4688 | live 0.6579 / v5 0.7105 (n=114) | 25 | 0.0403 |
| template-dev (T fit) | 795 | 0.9509 | 0.7880 | 1.0000 | 0.5321 | live 0.7895 / v5 0.8553 (n=76) | 24 | 0.0090 |
| unique-q-dev (early stop / T fit) | 625 | 0.7824 | 0.8712 | 0.7511 | 0.4560 | live 0.5435 / v5 0.6304 (n=92) | 14 | 0.0291 |

Round-2 minus round-1 unique-q acc: 0.0359 (same 640 rows; 390 of those questions were in template-train).

## CPU latency (batch 1)

{
  "n": 40,
  "decision_ms_mean": 98.14823742499357,
  "decision_ms_p50": 84.66261850026058,
  "decision_ms_p90": 88.93151729989768,
  "option_batch1_ms_mean": 42.168397600062235,
  "option_batch1_ms_p50": 41.93309750098706,
  "note": "batch=1 per option, then softmax over options (matches Hailo option loop)"
}

## ONNX (Hailo-10H DFC, no compile here)

- path: `/workspace/tools/orchestration/jevh_68m_v5/artifacts/jevh_68m_v5_seq128.onnx`
- sha256: `7f78a56e9a692c6c83baf064b86219919a2d7f8870c9813a4ffae50d4a89e292`
- size_bytes: 277144914
- opset: [17]
- inputs: [{'name': 'input_ids', 'shape': [1, 128], 'elem': 7, 'dtype': 'int64'}, {'name': 'attention_mask', 'shape': [1, 128], 'elem': 7, 'dtype': 'int64'}]
- outputs: [{'name': 'logits', 'shape': [1, 1], 'elem': 1, 'dtype': 'float32'}]
- attention_mask used: True
- forbidden ops: none
- PyTorch vs ORT cosine on eval logits: 1.000000 (need ≥ 0.999)

Calibration set: `/workspace/tools/orchestration/jevh_68m_v5/artifacts/calib_input_ids.npy` + `/workspace/tools/orchestration/jevh_68m_v5/artifacts/calib_attention_mask.npy` shape [256, 128] (real tokenized pairs, seed 42).

## Known gaps

- Stopped after epoch 3: hit --max-train-minutes=90.0
- Labels are biased to teacher-unsure or teacher-JEV disagreement cases.
- No HEF compile (no DFC). No deploy. Current-student comparison only on decide overlap rows.
- Requested 6 epochs, ran 3.
- Unique-question eval reuses round-1 rows; some of those questions can sit in template-train (see qsplit_eval_leaked). Template eval is the honest number.

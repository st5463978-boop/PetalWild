# JEV-H-small (ettin-encoder-17m)

Speed/size floor student for PetalWild JEV-H. Distils `jhu-clsp/ettin-encoder-17m` (~17M, hidden 256, 7 layers, 4 heads) into a multiple-choice / yes-no scorer that matches the live :8771 input format.

**No HEF compile. No Pi deploy. No paid APIs. Draft PR only.**

The full numbered receipt is `artifacts/RECEIPT.md`.

## Why 17m

The live chip student is Ettin-68m (hidden 512, 19 layers, seq 128). Ettin-17m is the same ModernBERT family and tokenizer, at the bottom of the 17–30M band, and is the published XXS / mobile-edge checkpoint. 32m is the next size if this floor is too weak.

## One command

From this directory (needs `python3-venv` on Debian/Ubuntu):

```bash
chmod +x run.sh
./run.sh
```

That creates `.venv`, installs pinned CPU torch from `requirements.txt`, and runs `python train.py` (seed 42). If deps are already installed: `python3 train.py`. Smoke: `python3 train.py --quick`.

## Data

Trainer resolves CLI / env, then the Cloud Agent upload dir, then `data/` samples.

| file | env | role |
|---|---|---|
| labels.jsonl | `JEVH_LABELS_PATH` | gold = `jev_choice` |
| decide_questions_dedup.jsonl | `JEVH_DECIDE_PATH` | teacher soft scores, **not gold** |
| jevh_lane_bank.jsonl | `JEVH_LANE_PATH` | unlabeled game questions for HEF calib |
| tokenizer.json | `JEVH_TOKENIZER_PATH` | live student tokenizer |

This run used the upload bundle: 4,220 label rows (4,108 unique questions), 9,402 decide rows (6,940 with teacher scores), 197 lane-bank questions. Split seed 42, **15.02% of unique questions held out** (617 / 4,108; 628 eval rows). Stratified by option count. 2-way vs multi-choice reported separately. PR #26 mining corpora were not used.

## This run (CPU, 4 threads, 3 epochs)

| split | n | student acc | teacher acc (`model_choice`) | confident mistakes (≥0.65) | ECE |
|---|---:|---:|---:|---:|---:|
| all | 628 | 0.9554 | 0.4618 | 12 | 0.1785 |
| yes/no (2-way) | 162 | 0.8642 | 0.9383 | 10 | 0.0462 |
| multi-choice | 466 | 0.9871 | 0.2961 | 2 | 0.2494 |

- Gold is `jev_choice` on the hard-case label set (teacher unsure or disagreed). Teacher accuracy 46% overall is the baseline on those same rows, not a 68m student score.
- CPU latency per decision, batch=1 per option: mean **13.7 ms** (p50 10.8, p95 22.1) over 64 eval questions.
- 16,864,001 params vs ~68M for Ettin-68m (~4.1×). Live 68m NPU was ~55 ms; 68m weights were not attached so CPU 68m was not re-run.

## Hailo ONNX

`artifacts/jevh_small_ettin17m_seq128.onnx` (~68.9 MB, not committed; `python train.py` regenerates it).

- sha256 `5bc20e976e2b4e16b607553c5d11cebe46712f2277f67d1e616d71ce482fce7b`
- opset 17, batch 1, seq 128, 610 nodes, 0 Shape, 0 Loop/If/NonZero, no dynamic Reshape
- inputs: `input_ids [1,128] int64`, `attention_mask [1,128] float32` (mask is added into attention scores)
- output: `logit [1] float32` (host softmax over 2–6 options)
- PyTorch vs ORT cosine **0.9999999999994112**
- calib: 256 real rows in `artifacts/calib/input_ids.npy` + `attention_mask.npy` (npy not committed; `meta.json` is)

## Tests

```bash
python3 test_jevh_small.py
```

## Known gaps

- Hard-case labels, so held-out acc is not in-the-wild decide acc. 2-way student trails the teacher; multi-choice looks easy because gold is JEV and many 4-way items are templated.
- ECE 0.18: no temperature fit. Multi ECE is high because the student is *underconfident* (mean p 0.78 vs 98.7% acc).
- One 6-way question landed entirely in eval (n=1 stratum).
- No HEF, no Pi, no 68m CPU re-run.

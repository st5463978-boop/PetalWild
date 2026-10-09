# JEV-H-small (ettin-encoder-17m)

Speed/size floor student for PetalWild JEV-H. Distils `jhu-clsp/ettin-encoder-17m` (~17M, hidden 256, 7 layers) into a multiple-choice / yes-no scorer that matches the live :8771 input format.

**No HEF compile. No Pi deploy. No paid APIs. Draft PR only.**

After a successful train the metrics table and ONNX sha are written into this file and `artifacts/RECEIPT.md`.

## Why 17m

The live chip student is Ettin-68m (hidden 512, 19 layers, seq 128). Ettin-17m is the same ModernBERT family and tokenizer, at the bottom of the 17–30M band, and is the published XXS / mobile-edge checkpoint. 32m is the next size if this floor is too weak.

## One command

From this directory:

```bash
chmod +x run.sh
./run.sh
```

That creates `.venv`, installs `requirements.txt` (CPU torch), and runs `python train.py` with seed 42.

If deps are already installed:

```bash
python3 train.py
```

Smoke (scaled down): `python3 train.py --quick`

## Data

Trainer resolves, in order: CLI / env, then the Cloud Agent upload dir, then `data/` samples.

| file | env | role |
|---|---|---|
| labels.jsonl | `JEVH_LABELS_PATH` | gold = `jev_choice` |
| decide_questions_dedup.jsonl | `JEVH_DECIDE_PATH` | teacher soft scores, **not gold** |
| jevh_lane_bank.jsonl | `JEVH_LANE_PATH` | unlabeled game questions for HEF calib |
| tokenizer.json | `JEVH_TOKENIZER_PATH` | live student tokenizer |

Full files are in the agent upload bundle (`labels_*.jsonl`, etc.). They are not committed when larger than ~5 MB. Tiny samples live in `data/`.

Split: unique **question** (no leakage), ≥15% eval, stratified by option count. 2-way vs multi-choice are reported separately.

## Hailo ONNX contract

Export is `artifacts/jevh_small_ettin17m_seq128.onnx`:

- batch 1, seq 128, opset 17
- inputs `input_ids` and `attention_mask`, both used (mask added into attention scores)
- output `logit` (one option). Host softmax over 2–6 options
- no Loop / If / NonZero; static reshape at export
- ORT vs PyTorch cosine ≥ 0.999 on eval logits
- calib `artifacts/calib/input_ids.npy` + `attention_mask.npy` (n ≥ 256, real tokenized rows)

Do not compile a HEF in this tree.

## Tests

```bash
python3 test_jevh_small.py
```

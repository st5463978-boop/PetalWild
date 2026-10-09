# JEV-H-68m-v5

Retrain of the live Hailo student (`jhu-clsp/ettin-encoder-68m`, seq 128) on
the current JEV review labels. Same input format as `:8771`:

- `text_a = "[qtype] question"` (plus `\n{context}` when context is not the question)
- each option as `text_b` (yes/no noul strings when the two options normalise to yes/no)
- one logit per option, softmax over the option set

This is **not** the teacher-swarm mining work (PR #26). It does not compile a
HEF, does not flash the Pi, and does not call paid APIs.

## One command

```bash
./tools/orchestration/jevh_68m_v5/run.sh
```

Creates `.venv`, installs `requirements.txt` (CPU torch + onnxruntime, pinned),
downloads `jhu-clsp/ettin-encoder-68m` if needed, trains, evaluates, exports
static ONNX, writes a 256-row calibration `.npy` pair, and overwrites
`RECEIPT.md`.

Useful flags (passed through to `train.py`):

```bash
./tools/orchestration/jevh_68m_v5/run.sh --epochs 2 --unfreeze-last 6 --max-train-minutes 70
./tools/orchestration/jevh_68m_v5/run.sh --skip-train   # eval/export an existing artifacts/jevh_68m_v5.pt
```

Unit tests (no training):

```bash
cd tools/orchestration/jevh_68m_v5
PYTHONPATH=. .venv/bin/python -m unittest test_jevh_68m_v5.py -v
```

## Recipe (short)

- Split by **unique question** (no leakage), ≥15% eval, 15% dev, stratified by option count.
- Gold = `jev_choice`. Teacher `model_choice` is a baseline only.
- Weight the 2,228 confident teacher-vs-JEV disagreements (JEV conf ≥ 0.65) at 3.0.
- Listwise CE + pairwise hinge vs the teacher-wrong option and the online near-miss.
- Shuffle option order every use (kills index bias in the listwise head).
- KL to teacher softmax on decide rows whose questions are outside eval/dev (never gold).
- Fit temperature on dev NLL.
- Freeze embeddings + early layers; train the last 6 encoder layers + head (CPU budget).
- Export ONNX opset 17, batch 1, seq 128, inputs `input_ids` and `attention_mask` (mask is an additive attention bias).

See `RECEIPT.md` for the run that produced metrics / sha256.

## Outputs (gitignored when large)

| file | commit? |
|---|---|
| `RECEIPT.md`, `artifacts/metrics.json`, `artifacts/split.json` | yes |
| `artifacts/calib_input_ids.npy`, `artifacts/calib_attention_mask.npy` | yes (≥256 × 128) |
| `artifacts/jevh_68m_v5_seq128.onnx` (~270 MB) | no (sha256 in the receipt) |
| `artifacts/jevh_68m_v5.pt`, `artifacts/hf/` | no |

## Hard rules

No HEF compile, no device deploy, no trades, no paid OpenRouter, no secrets.

# JEV-H-68m-v5

Retrain of the live Hailo student (`jhu-clsp/ettin-encoder-68m`, seq 128) on
the current JEV review labels. Same input format as `:8771`:

- `text_a = "[qtype] question"` (plus `\n{context}` when context is not the question)
- each option as `text_b` (yes/no noul strings when the two options normalise to yes/no)
- one logit per option, softmax over the option set

This is **not** the teacher-swarm mining work (PR #26). Training does not
compile a HEF, does not flash the Pi, and does not call paid APIs. Compilation
is a separate step: `./compile_hef.sh`. It refuses random calibration data and
does not bind the live decide port.

Round 2 trains the **full encoder** (layer-wise LR), distills JEV-H-large +
Qwen3 soft labels, and reports a **template-grouped** eval so near-duplicate
questions cannot leak. Gold is still `jev_choice`.

## One command

```bash
./tools/orchestration/jevh_68m_v5/run.sh
```

Creates `.venv`, installs `requirements.txt` (CPU torch + onnxruntime, pinned),
downloads `jhu-clsp/ettin-encoder-68m` if needed, trains, evaluates, exports
static ONNX, writes a 256-row calibration `.npy` pair, and overwrites
`RECEIPT.md`.

```bash
./tools/orchestration/jevh_68m_v5/run.sh --epochs 6 --patience 2 --max-train-minutes 90
./tools/orchestration/jevh_68m_v5/run.sh --skip-train   # eval/export artifacts/jevh_68m_v5_r2.pt
```

Unit tests (no training):

```bash
cd tools/orchestration/jevh_68m_v5
PYTHONPATH=. .venv/bin/python -m unittest test_jevh_68m_v5.py -v
```

## Recipe (round 2)

- **Train split:** template-grouped (numbers/names/entities normalised). No template in both train and eval. ≥15% eval.
- Also report the round-1 unique-question eval rows for comparison.
- Gold = `jev_choice`. Qwen3 `model_choice` and JEV-H-large scores are never gold.
- Blend large/Qwen soft targets (large 0.65/0.35 on agree, 0.80/0.20 on disagree).
- Weight confident teacher-vs-JEV disagreements at 3.0. Listwise CE + pairwise hinge. Option shuffle.
- If a pair would exceed seq128, keep the option and trim question/context.
- Full encoder + embeddings, layer-wise LR decay 0.9, init from the round-1 checkpoint, early stop on template-dev.
- Export ONNX opset 17, batch 1, seq 128, `input_ids` + `attention_mask`.

See `RECEIPT.md` for metrics / sha256.

## Compile (no deploy)

```bash
./tools/orchestration/jevh_68m_v5/compile_hef.sh
```

Reads the committed calibration pair and `artifacts/jevh_68m_v5_seq128.onnx`
(sha256 `7f78a56e9a692c6c83baf064b86219919a2d7f8870c9813a4ffae50d4a89e292`,
not in git). Writes `artifacts/hailo_compile_receipt.json`. Exit 0 only after
a HEF file is written. That is not a hardware pass: `hardware_tested` stays
false until a Hailo-10H run is measured. See `hailo/README.md`.

## Hard rules

No Pi deploy from this tree, no trades, no paid OpenRouter, no secrets, no
proprietary Hailo compiler binaries in git.

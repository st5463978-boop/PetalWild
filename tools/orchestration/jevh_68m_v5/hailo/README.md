# JEV-H 68M v5 on Hailo-10H

Compile target for the round-2 Ettin-68M student (PR #31). Choice, Noul, and
Score are one CLS logit with three prompt modes (`encode.build_input`), not
three weight matrices. The host softmaxes one logit per option.

This directory does not deploy to the Pi and does not replace the process on
port 8771.

## What was actually on disk

| Artifact | State |
|---|---|
| `artifacts/calib_input_ids.npy`, `calib_attention_mask.npy` | Present. 256 unique rows, seq 128, CLS 50281, PAD 50283 exactly where the mask is 0. Mask mean 0.382. Not noise. |
| `artifacts/jevh_68m_v5_seq128.onnx` | Not in git (`.gitignore`). Receipt sha256 `7f78a56e9a692c6c83baf064b86219919a2d7f8870c9813a4ffae50d4a89e292`, 277144914 bytes. |
| `artifacts/jevh_68m_v5_r2.pt` | Not in git. Required to re-export. |
| `hailo_sdk_client` | Not installed here. The wheel is proprietary and is not downloaded. |
| `/dev/hailo0` | Absent. No HEF was executed. |

`st5463978-boop/jev-h` (and issue #5) returned `Repository not found` / HTTP 404
for this environment, so `jev-h/scripts/compile_hef.sh` could not be read.
`compile_hef.sh` in this folder is the script that can run from the files that
are in PetalWild.

## Structure probe (not the student)

`compile_hef.sh` exports an untrained `Ettin68mScorer` when the student ONNX
is missing, checks the graph, and deletes the file. The run recorded in
`artifacts/hailo_compile_receipt.json` has no `Neg` and no `Gelu`. Operators:
Add, Cast, Concat, Constant, Div, Erf, Gather, Gemm, Identity, MatMul, Mul,
Pow, ReduceMean, Reshape, Slice, Softmax, Sqrt, Sub, Transpose. Inputs are
`input_ids` and `attention_mask`, both `[1, 128]` int64, and the mask is
consumed. That file was 277081047 bytes with sha256
`489dfd99199c313c7fc42efeabd76d371d84bfddcd5b9bb106857ed36806aff5`. Those
weights are `torch.manual_seed(0)` on an empty module. They are not
`7f78a56e…`, and they were not compiled.

## Why the previous graphs failed

The Clef-Flash port (DFC 5.4.0, `hw_arch=hailo10h`) recorded two facts this
student has to respect:

- Stock `rotate_half` (`cat(-x2, x1)`) crashes the ONNX fuser:
  `_handle_neg_feature_shuffle` / `group_sizes is None`. A swap plus a constant
  sign multiply parses. `model.py` now exports that form. The value matches
  the old rotate.
- Random calibration and a graph that never reads `attention_mask` are refused.
  The committed pair is checked for PAD/mask equality before `optimize`.

`F.gelu` is now `gelu_erf` (Mul / Add / Erf) so opset 17 cannot emit a `Gelu`
node. `Gelu` is in the trainer's forbidden-op set.

The community compiler at `l-nmch/hailo-10h-llm-compiler` is a different flow.
It targets generative HEFs (`__prefill` + `__tbt`, KV cache, hailo-ollama) on
DFC 5.3.0. Its eligibility screen is RMSNorm + RoPE + SwiGLU + GQA/MHA. It
says alternating local/global attention and fused QKV are unsupported. Ettin
is both: local window every non-multiple of 3, and one `Wqkv`. A Qwen3
checkpoint can enter that LLM flow; a Qwen3-1.7B DPO weight does not make an
Ettin classifier legal, and the project's own notes say hidden sizes at or
above 576 lose generation fidelity. Coherent hardware text was shown for a
25M model. Do not compile 68M v5, Ettin-17M, or the decision head through it.

## Candidate

68M v5 is the deployment candidate among the PetalWild students. It is the
live seq-128 Ettin shape, template-eval accuracy 0.886 on `jev_choice` (809
rows, from `RECEIPT.md`), and the only variant with a committed real
calibration pair. Ettin-17M is the latency floor (CPU p50 about 11 ms in that
PR) with a worse 2-way score and no committed ONNX. The 150M trainer is a
quality ceiling, not a 40 ms Hailo model. None of those numbers were
re-measured in this change. No HEF accuracy is claimed.

## Commands

```bash
./tools/orchestration/jevh_68m_v5/compile_hef.sh
```

Exit codes: 2 bad or missing calibration, 3 missing or unsafe ONNX, 4 DFC
missing or DFC error, 0 HEF bytes written. Exit 0 still sets
`hardware_tested` to false.

Re-export once `artifacts/jevh_68m_v5_r2.pt` is restored, from this directory,
with the training venv. Then rerun `compile_hef.sh` on an x86 machine that
already has DFC 5.4.0. Copy the HEF to the Pi over the LAN. Do not commit the
compiler wheel.

CPU fallback, loopback only, does not take port 8771:

```bash
PYTHONPATH=tools/orchestration/jevh_68m_v5 \
  python3 -m hailo.serve --port 8772
```

`GET /health` and `POST /v1/decide` with `question`, `options`, and optional
`qtype` (`choice`, `noul`, `score`) and `context`. If a HEF and `/dev/hailo0`
are both present, the request tries HailoRT and falls back to ONNX, naming
the backend in the JSON. Without the ONNX file the decide route returns 503.

Agreement gate, after a real HEF run has written index lists:

```bash
PYTHONPATH=tools/orchestration/jevh_68m_v5 \
  python3 -m hailo.parity --cpu-indexes cpu.json --hef-indexes hef.json
```

The floor is 0.99. A missing measurement is not a pass.

## Tests

```bash
cd tools/orchestration/jevh_68m_v5
PYTHONPATH=. python3 -m unittest hailo.test_pipeline -v
```

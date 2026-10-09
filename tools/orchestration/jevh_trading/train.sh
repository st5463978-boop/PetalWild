#!/usr/bin/env bash
# One command: venv, pinned deps, train, eval, ONNX export, receipt.
# Not financial advice. Offline research only. No HEF compile, no Pi deploy,
# no exchange/broker calls.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export PYTHONPATH="$(cd "$ROOT/.." && pwd)"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -U pip wheel
# CPU torch (no CUDA). Extra index is the official CPU wheel repo.
python -m pip install --index-url https://download.pytorch.org/whl/cpu \
  numpy==2.2.4 torch==2.7.1
python -m pip install tokenizers==0.21.1 onnx==1.17.0 onnxruntime==1.22.0
python -m jevh_trading "$@"
echo "[jevh-trading] done. See $ROOT/artifacts/RECEIPT.md and $ROOT/RECEIPT.md"

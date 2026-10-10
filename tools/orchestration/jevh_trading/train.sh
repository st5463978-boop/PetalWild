#!/usr/bin/env bash
# One command: ingest beebots jsonl, distill Jev, eval, static ONNX.
# Not financial advice. Offline research only. No HEF compile, no Pi deploy,
# no exchange/broker calls, no paid APIs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export PYTHONPATH="$(cd "$ROOT/.." && pwd)"
if ! python3 -c "import ensurepip" 2>/dev/null; then
  echo "python3 venv/ensurepip missing. On Ubuntu: sudo apt install python3.12-venv" >&2
  exit 1
fi
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -U pip wheel >/dev/null
# CPU torch (no CUDA). Extra index is the official CPU wheel repo.
python -m pip install --index-url https://download.pytorch.org/whl/cpu \
  numpy==2.2.4 torch==2.7.1
python -m pip install tokenizers==0.21.1 onnx==1.17.0 onnxruntime==1.22.0 \
  huggingface_hub==0.29.3 safetensors
python -m jevh_trading "$@"
echo "[jevh-trading] done. See $ROOT/artifacts/RECEIPT.md and $ROOT/RECEIPT.md"

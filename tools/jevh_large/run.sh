#!/usr/bin/env bash
# One command: create venv, pin-install, train JEV-H-large, export static ONNX.
set -euo pipefail
cd "$(dirname "$0")"
export TOKENIZERS_PARALLELISM=false
export HF_HOME="${HF_HOME:-$PWD/.hf_cache}"
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
fi
.venv/bin/pip install -U pip wheel
.venv/bin/pip install -r requirements.txt
exec .venv/bin/python train.py "$@"

#!/usr/bin/env bash
# JEV-H-68m-v5 one-command trainer. CPU only. No HEF, no deploy, no paid APIs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -U pip
  .venv/bin/pip install -r requirements.txt
fi
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
exec .venv/bin/python train.py "$@"

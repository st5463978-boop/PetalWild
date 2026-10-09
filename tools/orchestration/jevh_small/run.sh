#!/usr/bin/env bash
# One-command JEV-H-small trainer. CPU. No HEF, no Pi, no paid APIs.
set -euo pipefail
cd "$(dirname "$0")"
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -r requirements.txt
exec python train.py "$@"

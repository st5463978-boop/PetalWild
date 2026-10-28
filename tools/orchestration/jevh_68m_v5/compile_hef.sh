#!/usr/bin/env bash
# Compile the JEV-H 68M v5 student for Hailo-10H.
# Does not download the Dataflow Compiler, does not overwrite an existing HEF,
# and does not bind the live decide port.
set -euo pipefail
cd "$(dirname "$0")"
export PYTHONPATH="$(pwd)${PYTHONPATH:+:$PYTHONPATH}"
python3 -m hailo.compile_hef "$@"

#!/usr/bin/env bash
# Headless QA for the live garden. Does not run the Kenney grove tests/smoke.gd.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN="${PETALWILD_GODOT:-$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64}"
if [ ! -x "$BIN" ]; then
  BIN="$ROOT/tools/godot/Godot_v4.8-dev6_linux.x86_64"
fi
if [ ! -x "$BIN" ]; then
  echo "Godot 4.8-dev6 binary not found" >&2
  exit 1
fi
"$BIN" --headless --path "$ROOT" --import --quit
run_script() {
  local script="$1"
  local token="$2"
  local log
  log="$(mktemp)"
  if ! "$BIN" --headless --path "$ROOT" --script "$script" >"$log" 2>&1; then
    cat "$log"
    echo "FAIL $script" >&2
    exit 1
  fi
  if ! grep -q "$token" "$log"; then
    cat "$log"
    echo "missing $token from $script" >&2
    exit 1
  fi
  echo "$token"
  rm -f "$log"
}
run_script res://tools/smoke.gd PETAL_RULES_OK
run_script res://tests/test_systems.gd SYSTEMS_OK
run_script res://tests/test_integrate.gd PETAL_CONTRACTS_OK
echo "PETAL_QA_SCRIPTS_OK"
if [ "${PETAL_QA_GARDEN:-0}" = "1" ]; then
  export DISPLAY="${DISPLAY:-:1}"
  PETAL_INTEGRATE=1 "$ROOT/tools/run.sh" res://scenes/garden.tscn
fi

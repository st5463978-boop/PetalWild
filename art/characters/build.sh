#!/bin/sh
# CPU-only Blender build for veg villagers.
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
BIN="${BLENDER:-$HOME/.local/blender/blender-4.2.9-linux-x64/blender}"
if [ ! -x "$BIN" ]; then
  echo "Blender not found at $BIN" >&2
  exit 1
fi
SCRIPT="${1:-$ROOT/art/characters/build_carrot.py}"
if [ "$SCRIPT" = "$ROOT/art/characters/build_carrot.py" ] && [ -z "${2:-}" ]; then
  for folk in carrot tomato leek; do
    "$BIN" -b -P "$SCRIPT" -- "$folk"
  done
  exec "$BIN" -b -P "$ROOT/art/characters/build_human.py"
fi
exec "$BIN" -b -P "$SCRIPT" -- "${2:-}"

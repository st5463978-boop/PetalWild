#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -x "$ROOT/tools/godot/godot" ]]; then
  "$ROOT/tools/fetch_godot.sh"
fi
exec "$ROOT/tools/godot/godot" --path "$ROOT" --rendering-driver opengl3 "$@"

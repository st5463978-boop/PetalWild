#!/bin/sh
# Launch the pinned Godot 4.8-dev6 binary. See docs/ENGINE_VERSION.md.
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
BIN="${PETALWILD_GODOT:-$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64}"
if [ ! -x "$BIN" ]; then
  echo "Godot 4.8-dev6 binary not found at $BIN" >&2
  echo "Download Godot_v4.8-dev6_linux.x86_64.zip from the 4.8-dev6 release and do not substitute a later snapshot." >&2
  exit 1
fi
DRIVER="opengl3"
if [ "${PETAL_RENDER:-}" = "forward" ]; then
  DRIVER="vulkan"
fi
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "${XDG_RUNTIME_DIR}" ]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime}"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
fi
exec "$BIN" --path "$ROOT" --rendering-driver "$DRIVER" "$@"

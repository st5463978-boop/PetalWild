#!/bin/sh
GODOT="${GODOT:-$HOME/opt/godot/Godot_v4.8-dev6_linux.x86_64}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
exec "$GODOT" --path "$ROOT" "$@"

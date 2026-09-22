#!/usr/bin/env bash
# Pin: Godot 4.8.dev6 official 8898c2b3d
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/tools/godot"
URL="https://github.com/godotengine/godot-builds/releases/download/4.8-dev6/Godot_v4.8-dev6_linux.x86_64.zip"
SHA="d3678019d0a6501d754db36807110a02a1cfa24d49886be8d3a72d91faa80ca3"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
curl -L --fail --retry 3 -o "$TMP/godot.zip" "$URL"
echo "$SHA  $TMP/godot.zip" | sha256sum -c -
unzip -o "$TMP/godot.zip" -d "$DEST"
chmod +x "$DEST/Godot_v4.8-dev6_linux.x86_64"
ln -sfn "$DEST/Godot_v4.8-dev6_linux.x86_64" "$DEST/godot"
"$DEST/godot" --version

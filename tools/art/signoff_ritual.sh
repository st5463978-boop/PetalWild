#!/usr/bin/env bash
# Capture + score + compare sheet for the current HEAD. Tier (b): Compatibility / llvmpipe.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SHA="$(git rev-parse --short HEAD)"
OUT="${SIGNOFF_OUT:-/tmp/signoff/$SHA}"
PREV_SHA="${1:-}"
mkdir -p "$OUT" /opt/cursor/artifacts/signoff/"$SHA" docs/screenshots/compare
DISPLAY="${DISPLAY:-:1}" tools/run.sh -s res://tools/signoff_capture.gd -- --scene=res://scenes/garden.tscn --out="$OUT" --hour=16.5 --weather=clear
python3 docs/art/visual_target/signoff_check.py "$OUT" || true
THIS="$OUT/CAM_08_PHONE_PLAY.png"
if [[ -z "$PREV_SHA" ]]; then
  PREV_SHA="$(git log --pretty=%h -2 | tail -1)"
fi
PREV="/tmp/signoff/$PREV_SHA/CAM_08_PHONE_PLAY.png"
python3 tools/art/compare_sheet.py \
  docs/screenshots/petalwild_overview.png \
  "$THIS" \
  "$PREV" \
  docs/art/refs/petalwild_target_garden_02.png \
  --out "docs/screenshots/compare/${SHA}.png" || true
cp -a "$OUT"/. /opt/cursor/artifacts/signoff/"$SHA"/
cp -a "docs/screenshots/compare/${SHA}.png" /opt/cursor/artifacts/signoff/"$SHA"/compare.png 2>/dev/null || true
echo "SIGNOFF_DIR $OUT"

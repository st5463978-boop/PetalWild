#!/bin/sh
# Art-pass lint. Exit 1 on banned tokens. See docs/art/ASTRA_PLAN.md §8.
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
if grep -nE "sin\(|cos\(" shaders/terrain.gdshader shaders/bed_soil.gdshader 2>/dev/null; then
  echo "art_lint: procedural sin/cos on ground shaders" >&2
  exit 1
fi
if grep -rnE "Wild_Grass_Red|VP02_|VP03_|VP09_|VP18_|VP30_|havenbrook" scripts scenes shaders materials 2>/dev/null; then
  echo "art_lint: banned asset token" >&2
  exit 1
fi
if grep -rnE "act_label\s*=\s*true" scripts 2>/dev/null; then
  echo "art_lint: act_label forced on" >&2
  exit 1
fi
echo "PETAL_ART_LINT_OK"
exit 0

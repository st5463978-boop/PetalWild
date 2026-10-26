#!/usr/bin/env bash
# Headless M1 suite on the pinned Godot 4.8-dev6 binary.
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
BIN="${PETALWILD_GODOT:-$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64}"
if [ ! -x "$BIN" ]; then
  if [ -x "$ROOT/tools/godot/godot" ]; then
    BIN="$ROOT/tools/godot/godot"
  else
    echo "Godot 4.8-dev6 binary not found at $BIN" >&2
    exit 1
  fi
fi

run_script() {
  local script="$1"
  echo "== $script"
  "$BIN" --headless --path "$ROOT" --script "$script"
}

echo "== import"
"$BIN" --headless --path "$ROOT" --import --quit

run_script "res://tests/live/test_event_queue.gd"
run_script "res://tests/live/test_v1_save_migration.gd"
run_script "res://tests/live/test_jev_game_core.gd"
run_script "res://tests/live/test_service_field.gd"
run_script "res://tests/live/test_city_demand.gd"
run_script "res://tests/live/test_path_graph.gd"
run_script "res://tests/live/test_vc3_ecology.gd"
run_script "res://tests/live/test_overlays.gd"
run_script "res://tests/live/test_districts.gd"
run_script "res://tests/live/test_balance_soak.gd"
run_script "res://tests/live/test_art_manifest.gd"
run_script "res://tests/live/test_garden_scene.gd"
run_script "res://tests/live/test_vc11_menus.gd"
run_script "res://tests/live/test_vc12_carry.gd"
run_script "res://tests/live/test_grok_town.gd"
run_script "res://tools/smoke.gd"
run_script "res://tests/smoke.gd"

if [ "${PETAL_GARDEN_SMOKE:-}" = "1" ]; then
  echo "== garden smoke"
  if command -v xvfb-run >/dev/null 2>&1 && [ -z "${DISPLAY:-}" ]; then
    DISPLAY=:99 xvfb-run -a -s "-screen 0 1440x900x24" \
      env PETAL_SMOKE=1 "$BIN" --path "$ROOT" --rendering-driver opengl3 res://scenes/garden.tscn
  else
    PETAL_SMOKE=1 "$BIN" --path "$ROOT" --rendering-driver opengl3 res://scenes/garden.tscn
  fi
fi

echo "ALL OK"

# PETAL-01 Foundation / Garden

Updated 2026-09-27. Pass 2.

| | |
| --- | --- |
| Lane | PETAL-01 |
| Branch | `petal/01-foundation` |
| Baseline | `cursor/dpo-cpu-decide-9cb0` @ `f96457e` (tag `petal-campaign-baseline-20260927`) |
| Task | Stable playable foundation: boot, garden, camera, clickable face, save/load, time, events, smokes |

## Census

Extend, do not recreate. The Hedge Hollow garden (`scenes/garden.tscn`, `scripts/game/garden.gd`) is the running scene. The grove sim under `scripts/sim/` and `scripts/main.gd` is sidelined.

| Subsystem | Status | Notes |
| --- | --- | --- |
| Godot project / boot | COMPLETE | Title `scenes/main.tscn` → garden. Autoloads Clock, Economy, Trust, SaveGame, Settings, ContentDB, SimLod, PetalDecide |
| Core scenes | COMPLETE | `main.tscn`, `garden.tscn` |
| Player / camera | COMPLETE | `GardenCamera` orbit, pan, zoom, WASD |
| Garden scene | COMPLETE | Playable Hedge Hollow; do not rewrite ecology, genetics, shop, road |
| Interaction | REPAIRED | Tools, grab/throw, people click were in. Face was visual only. Click a jelly face to inspect. Space rests time (was documented, missing) |
| Placement | COMPLETE | Till, plant, water, feed, tend, scoop, home kit |
| Save / load | REPAIRED | Slots 1–3, F5/F9. Harvest `crate_yields` now round-trip |
| UI foundations | REPAIRED | HUD, journal, stall, pause. New inspect card on a face click |
| Time / state | COMPLETE | Clock autoload; Space toggles `Clock.running` without the pause menu |
| Events / messages | REPAIRED | Toast log kept. `GardenBus` notes inspect/save/load/time |
| Debug | COMPLETE | F3 overlay now names the inspected face |
| Smokes | REPAIRED | Grove `tests/smoke.gd` had a 4.8 `:=` Variant parse error. New `tests/test_foundation.gd`. Garden smoke covers face, yield reload, time rest |

## Player-facing this round

- Click a creature's face: it winks, looks back, the camera closes in, and a card shows mood and bond. Esc lets go.
- Space rests or moves garden time.
- Harvest yields survive F5/F9.
- Hover over a face reads `Bellhelp's face · click`.
- Click again while they are hungry beside ripe food: you share that bed.

## Paths

- `scripts/core/garden_bus.gd`
- `scripts/creatures/jelly.gd`
- `scripts/game/garden.gd`
- `scripts/ui/hud.gd`
- `tests/test_foundation.gd`
- `tests/smoke.gd`
- `README.md`

## Interface

- `Jelly.inspect_face()` / `clear_inspect()` / `poke()` / `face_point()` / `snack()`
- `Garden._inspect_face()` — any tool, before bed tools. A second click shares ripe food.
- `GardenBus.note(kind, text)`
- Save payload key `crate_yields`

## Tests

| Check | Result |
| --- | --- |
| `tests/test_foundation.gd` | `FOUNDATION_OK` |
| `tests/smoke.gd` | `SMOKE OK` |
| `tests/test_systems.gd` | `SYSTEMS_OK` |
| `tools/smoke.gd` | `PETAL_RULES_OK` |
| `PETAL_SMOKE=1` garden | `PETAL_SMOKE_OK` (face, yield reload, time rest) |
| `PETAL_CAPTURE=1` | `PETAL_CAPTURE_OK` (llvmpipe). Did **not** commit overwritten `wave1_overview` / jelly / night plates |
| `PETAL_FACE_SHOT=1` | `PETAL_FACE_SHOT_OK` → `docs/screenshots/wave1_face.png` |

Qwen3-VL is not operational in this repo (no assessor). Visual QA is the capture loop plus reading the face frame.

Face frame evidence: inspect card shows Bellhelp, mood happy, bond 12%, Visitor. The body sits under the stall roof in this llvmpipe angle; the card is the player-facing proof. PETAL-05 owns dressing density.

## Pass 2

Merged `petal/08-integration` @ `3402530` so this lane builds on the seven-lane garden.

Highest-value garden-rung work:

1. **Inspect card names the garden.** Hunger, food plant, habitat, and the bed they stand on. A second click shares ripe food when they are empty enough.
2. **Share a snack.** Visitor or resident. Uses the existing bite soil write (`growth` 0.55, `eaten_by`, `bite_wait`). Connects inspect (01) to ecology feeding (02).
3. **Rest names the hour, and the face shot stands on a meadow bed** instead of under the stall.

| Check | Result |
| --- | --- |
| `tests/test_foundation.gd` | `FOUNDATION_OK` (bus snack note, `Jelly.snack()` fills hunger) |
| `tools/petal_qa.sh` | `PETAL_RULES_OK` `SYSTEMS_OK` `PETAL_CONTRACTS_OK` `FOUNDATION_OK` `JELLY_FEEL_OK` `RESIDENT_LIFE_OK` `TOWN_OK` `REGION_OK` `PETAL_QA_SCRIPTS_OK` |
| `PETAL_SMOKE=1` garden | `PETAL_SMOKE_OK` (card fields + snack share). Leaks match baseline: 3 CanvasItem, 6 ObjectDB |
| `PETAL_INTEGRATE=1` | `PETAL_INTEGRATE_OK` |
| `PETAL_FACE_SHOT=1` | `PETAL_FACE_SHOT_OK` → `docs/screenshots/wave1_face.png` |

Qwen3-VL is not operational here; the face frame was read directly. The card shows Bellhelp, mood hungry, bond 12%, Hunger 22% wants Meadowbell, Meadow on the Meadowbell, Visitor, Click again to share the Meadowbell. The body is a cream-green blob in the meadow foliage in this llvmpipe angle; the card is the player-facing proof. One placement change (stall → meadow bed). No further camera variants.

## Requests

- PETAL-03: keep the face pickable if Bellhelp mesh changes.
- PETAL-07: inspect card is a left HUD panel; restyle if the HUD is rewritten.
- PETAL-08: `crate_yields` is now in the save; shop price still reads it.
- Do not rewrite `scripts/game/garden.gd` ecology, road, or shop loops from this lane.

## Blockers

None.

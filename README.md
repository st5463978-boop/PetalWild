# PetalWild

PetalWild is a garden-scale living world. You till, plant, water, and fertilise a small grove. Plants change who visits. Grokbot jellies can be picked up, squeezed, and thrown. Veg people keep a stall. The town beyond the hedge is named and not built yet.

The art target is the dense sunlit garden in `docs/reference/`. The current scene is a playable step toward that, and `docs/VISUAL_GAP.md` says what is still wrong.

## Run

Install the pinned editor binary and no other Godot snapshot. Details are in `docs/ENGINE_VERSION.md`.

```bash
chmod +x tools/run.sh
./tools/run.sh
```

Headless QA (live garden). `tests/smoke.gd` is the sidelined Kenney grove and does not match live catalogs.

```bash
chmod +x tools/petal_qa.sh
./tools/petal_qa.sh
```

Tokens: `PETAL_RULES_OK`, `SYSTEMS_OK`, `PETAL_CONTRACTS_OK`. Garden east-chain smoke is still `DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn` (`PETAL_SMOKE_OK`). Cross-lane save/shop/settle/self-play: `PETAL_INTEGRATE=1 tools/run.sh res://scenes/garden.tscn` (`PETAL_INTEGRATE_OK`). F8 or F3 → Self-play beat plants a Meadowbell on an empty bed.

Screenshot and quit (needs a display):

```bash
PETALWILD_SHOT=overview ./tools/run.sh
```

Modes: `overview`, `golden`, `creature`, `person`, `shop`, `night`, `rain`.

## Play

1 till, 2 seed, 3 water, 4 fertilise, 5 tend, 6 pond, 7 home kit. R cycles the seed or the home prop. Right-drag orbits. Scroll zooms. WASD pans. Click a jelly and drag to pet or throw. E opens the stall. J journal, M map, C town, P photo, Space pauses time, F5 saves, F9 loads, F3 debug, F8 self-play beat (plants a Meadowbell on an empty bed).

The scenic pond west of the hedge is not a gameplay pond. Ribbon wants pond plots you scoop yourself.

## Studio tools

`tools/orchestration/` is a local Hailo router for development. It is not in the game. On this machine the NPU was absent, so the service escalates instead of guessing. See `tools/orchestration/README.md`.

## State

`docs/PETALWILD_MASTER_STATE.md`

A second scene, `scenes/garden.tscn`, came in from a parallel build called Hedge Hollow. It is not the scene `tools/run.sh` launches.

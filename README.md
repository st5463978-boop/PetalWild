# PetalWild

PetalWild is a garden-scale living world. You till, plant, water, and fertilise a small grove. Plants change who visits. Grokbot jellies can be picked up, squeezed, and thrown. Veg people keep a stall. The town beyond the hedge is named and not built yet.

The art target is the dense sunlit garden in `docs/reference/`. The current scene is a playable step toward that, and `docs/VISUAL_GAP.md` says what is still wrong.

## Run

Install the pinned editor binary and no other Godot snapshot. Details are in `docs/ENGINE_VERSION.md`.

```bash
chmod +x tools/run.sh
./tools/run.sh
```

Headless smoke:

```bash
"$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64" --headless --path . --script res://tests/smoke.gd
```

Screenshot and quit (needs a display):

```bash
PETALWILD_SHOT=overview ./tools/run.sh
```

Modes: `overview`, `golden`, `creature`, `person`, `shop`, `night`, `rain`.

## Play

1 till, 2 seed, 3 water, 4 fertilise, 5 tend, 6 pond, 7 home kit. R cycles the seed or the home prop. Right-drag orbits. Scroll zooms. WASD pans. Click a jelly and drag to pet or throw. E opens the stall. J journal, M map, C town, P photo, Space pauses time, F5 saves, F9 loads, F3 debug.

The scenic pond west of the hedge is not a gameplay pond. Ribbon wants pond plots you scoop yourself.

## Studio tools

`tools/orchestration/` is a local Hailo router for development. It is not in the game. On this machine the NPU was absent, so the service escalates instead of guessing. See `tools/orchestration/README.md`.

## State

`docs/PETALWILD_MASTER_STATE.md`

A second scene, `scenes/garden.tscn`, came in from a parallel build called Hedge Hollow. It is not the scene `tools/run.sh` launches.

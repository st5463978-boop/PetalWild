# PetalWild master state

Date: 2026-09-22

## Active build

Branch: `main`

Engine: Godot `4.8.dev6.official.8898c2b3d` (see `docs/ENGINE_VERSION.md`)

Renderer: GL Compatibility, Mesa llvmpipe, shadows off

Smoke: `tests/smoke.gd` prints `SMOKE OK`

Shots: `docs/screenshots/petalwild_overview.png`, `creature`, `person`, `shop`, `night`, `rain`

## Working

- New game, three save slots, versioned JSON under `user://petalwild/`
- Till, plant, water, fertilise, tend, pond scoop, home kit
- Sunpetal, petal corn, mossbell, nightbloom data
- Nine grokbot jellies with visit and settle requirements
- Cara present; Mia, Pod, Bran, Oshi gated
- Petal Stall buy and sell
- Grab, pet, throw, mood
- Journal, map, town panel, debug keys, photo mode
- Clock, weather, seasons
- Oshi proposal writes an audit row and does not spend coins or leave the simulation
- CC0 Kenney nature kit, foliage, mini forest, interface sounds; CC0 Poly Haven 1K grounds; CC0 forest ambience

## Broken or still placeholder

- Visual target not met. See `docs/VISUAL_GAP.md`
- Forest ambience file is not wired into the bed yet
- City venues other than the stall are listed as not built
- L3 and L4 simulation are records only
- No real-world action is implemented, by design
- ALSA has no sound card here; audio falls back to the dummy driver

## Agents

This integration run: `bc-1310adff-2802-4fa6-b870-0aed28cc5bfd`

Asset hunt: [CC0 asset hunt](bc-92f7cabe-42c3-5c56-98d9-6433f0c29b4c) wrote `docs/research/ASSET_HUNT.md` and `assets/third_party/`

Licence notes: [Reference licence notes](bc-e253eec1-0242-5c0e-93d7-c6a3a1fc95dc) wrote `docs/research/REFERENCES.md`

Other executives were visible on the same remote earlier in the session. They are not this tree. Do not assume their commits are merged.

## Hailo foreman

`tools/orchestration/` is local development routing. It is not in the game.

Probe result: `no_hailo_device`. Selected router model: none. 174 gold tasks are ready. Invalid model output escalates to Grok. See `tools/orchestration/MODEL_SELECTION.md`.

## Higgsfield

Spent this wave: 0

Balance read 2026-09-22: 367.46 credits, plan pro

## Performance

No populated FPS counter was captured beyond the llvmpipe shots. Overview capture completed in a few seconds at 1440×900. Treat that as a load time, not a frame budget. Shadows stay off on this adapter.

## Next integration

1. Hedge rooms, stone paths, and ground cover so the terrace stops reading as a grid
2. Authored silhouettes for Cara and Sunburst
3. Wire the CC0 forest loop
4. Re-run the Hailo benchmark on a machine that actually has the NPU

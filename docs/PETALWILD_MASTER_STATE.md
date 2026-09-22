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

`cursor/opening-grove-parallel-a334` is a second grove branch from before this tree was on `main`. It is not the scene this build runs.

Other executives were visible on the same remote earlier in the session. Do not assume a push is merged until it is on `main`.

## Hailo foreman

`tools/orchestration/` is local development routing. It is not in the game.

Probe result: `no_hailo_device`. Selected router model: none. 174 gold tasks are ready. Invalid model output escalates to Grok. See `tools/orchestration/MODEL_SELECTION.md`.

## Parallel Hedge Hollow tree

`scenes/garden.tscn` and `scripts/world/dressing.gd` are the other playable grove. A follow-up on that scene raised the outer hedge and boxed the beds. It was aimed at Forward Plus and uses different resident names. The running scene stays `scenes/main.tscn` (GL Compatibility, Cara, the salvaged species list) because this machine has no Vulkan device. The CC0 Asset Quest demo in `third_party/incoming/` and the Inter font stay in the tree. They are not required by the running loop.

## Higgsfield

Spent this wave: 0

Balance read 2026-09-22: 367.46 credits, plan pro

Compared `docs/screenshots/wave1_overview.png`, `wave1_jelly.png`, and `wave1_lumen.png` with `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`.

The outer hedge is taller. A lower hedge boxes the four beds, with gaps on the paths. CC0 flowers and grass sit along that wall. Bellhelp’s close-up is a lathed bell with two rings of petals. Lumen has a stacked leek stalk, a leaf crown, an apron, and a satchel. `PETAL_SMOKE_OK` still passes.

Three largest gaps still open:

1. **Hedge surface.** The walls are one smooth shader tube. The concepts are leafy and uneven. PETAL-05 and PETAL-06: break that silhouette and keep this palette.
2. **Bellhelp’s face.** The petals read, and the core is still a glossy lathe with the eyes off the surface. PETAL-03: seat the face on the bell and curl the petals.
3. **Lumen’s hands and the lawn.** The leaf crown is there. The body is still capsules, there is no seed tray, and the ground inside the rooms is one plane. PETAL-04 for the face, hands, and tray. PETAL-06 for ground cover and sun shafts.

## Next integration

Keep this build playable. The next pass stays inside the running garden scene, then recaptures the six shots. Do not open a side demo.

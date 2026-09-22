# PetalWild master state

Updated 2026-09-22 after wave 1 capture and smoke.

## Active build

| | |
| --- | --- |
| Branch | `main` |
| Engine | Godot `4.8.dev6.official.8898c2b3d` (4.8-dev6). See `docs/ENGINE_VERSION.md` |
| Scene | `res://scenes/main.tscn` → garden |
| Save | Version 1, `user://saves/slot_N.json` |
| Smoke | `PETAL_SMOKE_OK` and `PETAL_RULES_OK` on this tree |
| Latest shots | `docs/screenshots/wave1_overview.png`, `wave1_jelly.png`, `wave1_lumen.png`, `wave1_stall.png`, `wave1_journal.png`, `wave1_night.png` |

This machine has no Vulkan surface. Godot falls back to OpenGL 3 / llvmpipe. Audio falls back to the dummy driver. Screenshots still save. FPS on a real GPU has not been measured.

## Working

- Title, three slots, settings, licence reader, pause.
- Orbit camera, tool row, journal, stall, trust page, F3 debug.
- Soil till, plant, water, fertilise, tend, pond scoop, home kit.
- Clock (6 game-minutes per real second), golden / mist / rain / night.
- Data-driven plants and nine jelly species. Bellhelp arrives for 3 mature Meadowbells.
- Chain continues through Bulrush, Reedic, Cirlark, Dusknip night-loam, Pegapear, Gushorn.
- Grab, drop, and throw on the jelly spring body. Mood and bond change.
- Lumen Peel, Bram Cobble, and Nessa Pod (Nessa waits for a resident Bellhelp and a home kit).
- Petal coins. Fertiliser purchase spends coins. Peach-tray proposal spends 8 only after approval, once a day.
- Save and reload round-trip coins and garden state.
- Procedural wind, pad, UI, squish, and harvest tones. No third-party audio.
- Sim LOD counters. Trust levels named 0–5. Only 0 and 1 can happen, and both stay in the game.

## Broken or not built

- The garden does not yet look like the concept plates. See the gap list below.
- Bellhelp is a lathed bell with cupped petals that curl back, a dark throat, and a seed. It still is not an authored sculpt.
- Lumen has a leek crown, apron, spectacles, satchel, and a seed tray. The body is still capsules.
- Hedge walls are three overlapping shoulders with clumps and a leaf-card fringe. Daylight adds a few additive shafts. There is still no insect or bird life.
- City, venues, and the agent civilisation are a single parish record (`data/district.json`, Hedge Hollow, phase A).
- Tiers 3 and 4 of the simulation are specified, not simulated.
- Trust cannot research, draft, or act outside the process.
- Large-text setting applies on the title screen, not live in the garden HUD.
- The sidelined Kenney grove (`scripts/presentation/`) now plays the CC0 forest loop. The running scene still uses procedural tones. This VM has no sound card.

## Agents

No parallel workers are running. A second wave committed to `main` during this integration (`c140089`). Its scripts stay in `game/` behind `.gdignore`. The running scene is still `res://scenes/main.tscn`. Ownership for the next wave is in `docs/AGENT_CONTRACTS.md`.

## Branches and merges

`main` is the playable Hedge Hollow scene: Forward+, Bellhelp, Lumen Peel, the stall, and the hedge rooms. A second grove import (Sunpetal, Cara, Kenney CC0 files, `scripts/presentation/`, `scripts/sim/`) is in the tree and is not the running scene. `cursor/opening-grove-parallel-a334` is an earlier side grove and is not compiled. See `docs/RECOVERY_MATRIX.md`.

## Assets and licences

Inter 4.1 (OFL) is the UI font. The Asset Quest Stylized Garden demo (CC0) is placed as flowers, grass, a bench, a planter, a table, and an umbrella. Nunito (OFL) is in `third_party/fonts/` and is not the live UI font. Ledger: `ASSET_PROVENANCE.md`, `THIRD_PARTY_NOTICES.md`, `docs/LICENSE_MATRIX.md`. Hunt list: `docs/ASSET_HUNT.md` and `docs/research/ASSET_HUNT.md`.

## Higgsfield

Spent: 0. Remaining on the connected account: **367.46** (pro). Catalog check recorded in `docs/HIGGSFIELD_LEDGER.md`. No generation has been approved.

## Visual compare

Compared `docs/screenshots/wave1_overview.png`, `wave1_jelly.png`, and `wave1_lumen.png` with `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`.

The hedge is three overlapping shoulders with clumps, a rising top, and a leaf-card fringe. Lawn tufts sit on the open grass. The stall bench, planter, table, and umbrella use the CC0 prop atlas. Bellhelp’s petals curl back from a dark throat, with a seed. Lumen carries a seed tray. A few warm additive shafts show in daylight. `PETAL_SMOKE_OK` still passes.

Three largest gaps still open:

1. **Hedge surface.** Shoulders and clumps break the tube. The crown is still shaded volumes, not a clipped leafy hedge. PETAL-05 and PETAL-06: keep this green and cover the spheres with leaves.
2. **Creature sculpt.** The petals curl. The body is still a lathe. PETAL-03: a rib on the petal, and a body that is not a turned solid.
3. **Cast and light.** The shafts are thin additive beams. Lumen’s body is still capsules and the hands are tiny spheres. PETAL-04 for hands. PETAL-06 for light that falls through the hedge.

## Next integration

Keep this build playable. The next pass stays inside `scenes/main.tscn` (Hedge Hollow): a leafier hedge crown, a ribbed petal, and hands that read as hands. Do not open a side demo. The Kenney/Cara grove in `scripts/presentation/` is not the running scene.

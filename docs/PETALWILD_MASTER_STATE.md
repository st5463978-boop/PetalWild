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
- Bellhelp’s five sphere lobes are gone. The body is a low pad, five standing petals, and the skirt. The close-up is on open lawn, the cup reads, and the shader is matte. The center is a small gold sphere with emission off.
- Lumen’s stalk is one fluted taper, cream at the base and green at the crown. The raised hand holds a seed tray. Each hand is a palm with three fingers and a thumb.
- The far hedge has three sky notches, with the hill cut behind each one. The crests between them are broken: overview row 280 is about 71% sky and 27% hedge. The body of each mound is still a solid leafy wall. The north backdrop trees are shorter. Paths are dark dirt with flagstones. Blooms are rose and no longer fade toward white. About 0.88% of overview pixels are still pure white. There is still no insect or bird life.
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

The north backdrop trees are shorter than the hedge. The far wall has three openings onto the pale sky, and the crests between them are broken: overview row 280 is about 71% sky and 27% hedge. The body under those crests is still a solid leafy wall. Bellhelp’s sphere lobes are gone; the close-up is on open lawn and the body reads as a matte green cup with a small gold center and no emission. Paths are flagstones on dark dirt. Lumen’s stalk is one fluted taper, and the raised hand holds the seed tray. `PETAL_SMOKE_OK`, `PETAL_RULES_OK`, and `PETAL_CAPTURE_OK` passed on this tree. Shots are the six `wave1_*.png` files.

Three largest gaps still open, against `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`:

1. **Hedge skyline.** The crest is broken and the notches show sky. The body of each mound is still a solid leafy wall. PETAL-05.
2. **Bellhelp.** The cup reads, the surface is matte, and the center no longer glows. The silhouette is still a simple cup. PETAL-03.
3. **Highlights.** About 0.88% of overview pixels are still pure white. PETAL-06.

## Next integration

Keep this build playable. The next pass stays inside `scenes/main.tscn` (Hedge Hollow): thin the solid hedge body so the broken crest reads as a leaf canopy, and find the remaining pure-white cluster. Do not open a side demo. The Kenney/Cara grove in `scripts/presentation/` is not the running scene.

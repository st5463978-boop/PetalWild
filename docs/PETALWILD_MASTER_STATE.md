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
- Bellhelp’s five sphere lobes are gone. Five narrow petals run from the tips down to a small pad, with a dark five-petal well, a gold seed, a wider flared whorl, a lower rim, five gap tips past the lobes, a darker band, and a wide short rank inside the tips. The wide skirt of spheres is gone.
- Lumen’s stalk is one fluted taper, cream at the base and green at the crown. The raised hand holds a seed tray. Each hand is a palm with three fingers and a thumb.
- Crest leaf cards are 0.4 scale, and the far hedge keeps one 2.5 m tuft in four. A dark shrub row stands just behind that wall, taller at the east end. Light-green in the upper opening band fell from 53% to 24%, and in the lower band from 36% to 13%. The hill did not move. The stall still shows through the middle. The north backdrop trees are shorter. Paths are dark dirt with darker flagstones. Blooms are rose. StandardMaterial specular is off. The bench and planter are darkened, and bright plant-atlas texels are capped. About 0.024% of overview pixels are pure white. There is still no insect or bird life.
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

The north backdrop trees are shorter than the hedge. Crest leaf cards are 0.4 scale, and the far hedge keeps one 2.5 m tuft in four. A dark shrub row stands just behind that wall, taller at the east end. Light-green pixels fell from 53% to 24% in the upper opening band (screen y 265–320) and from 36% to 13% in the lower band (y 290–360). East-lip luminance (y 252–272) fell from 200 to 162. The hill (y 200–245) did not change. Bellhelp’s close-up is on open lawn: five narrow lobes, a dark five-petal well, a gold seed, a wider flared whorl, a lower rim, five gap tips past the lobes, a darker band, and a wide short rank inside the tips. The bench and planter use a dark multiply, and bright plant-atlas texels are capped. Pure white on this overview is 0.024% (310 pixels). Paths are flagstones on dark dirt. Lumen’s stalk is one fluted taper, and the raised hand holds the seed tray. `PETAL_SMOKE_OK`, `PETAL_RULES_OK`, and `PETAL_CAPTURE_OK` passed on this tree. Shots are the six `wave1_*.png` files.

Three largest gaps still open, against `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`:

1. **Hedge skyline.** The shrub row covers the lower holes and the east lip is darker. About 24% of the upper band is still light-green, and the stall still reads through the middle. The hill above the hedge is unchanged. PETAL-05.
2. **Bellhelp.** Ten tips, a short rank inside them, a darker band, and a wider skirt. The dark throat is still the center. PETAL-03.
3. **Highlights.** 0.024% of overview pixels are pure white. The bench cluster and the south tip are gone. The largest speck left is a pink tip around screen x 258, y 465. PETAL-06.

## Next integration

Keep this build playable. The next pass stays inside `scenes/main.tscn` (Hedge Hollow): a pink tip around screen x 258, y 465 is still pure white. Do not fill Bellhelp’s dark throat, and do not raise the east shrubs into the hill. Do not open a side demo. The Kenney/Cara grove in `scripts/presentation/` is not the running scene.

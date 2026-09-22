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
- Bellhelp’s blossom still reads as one glossy sphere in the close shot.
- Veg People are readable primitives, not an authored cast.
- No hedge rooms, no sun shafts, no insect or bird life.
- City, venues, and the agent civilisation are a single parish record (`data/district.json`, Hedge Hollow, phase A).
- Tiers 3 and 4 of the simulation are specified, not simulated.
- Trust cannot research, draft, or act outside the process.
- No CC0 environment pack imported yet.
- Large-text setting applies on the title screen, not live in the garden HUD.
- Smoke quits during `_ready` and leaks a handful of canvas items. The check itself passes.

## Agents

No parallel workers are running. A second wave committed to `main` during this integration (`c140089`). Its scripts stay in `game/` behind `.gdignore`. The running scene is still `res://scenes/main.tscn`. Ownership for the next wave is in `docs/AGENT_CONTRACTS.md`.

## Branches and merges

`main` only. Nothing is waiting to merge. The lost Garden Grove tree was not recoverable. See `docs/RECOVERY_MATRIX.md`.

## Assets and licences

Inter 4.1 (OFL) is the UI font. Nunito (OFL) and the Asset Quest Stylized Garden demo (CC0) arrived with the parallel commit and are staged, not yet the garden's look. Ledger: `ASSET_PROVENANCE.md`, `THIRD_PARTY_NOTICES.md`, `docs/LICENSE_MATRIX.md`. Hunt list: `docs/ASSET_HUNT.md` and `docs/research/ASSET_HUNT.md`.

## Higgsfield

Spent: 0. Remaining on the connected account: **367.46** (pro). Catalog check recorded in `docs/HIGGSFIELD_LEDGER.md`. No generation has been approved.

## Visual compare

Compared `docs/screenshots/wave1_overview.png` with `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`.

The shot now looks over a trimmed hedge into four beds, a pond, a stall, and cone trees. Night lanterns read. That is as far as this wave goes.

Three largest gaps, and who has them next:

1. **Creatures.** The close-up is still a glossy ball. PETAL-03 and PETAL-06: authored blossom mesh, seed eyes on the surface, internal structure in the jelly shader.
2. **Cast.** Lumen is a capsule, an apron, and spectacles. PETAL-04: leek, beet, and pea silhouettes with faces, clothes, and a stance.
3. **Interior density.** CC0 poppies, cornflowers, and a sunflower now sit in the beds, on the Asset Quest atlas. The lawn between them is still one green plane, the bench and planter are flat-coloured, and there are no hedge rooms or sun shafts. PETAL-05 and PETAL-06 continue this, using more of the same CC0 pack only where the scale and palette already match.

## Next integration

Keep this build playable. Next wave should land one of the three gaps into `scripts/game/garden.gd`’s existing scene, then recapture the six shots and name the new three gaps. Do not open a side demo.

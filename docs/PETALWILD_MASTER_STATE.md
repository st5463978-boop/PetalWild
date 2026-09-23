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
| Latest shots | `docs/screenshots/wave1_overview.png`, `wave1_jelly.png`, `wave1_lumen.png`, `wave1_stall.png`, `wave1_journal.png`, `wave1_night.png`, `wave1_pond.png` |

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
- Slobad's CC0 forest loop is the garden bed. Tool sounds stay procedural. Eight bees drift over the beds and sit on the flowers in the rain. Four birds cross the garden by day and perch at dusk and in the rain. The parish page counts both.
- Large text resizes the garden HUD without leaving the scene.
- Sim LOD counters. Trust levels named 0–5. Only 0 and 1 can happen, and both stay in the game.
- Off-screen jellies hide. A resident walks to the nearest placed home kit. A visitor keeps the flower. Back in frame, the body shows again.
- By day Lumen keeps the stall, Bram walks the plots, and Nessa watches the gate. After dusk they walk home. The directory says which. Ask Bram and he walks the driest tilled bed and waters it. The potting shed is open. Its demand is 1 while he is here. The hedge tea house stands on the south lawn. Its demand is 1 while Nessa is here, and her day round stops at the porch. The research hut stands on the south lawn, west of the tea house. She walks there to file parish notes, nothing leaves the garden, and its demand is 1 once those notes are filed. When a creature arrives and Nessa is here, she walks to them and writes the name in the parish book. The journal hides a species name until that creature is sighted. A species that has already visited comes back as a repeat, and the journal says they are back again. Scooping the bank widens the pond, and the new shore sits on the ground. Bulrush wades in once that water and three mature reeds are there. Once Bulrush is a visitor and the beds are wet, Reedic follows. Fertility is the tilled beds, so feeding them counts. Two mature brambles bring Berrypatch, and a third plus those fed beds bring Grapling. A resident Bellhelp brings Cirlark. Dusknip follows a visiting Bellhelp and, once it settles, leaves night-loam, which unwraps the nightlantern seed. A ripe peach and a nightlantern in the evening rain bring Pegapear. Night-loam, two mosspears, and those fed beds bring Gushorn. A planted meadowbell is three bells on a leaf pad, and every crop sits in a ring of eight leaves.

## Broken or not built

- The garden does not yet look like the concept plates. See the gap list below.
- Bellhelp’s five sphere lobes are gone. Five narrow petals run from the tips down to a small pad, with a dark five-petal well, a gold seed, a wider flared whorl, a lower rim, five gap tips past the lobes, a darker band, and a wide short rank inside the tips. The wide skirt of spheres is gone.
- Lumen’s stalk is one fluted taper, cream at the base and green at the crown. The raised hand holds a seed tray. Each hand is a palm with three fingers and a thumb.
- Crest leaf cards are 0.4 scale, and the far hedge keeps one 2.5 m tuft in four. A dark shrub row stands just behind that wall, taller at the east end. Light-green in the upper opening band fell from 53% to 24%, and in the lower band from 36% to 13%. The hill did not move. The stall still shows through the middle. The bright blue in that opening was the awning cloth. That stripe is darker now, about (171, 171, 173), and the sky-blue detector on the overview is 0. The shrub row behind the wall was the pale green in the upper band. That check now covers 1.2%, down from 3.5%. The crest leaf cards and the far trees were the side-opening pale pixels. The north backdrop trees are shorter. Paths are dark dirt with darker flagstones. Blooms are rose. StandardMaterial specular is off. The bench and planter are darkened, bright plant-atlas texels are capped, and the lantern glass is amber. The pink disk by the south-west rail, the untilled grass-plot tops, the meadowbell petals, the mauve bed, the resident hands, the light flagstones, the path dirt, and the loose stones are darkened. Overview pixels at pure white are 0. Eight bees drift over the beds. Four birds cross the garden by day and perch at dusk and in the rain.
- City, venues, and the agent civilisation are a single parish record (`data/district.json`, Hedge Hollow, phase A).
- On-screen jellies stay at district fidelity or nearer. The directory shows each resident's home and job. The parish page lists venues. Petal Stall, the potting shed, the hedge tea house, and the research hut are open. Every other room is not built, and demand for those rooms is not simulated. Petal Stall demand is the people present plus creature residents.
- Trust cannot research, draft, or act outside the process.
- The running garden and the sidelined Kenney grove both play the CC0 forest loop when the mp3 loads. Tool sounds stay procedural. This VM has no sound card.

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

The north backdrop trees are shorter than the hedge. Crest leaf cards are 0.4 scale, and the far hedge keeps one 2.5 m tuft in four. A dark shrub row stands just behind that wall, taller at the east end. Light-green pixels fell from 53% to 24% in the upper opening band (screen y 265–320) and from 36% to 13% in the lower band (y 290–360). East-lip luminance (y 252–272) fell from 200 to 162. The hill (y 200–245) did not change. Bellhelp’s close-up is on open lawn: five narrow lobes, a dark five-petal well, a gold seed, a wider flared whorl, a lower rim, five gap tips past the lobes, a darker band, and a wide short rank inside the tips. The bench and planter use a dark multiply, bright plant-atlas texels are capped, and the lantern glass is amber. The pink disk by the south-west rail, the untilled grass-plot tops, the meadowbell petals, the mauve bed, the resident hands, the light flagstones, the path dirt, and the loose stones are darkened. Pure white on this overview is 0. The stall awning’s bright blue was cloth, now about (171, 171, 173), and the sky-blue detector is 0. The shrub row behind the wall no longer reads as pale green; that upper-band check is 1.2%. On the previous shot that check was 1.17% and the hill mean was (212.9, 224.4, 147.6). With the hedge tea house in the lower left, this shot is 1.30% and the hill mean is (212.0, 223.6, 146.4). A planted meadowbell is three bells on a leaf pad, and every crop sits in a ring of eight leaves. Eight bees drift over the beds. Four birds cross the garden by day and perch at dusk and in the rain. Paths are flagstones on dark dirt. Lumen’s stalk is one fluted taper, and the raised hand holds the seed tray. `PETAL_SMOKE_OK`, `PETAL_RULES_OK`, and `PETAL_CAPTURE_OK` passed on this tree. Shots are the six `wave1_*.png` files.

Three largest gaps still open, against `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`:

1. **Hedge skyline.** The crest cards and the far trees are darker. On this shot 1.30% of the upper band is still light-green, mostly the west edge of the hill. The hill mean is (212.0, 223.6, 146.4). The stall still shows through the middle. The hedge tea house is in the lower left and does not cover that edge. PETAL-05.
2. **Bellhelp.** Ten tips, a short rank inside them, a darker band, and a wider skirt. The dark throat is still the center. PETAL-03.
3. **Highlights.** Overview pixels at pure white are 0. The lanterns, the pink disk, the grass-plot tops, the meadowbell petals, the mauve bed, the flagstones, the path dirt, and the loose stones at screen x 618, y 727 are gone. Pixels with red and green at 255 and blue at 220 or above are 0. The brightest clipped pixels left are (255, 255, 201) at screen x 1034, y 178, the warm horizon in the hedge opening. That is sky. PETAL-06.

## Next integration

Keep this build playable. The next pass stays inside `scenes/main.tscn` (Hedge Hollow). The creature chain through Gushorn can happen in this garden. The media foundry and town hall are still not built. The hedge tea house stands on the south lawn. The research hut stands on the south lawn, west of the tea house. Meadowbells are a clump of three, and every crop sits in a ring of leaves. On this shot 1.30% of the upper band is still light green, mostly the west edge of the hill, and the stall still shows through the middle. The hill mean is (212.0, 223.6, 146.4). The hedge tea house is in the lower left. Bees sit on the flowers while it rains. Do not paint that hill edge, do not cut the hill, and do not raise the east shrubs. Do not fill Bellhelp’s dark throat. Do not open a side demo. The Kenney/Cara grove in `scripts/presentation/` is not the running scene.

# Recovery matrix

Forensic pass, 2026-09-22. This repository started empty apart from an init commit. The previous Garden Grove cloud run (`bc-de2329c2-3768-409c-ac9b-20a87a58fc6a`) is not readable from this environment, and that work was never pushed to a GitHub remote (the agent UI still showed “Create repo”). Public search did not find a Garden Grove / PetalWild / Hedge Hollow source tree. Unique names from the playable screenshot (Petal Stall, Bulrush, Bellhelp, Gushorn) do not appear in a public repository.

Decision: reconstruct the observed playable loop and the recovered names. Do not claim the old source was merged. Do not copy GPL implementations from the research references.

## Sources inspected

| Source | What was found | Decision |
| --- | --- | --- |
| This git repo | Empty init commit, then the uploaded reference images | Foundation is the reconstruction in this branch |
| Cloud agent `bc-de2329c2` | Not accessible. Screenshot shows a Godot project with `CREDITS.md`, `day.ogg`, `dialog.ogg` | ARCHIVE the screenshot. Do not invent the missing files |
| GitHub `scottstts/Jelly-Baby` | GPL-3.0. Interaction vocabulary: drag, stretch, throw, wobble, hop | KEEP as behaviour reference only. No source copied |
| GitHub `SFTtech/openage` | GPL. Large-scale simulation architecture | KEEP as textbook. No source copied |
| GitHub `redplanethq/town` | Agent-town reference | KEEP ideas (roles, walkable town). No code imported |
| GitHub `VivaPinataPlus` | Modding / systems research lead | KEEP as systems research. No assets, names, or code |
| GitHub `SolarCookies/TiP-Recomp` | Exists. Explicit no-AI policy | ARCHIVE as a name only. Not fetched, not analysed |
| Concept images | Lush hedge garden, stall, veg-scale people | KEEP as the art north star in `docs/reference/` |
| Garden Grove screenshot | Journal, tools, Petal Stall, Day/Dusk HUD, grid plots | KEEP the loop and the names. REPLACE the grid look |
| Havenbrook screenshot | Jelly-bot campus photos | KEEP the agent-society idea. No code existed to merge |

## Matrix

### KEEP

- Species names already on screen: Bulrush, Bellhelp, Berrypatch, Reedic, Cirlark, Grapling, Pegapear, Gushorn. Dusknip was added as the night-loam link in that chain.
- Tool row: Tiller, Seed, Raincan, Fertilize, Tend, Pond Scoop, Home Kit, plus Hands.
- Petal Stall, petal coins, garden journal, day/weather HUD.
- Lumen Peel at the stall.
- The first playable loop: till, plant, water, fertilise, visitor requirements, shop purchase, save, reload.
- Concept plates in `docs/reference/`.

### MERGE

A second reconstruction landed on `main` while this one was being written (`c140089`, species names Sunpetal / Sunburst / Quin Hearth). It is kept in `game/` with a `.gdignore`, so Godot does not compile it beside this project.

Take from it: the CC0 Asset Quest demo, the Nunito OFL file, `docs/research/`, and the idea of a trust level that can hold a proposal without executing. Do not take its species names. Those replace the names visible in the Garden Grove screenshot.

### REFACTOR

- Simulation fidelity is a real counter (`SimLod`) with tiers 0–2 in this small garden. Tiers 3–4 are named and persisted as data, not a city sim.
- Trust levels 0–5 are named. Only 0 and 1 are reachable, and both stay inside the game.

### REPLACE

- Flat debug grid and sphere-canopy dressing. Wave 1 now uses a trimmed hedge wall, cone backdrop trees, and a south camera that looks into the beds. The interior is still far from the concept plates.
- Sphere-stacked Bellhelp. The blossom layout is in, and it still reads as one glossy body at gameplay distance.
- Capsule Veg People. Spectacles and an apron read at close range. They are not an authored cast yet.

### ARCHIVE

- `docs/reference/current_garden_grove_01.png` and `current_grok_grove_01.png` as evidence of the lost build.
- `docs/reference/jelly_baby_reference_01.png` and `havenbrook_reference_01.png` as design references, not assets to trace.

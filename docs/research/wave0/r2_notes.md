# R2 technique notes

Checked 27 September 2026. Ideas only. No source copied, and nothing was cloned into the game tree. openage was not cloned. Town (~31 MB) and VivaPinataPlus (~21 KB) were read through the GitHub API.

The decision service exited 2 on every call (`HTTP 502`). Grok locked each card to its evidence recommendation. `options[0]` was not used. LimboAI is YELLOW because the repo ships CC-BY-4.0 logo and demo art with the MIT code. Lanes below are the assignment.

`docs/research/ARCHITECTURE_REFERENCES.md` still matches the openage and town documents read this pass. Corrections are marked inline.

## PETAL-02 Ecology

- **Growth as a curve, then an event.** openage stores gradual quantities as keyframes and fires the next event when the clock reaches it. A plant stage change is a discrete step. Fill between stages (water, size, fruit) is a gradual value. The view samples the value. It does not advance every plant every frame.
- **Carrying capacity is a type budget.** VivaPinataPlus does not document romance, diets, or species data. Its launcher only claims to lift per-type item budgets in the commercial PC build, plus a windowed-mode switch. Petalwild can give each object class its own garden budget. It must not ship that launcher or require the commercial game.

## PETAL-04 Residents

- **A resident is a slot, not a subclass.** In Town, a building variant declares slots. An author file binds a name, a walk-up description, and a voice to one slot. Movement and cell choice stay with the host. Speech starts when someone is close. People sharing a room share one conversation. A full day clock is not what the README ships. Scheduled gatherings and a persistent passport are still unchecked roadmap items.
- **Schedules are time windows.** Skelerealms hangs schedule events under an NPC. An event applies only between a from-time and a to-time, and only if its conditions pass. Idle time is "stay in this place and mill." That shape fits a garden day. The rest of that repo is a first-person combat RPG (crime, hitboxes, factions). Do not adopt the kit. Stars: 0. Last push 15 May 2026.
- **Utility scoring stays the brain.** Petalwild already scores actions as a product of considerations. Beehave (MIT, GDScript, Godot 4 branch, push 20 September 2026) is the tree to read if a multi-step action later needs one. LimboAI (MIT code, push 4 September 2026) adds a tree editor, a debugger, and state machines, and the current line wants Godot 4.6+. Its logo and demo art are CC-BY-4.0. Do not install either yet.
- **GOAP is a planner beside the scorer, not a replacement.** `goap-godot-4` (MIT, GDScript, plugin 1.1.4) searches backward from a goal and replans when the world changes. Use that pattern only if a resident must chain steps (find, then use). Skelerealms documents the same split: a planner picks the goal, a tree runs the step.
- **Talk is a short turn.** Dialogue Manager (MIT, Godot 4.6+, push 27 September 2026) is the lighter editor if scripted lines appear. Dialogic (MIT, Godot 4.5+, push 30 August 2026) is the heavier visual-novel kit. An example font there is Apache-2.0. Proximity talk (place, role, tone, one turn) does not need either yet.

## PETAL-05 Economy

- **Bags stay a dictionary until they grow rules.** The session inventory is already a dictionary of counts. Gloot (MIT, GDScript, Godot 4.4+, push 14 July 2026) separates item prototypes from constraints: grid, weight, count. UI is a control node on top. Read it when a stall needs weight or slots. Do not replace the dictionary in this wave.
- **Craft is not a supply chain.** Expresso Inventory (MIT, C++, push 20 February 2026) adds stacks, categories, equipment, and recipes, and credits Gloot for its grid. The repo is about 500 MB and builds on godot-cpp. Not carded. Do not vendor it.
- **No green logistics library cleared the bar.** Shops in Skelerealms are barter filters on an item list. That is a stall, not a production chain. OpenTTD-style cargo links were not cloned (GPL, large).
- **ecks is closed.** `unauthorizedlogin/ecks` is all-rights-reserved in `LICENSE.md` (view and evaluate only). GitHub SPDX `NOASSERTION`. Do not copy it.

## PETAL-06 Town

- **The author names the place. The sim places it.** Town: a town file lists buildings. The server picks a free cell, routes a path from home, and refills the edge. The same edit lands in the same spot because placement is seeded. A plot record holds buildings, paths, water, decor, and NPCs, and a validator checks that every reference exists. An interior has a walkable region and a way in. Crossing the threshold changes what you can do. Licence is AGPL-3.0-or-later plus a section 7 extra permission plus Commons Clause v1.0 (sell is withheld). SPDX `NOASSERTION`. Commit `02d70556` (27 July 2026). Not cloned.
- **Zoom by dwelling size, then walk in.** Dwellcraft's site offers three homes (about 100 m², 200 m², and a large estate), an empty start or a styled sample, then a first-person walk. The repo (`Ryan-fm/Dwellcraft`, commit `5055fefa`) has placement, navigation, and local-save files, and no licence file. UX only.
- **A city reads as chapters, not as every building.** CityMaker (`https://citymaker.0to1app.com/`) is the homepage of `derek-wangpch/OpenCityMaker` (MIT, SPDX MIT, push 21 September 2026). It is a 2048 merge: twelve cities, a score, a tile ladder, WASD or swipe. WebGL is required. Useful as a readability ladder. Not a settlement simulator, so it was not carded.
- **Object budgets.** See PETAL-02. A town plot should refuse a fifth of the same object when the type budget is full, and say so.

## PETAL-07 Region

- **No global tick.** openage `master` `b23f5df` (26 September 2026). `copying.md` is still GPL-3.0-or-later for files that do not say otherwise. GitHub SPDX remains `NOASSERTION`. README still says GNU GPLv3 or later. Listed third-party exceptions include 3-clause BSD and LGPL-2.0. They do not relicense the engine. Docs still describe: presenter, simulation, and clock on separate loops; an event queue runs everything with fire time up through now; a missing entity drops its events; entities are an id plus components; activities are a node graph of immediate systems; the renderer is optional.
- **Crowds share a field.** Pathfinding is its own grid, loosely fed by terrain. Cells group into fixed sectors. Each movement type can have its own cost grid. Passable runs on a sector edge are portals. A cheap search on that portal graph picks sectors. Flow fields are built only there, then walked into straight segments. The cited algorithm is Elijah Emerson, Game AI Pro chapter 23. Many agents with one destination share one field. That is the regional crowd lesson. Do not copy the classes.
- **Far residents are counts.** The same split already in the architecture note still holds: embodied agents near the camera, statistics (species counts, need averages, service capacity) everywhere else. openage's optional presenter is the evidence that the sim can run without drawing.
- **nyan correction.** The separate repo `SFTtech/nyan` (push 14 September 2025) is the content database. Its `copying.md` says LGPL-3.0-or-later, not "LGPLv3" with no later versions. GitHub SPDX `NOASSERTION`. It was not copied. Do not link it into Petalwild. Species stay original Godot resources.
- **Chunks are a radius, not a faction sim.** Skelerealms describes an active radius, a preload radius, and cache eviction for world chunks. That is the only regional pattern worth remembering there. Faction disposition and crime response stay inside that RPG kit.

## Visual sites

Fetched 27 September 2026. Observed text only.

| Site | Reachable | Lane | What the page actually showed |
| --- | --- | --- | --- |
| https://loulous-apartment.vercel.app/ | Yes | PETAL-06 | Title "Loulou's Apartment" only. No camera, controls, or source repo in the HTML. |
| https://citymaker.0to1app.com/ | Yes | PETAL-06 | City chapters, score, personal best, grid merge, WASD/swipe. WebGL warning. Source: OpenCityMaker, MIT. Not carded. |
| https://dwellcraft.vercel.app/ | Yes | PETAL-06 | Pick one of three scaled homes, then start empty or from a style. Source has no licence. Carded as reject. |
| https://cabsolutely.vercel.app/ | Yes | PETAL-05 | Taxi shift, district load progress, earnings and ride count, pickup then destination, drive keys, a map. `ilkerzg/cabsolutely` (SPDX MIT, `vercel.json` present) describes the same Mission Street taxi. Its grant covers original code only. Geo data and generated media are excluded. Homepage field was empty, so the URL is not a repo metadata link. Not carded. |
| https://wesche.com/lab/astra/boat-explorer/ | Yes | PETAL-07 | "Sundrift": no destination, heading, knots, distance, islands, a golden-hour clock. Slow travel with instruments. No matching source repo. `NathanBWaters/astra` is a different project. |
| https://monopoly-city.eekosystems.chatgpt.site/ | Yes | PETAL-06 | Title plus "Preparing your corner of the city". No board, camera, or source repo in the HTML. |
| https://agiofempires.com/ | Yes | PETAL-07 | Title "AGI of Empires V4 · The Compute Wars" only. No readable sim UI and no source repo. |
| https://vale-dos-vinhedos.lucas579686.chatgpt.site/ | Yes | PETAL-04 | "The Free Game." One line: you plan the village, residents bring it to life. Then a loading state. No source repo. |

## Godot libraries named, not all carded

Navigation: no third-party addon was worth a card. Use Godot's navigation server for embodied residents. Crowd sharing stays the openage/Emerson reference.

Save/load: no small MIT save addon was strong enough. Skelerealms documents named slots, a schema version, and migrations, which is the pattern Petalwild already uses. Keep original snapshots.

Dialogic and Expresso Inventory are the runners-up named under PETAL-04 and PETAL-05. They were not given cards.

# Petal recovery map

Action map for the build lanes. 27 September 2026.

Read this file and `docs/research/KANBAN.md` before new implementation. A card is an opportunity. It is not permission to replace a working system.

A second pass opened the Astra catalogue (162 entries). The notes are `docs/research/wave0/ASTRA_INDEX_PASS.md`. It did not add a solver and it did not add a town importer.

Hailo `POST /decide` returned HTTP 502. Decisions were locked from the repositories. `options[0]` was not used. Full records: `docs/research/OPEN_SOURCE_CANDIDATES.md`.

The Godot store pass vendored one project: Kenney's Starter Kit City Builder, as `scenes/parish.tscn`. Notes: `docs/research/wave0/GODOT_STORE_PASS.md`. Other clones stay in gitignored `_research/`.

## PETAL-01

Foundation is the existing clock, save schema, and the split between simulation and view. Do not leave the Godot 4.8-dev6 pin.

- the-free-game. Decision STUDY. Class YELLOW. Repository `LucasMarquesShiva/the-free-game`. Benefit: places create jobs, and the view only reads state. That is already `docs/SIMULATION_LAYERS.md`. Integration: do not copy the 4.7.2 project or the CC-BY art.
- Citybound. Decision STUDY. Class REVIEW (AGPL-3.0). Repository `citybound/citybound`. Benefit: a household can be a crop offer. Integration: soil and growth already exist. Copy nothing.
- Harvest Moon 2.0. Decision REJECT. Class RED. Repository `Kenny-Haworth/Harvest-Moon-2.0`. The MIT text does not cover a Pokémon sheet or an unlabeled Utumno tileset. Do not clone it into the tree.

## PETAL-02

No plant-growth library cleared the bar. Keep the current ecology.

- Stage changes are events. Water, size, and fruit are values the view samples. The source of that idea is openage, which PETAL-07 holds as STUDY. Do not import openage.
- A per-type object budget is an original rule if a later wave needs one. The Viva Piñata Plus launcher is REJECT. Do not ship it and do not require commercial game files.

## PETAL-03

The running body is `scripts/presentation/jelly_actor.gd`, instanced by `scripts/presentation/grove_view.gd`. `shaders/jelly.gdshader` is a normal wobble. `game/` is not the running tree.

- Jelly-Baby. Decision STUDY. Class REVIEW (GPL-3.0-only). Commit `19fc6ea`. Repository `scottstts/Jelly-Baby`. Benefit: the feel of a lagged grab, a flick, and a short settle. Integration: rewrite that feel in the existing actor. Rate-limit the grab target, stretch along the pull, keep the constraint for one or two ticks after release so a flick becomes velocity, then damp the squash back to rest. A very short gesture stays a pet. Do not replace the controller. Do not copy source, meshes, cages, or constants. Note: `docs/research/JELLY_BABY_PORT_ANALYSIS.md`.
- Dead shader names. The actor sets `impact` and `push`. The shader does not declare them. While touching the grab, drive a uniform the shader actually has, or stop setting the unused names. Do not let a shader invent a different silhouette from the one that was grabbed.
- SpringBoneSimulator3D. Decision ADOPT. Class GREEN. It is `scene/3d/spring_bone_simulator_3d.h` in Godot `8898c2b3d`, already in this pin. Benefit: crests, leaves, and lobes settle without a soft-body solve. Integration: call the engine node only after an appendage has a bone chain. The current jelly is stacked meshes with no skeleton, so this does not land in the same change as the grab. Do not write a second jiggle solver. Do not import godot-vrm.
- Godot SoftBody3D. Decision STUDY. Class GREEN. Benefit: a supported deformer for one prop. Integration: do not make it the creature, and do not simulate the garden as soft bodies. Soft bodies do not collide with each other.
- PositionBasedDynamics and Gloop. Decision STUDY. Class GREEN. Benefit: a close-up cluster can be tens of points, not a thousand. Integration: only if the directional squash is still too stiff. Write an original cluster. Do not vendor either repository.
- godot-softbody2d. Decision STUDY. Class GREEN. 2D rigid-body lattice. Do not vendor it.
- JoltPhysics upstream. Decision REJECT. Class GREEN. The engine already contains `modules/jolt_physics`. Do not add the upstream repository.
- godot-vrm. Decision REJECT. Class REVIEW. Spring bone is already in the engine. Sample models are separately licensed.
- Melon Lab. Decision REJECT. Class RED. Repository `Ayi1337/gpt6-astra-one-shot-games` at `4178b08`. It is an eighteen-point 2D ring with no `LICENSE` file. Gloop is the MIT note for that scale. Do not copy `physics.js`.

## PETAL-04

The resident brain stays utility scoring. Godot's navigation server stays the pathfinder for embodied people. Do not install a behaviour-tree or dialogue addon in this wave.

- Beehave, goap-godot-4, Dialogue Manager, Skelerealms. Decision STUDY. Class GREEN. Benefit: a later multi-step action, a time window, or scripted lines. Integration: read the card, do not add the plugin. Proximity talk does not need Dialogue Manager yet.
- LimboAI. Decision STUDY. Class YELLOW. MIT code, CC-BY-4.0 logo and demo art. Do not install it.
- IsoCity. Decision STUDY. Class GREEN. Benefit: a passer is a count plus a zone, not a unique mind. Integration: the parish already counts passers. Do not import the city.
- CorsixTH. Decision STUDY. Class GREEN for the project MIT grant. Benefit: a needs queue. Integration: do not copy Theme Hospital data or the LGPL and OFL sections of `LICENSE.txt`.
- DwarfCorp. Decision STUDY. Class REVIEW. Modified MIT, proprietary art, SteamSDK in the tree. Do not take the repository.
- Egregoria. Decision STUDY. Class REVIEW (GPL-3.0). Benefit: desires, and a sim that does not store meshes. Copy nothing.
- Julius. Decision STUDY. Class REVIEW (AGPL-3.0). Benefit: a service is a radius and a count. Venues already store demand. Do not port walkers.

## PETAL-05

The stall inventory stays the session dictionary.

- Gloot. Decision STUDY. Class GREEN. Repository `peter-kish/gloot`. Benefit: grid, weight, and count constraints if a stall later needs slots. Integration: do not replace the dictionary and do not vendor the addon.
- No green production-chain library cleared the bar. Do not import OpenTTD, Unknown Horizons, or a belt-logistics game to get one.

## PETAL-06

Play opens the Kenney city builder. Grove Park stays unbuilt. The grove scene is still `scenes/main.tscn`. The parish grid is not the sim's town counts.

- Starter Kit City Builder. Decision ADOPT. Class GREEN for the MIT code and the CC0 models, sprites, and sounds. The bundled Lilita One file is SIL OFL 1.1 and ships with `fonts/license.txt`. Repository `KenneyNL/Starter-Kit-City-Builder`, commit `4535092`. Integration: `scenes/parish.tscn` is `run/main_scene`. Fifteen kit structures, then church, restaurant, cafe, clinic, school, shop, library, bakery, post office, town hall, and inn. Empty grid and $10000 on play. F3 loads the 122-cell sample. Same street controls as the upstream project. Enter opens a small apartment or one of those buildings.
- CityCrafter3D. Decision STUDY. Class GREEN (MIT, copyright 2025 immaculate-lift-studios). Editor generator. Default block 200, street 25. It does not run without building scenes assigned. Do not vendor the plugin or the example gif.
- town. Decision STUDY. Class REVIEW (AGPL-3.0-or-later plus Commons Clause). Repository `RedPlanetHQ/town`. Benefit: an author names a place, the sim picks the cell, placement is seeded, and a resident is a slot. Integration: copy nothing. Pathing stays a separate service.
- VivaPinataPlus. Decision REJECT. Class GREEN. The MIT grant is the launcher, not the commercial game. The README has no store link. Do not import it. Do not run it. Do not require original Viva Piñata files.
- Dwellcraft. Decision REJECT. Class RED. No licence file. The only keep is an observed order: pick a scale, then walk in. Do not copy the site or `Ryan-fm/Dwellcraft`.
- OpenCityMaker. Decision STUDY. Class GREEN (MIT, copyright 2026 Derek Wang). Commit `dc78e7f`. Benefit: a town can read as a few silhouettes on a board, with a closer view as a choice. Integration: do not import the 2048 board, the landmark atlas, or the real city names.

## PETAL-07

Embodied residents use Godot's navigation server. Everyone else stays a count. Do not build a sector portal graph on the parish grid.

- openage. Decision STUDY. Class REVIEW (GPL-3.0-or-later). Commit `b23f5df` on `master` when this note was written. Benefit: an event clock, and one flow field shared by a crowd with one destination. Integration: the algorithm reference is Elijah Emerson, Game AI Pro chapter 23, not the openage classes. Do not copy source. Do not link `SFTtech/nyan` (LGPL-3.0-or-later). Species stay original resources. Build a shared field only after many embodied agents share a destination and the navigation server is the measured cost.

## PETAL-08

`tools/orchestration/` stays the foreman. The game does not import it. Parallel lanes do not edit the same garden file. `PETAL_SMOKE_OK` is the gameplay gate. A picture requires `DISPLAY=:1`. Headless success is not a picture of the hedge.

- game-creator. Decision REJECT. Class RED. No `LICENSE` file. README, `package.json`, and a named AGPL audio dependency disagree. Do not read it as a source.
- pocket-salvage. Decision REJECT. Class RED. No repository licence.
- Claude-Code-Game-Studios, claude-one-button-game-creation, quasar-saz, world-of-claudecraft. Decision STUDY. Class GREEN. Benefit: gates, isolated workers, and a headless step of the real sim. Integration: do not vendor the agent packs, gdUnit4's embedded copy, a gym, or a token.
- Godot-MCP. Decision STUDY. Class GREEN (Apache-2.0). It needs a mono editor and a cloud login. This pin is the standard 4.8-dev6 binary. Do not install it.
- JSettlers. Decision STUDY. Class GREEN. Benefit: flags and carriers as a textbook. The repo needs original Settlers III GFX and SND, which are not licensed to us. Do not take those assets. Owner is PETAL-08 so the tree is not vendored into the economy.
- Space Station 14. Decision STUDY. Class REVIEW. Inventory pattern only. Gloot is the Godot note. Assets are share-alike. Do not copy them.
- OpenTTD, Unknown Horizons Godot port, MicropolisCore. Decision STUDY. Class REVIEW (GPL or GPL plus EA terms). Benefit: save versions, a production slot, and cellular demand. Petalwild already versions saves. Do not paste scripts. Do not use the SimCity or Micropolis names.

## What no lane should do

Do not clone a candidate over the Godot project. Do not treat a CC0 index as permission. Do not treat GitHub `NOASSERTION` as MIT or as "no licence": openage, town, OpenTTD, and MicropolisCore are copyleft in their licence files.

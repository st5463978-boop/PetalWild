# Architecture references

Research notes for the original game PetalWild, written 22 September 2026. The projects below were read as textbooks through public pages (README, licence, and design docs). Nothing was cloned into this workspace. No source code is pasted here, and none of it is imported into the game.

PetalWild may adapt an idea from a section marked adaptable. It may not copy source, data files, art, species, or names. Where a licence is copyleft, copying code would put that licence on PetalWild.

## openage

- Link: https://github.com/SFTtech/openage
- Pages read: README, `copying.md`, `doc/code/architecture.md`, `doc/code/event_system.md`, `doc/code/game_simulation/README.md`, `doc/code/game_simulation/game_entity.md`, `doc/code/pathfinding/README.md`
- Licence: README and `copying.md` state GNU GPL version 3 or any later version (GPL-3.0-or-later), copyright the openage authors. GitHub's licence API reports SPDX `NOASSERTION` because the grant lives in `copying.md`. A project FAQ also lists the separate nyan library as LGPLv3. This note does not use nyan's source.

### Licence risk if code were copied

openage is strong copyleft. Copying its source, headers, or other GPL-covered files into a distributed PetalWild build would make the combined work GPL-3.0-or-later, with corresponding source owed to recipients. That includes static linking and other ways of forming a derivative. PetalWild takes ideas only. Do not copy openage code, nyan schemas, or its asset-conversion tooling.

### Entity simulation

Simulation is its own subsystem. A session holds terrain and game entities. An entity is a thin identity: an id, a bag of components, and a manager that listens for events. What an entity can do comes from which components are attached, not from a subclass per unit type. The authors call this composition. They also say the vocabulary resembles an entity-component-system without being a textbook ECS.

Persistent numbers (the stats that are the same every session) live in a content database. The component keeps a reference to that record, plus runtime values. Runtime values sit on curves: keyframes of a quantity over simulation time, so a position is a history the renderer can sample.

Behaviour splits three ways. Systems are stateless functions that run immediately on components and are not supposed to call each other. Activities chain those systems as a node graph stored on the entity, so the current node is the current action. A manager receives events and advances the graph. Waiting and cancelling belong to the event machinery, not inside the system function.

### Data-driven content

Units are configuration, loaded as modpacks into a session, not classes compiled into the engine. Abilities declared in data become components when an entity is spawned, and activity graphs are configurable from that same data. A converter turns external media into the moddable form. The engine does not ship the commercial game's assets. PetalWild's analogue is an original species resource (see the Godot notes), not a port of their database.

### Large populations and pathfinding

Pathfinding is a simulation service, loosely tied to terrain. Terrain may change the cost of a step, but the path grid can exist on its own. The map is cells grouped into fixed-size sectors. Each movement type can have its own cost grid. A run of passable cells on the edge between two sectors becomes a portal, and the portals form a graph of their own.

A request names a grid, a start cell, and a target cell. Search is two-level. A cheap high-level search (A* over the portal graph) chooses which sectors the trip touches, so the expensive step never covers the whole map. Flow fields are built only in those sectors, starting at the target and passing through the chosen portals so the fields meet. Each cell stores a step toward a cheaper neighbour. Walking those steps produces a waypoint wherever the direction changes, and the entity travels in straight segments.

The technique they cite is Elijah Emerson, "Crowd Pathfinding and Steering Using Flow Field Tiles," *Game AI Pro*, chapter 23: http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf

The crowd lesson is reuse. Many agents heading the same way share one field instead of each running a private search, and the field can also steer them apart. Building the field is the expensive part; sectors and caching exist to limit that cost. PetalWild should treat Emerson's chapter as the algorithm reference. openage is evidence that a game simulation can organise the work this way. Do not copy openage's path classes.

### World update organisation

There is no global simulation tick. A time subsystem exposes the current simulation time. Each pass, an event loop runs every event whose fire time is after the previous pass and up through now, earliest first. A handler applies an effect and predicts the next fire time. An entity can be the target of an event; if the entity is gone, events aimed at it are dropped. Changing an entity can reschedule events that depend on it. Events can also be cancelled.

The presenter, the simulation, and time each loop on their own thread and meet through interfaces. Input becomes events, the simulation advances, and the renderer samples state (including curves) to draw. The renderer is optional, so the sim can run headless. Their stated goal adds networking and scripting as further event sources, with one authoritative simulation. PetalWild can keep the organisational idea — a clock, a queue of future work, and a view that only samples state — inside one Godot process.

## Town

- Link: https://github.com/RedPlanetHQ/town
- Read via the web: `README.md` and `LICENSE` on the default branch `main`. No source files were opened for this note.
- What it is: a walkable pixel town. Buildings host characters. Visitors walk the same map and can talk, including together inside one room.

### Licence recorded from the repo

`LICENSE` is titled "Town License", copyright 2025 Poozle Inc. It grants the GNU Affero General Public License version 3 or any later version. It adds an AGPL section 7 extra permission about combining a work that uses the library. It also adds the Commons Clause v1.0: the grant does not include the right to sell the software. In that clause, "sell" includes paid hosting or support when the product's value comes substantially from the software. GitHub's licence API reports SPDX `NOASSERTION`, which matches this non-standard stack.

PetalWild copies none of Town's files. AGPL is network copyleft, and the Commons Clause is a commercial restriction on top of it. The ideas below are not permission to reuse their code, prompts, or art.

### Adaptable ideas

**Places as functions.** A town is a short list of places. Each place is an experience with a resident, and the author writes what the place is for and who stands in it. The host, not the author, chooses the cell, routes a path, and keeps that placement stable when the description is edited again. A place carries a walkable interior, a way in, and a way out. Crossing the threshold changes which interaction is available. For PetalWild, a clearing, nest, or facility is a function a creature calls: arrive, perform the place's action, leave. Pathing stays a separate service.

**Schedules.** The playable town is "walk over and talk now." The public roadmap also describes scheduled, time-boxed gatherings: a creator names a themed visit, people are invited, and they arrive together. PetalWild uses that shape for creatures and places. A place publishes when it is open. A creature publishes when it means to be there. The simulation resolves the overlap. That schedule is our model, drawn from their event roadmap, and it is not a claim that their characters already run a full day clock.

**Conversations.** Speech starts when someone is close and chooses to speak. Voice (how they greet, what they care about, how long a turn is, staying inside the scene) is separate from capability (what they can look up or remember). One room can hold a single shared conversation among visitors and residents, and a resident may join without being addressed one at a time. PetalWild conversations are the same kind of data: place, role, tone, and a short turn, triggered by proximity, with one shared exchange when several creatures occupy one place.

**Walkable agents.** Visitors and residents share a map, and movement is something you see. You enter a building; you do not open it as a menu. The population is small and embodied. That fits the creatures near the camera. Counts farther away belong to the statistical layer below.

## Jelly Baby

- Link: https://github.com/scottstts/Jelly-Baby
- Licence: the README states the GNU General Public License v3.0 only (GPL-3.0-only). GitHub's licence API reports SPDX `GPL-3.0`. A distributed modification would have to ship corresponding source under GPLv3. The "only" wording does not grant later GPL versions.

**No Jelly Baby source may be copied into PetalWild.** That covers scripts, shaders, meshes, scenes, and assets. A derivative that included their code would be GPL-3.0-only, and PetalWild will not create that derivative. The notes below are behaviour and feel only.

The creature is a 7 cm resident of a wooden tabletop. The camera is close enough that a stretch reads. The piece has no score and no errand list. The pleasure is handling a small body.

- Grab, stretch, and throw. The player pulls the body and lets go into a throw. The deformation is the interaction.
- Wobble propagation. After a pull or a landing, the wobble travels through the body as a wave, rather than one global squash on the whole sprite.
- Hop. A dedicated action, separate from walking, on a key or a button.
- Face reaction. The face changes during a stretch, so expression is tied to the deformation.
- Facilities. A swing and a trampoline sit in the room. When the creature is close enough, one control starts the facility, and the same control leaves it.

PetalWild aims for that handling at creature scale: a body you can tug, a hop, a face that answers the tug, and a few facilities you step onto. Our creatures also have needs and places. The tactile layer sits on the simulation.

## Viva Pinata Plus

- Link: https://github.com/VivaPinataPlus/VivaPinataPlus
- Recorded only because the repository exists. GitHub lists it as a public C# project, created in 2024, default branch `main`. The published `LICENSE` is the MIT License, copyright 2024 VivaPinataPlus. GitHub reports SPDX `MIT`.

That MIT grant covers the repository's own files. It does not license the commercial game, and it does not license any species, names, or assets. PetalWild copies no species, names, assets, or code from the repository or from the game it concerns. No systems were taken from it. Existence and the published licence are the whole of this entry.

## TiP-Recomp

https://github.com/SolarCookies/TiP-Recomp was not used. The repository has an explicit no-AI policy, so this research did not fetch, quote, or analyse its source, disassembly, or assets. Nothing from it informs PetalWild.

## Cities: Skylines topic

Topic listing: https://github.com/topics/cities-skylines

Three public projects returned for that topic, with licences visible on the GitHub API:

| Project | Public description | Licence |
| --- | --- | --- |
| [CitiesSkylinesMultiplayer/CSM](https://github.com/CitiesSkylinesMultiplayer/CSM) | Multiplayer mod | MIT |
| [CitiesSkylinesMods/TMPE](https://github.com/CitiesSkylinesMods/TMPE) | Traffic Manager: President Edition | MIT |
| [dymanoid/RealTime](https://github.com/dymanoid/RealTime) | Time flow and citizen behaviour | MIT |

These are mods for a commercial city builder. An MIT grant covers that mod's own source, not the game. PetalWild does not copy their code.

The simulation idea worth adapting is a split population. A garden the size of a town cannot give every creature a unique mind, a unique path, and a unique conversation on every frame. Most of the population can be statistics: counts by species, average needs, and whether a service still has capacity. A small set near the camera are embodied agents with positions, choices, and paths. Services (food, rest, play, care) are places with a radius and a capacity. When capacity is gone, the statistic worsens and an embodied creature looks elsewhere. In a city builder, traffic is where individual agents earn their cost, because congestion is what the player watches. PetalWild spends pathfinding and animation on the creatures in view, and lets the rest of the garden move as numbers until a creature joins the embodied set.

## Godot design notes

Original notes for PetalWild. They follow two public patterns: Godot custom resources, and utility AI (score an action from considerations). They are design notes, not copied implementations, and they import no third-party AI framework.

### Utility AI

An embodied creature stores needs as plain numbers. Its species resource lists the actions that species may try. For each candidate, a few considerations read needs and context: hunger against foraging, distance to the place, crowding, time of day, a recent failure. Each consideration is a curve from 0 to 1. The action score is the product of those curves, so a single hard zero can veto the action. The creature commits to the best score, runs it until it finishes or a clearly better score appears, and writes the outcome back into the needs. One shared scorer does this for every species. Species differ by the data they carry.

### Data-driven species

One creature scene. A species is a Godot `Resource`: a display name written for this game, body scale, palette, diet tags, need rates, which facility types it will use, conversation tone, and utility weights. Spawning reads the resource and attaches the shared creature script. A new species is a new resource file. Godot's resource model is documented at https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html

### Save versioning

A save is a dictionary whose first field is an integer `schema`. The loader refuses a schema newer than the game. An older schema passes through an ordered list of migrations, each turning version N into N+1, and only then does the current loader build the world. A migration reshapes data. It does not spawn nodes. The file stores a snapshot: creature ids, species ids, need values, place ids, and schedule phase. Live event-queue objects and path objects are rebuilt after load. One fixture save per historical schema keeps the chain honest.

## What PetalWild keeps

1. A clock and a queue of future work. The view samples state.
2. Creatures as ids plus components. Actions come from data, chosen by utility.
3. Pathfinding for the embodied crowd, shared when many share a destination. Statistics for everyone else.
4. Places as functions on a schedule, and a conversation when creatures arrive together.
5. Handling at a small-body scale: grab, stretch, throw, a travelling wobble, hop, a reactive face, and facilities.
6. Species and saves as versioned data we author ourselves.

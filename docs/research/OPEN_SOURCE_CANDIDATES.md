# Open-source candidates

Scouted 27 September 2026 for the current Godot garden. Stars are not a quality score. Each row was read from the repository licence file or the GitHub licence API, then given to the Pi decide service, then reviewed here.

The decide service is the Hailo path in `tools/orchestration/`. Health on this run reported `model: Qwen3-1.7B.hef`, `ollama_tag: qwen3:1.7b`, `device: Hailo-10H`. The payload does not describe an RLCD policy. Other tags exist on that Pi (`deepseek_r1_distill_qwen:1.5b`, `llama3.2:3b`, `qwen2.5-coder:1.5b`, `qwen2.5-instruct:1.5b`, `qwen2:1.5b`). The decide call uses the HEF, not those tags, and not OpenRouter.

`tools/orchestration/repo_triage.py` posts one candidate and prints the model's choice. It does not clone or execute anything the model says. Where the model said `DIRECT_IMPORT` and the licence or the fit forbids it, the decision below is the Cursor override.

No candidate repository was cloned into this tree.

## Decision key

`ADOPT` means the code can go into the MIT game. `PORT` means reimplement the idea. `STUDY` means read only. `REJECT` means do not use.

## Candidates

### Jelly-Baby

- Name: Jelly-Baby
- URL: https://github.com/scottstts/Jelly-Baby
- Purpose: tabletop soft-body toy. Grab, stretch, throw, hop, facilities.
- Language: TypeScript / JavaScript / C
- Engine: Three.js, WebGPU
- Last activity: 2026-09-14
- Licence: GPL-3.0-only
- PetalWild target: Grokbot jelly feel
- Directly reusable: no
- Portable: the interaction idea, not the solver
- Reference only: the cage, kernel, and mesh
- Quality: the solver matches the feel. It is a full soft-body, not a pose.
- Integration cost: a native port of the kernel would be a second creature stack and a GPL relicensing
- Expected benefit: directional stretch and recovery, which the parish was faking with a vertical scale
- Qwen3: `DIRECT_IMPORT` (overridden)
- Decision: PORT
- Detail: `docs/research/JELLY_BABY_PORT_ANALYSIS.md`. Implemented as `scripts/creatures/jelly_deform.gd`.

### godot-jigglebones

- Name: godot-jigglebones
- URL: https://github.com/yaelatletl/godot-jigglebones
- Purpose: spring jiggle on `Skeleton3D` bones
- Language: GDScript
- Engine: Godot 4
- Last activity: 2025-02-20
- Licence: MIT
- PetalWild target: jelly secondary motion
- Directly reusable: no. The jellies are sphere clusters and have no skeleton.
- Portable: the spring idea, already smaller in `JellyDeform`
- Reference only: yes
- Quality: a real addon, aimed at tails and cloth bones
- Integration cost: a skeleton none of the creatures have
- Expected benefit: none over the body-basis spring
- Qwen3: `USE_AS_REFERENCE`
- Decision: STUDY

### WiggleBone

- Name: WiggleBone
- URL: https://github.com/detomon/wigglebone
- Purpose: `SkeletonModifier3D` jiggle (Godot 4.3+)
- Language: GDScript
- Engine: Godot 4
- Last activity: 2026-05-14
- Licence: MIT
- PetalWild target: jelly secondary motion
- Directly reusable: no, same skeleton mismatch. Godot's own `SpringBoneSimulator3D` is the same class of tool.
- Portable: not needed
- Reference only: yes
- Quality: maintained, and the asset library lists it as MIT
- Integration cost: addon plus a rig
- Expected benefit: none for these bodies
- Qwen3: `USE_AS_REFERENCE`
- Decision: STUDY

### Godot SoftBody3D

- Name: SoftBody3D
- URL: https://docs.godotengine.org/en/stable/classes/class_softbody3d.html
- Purpose: engine mesh soft body
- Language: engine (C++)
- Engine: Godot
- Last activity: ships with the pinned 4.8-dev6 binary
- Licence: MIT (engine)
- PetalWild target: jelly deformation
- Directly reusable: the node is available. Using it would replace `Jelly`.
- Portable: no
- Reference only: yes
- Quality: real physics. Jolt is the recommended backend. This project is on the pinned dev6 renderer and a working kinematic creature.
- Integration cost: one soft body per visitor, fighting the existing grab, hop, and sleep
- Expected benefit: folding mesh. Not worth the controller rewrite.
- Qwen3: `DIRECT_IMPORT` (overridden)
- Decision: REJECT

### OpenCityMaker

- Name: OpenCityMaker
- URL: https://github.com/derek-wangpch/OpenCityMaker
- Purpose: procedural 3D city 2048. Source of https://citymaker.0to1app.com/
- Language: TypeScript
- Engine: Three.js, React, Vite
- Last activity: 2026-09-21
- Licence: MIT
- PetalWild target: town camera and building massing
- Directly reusable: no. It is a puzzle board, not a garden.
- Portable: the 45° orbit and the tiered building silhouettes, as ideas
- Reference only: yes
- Quality: 132 procedural buildings, documented creation notes
- Integration cost: a second renderer
- Expected benefit: camera and massing notes only
- Qwen3: `DIRECT_IMPORT` (overridden)
- Decision: STUDY

### game-creator

- Name: game-creator
- URL: https://github.com/PlayableIntelligence/game-creator
- Purpose: agent plugin that scaffolds Phaser and Three.js browser games
- Language: JavaScript
- Engine: Phaser / Three.js
- Last activity: 2026-05-25
- Licence: none. No `LICENSE`, `LICENSE.md`, `LICENCE`, or `COPYING` file. GitHub reports no SPDX id.
- PetalWild target: agent workflow
- Directly reusable: no
- Portable: no
- Reference only: no, until a licence exists
- Quality: a large skill pack. Unusable without a licence.
- Integration cost: blocked
- Expected benefit: none until licensed
- Qwen3: `REJECT_LICENSE`
- Decision: REJECT

### Claude Code Game Studios

- Name: claude-code-game-studios
- URL: https://github.com/donchitos/claude-code-game-studios
- Purpose: multi-agent studio layout (agents, skills, hooks)
- Language: Shell / markdown
- Engine: none
- Last activity: 2026-09-24
- Licence: MIT
- PetalWild target: agent development tooling
- Directly reusable: no. PetalWild already routes through `tools/orchestration/`.
- Portable: the idea of one owner per system, which `docs/AGENT_CONTRACTS.md` already states
- Reference only: yes
- Quality: a Claude Code kit, not a Godot architecture
- Integration cost: a second studio inside a project that has one
- Expected benefit: naming ideas only
- Qwen3: `DIRECT_IMPORT` (overridden)
- Decision: STUDY

### One-button game creation

- Name: claude-one-button-game-creation
- URL: https://github.com/abagames/claude-one-button-game-creation
- Purpose: batch small browser games, then browser-check them
- Language: JavaScript
- Engine: crisp-game-lib
- Last activity: 2026-07-27
- Licence: MIT
- PetalWild target: build/test loop
- Directly reusable: no
- Portable: the loop "generate, run, keep the failures" is already how `tests/smoke.gd` is used
- Reference only: yes
- Quality: small and specific to that lib
- Integration cost: a Node toolchain the garden does not need
- Expected benefit: none in-tree
- Qwen3: `PORT_TECHNIQUE` (overridden; nothing to port into Godot)
- Decision: STUDY

### openage

- Name: openage
- URL: https://github.com/SFTtech/openage
- Purpose: RTS engine. Data-driven units, event time, optional presentation.
- Language: C++ / Python
- Engine: own
- Last activity: 2026-09-26
- Licence: GPL-3.0-or-later by default (`copying.md`). GitHub SPDX is unset.
- PetalWild target: many creatures, schedules
- Directly reusable: no
- Portable: the split between event simulation and a close-up presentation. Already described in `docs/research/REFERENCES.md`. `SimLod` is the parish version.
- Reference only: yes
- Quality: a large, serious engine
- Integration cost: GPL, and a different genre
- Expected benefit: architecture only
- Qwen3: `DIRECT_IMPORT` (overridden)
- Decision: STUDY

### town

- Name: town
- URL: https://github.com/RedPlanetHQ/town
- Purpose: walkable pixel town, NPC slots on buildings
- Language: TypeScript
- Engine: web
- Last activity: 2026-07-28
- Licence: AGPL-3.0-or-later plus a Commons Clause (`LICENSE`, titled "Town License")
- PetalWild target: residents and places
- Directly reusable: no
- Portable: places, roles, and a time when people are expected. The parish already has routes on Lumen, Bram, and Nessa.
- Reference only: yes
- Quality: a small social space, not a garden sim
- Integration cost: AGPL
- Expected benefit: none beyond the existing routes
- Qwen3: `DIRECT_IMPORT` (overridden)
- Decision: STUDY

### VivaPinataPlus

- Name: VivaPinataPlus
- URL: https://github.com/VivaPinataPlus/VivaPinataPlus
- Purpose: quality-of-life mod for the commercial game
- Language: C#
- Engine: the original game
- Last activity: 2024-08-18
- Licence: MIT for the mod repository
- PetalWild target: gardening reminders only
- Directly reusable: no. The mod depends on proprietary game files.
- Portable: no content
- Reference only: the mod talks about item limits. PetalWild does not import that.
- Quality: a small mod
- Integration cost: blocked by the commercial game
- Expected benefit: none
- Qwen3: `USE_AS_REFERENCE`
- Decision: STUDY

### awesome-gpt-6-astra

- Name: awesome-gpt-6-astra
- URL: https://github.com/MartinDelophy/awesome-gpt-6-astra
- Purpose: catalogue of AI-built games
- Language: markdown
- Engine: none
- Last activity: 2026-09-26
- Licence: CC0-1.0 for the list. Linked projects keep their own licences.
- PetalWild target: discovery
- Directly reusable: the list text is CC0. Nothing from it was copied into the game.
- Portable: no
- Reference only: yes
- Quality: a directory. It is how OpenCityMaker and Jelly-Baby were found again.
- Integration cost: none
- Expected benefit: pointers
- Qwen3: `USE_AS_REFERENCE`
- Decision: STUDY

### open-source-games

- Name: open-source-games
- URL: https://github.com/bobeff/open-source-games
- Purpose: directory of open-source games
- Language: Python / markdown
- Engine: none
- Last activity: 2026-02-25
- Licence: CC0-1.0 for the directory
- PetalWild target: discovery
- Directly reusable: no game from the list was imported
- Portable: no
- Reference only: yes
- Quality: a wide index. Godot entries (Liblast, Unknown Horizons' Godot port) are other games, not garden systems.
- Integration cost: importing a whole game
- Expected benefit: none this pass
- Qwen3: not asked. It is an index, same class as the Astra list.
- Decision: STUDY

### awesome-ai-built-games

- Name: awesome-ai-built-games
- URL: https://github.com/lappemic/awesome-ai-built-games
- Purpose: catalogue of AI-built games
- Language: markdown
- Engine: none
- Last activity: 2026-09-27
- Licence: CC0-1.0 for the list
- PetalWild target: discovery
- Directly reusable: no
- Portable: no
- Reference only: yes
- Quality: short list. Godot entries are finished games (surgery sim, kiosk sim, crane sim), not extractable garden modules.
- Integration cost: whole games
- Expected benefit: none this pass
- Qwen3: not asked
- Decision: STUDY

### Godot-MCP

- Name: Godot-MCP
- URL: https://github.com/IvanMurzak/Godot-MCP
- Purpose: MCP server for the Godot editor
- Language: C#
- Engine: Godot 4
- Last activity: 2026-09-27
- Licence: Apache-2.0
- PetalWild target: agent tooling
- Directly reusable: not this run. The garden is driven by the pinned headless binary and `tests/`.
- Portable: no
- Reference only: yes
- Quality: an editor bridge
- Integration cost: a C# plugin and a running editor
- Expected benefit: none for the jelly pass
- Qwen3: `DIRECT_IMPORT` (overridden)
- Decision: REJECT

### Melon Lab

- Name: Melon Lab (瓜体实验室)
- URL: https://melon-game.jack-514.chatgpt.site/
- Purpose: watermelon merge with soft-body fruit
- Language: unknown
- Engine: browser
- Last activity: listed in the Astra catalogue
- Licence: no source repository and no licence found
- PetalWild target: soft-body contact
- Directly reusable: no
- Portable: no
- Reference only: no
- Quality: unknown
- Integration cost: blocked
- Expected benefit: none
- Qwen3: `REJECT_LICENSE`
- Decision: REJECT

## Visual case studies

These are playable pages, not repositories. No page source was copied. Notes are limited to what the page itself says about camera and play.

| Page | What it says it is | Useful observation | Decision |
| --- | --- | --- | --- |
| https://loulous-apartment.vercel.app/ | Interactive isometric apartment | A fixed isometric room is enough when the subject is one interior | STUDY |
| https://citymaker.0to1app.com/ | Free 3D landmark 2048 | Discrete 45° turns. PetalWild already orbits continuously. Do not switch the garden to a puzzle camera. | STUDY |
| https://dwellcraft.vercel.app/ | Choose a home and arrange it | Interior dressing. The parish already places a home kit. | STUDY |
| https://cabsolutely.vercel.app/ | Drive around 300 Mission | A street-level drive. Wrong scale for a hand-held jelly. | REJECT |
| https://wesche.com/lab/astra/boat-explorer/ | Slow ocean boat, sunset, islands | A slow camera sells a place. The garden camera is already a close orbit. | STUDY |
| https://monopoly-city.eekosystems.chatgpt.site/ | 3D property board, first person and board view | Two cameras on one small board. The parish does not need a second mode. | STUDY |
| https://agiofempires.com/ | Browser RTS about AI labs | Faction RTS. openage already covers the architecture lesson, under GPL, as study only. | STUDY |
| https://vale-dos-vinhedos.lucas579686.chatgpt.site/ | A village scene ("The Free Game") | A walked village. No licensed source. | REJECT |

## What was integrated

Only the original spring in `scripts/creatures/jelly_deform.gd`, called from the existing `Jelly`. No third-party source tree was vendored.

# Open-source candidates

Second pass, 27 September 2026: the Astra catalogue was opened entry by entry. New records are under "Astra index additions" at the bottom. See `docs/research/wave0/ASTRA_INDEX_PASS.md`.

Wave 0 catalogue, 27 September 2026. Hailo `POST /decide` returned HTTP 502. Grok locked every decision from the licence file and the inspected code. `options[0]` was not used.

Indexes are not candidates. `bobeff/open-source-games`, `awesome-gpt-6-astra`, and `awesome-ai-built-games` are CC0 lists. A list's licence is not the licence of a linked repository.

Nothing in this catalogue was copied into `scripts/`, `scenes/`, `data/`, `shaders/`, or `addons/`.

| Name | Lane | Decision | Class | SPDX |
| --- | --- | --- | --- | --- |
| Jelly-Baby | PETAL-03 | STUDY | REVIEW | GPL-3.0 |
| Godot SoftBody3D | PETAL-03 | STUDY | GREEN | MIT |
| SpringBoneSimulator3D | PETAL-03 | ADOPT | GREEN | MIT |
| godot-softbody2d | PETAL-03 | STUDY | GREEN | MIT |
| PositionBasedDynamics | PETAL-03 | STUDY | GREEN | MIT |
| Gloop | PETAL-03 | STUDY | GREEN | MIT |
| JoltPhysics | PETAL-03 | REJECT | GREEN | MIT |
| godot-vrm | PETAL-03 | REJECT | REVIEW | NOASSERTION |
| openage | PETAL-07 | STUDY | REVIEW | NOASSERTION |
| town | PETAL-06 | STUDY | REVIEW | NOASSERTION |
| VivaPinataPlus | PETAL-06 | REJECT | GREEN | MIT |
| Skelerealms | PETAL-04 | STUDY | GREEN | MIT |
| Gloot | PETAL-05 | STUDY | GREEN | MIT |
| LimboAI | PETAL-04 | STUDY | YELLOW | MIT |
| Beehave | PETAL-04 | STUDY | GREEN | MIT |
| Dialogue Manager | PETAL-04 | STUDY | GREEN | MIT |
| goap-godot-4 | PETAL-04 | STUDY | GREEN | MIT |
| Dwellcraft | PETAL-06 | REJECT | RED | NONE |
| game-creator | PETAL-08 | REJECT | RED | none |
| Claude-Code-Game-Studios | PETAL-08 | STUDY | GREEN | MIT |
| claude-one-button-game-creation | PETAL-08 | STUDY | GREEN | MIT |
| Godot-MCP | PETAL-08 | STUDY | GREEN | Apache-2.0 |
| quasar-saz | PETAL-08 | STUDY | GREEN | MIT |
| pocket-salvage | PETAL-08 | REJECT | RED | none |
| world-of-claudecraft | PETAL-08 | STUDY | GREEN | MIT |
| the-free-game | PETAL-01 | STUDY | YELLOW | MIT |
| IsoCity | PETAL-04 | STUDY | GREEN | MIT |
| Harvest Moon 2.0 | PETAL-01 | REJECT | RED | MIT |
| JSettlers | PETAL-08 | STUDY | GREEN | MIT |
| CorsixTH | PETAL-04 | STUDY | GREEN | MIT |
| DwarfCorp | PETAL-04 | STUDY | REVIEW | NOASSERTION |
| Space Station 14 | PETAL-08 | STUDY | REVIEW | MIT |
| Egregoria | PETAL-04 | STUDY | REVIEW | GPL-3.0 |
| Citybound | PETAL-01 | STUDY | REVIEW | AGPL-3.0 |
| Julius | PETAL-04 | STUDY | REVIEW | AGPL-3.0 |
| OpenTTD | PETAL-08 | STUDY | REVIEW | GPL-2.0 |
| Unknown Horizons Godot port | PETAL-08 | STUDY | REVIEW | GPL-2.0 |
| MicropolisCore | PETAL-08 | STUDY | REVIEW | GPL-3.0-or-later |
| OpenCityMaker | PETAL-06 | STUDY | GREEN | MIT |
| Melon Lab | PETAL-03 | REJECT | RED | none |

Field records follow. `research_doc` is the note a build agent should open before acting.

## Jelly-Baby

- NAME: Jelly-Baby
- URL: https://github.com/scottstts/Jelly-Baby
- SOURCE REPOSITORY: scottstts/Jelly-Baby
- PURPOSE: Tabletop soft creature: compliant multi-point grab, tet-cage deformation, inversion recovery, flick throw, face reaction.
- LANGUAGE: JavaScript
- ENGINE: Three.js (browser)
- LAST ACTIVITY: 2026-09-14T10:19:54Z
- LICENCE: REVIEW (GPL-3.0)
- LICENCE EVIDENCE: README states GPL-3.0-only. LICENSE is the GNU GPL v3 text. GitHub licence API returns spdx_id GPL-3.0, which does not encode the 'only' grant. Shallow-cloned and read at 19fc6ea.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: The feel spec for a held jelly: lagged force-limited grab, flick momentum, small bounce, internal settle, hold-timed face.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: 19fc6ea487262f7a32fa8935712624ae5249db68
- FILES / SUBSYSTEMS: src/physics/grab.ts, src/app/input.ts, src/physics/soft-body.js, src/physics/deform-surface.js, src/physics/orientation-safety.js, src/physics/constants.js, src/app/locomotion.ts, src/graphics/character/face-expression.ts
- RECOMMENDED ACTION: Reimplement the grab, flick, and settle ideas in jelly_actor.gd. Lane call escalated. Owner is PETAL-03.
- DO NOT: Copy or translate any Jelly-Baby source, shader, asset, kernel, or constant block.; Replace jelly_actor.gd with this solver.; Vendor the repository.
- RESEARCH DOCUMENT: docs/research/JELLY_BABY_PORT_ANALYSIS.md

## Godot SoftBody3D

- NAME: Godot SoftBody3D
- URL: https://github.com/godotengine/godot
- SOURCE REPOSITORY: godotengine/godot
- PURPOSE: In-engine deformable mesh: pinned vertices, per-point impulses, pressure and sleep on the Jolt backend.
- LANGUAGE: C++
- ENGINE: Godot 4.8-dev6
- LAST ACTIVITY: 2026-09-14T21:10:40Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT. soft_body_3d.h at this commit carries the Godot MIT header. Backends: modules/godot_physics_3d/godot_soft_body_3d.cpp and modules/jolt_physics/objects/jolt_soft_body_3d.cpp. Official demo godotengine/godot-demo-projects 15d4fcd70a429dfd455d6fce9d0cd004abd07373 is also MIT.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: medium
- EXPECTED BENEFIT: A supported mesh deformer for one prop. Documents pins, impulses, and the Jolt pressure path already linked into this engine pin.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: 8898c2b3db32adf6f92c694ffb6dac19af672e5f
- FILES / SUBSYSTEMS: scene/3d/physics/soft_body_3d.h, modules/jolt_physics/objects/jolt_soft_body_3d.h, modules/godot_physics_3d/godot_soft_body_3d.h
- RECOMMENDED ACTION: Leave it available for a single prop test. Do not make it the creature body. Lane call escalated. Owner is PETAL-03.
- DO NOT: Replace jelly_actor.gd with SoftBody3D.; Simulate every garden jelly as a soft body.
- RESEARCH DOCUMENT: docs/research/JELLY_BABY_PORT_ANALYSIS.md

## SpringBoneSimulator3D

- NAME: SpringBoneSimulator3D
- URL: https://github.com/godotengine/godot
- SOURCE REPOSITORY: godotengine/godot
- PURPOSE: Secondary motion on a Skeleton3D bone chain: Verlet tails, stiffness, drag, gravity, child collision shapes.
- LANGUAGE: C++
- ENGINE: Godot 4.8-dev6
- LAST ACTIVITY: 2026-09-14T21:10:40Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT. scene/3d/spring_bone_simulator_3d.h at 8898c2b3d carries the Godot MIT header and a Verlet tail record. Present since 4.4 (PR 101409). Movement follows the MIT VRM spring-bone spec and is already compiled into this pin.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? yes
- PORTABLE? no
- REFERENCE ONLY? no
- QUALITY: high
- INTEGRATION COST: low
- EXPECTED BENEFIT: Crests, leaves, and lobes keep moving after the body stops, without a soft-body solve.
- DECISION: ADOPT
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: 8898c2b3db32adf6f92c694ffb6dac19af672e5f
- FILES / SUBSYSTEMS: scene/3d/spring_bone_simulator_3d.h, scene/3d/spring_bone_simulator_3d.cpp, scene/3d/spring_bone_collision_3d.h
- RECOMMENDED ACTION: Call the engine node for appendages from the jelly presentation. Lane call escalated. Owner is PETAL-03.
- DO NOT: Reimplement Verlet jiggle beside this node.; Import godot-vrm to get the same behaviour.
- RESEARCH DOCUMENT: docs/research/JELLY_BABY_PORT_ANALYSIS.md

## godot-softbody2d

- NAME: godot-softbody2d
- URL: https://github.com/appsinacup/godot-softbody2d
- SOURCE REPOSITORY: appsinacup/godot-softbody2d
- PURPOSE: 2D plugin that fills a polygon with rigid bodies, joints, and a weighted skeleton so a texture squishes.
- LANGUAGE: GDScript
- ENGINE: Godot 4
- LAST ACTIVITY: 2026-08-15T15:16:22Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT. LICENSE is the MIT licence, copyright Dragos Daian. Commit 7b4c80e on main.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: A reminder that a skinned lattice can squash. The 3D creature should not pay one rigid body per region.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: 7b4c80e36a25a66f3c2a76eec3bffcf4e58a5064
- FILES / SUBSYSTEMS: addons/softbody2d/softbody2d.gd, addons/softbody2d/softbody2d_physics.gd, addons/softbody2d/softbody2d_lattice.gd
- RECOMMENDED ACTION: Leave the plugin out. If a lattice is needed, write a few points in the actor, not a field of rigid bodies. Lane call escalated. Owner is PETAL-03.
- DO NOT: Vendor addons/softbody2d into Petalwild.; Rebuild the 3D jelly as jointed rigid bodies.
- RESEARCH DOCUMENT: docs/research/JELLY_BABY_PORT_ANALYSIS.md

## PositionBasedDynamics

- NAME: PositionBasedDynamics
- URL: https://github.com/InteractiveComputerGraphics/PositionBasedDynamics
- SOURCE REPOSITORY: InteractiveComputerGraphics/PositionBasedDynamics
- PURPOSE: MIT C++ library of PBD and XPBD constraints: distance, volume, FEM tets, and shape matching.
- LANGUAGE: C++
- ENGINE: none (standalone library)
- LAST ACTIVITY: 2026-09-01T06:08:48Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT. LICENSE is the MIT licence, copyright PositionBasedDynamics contributors. ShapeMatchingConstraint, DistanceConstraint_XPBD, VolumeConstraint_XPBD, and XPBD_FEMTetConstraint are declared in Simulation/Constraints.h at 10a70bc.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: The cheap close-up stand-in for a tet solve: shape matching plus a volume constraint on a handful of points.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: 10a70bc146a97873dc3c8fef372f5217e010542e
- FILES / SUBSYSTEMS: Simulation/Constraints.h, Simulation/TimeStep.cpp, Simulation/SimulationModel.h
- RECOMMENDED ACTION: Read the shape-matching and XPBD volume ideas, then write a tiny original cluster for the held fidelity only. Lane call escalated. Owner is PETAL-03.
- DO NOT: Vendor PositionBasedDynamics.; Translate Constraints.cpp into the Godot project.; Promote this to a PETAL-01 primitive unless a later lane decision says the jelly lane must call a shared solver.
- RESEARCH DOCUMENT: docs/research/JELLY_BABY_PORT_ANALYSIS.md

## Gloop

- NAME: Gloop
- URL: https://github.com/idreesaziz/Gloop
- SOURCE REPOSITORY: idreesaziz/Gloop
- PURPOSE: 2D Godot blob: a ring of masses, neighbor and radial springs, pressure, iterative distance repair, spline mesh, eyes.
- LANGUAGE: GDScript
- ENGINE: Godot 4.5
- LAST ACTIVITY: 2026-01-12T13:46:01Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT. LICENSE is the MIT licence, copyright 2026 Gloop Contributors. README describes the spring-mass ring. Commit aa53ebe on master.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: medium
- EXPECTED BENEFIT: Shows a readable soft creature at tens of points (the README allows 6 to 48), which is the budget for one held jelly.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: aa53ebea464f42794bebae5972de012bcc559e51
- FILES / SUBSYSTEMS: scripts/soft_body_blob.gd, scripts/blob_player_controller.gd
- RECOMMENDED ACTION: Use it as a scale check for a future 3D cluster. Keep the current actor for locomotion. Lane call escalated. Owner is PETAL-03.
- DO NOT: Copy soft_body_blob.gd into Petalwild.; Adopt the platformer controls or the generated eye textures.
- RESEARCH DOCUMENT: docs/research/JELLY_BABY_PORT_ANALYSIS.md

## JoltPhysics

- NAME: JoltPhysics
- URL: https://github.com/jrouwe/JoltPhysics
- SOURCE REPOSITORY: jrouwe/JoltPhysics
- PURPOSE: MIT rigid-body library with its own soft-body type. Already compiled into Godot as modules/jolt_physics.
- LANGUAGE: C++
- ENGINE: none (Godot vendors a module)
- LAST ACTIVITY: 2026-09-27T10:08:18Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT. LICENSE is the MIT licence, copyright 2021 Jorrit Rouwe. Godot pin 8898c2b3d already contains modules/jolt_physics/objects/jolt_soft_body_3d.cpp.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: None beyond what Godot's Jolt module already exposes through SoftBody3D.
- DECISION: REJECT
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: 9ef6ce6215453b5b85048200c8de27ed04f6b7ce
- FILES / SUBSYSTEMS: Jolt/Physics/SoftBody/SoftBodySharedSettings.h
- RECOMMENDED ACTION: Do not add this repository. Use the engine module only if a single SoftBody3D prop is ever justified. Lane call escalated. Owner is PETAL-03.
- DO NOT: Vendor jrouwe/JoltPhysics.; Write a GDExtension against upstream Jolt for jelly.
- RESEARCH DOCUMENT: docs/research/JELLY_BABY_PORT_ANALYSIS.md

## godot-vrm

- NAME: godot-vrm
- URL: https://github.com/V-Sekai/godot-vrm
- SOURCE REPOSITORY: V-Sekai/godot-vrm
- PURPOSE: VRM avatar importer. Historical source of the spring-bone motion now implemented by SpringBoneSimulator3D.
- LANGUAGE: GDScript
- ENGINE: Godot 4
- LAST ACTIVITY: 2026-07-08T17:20:14Z
- LICENCE: REVIEW (NOASSERTION)
- LICENCE EVIDENCE: GitHub licence API spdx_id NOASSERTION. LICENSE opens by warning that .vrm sample models have their own terms (vrm_samples/LICENSE_SAMPLES.txt), then an MIT grant for the software. Ambiguous repo: code text is MIT, samples are carved out, SPDX is not MIT.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: None for jelly. The engine node replaced the spring-bone path this addon was ported from.
- DECISION: REJECT
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: e15199f980064028bfa4fbee5e70dddb82dd55c3
- FILES / SUBSYSTEMS: LICENSE, vrm_samples/LICENSE_SAMPLES.txt
- RECOMMENDED ACTION: Reject the addon. Secondary motion goes through SpringBoneSimulator3D. Lane call escalated. Owner is PETAL-03.
- DO NOT: Vendor godot-vrm.; Copy VRM sample models or their spring parameters.; Treat NOASSERTION as permission.
- RESEARCH DOCUMENT: docs/research/JELLY_BABY_PORT_ANALYSIS.md

## openage

- NAME: openage
- URL: https://github.com/SFTtech/openage
- SOURCE REPOSITORY: SFTtech/openage
- PURPOSE: Event-scheduled RTS simulation, data-driven entities, and sector flow-field pathfinding for large crowds.
- LANGUAGE: C++ and Python
- ENGINE: Custom (not Godot)
- LAST ACTIVITY: 2026-09-26
- LICENCE: REVIEW (NOASSERTION)
- LICENCE EVIDENCE: copying.md grants GPL-3.0-or-later for files that do not say otherwise. README says GNU GPLv3 or later. gh api license.spdx_id is NOASSERTION. Listed exceptions include 3-clause BSD and LGPL-2.0 for named third-party files. Separate repo SFTtech/nyan copying.md is LGPL-3.0-or-later, also SPDX NOASSERTION.
- PETALWILD TARGET: PETAL-07
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: A clock plus a future-event queue, optional presentation, and shared crowd fields for residents far from the camera.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-07
- COMMIT: b23f5df2017c76f79774f6baa92bd5621015c053
- FILES / SUBSYSTEMS: copying.md, doc/code/architecture.md, doc/code/event_system.md, doc/code/time.md, doc/code/curves.md, doc/code/game_simulation/README.md, doc/code/game_simulation/game_entity.md, doc/code/pathfinding/README.md, doc/code/optimization.md
- RECOMMENDED ACTION: Keep the 22 September architecture note. It still matches master. Reimplement the clock, the event queue, and shared fields in original GDScript. Cite Emerson for the algorithm.
- DO NOT: Do not clone the repo into the game tree, copy sources, headers, nyan schemas, or the asset converter.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## town

- NAME: town
- URL: https://github.com/RedPlanetHQ/town
- SOURCE REPOSITORY: RedPlanetHQ/town
- PURPOSE: Walkable pixel towns where buildings are experiences and residents occupy authored slots.
- LANGUAGE: TypeScript
- ENGINE: Web (Next.js, Kaplay)
- LAST ACTIVITY: 2026-07-27
- LICENCE: REVIEW (NOASSERTION)
- LICENCE EVIDENCE: LICENSE is titled Town License, copyright 2025 Poozle Inc. It grants AGPL-3.0-or-later, adds an AGPL section 7 extra permission, then adds Commons Clause v1.0 withholding the right to sell. gh api license.spdx_id is NOASSERTION. Same repo as redplanethq/town.
- PETALWILD TARGET: PETAL-06
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: Places as functions: seeded placement, paths between buildings, walkable interiors, and one resident per slot.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-06
- COMMIT: 02d705563951a4bb6a5750b2540d806222095d60
- FILES / SUBSYSTEMS: LICENSE, README.md, AGENTS.md, packages/plot/README.md, packages/plot-gen/README.md, packages/types, packages/catalog
- RECOMMENDED ACTION: Model a garden place as a named function with a stable seeded footprint, a path, a threshold, and resident slots. Author residents as data. Let the sim choose the cell.
- DO NOT: Do not copy source, prompts, art, or the layout generator. Do not treat the section 7 clause as permission to vendor the repo.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## VivaPinataPlus

- NAME: VivaPinataPlus
- URL: https://github.com/VivaPinataPlus/VivaPinataPlus
- SOURCE REPOSITORY: VivaPinataPlus/VivaPinataPlus
- PURPOSE: Windows launcher that patches the commercial Viva Piñata process for item budgets and windowed mode.
- LANGUAGE: C#
- ENGINE: None (Win32 process patcher)
- LAST ACTIVITY: 2024-08-18
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: LICENSE is the MIT License, copyright 2024 VivaPinataPlus. gh api license.spdx_id is MIT. The only public repo on the user account. The grant covers this launcher, not the commercial game.
- PETALWILD TARGET: PETAL-06
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: low
- INTEGRATION COST: high
- EXPECTED BENEFIT: One observed rule: a garden can cap how many objects of each type may be placed.
- DECISION: REJECT
- ASSIGNED PETAL LANE: PETAL-06
- COMMIT: 3098b705745d7ca5968f9e33e4c429583f61661a
- FILES / SUBSYSTEMS: LICENSE, README.md, Launcher/Program.cs, Launcher/Patches/NoPlacementLimits.cs, Launcher/Patches/WindowedModePatch.cs
- RECOMMENDED ACTION: Reject the repository as a dependency. If object clutter matters, invent original per-type placement budgets in the town plot.
- DO NOT: Do not import the launcher, memory patches, species, names, or assets. Do not require the original game.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## Skelerealms

- NAME: Skelerealms
- URL: https://github.com/awest813/skelerealms
- SOURCE REPOSITORY: awest813/skelerealms
- PURPOSE: Godot 4.4+ RPG framework with NPC schedules, GOAP, persistence, inventories, barter, and faction disposition.
- LANGUAGE: GDScript
- ENGINE: Godot 4.4+
- LAST ACTIVITY: 2026-05-15
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: LICENSE is an MIT grant, copyright 2024 Slashscreen. gh api license.spdx_id is MIT. Plugin version claimed as 1.0 in the README.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: low
- INTEGRATION COST: high
- EXPECTED BENEFIT: Time-window NPC routines, a versioned save schema, and a reminder that GOAP and a behaviour tree can split planning from execution.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: b3f2e7d854b70e764f936a7d31d76df9aab1c755
- FILES / SUBSYSTEMS: LICENSE, README.md, docs/user guide/schedules.md, docs/user guide/goap_actions.md, docs/user guide/npcs.md, docs/user guide/save_system.md, docs/user guide/navigation.md, docs/user guide/covens.md
- RECOMMENDED ACTION: Read the schedule and save-schema docs only. Keep Petalwild schedules as data on the resident and the place. Do not enable the plugin.
- DO NOT: Do not vendor the framework, its combat modules, or its faction crime loop.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## Gloot

- NAME: Gloot
- URL: https://github.com/peter-kish/gloot
- SOURCE REPOSITORY: peter-kish/gloot
- PURPOSE: Godot 4.4+ inventory addon: item prototypes plus grid, weight, and count constraints, with UI separated from storage.
- LANGUAGE: GDScript
- ENGINE: Godot 4.4+
- LAST ACTIVITY: 2026-07-14
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: LICENSE is the MIT License, copyright 2022 Peter Kish. gh api license.spdx_id is MIT. README states Godot 4.4 and newer.
- PETALWILD TARGET: PETAL-05
- DIRECTLY REUSABLE? yes
- PORTABLE? yes
- REFERENCE ONLY? no
- QUALITY: high
- INTEGRATION COST: medium
- EXPECTED BENEFIT: A ready constraint model if a stall needs slots or weight. The current session dictionary does not need it yet.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-05
- COMMIT: 6b09b87ac07a8536779ef1ab0fafc7e99830f948
- FILES / SUBSYSTEMS: LICENSE, README.md, addons/gloot, docs/grid_constraint.md, docs/weight_constraint.md, docs/prototree.md
- RECOMMENDED ACTION: Leave the dictionary inventory. If a shop needs capacity, port the constraint idea (count and weight) in original code, or adopt this addon in a later economy pass.
- DO NOT: Do not replace the session inventory in this wave. Do not vendor Expresso Inventory.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## LimboAI

- NAME: LimboAI
- URL: https://github.com/limbonaut/limboai
- SOURCE REPOSITORY: limbonaut/limboai
- PURPOSE: C++ behaviour trees and state machines for Godot 4, with an editor and a visual debugger.
- LANGUAGE: C++
- ENGINE: Godot 4.6+ (GDExtension line 1.8)
- LAST ACTIVITY: 2026-09-04
- LICENCE: YELLOW (MIT)
- LICENCE EVIDENCE: LICENSE.md is an MIT grant, copyright 2023-2025 Serhii Snitsaruk and contributors. gh api license.spdx_id is MIT. README says the logo and demo art are CC-BY-4.0. Card class is YELLOW because the same repo ships CC-BY-4.0 logo and demo art.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? yes
- PORTABLE? yes
- REFERENCE ONLY? no
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: A maintained tree-plus-state-machine editor if utility scoring later needs a scripted executor.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: 3f14ea4c26911e8b8e30c6bcdb575fc589a59deb
- FILES / SUBSYSTEMS: LICENSE.md, LOGO_LICENSE.md, README.md, bt, hsm
- RECOMMENDED ACTION: Do not install. If a tree is required later, prefer Beehave unless the editor and state machines are worth a native plugin.
- DO NOT: Do not copy the logo or demo art. Do not replace utility scoring.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## Beehave

- NAME: Beehave
- URL: https://github.com/bitbrain/beehave
- SOURCE REPOSITORY: bitbrain/beehave
- PURPOSE: GDScript behaviour-tree addon for Godot 4.
- LANGUAGE: GDScript
- ENGINE: Godot 4.x
- LAST ACTIVITY: 2026-09-20
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: LICENSE is the MIT License, copyright 2023 bitbrain. gh api license.spdx_id is MIT. Default branch is godot-4.x. plugin.cfg version 2.9.4-dev.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? yes
- PORTABLE? yes
- REFERENCE ONLY? no
- QUALITY: high
- INTEGRATION COST: low
- EXPECTED BENEFIT: The lowest-cost tree addon if one resident action needs an ordered script. Not needed while utility scoring commits to a single action.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: fe589153fa780a3f88989578ceb5f539afffb7c2
- FILES / SUBSYSTEMS: LICENSE, README.md, addons/beehave/plugin.cfg, addons/beehave
- RECOMMENDED ACTION: Name this as the tree to add later, and do not add it now. Keep one shared utility scorer.
- DO NOT: Do not install the addon in this wave. Do not write per-species behaviour trees.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## Dialogue Manager

- NAME: Dialogue Manager
- URL: https://github.com/nathanhoad/godot_dialogue_manager
- SOURCE REPOSITORY: nathanhoad/godot_dialogue_manager
- PURPOSE: Nonlinear dialogue addon for Godot 4.6+: a script-like editor and a stateless runtime.
- LANGUAGE: GDScript
- ENGINE: Godot 4.6+
- LAST ACTIVITY: 2026-09-27
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: LICENSE is the MIT License, copyright 2022-present Nathan Hoad and contributors. gh api license.spdx_id is MIT. README titles the current line Dialogue Manager 4 for Godot 4.6+.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? yes
- PORTABLE? yes
- REFERENCE ONLY? no
- QUALITY: high
- INTEGRATION COST: medium
- EXPECTED BENEFIT: A maintained way to author branching lines if residents later speak more than one proximity turn.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: cb0e4c7f87d326bd2042b6c31737699030b87244
- FILES / SUBSYSTEMS: LICENSE, README.md, addons/dialogue_manager/plugin.cfg, addons/dialogue_manager
- RECOMMENDED ACTION: Prefer this over Dialogic if scripted talk is added. Do not add it while conversations stay proximity data.
- DO NOT: Do not adopt Dialogic and Dialogue Manager together. Do not pull itch.io example art.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## goap-godot-4

- NAME: goap-godot-4
- URL: https://github.com/pixelrogueart/goap-godot-4
- SOURCE REPOSITORY: pixelrogueart/goap-godot-4
- PURPOSE: Small GDScript GOAP plugin: backward-chaining planner, priority goals, replan, editor debugger.
- LANGUAGE: GDScript
- ENGINE: Godot 4
- LAST ACTIVITY: 2026-08-06
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: LICENSE is the MIT License, copyright 2026 Pixelrogueart. gh api license.spdx_id is MIT. plugin.cfg version 1.1.4.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? yes
- PORTABLE? yes
- REFERENCE ONLY? no
- QUALITY: medium
- INTEGRATION COST: low
- EXPECTED BENEFIT: A concrete planner to read if a resident must chain find-then-use. Utility scoring already covers single actions.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: 212224cb52285a9c35387b75af63552b6ce2aa51
- FILES / SUBSYSTEMS: LICENSE, README.md, addons/goap/plugin.cfg, addons/goap/goap_agent.gd, addons/goap/goap_action_planner.gd, addons/goap/goap_goal.gd, addons/goap/goap_world_state.gd
- RECOMMENDED ACTION: Leave it as the GOAP reference. Stay with the product-of-considerations scorer for embodied residents.
- DO NOT: Do not install the plugin. Do not run GOAP for the statistical population.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## Dwellcraft

- NAME: Dwellcraft
- URL: https://github.com/Ryan-fm/Dwellcraft
- SOURCE REPOSITORY: Ryan-fm/Dwellcraft
- PURPOSE: Browser 3D home editor: pick a dwelling scale, place furniture, walk inside. Live at https://dwellcraft.vercel.app/.
- LANGUAGE: TypeScript
- ENGINE: Web (React, Babylon.js)
- LAST ACTIVITY: 2026-09-09
- LICENCE: RED (NONE)
- LICENCE EVIDENCE: gh api returned no licence object. The git tree has README.md and no LICENSE file. No SPDX grant was found.
- PETALWILD TARGET: PETAL-06
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: UX only: choose a scale, start empty or from a styled sample, snap and collide placements, then walk in at eye height.
- DECISION: REJECT
- ASSIGNED PETAL LANE: PETAL-06
- COMMIT: 5055fefac14f0fe7214c6cbb66853e62a2154a88
- FILES / SUBSYSTEMS: README.md, lib/placement.ts, lib/navigation.ts, lib/world.ts, lib/storage.ts, lib/scene-design.json
- RECOMMENDED ACTION: Reject the repository. Keep the observed UX: a few dwelling scales, an empty start, snap, undo, and a walk-in camera.
- DO NOT: Do not copy code, models, screenshots, or scene JSON. Do not treat the public site as a source licence.
- RESEARCH DOCUMENT: docs/research/wave0/r2_notes.md

## game-creator

- NAME: game-creator
- URL: https://github.com/PlayableIntelligence/game-creator
- SOURCE REPOSITORY: https://github.com/PlayableIntelligence/game-creator
- PURPOSE: Claude/Cursor plugin that scaffolds Phaser or Three.js browser games and runs a QA subagent after each code step.
- LANGUAGE: JavaScript
- ENGINE: Phaser 3 and Three.js
- LAST ACTIVITY: 2026-05-25T18:02:30Z
- LICENCE: RED (none)
- LICENCE EVIDENCE: GitHub licence API returned null. Shallow clone at this commit has no LICENSE file. README ends by claiming MIT and says @strudel/web is AGPL-3.0. package.json says ISC. skills/game-qa frontmatter says MIT. Those statements disagree, so the grant is ambiguous. R4 firewall: no LICENSE file. Conflicting README MIT, package.json ISC, and a named AGPL audio dependency are not a grant. Class RED. Decision REJECT.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? no
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: A five-phase check (build, runtime, gameplay, architecture, visual) plus a text dump of game state an agent can read without pixels.
- DECISION: REJECT
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: 4e64b83b5fe400b34ad3a484d9b4a6090b26d512
- FILES / SUBSYSTEMS: README.md, agents/game-qa-runner.md, skills/game-qa/SKILL.md, skills/make-game/SKILL.md, skills/make-game/templates/state.md, skills/make-game/sub-pipelines/state-machine.md
- RECOMMENDED ACTION: Reject the repository. Restate a QA loop in Petalwild's own notes. Do not read its skills as a source.
- DO NOT: Copy skills, agents, or templates from this repository.; Add the Strudel / AGPL audio dependency.; Treat a README licence claim without a LICENSE file as permission.
- RESEARCH DOCUMENT: docs/research/wave0/r3_notes.md

## Claude-Code-Game-Studios

- NAME: Claude-Code-Game-Studios
- URL: https://github.com/Donchitos/Claude-Code-Game-Studios
- SOURCE REPOSITORY: https://github.com/Donchitos/Claude-Code-Game-Studios
- PURPOSE: Claude Code studio pack: many role agents, director review gates, hooks, and a run-and-observe capture procedure including Godot.
- LANGUAGE: Shell and Markdown
- ENGINE: Multi-engine notes, including Godot 4
- LAST ACTIVITY: 2026-09-24T02:40:26Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API reports MIT. LICENSE at this commit is the MIT licence, copyright 2026 Donchitos.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: Named director gates and a Godot frame-capture rule that matches events the foreman already accepts.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: 7ed2c3e9c46c880c9780fbce49266e7edfa15141
- FILES / SUBSYSTEMS: LICENSE, .claude/docs/director-gates.md, .claude/docs/coordination-rules.md, .claude/docs/automation-modes.md, .claude/docs/error-recovery-protocol.md, .claude/docs/run-and-observe.md, .claude/agents/qa-lead.md, .claude/agents/godot-specialist.md, .claude/hooks/validate-push.sh
- RECOMMENDED ACTION: Keep their gate index as a checklist. Map test, build, and visual failures onto the foreman's existing events. Lane recommendation PETAL-08. Godot specialist notes can inform PETAL-03 scene work later, without copying the agent file.
- DO NOT: Do not install the .claude agent pack into the Petalwild repo.; Do not treat their Godot launch line as a replacement for tools/run.sh.
- RESEARCH DOCUMENT: docs/research/wave0/r3_notes.md

## claude-one-button-game-creation

- NAME: claude-one-button-game-creation
- URL: https://github.com/abagames/claude-one-button-game-creation
- SOURCE REPOSITORY: https://github.com/abagames/claude-one-button-game-creation
- PURPOSE: Agent workflow that designs ten independent one-button browser games from random tags, then smoke-tests the batch in a real browser and stops.
- LANGUAGE: JavaScript
- ENGINE: crisp-game-lib (browser)
- LAST ACTIVITY: 2026-07-27T09:08:43Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API reports MIT. LICENSE.txt is the MIT licence, copyright 2026 ABA Games. The skill pack it installs, abagames/agentic-gamedev-skills, also reports MIT. crisp-game-lib reports MIT. Those grants do not cover dropping the workflow into Petalwild.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: low
- EXPECTED BENEFIT: A hard batch contract: independent contexts, a smoke command that fails the batch, and no automatic ranking or publish.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: d81f02a0928b35d9c979e9918aa9dc3c2770821b
- FILES / SUBSYSTEMS: LICENSE.txt, README.md, AGENTS.md, workflows/game-generation.md, scripts/check_batch.js
- RECOMMENDED ACTION: Adopt the social rule, not the generator: parallel agents do not read each other's output, a smoke gate is mandatory, and only a human lands the result. Lane recommendation PETAL-08.
- DO NOT: Do not generate one-button games into scenes/ or scripts/.; Do not vendor crisp-game-lib or the agentic-gamedev-skills tree.
- RESEARCH DOCUMENT: docs/research/wave0/r3_notes.md

## Godot-MCP

- NAME: Godot-MCP
- URL: https://github.com/IvanMurzak/Godot-MCP
- SOURCE REPOSITORY: https://github.com/IvanMurzak/Godot-MCP
- PURPOSE: C# Godot editor addon that exposes scene, script, and screenshot operations to MCP agents, by default through ai-game.dev.
- LANGUAGE: C#
- ENGINE: Godot 4.3+ mono/.NET
- LAST ACTIVITY: 2026-09-27T08:28:35Z
- LICENCE: GREEN (Apache-2.0)
- LICENCE EVIDENCE: GitHub licence API reports Apache-2.0. LICENSE at main is the Apache License 2.0. The README states the standard GDScript Godot build cannot host the addon.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: Named checks Petalwild lacks in-editor: GDScript validate, viewport capture, and an isolated-node picture for visual QA.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: 44ec55597dace964abb008b731b419474dc5b6fb
- FILES / SUBSYSTEMS: LICENSE, README.md, docs/ARCHITECTURE.md, docs/runtime-security.md
- RECOMMENDED ACTION: Use the tool list as a wish list for our own smoke and shot modes. Lane recommendation PETAL-08. Isolated shots would later help PETAL-03 (Bellhelp) and PETAL-05 (hedge skyline) without this addon.
- DO NOT: Do not install the Godot-MCP addon or point agents at ai-game.dev.; Do not switch the project to a .NET Godot build to host it.; Do not adopt IvanMurzak/Unity-MCP; same cloud family, wrong engine. Followed at e4af84e5ea885a10186984a8beae05da33f92696, Apache-2.0.
- RESEARCH DOCUMENT: docs/research/wave0/r3_notes.md

## quasar-saz

- NAME: quasar-saz
- URL: https://github.com/cleak/quasar-saz
- SOURCE REPOSITORY: https://github.com/cleak/quasar-saz
- PURPOSE: Godot arcade game produced by Claude Code under a dog-typed brief, kept runnable by tests, linters, and an input-replay runtime.
- LANGUAGE: GDScript
- ENGINE: Godot
- LAST ACTIVITY: 2026-02-23T19:51:40Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API reports MIT for the repository. The vendored addons/gdUnit4/LICENSE is MIT, copyright 2023 Mike Schulze. That embedded copy is not an upstream pin.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: medium
- EXPECTED BENEFIT: Evidence that an unattended Godot loop can require a unit suite, scene linters, and scripted input before shipping a change.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: e56e93ea8c72cbe2ff9f1e754eb68f6829e6ae43
- FILES / SUBSYSTEMS: README.md, LICENSE, addons/gdUnit4/LICENSE, CLAUDE.md
- RECOMMENDED ACTION: Keep the rule that a change is not done until the existing smoke passes, and consider scripted input only as a later original test. Lane recommendation PETAL-08. If a unit framework is wanted later, take gdUnit4 from Mike Schulze's upstream, not from this tree.
- DO NOT: Do not import the game, its scenes, or the vendored gdUnit4 addon.; Do not copy the dog-prompt interpreter into the campaign.
- RESEARCH DOCUMENT: docs/research/wave0/r3_notes.md

## pocket-salvage

- NAME: pocket-salvage
- URL: https://github.com/RaresKeY/pocket-salvage
- SOURCE REPOSITORY: https://github.com/RaresKeY/pocket-salvage
- PURPOSE: Small Godot crane game from the AI-built-games index, with a large headless check suite and a note that headless pixels are not a GPU proof.
- LANGUAGE: GDScript
- ENGINE: Godot
- LAST ACTIVITY: 2026-09-26T23:56:50Z
- LICENCE: RED (none)
- LICENCE EVIDENCE: GitHub licence API returned null. Repository root has no LICENSE file. THIRD_PARTY_NOTICES.md licenses only the Tiny5 font (SIL OFL 1.1) and says that font licence does not license the game source or other assets.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: A warning already true on this VM: a headless Godot check can pass while the pictured garden is still wrong.
- DECISION: REJECT
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: 5909b839b0a7e3463ded69660e2f61f672e587c0
- FILES / SUBSYSTEMS: README.md, THIRD_PARTY_NOTICES.md, tests/README.md, examples_agents/README.md, docs/collaboration.md
- RECOMMENDED ACTION: Reject the repository. Lane recommendation if anyone restates the lesson: PETAL-08. Keep Petalwild shots on DISPLAY=:1 and do not call headless smoke a picture of the hedge. That same split helps PETAL-03 and PETAL-05 visual work.
- DO NOT: Do not copy tests, tools, prompts, shaders, or agent examples.; Do not treat OFL on the font as a licence for the game.
- RESEARCH DOCUMENT: docs/research/wave0/r3_notes.md

## world-of-claudecraft

- NAME: world-of-claudecraft
- URL: https://github.com/levy-street/world-of-claudecraft
- SOURCE REPOSITORY: https://github.com/levy-street/world-of-claudecraft
- PURPOSE: Browser MMO whose deterministic sim also runs as a headless Gymnasium environment so an agent trains against the game itself.
- LANGUAGE: TypeScript
- ENGINE: Three.js, with a Python Gymnasium binding
- LAST ACTIVITY: 2026-09-27T04:15:13Z
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API reports MIT. README badge links LICENSE as MIT. The same README describes an optional Solana token and wallet linking.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: Self-play shape: one sim, a reset/step loop, observations derived from live content rather than a second simplified model.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: cecebab4da06287351b37e118c630c185717b81c
- FILES / SUBSYSTEMS: README.md, headless/CLAUDE.md, python/CLAUDE.md
- RECOMMENDED ACTION: Study only the split between the played sim and a headless step API. Lane recommendation PETAL-08 for the harness. A creature policy, if ever built, is PETAL-01 data driven by that harness, written here, not imported.
- DO NOT: Do not import the MMO, the headless server, the Python bindings, or any token or wallet code.; Do not add Gymnasium as a Petalwild dependency in this wave.
- RESEARCH DOCUMENT: docs/research/wave0/r3_notes.md

## the-free-game

- NAME: the-free-game
- URL: https://github.com/LucasMarquesShiva/the-free-game
- SOURCE REPOSITORY: https://github.com/LucasMarquesShiva/the-free-game
- PURPOSE: Godot village builder: autonomous workers, production chains, a fixed sim clock, and a Python dev command for doctor, test, and web export.
- LANGUAGE: GDScript
- ENGINE: Godot 4.7.2 standard
- LAST ACTIVITY: 2026-09-19T16:33:49Z
- LICENCE: YELLOW (MIT)
- LICENCE EVIDENCE: GitHub licence API reports MIT for the repository. README says code, tools, and docs are MIT, and original artwork is CC BY 4.0, credited to Lucas Marques, from Shiva, with LICENSE-ASSETS.md. CC-BY art is the constraint on the asset half.
- PETALWILD TARGET: PETAL-01
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: A worked split between a fixed-step village sim and a 3D view, close to Petalwild's embodied-versus-aggregate plan.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-01
- COMMIT: 7798cd9771f99d5c99422789a9b94a69df6c3e3e
- FILES / SUBSYSTEMS: LICENSE, LICENSE-ASSETS.md, README.md, docs/ARCHITECTURE.md, tools/dev.py
- RECOMMENDED ACTION: Study the sim-versus-view split and the rule that placing a place creates a job. Lane recommendation PETAL-01. The single dev command is a PETAL-08 echo of tools/run.sh, not a second runner to vendor.
- DO NOT: Do not copy scenes, scripts, art, or the 4.7.2 project into Petalwild.; Do not treat the MIT code grant as a grant on the CC-BY art.
- RESEARCH DOCUMENT: docs/research/wave0/r3_notes.md

## IsoCity

- NAME: IsoCity
- URL: https://github.com/amilich/isometric-city
- SOURCE REPOSITORY: amilich/isometric-city
- PURPOSE: Isometric city and park sim: zoned growth, budgets, pedestrian crowds, and a save worker. Discovered from the bobeff index City-Building section.
- LANGUAGE: TypeScript
- ENGINE: Custom (Next.js, HTML canvas)
- LAST ACTIVITY: 2026-06-30
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT. README says the project is distributed under the MIT License and points at LICENSE. simulation.ts has no Micropolis or GPL header.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: A readable pedestrian crowd and zone-demand loop for the lane beyond the hedge, written in one language, without a GPL city engine.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: f1bbce8a93fae61d2446d1ece50309f26531d987
- FILES / SUBSYSTEMS: src/lib/simulation.ts, src/lib/saveWorker.ts, src/components/game/pedestrianSystem.ts, src/games/isocity/types/zones.ts
- RECOMMENDED ACTION: Study pedestrianSystem.ts and the zone types. Reimplement only a small demand counter for stall passers in original GDScript. Lane recommendation PETAL-04 because the bodies are people. Hailo did not choose.
- DO NOT: Do not copy simulation.ts into scripts/.; Do not treat the web renderer as a Godot scene.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## Harvest Moon 2.0

- NAME: Harvest Moon 2.0
- URL: https://github.com/Kenny-Haworth/Harvest-Moon-2.0
- SOURCE REPOSITORY: Kenny-Haworth/Harvest-Moon-2.0
- PURPOSE: Godot 3 farm loop: till, water, plant, harvest, seasons, inventory stacks, and a dictionary save. Found via the index's Trilarion list as the only GDScript farming sim.
- LANGUAGE: GDScript
- ENGINE: Godot 3
- LAST ACTIVITY: 2020-07-15
- LICENCE: RED (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT, and LICENSE is an MIT grant, copyright 2020 Kendall Haworth. That grant does not cover the art. The tree contains tilesets/Pokemon tiles.png (a 2240x2400 sheet of Pokémon-style centers, gyms, and creature sprites) and tilesets/DungeonCrawl_ProjectUtumnoTileset.png with no separate asset licence.
- PETALWILD TARGET: PETAL-01
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: low
- INTEGRATION COST: high
- EXPECTED BENEFIT: None. Petalwild already grows, waters, and saves crops. The repo's growth functions are a student tile loop beside ripped sheets.
- DECISION: REJECT
- ASSIGNED PETAL LANE: PETAL-01
- COMMIT: 8d9ccc4e49ad86b22eb38a9e00ddfa60150cd00c
- FILES / SUBSYSTEMS: LICENSE, Harvest Moon 2.0/areas/Farm.gd, Harvest Moon 2.0/ui/inventory/Inventory.gd, Harvest Moon 2.0/save_load/GameManager.gd, Harvest Moon 2.0/tilesets/Pokemon tiles.png, Harvest Moon 2.0/tilesets/DungeonCrawl_ProjectUtumnoTileset.png
- RECOMMENDED ACTION: Reject the repository. Do not study it as a growth reference. Lane it would have touched is PETAL-01. Hailo did not choose.
- DO NOT: Do not copy scripts, scenes, or tilesets.; Do not treat the MIT LICENSE as a grant on the PNG sheets.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## JSettlers

- NAME: JSettlers
- URL: https://github.com/jsettlers/settlers-remake
- SOURCE REPOSITORY: jsettlers/settlers-remake
- PURPOSE: Carrier and flag logistics for a Settlers III remake: movables, a flags grid, and goods moving between buildings. Index Real-Time strategies lists Freeserf; this MIT remake is the permissive carrier model found from the linked Trilarion catalog.
- LANGUAGE: Java
- ENGINE: Custom (Java2D / Android)
- LAST ACTIVITY: 2022-10-01
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id MIT. LICENSE.txt is the MIT License, copyright 2015. README says play requires the original Settlers III GFX and SND folders, which are not in the repo. The repo is archived. Fork paulwedeck/settlers-remake is also MIT and also archived.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: A worked example of stocks, flags, and carriers so a later parish warehouse does not invent goods movement from scratch.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: 456528bb304eb57d30d8e86b7a2227180b0dd7f0
- FILES / SUBSYSTEMS: LICENSE.txt, jsettlers.logic/src/main/java/jsettlers/logic/movable/Movable.java, jsettlers.logic/src/main/java/jsettlers/logic/movable/MovableStrategy.java, jsettlers.logic/src/main/java/jsettlers/logic/map/grid/flags/FlagsGrid.java, jsettlers.logic/src/main/java/jsettlers/logic/map/grid/movable/MovableGrid.java
- RECOMMENDED ACTION: Study the flag grid and movable strategies as a textbook. If the stall later moves goods, write an original carrier in GDScript. Lane recommendation PETAL-08. Hailo did not choose.
- DO NOT: Do not copy Java sources into the game.; Do not download Settlers III GFX or SND.; Do not vendor the archived tree.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## CorsixTH

- NAME: CorsixTH
- URL: https://github.com/CorsixTH/CorsixTH
- SOURCE REPOSITORY: CorsixTH/CorsixTH
- PURPOSE: Staff and patient queues for a Theme Hospital reimplementation. Needs, rooms, and walk-to-treatment are the service loop a parish resident already sketches. Index Business and Tycoon section.
- LANGUAGE: Lua, C++
- ENGINE: Custom (SDL2, Lua)
- LAST ACTIVITY: 2026-09-24
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: GitHub licence API spdx_id NOASSERTION because LICENSE.txt bundles many third-party grants. The project grant itself, after the copyright list, is the MIT permission paragraph (copyright 2009-2026 the CorsixTH authors). Later sections of the same file are zlib, BSD, LGPL, and SIL OFL notices for vendored libraries.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: A mature, permissive model of people who queue, walk to a room, and finish a service. Useful when residents stop being a single scripted round.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: 171587f67e8a7a0188d2c606e93bb98fc3acae77
- FILES / SUBSYSTEMS: LICENSE.txt, CorsixTH/Lua/humanoid_action.lua, CorsixTH/Lua/humanoid_actions/, CorsixTH/Lua/hospital.lua, CorsixTH/Lua/entities/
- RECOMMENDED ACTION: Study the humanoid action queue only. Keep Petalwild needs in the existing utility scorer. Lane recommendation PETAL-04. Hailo did not choose.
- DO NOT: Do not copy Lua or C++ into scripts/.; Do not fetch Theme Hospital data.; Do not vendor the LGPL or OFL blobs that share LICENSE.txt.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## DwarfCorp

- NAME: DwarfCorp
- URL: https://github.com/Blecki/dwarfcorp
- SOURCE REPOSITORY: Blecki/dwarfcorp
- PURPOSE: Colony jobs: dwarves take work, path, and build. The closest permissive-ish job AI to a resident who waters and feeds beds. Found from the Trilarion list linked by the index.
- LANGUAGE: C#
- ENGINE: MonoGame / XNA
- LAST ACTIVITY: 2020-07-04
- LICENCE: REVIEW (NOASSERTION)
- LICENCE EVIDENCE: GitHub licence API spdx_id NOASSERTION. LICENSE.txt is titled Modified MIT License, copyright 2015 Completely Fair Games Ltd. The code grant reads as MIT, then it declares images, 3D models, sound, and music PROPRIETARY and forbids them in derivative works. The tree also contains SteamSDK and SteamWorks.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: A job-queue shape for Bram and Nessa: a dwarf picks a task, walks, and finishes. The art and the Steam SDK are not part of that lesson.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: 45a1c39663fce226ea4b4b868f0a43a0570c877a
- FILES / SUBSYSTEMS: LICENSE.txt, DwarfCorp/Entities/Dwarves/Dwarf.cs, DwarfCorp/Entities/Dwarves/NonPlayerDwarf.cs, DwarfCorp/Entities/Plants/
- RECOMMENDED ACTION: Study the non-player dwarf task pick as an idea. Do not port the classes. Lane recommendation PETAL-04. Hailo did not choose.
- DO NOT: Do not copy C# sources.; Do not copy images, models, audio, or anything under SteamSDK or SteamWorks.; Do not treat Modified MIT as SPDX MIT.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## Space Station 14

- NAME: Space Station 14
- URL: https://github.com/space-wizards/space-station-14
- SOURCE REPOSITORY: space-wizards/space-station-14
- PURPOSE: Inventory slots, nutrition, and HTN NPC pathing on the Robust engine. This is the living permissive-code reference for an inventory that is more than a count dictionary, and for a planner that is more than a score. Found from the Trilarion list linked by the index.
- LANGUAGE: C#
- ENGINE: Robust Toolbox
- LAST ACTIVITY: 2026-09-27
- LICENCE: REVIEW (MIT)
- LICENCE EVIDENCE: Content LICENSE.TXT is the MIT License, copyright 2017-2026 Space Wizards Federation. README says most assets are CC-BY-SA 3.0 unless a meta file says otherwise, and some assets are CC-BY-NC-SA 3.0. The RobustToolbox submodule is mixed: legal.md puts code from before 2019-03-13 on GPL-3.0 and later code on MIT, and images on CC-BY-SA 3.0. GitHub reports RobustToolbox as NOASSERTION.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? yes
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: Slot prototypes, item relays, and an entity serializer are the pattern if the stall outgrows a string-to-count map. HTN is the comparison point for the utility scorer, not a replacement.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: b924dedb4f5166b0a1c6411a7a6e529f3e31facc
- FILES / SUBSYSTEMS: LICENSE.TXT, README.md, Content.Shared/Inventory/InventorySystem.cs, Content.Shared/Inventory/InventoryTemplatePrototype.cs, Content.Shared/NPC/RequestHTNMessage.cs, Content.Shared/Nutrition/, RobustToolbox/legal.md, RobustToolbox/Robust.Shared/EntitySerialization/EntitySerializer.cs
- RECOMMENDED ACTION: Study the inventory prototype and the HTN request names only. Keep the petal dictionary until a shop needs slots, then write original GDScript or adopt Gloot. Lane recommendation PETAL-08. Hailo did not choose.
- DO NOT: Do not vendor Space Station 14 or RobustToolbox.; Do not copy CC-BY-SA or CC-BY-NC-SA assets.; Do not copy pre-2019 Robust sources.; Do not install this beside Gloot.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## Egregoria

- NAME: Egregoria
- URL: https://github.com/Uriopass/Egregoria
- SOURCE REPOSITORY: Uriopass/Egregoria
- PURPOSE: Agent city without a grid: desires (home, work, buy food), lane pathfinding, a market, and a simulation that does not store render meshes. Index City-Building section. Shallow-cloned under _research/egregoria for the architecture note only.
- LANGUAGE: Rust
- ENGINE: Custom (wgpu)
- LAST ACTIVITY: 2025-06-02
- LICENCE: REVIEW (GPL-3.0)
- LICENCE EVIDENCE: GitHub licence API spdx_id GPL-3.0. LICENSE in the shallow clone is the GNU General Public License version 3.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: The split Petalwild already wants: souls decide, the map paths, the renderer only caches meshes. Desire modules are a check against the utility scorer, not a new brain to paste.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: ae65c857948a905120474cf93b96dd51cec6d5f6
- FILES / SUBSYSTEMS: LICENSE, ARCHITECTURE.md, simulation/src/souls/desire/home.rs, simulation/src/souls/desire/work.rs, simulation/src/souls/desire/buyfood.rs, simulation/src/map/pathfinding.rs, simulation/src/economy/market.rs, headless/
- RECOMMENDED ACTION: Keep the architecture lesson: deterministic tick, desires as data, renderer cache on the side. Do not port Rust. Lane recommendation PETAL-04. Hailo did not choose.
- DO NOT: Do not copy Rust sources into the game tree.; Do not move the _research/egregoria clone into scripts, assets, or a vendor directory.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## Citybound

- NAME: Citybound
- URL: https://github.com/citybound/citybound
- SOURCE REPOSITORY: citybound/citybound
- PURPOSE: Microscopic households: members take timed tasks and trips, and a vegetable farm publishes produce onto a market. This is the index city builder whose farm household is the plant-economy lesson. Shallow-cloned under _research/citybound.
- LANGUAGE: Rust
- ENGINE: Custom (Rust, browser UI)
- LAST ACTIVITY: 2023-01-07
- LICENCE: REVIEW (AGPL-3.0)
- LICENCE EVIDENCE: GitHub licence API spdx_id AGPL-3.0. LICENSE.txt is the GNU Affero General Public License version 3. README points at that file.
- PETALWILD TARGET: PETAL-01
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: A farm as a household that offers a crop on a time window, instead of another soil tick. Useful if parish plots ever sell into a market rather than a single stall tin.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-01
- COMMIT: 817de551d2bc96c90d0b7c74af4872454f42b44c
- FILES / SUBSYSTEMS: LICENSE.txt, cb_simulation/src/economy/households/tasks/mod.rs, cb_simulation/src/economy/households/household_kinds/vegetable_farm/mod.rs, cb_simulation/src/economy/market/mod.rs, cb_simulation/src/transport/pathfinding/mod.rs
- RECOMMENDED ACTION: Study the vegetable-farm household as the shape of a crop offer. Keep Petalwild growth in soil_field.gd. Lane recommendation PETAL-01. Hailo did not choose.
- DO NOT: Do not copy Rust sources.; Do not move the _research/citybound clone into the game tree.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## Julius

- NAME: Julius
- URL: https://github.com/bvschaik/julius
- SOURCE REPOSITORY: bvschaik/julius
- PURPOSE: Caesar III walker services: priests, engineers, markets, and cart pushers roam until they cover a building. Index City-Building section. This is the service-coverage walk, which is the crowd pattern a garden uses when not every visitor has a mind.
- LANGUAGE: C
- ENGINE: Custom (SDL)
- LAST ACTIVITY: 2026-09-12
- LICENCE: REVIEW (AGPL-3.0)
- LICENCE EVIDENCE: GitHub licence API spdx_id AGPL-3.0. Trilarion's entry, linked from the index's other-lists section, records the same AGPL-3.0 grant.
- PETALWILD TARGET: PETAL-04
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: Service figures that wander a district and mark coverage, so off-screen passers can stay statistics until they enter the parish.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-04
- COMMIT: 34d1ecd54befb845c0139b371fa8a0438210dac1
- FILES / SUBSYSTEMS: src/figuretype/service.c, src/figuretype/cartpusher.c, src/figuretype/market.c, src/figure/movement.c, src/figure/service.c
- RECOMMENDED ACTION: Study service coverage as a radius and a count, not as a port of figuretype. Lane recommendation PETAL-04. Hailo did not choose.
- DO NOT: Do not copy C sources.; Do not fetch Caesar III data files.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## OpenTTD

- NAME: OpenTTD
- URL: https://github.com/OpenTTD/OpenTTD
- SOURCE REPOSITORY: OpenTTD/OpenTTD
- PURPOSE: Versioned save chunks and cargo packets. Petalwild's petal_save refuses any version other than 1. Index Business and Tycoon section. Recorded because the save schema is a hard system, not because the transport game should be ported.
- LANGUAGE: C++
- ENGINE: Custom
- LAST ACTIVITY: 2026-09-26
- LICENCE: REVIEW (GPL-2.0)
- LICENCE EVIDENCE: GitHub licence API spdx_id NOASSERTION. README section 3.0 says OpenTTD is licensed under the GNU General Public License version 2.0 and points at COPYING.md. Named third-party files (squirrel, md5, fmt, nlohmann json) use Zlib or MIT and do not relicense the game.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: The pattern of a save version, per-chunk loaders, and an afterload pass. Cargo packets are the reference if the stall tin ever tracks lots instead of one coin counter.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: b9a4a1831451718f0650de59f1c52f4fe5cea73a
- FILES / SUBSYSTEMS: README.md, COPYING.md, src/saveload/saveload.h, src/saveload/saveload.cpp, src/saveload/afterload.cpp, src/saveload/cargopacket_sl.cpp, src/saveload/economy_sl.cpp
- RECOMMENDED ACTION: Add original schema migrations in petal_save when a second version exists. Do not import the saveload tables. Lane recommendation PETAL-08 for cargo; the save file itself has no lane in 01-08. Hailo did not choose.
- DO NOT: Do not copy saveload sources.; Do not adopt OpenTTD's chunk format as the petal JSON schema.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## Unknown Horizons Godot port

- NAME: Unknown Horizons Godot port
- URL: https://github.com/unknown-horizons/godot-port
- SOURCE REPOSITORY: unknown-horizons/godot-port
- PURPOSE: Godot production lines, inventory slots, and a tile pathfinder for an economy city builder. Index City-Building section names this port beside the FIFE original. It is the Godot-shaped production graph.
- LANGUAGE: GDScript
- ENGINE: Godot
- LAST ACTIVITY: 2026-09-14
- LICENCE: REVIEW (GPL-2.0)
- LICENCE EVIDENCE: GitHub licence API spdx_id GPL-2.0. LICENSE.md is the GNU General Public License version 2. README says the project uses GPL version 2, and that art and audio have their own licences.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high
- EXPECTED BENEFIT: A Godot component split: a production line, an inventory slot, and a pathfinding manager. The shape matches a stall that crafts from beds, without taking the GPL scripts.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: fa0d5146162ae2e0bc8966a0254c6a2c4585dc54
- FILES / SUBSYSTEMS: LICENSE.md, README.md, Assets/World/Components/ProductionLine/ProductionLineComponent.gd, Assets/UI/BasicControls/InventorySlot.gd, Assets/UI/TabWidgets/InventoryTab.gd, Assets/World/Tilemaps/PathfindingManager.gd, Assets/World/Tilemaps/Pathfinder.gd
- RECOMMENDED ACTION: Study the component names. Keep Petalwild production as data in items.json and plants.json. Lane recommendation PETAL-08. Hailo did not choose.
- DO NOT: Do not copy GDScript, scenes, or assets from the port.; Do not prefer this over the MIT Gloot note in R2 for inventory UI.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## MicropolisCore

- NAME: MicropolisCore
- URL: https://github.com/SimHacker/MicropolisCore
- SOURCE REPOSITORY: SimHacker/MicropolisCore
- PURPOSE: The maintained SimCity cellular engine: zone demand, power, and map scan. The index points at micropolisJS; that port's original is this engine. Recorded for the L4 demand layer, not as a city to embed.
- LANGUAGE: C++, TypeScript
- ENGINE: Custom (headless core, web UI)
- LAST ACTIVITY: 2026-09-18
- LICENCE: REVIEW (GPL-3.0-or-later)
- LICENCE EVIDENCE: GitHub licence API spdx_id NOASSERTION. LICENSE and gpl-3.0.txt grant GPL-3.0-or-later, copyright 1989-2007 Electronic Arts, plus GPL section 7 terms: no SimCity trademark, mark modifications, and an indemnity if you add a warranty. MicropolisPublicNameLicense.md is a separate, revocable, non-commercial trademark licence for the name Micropolis. The older SimHacker/micropolis dump has no root licence file (API spdx NONE). graememcc/micropolisJS COPYING is the same GPL-3.0 plus the EA terms.
- PETALWILD TARGET: PETAL-08
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: high
- INTEGRATION COST: high
- EXPECTED BENEFIT: The canonical lesson that most of a city is a cellular demand scan, not an agent. That is the L4 passer count Petalwild already sketches, with a real model behind it.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-08
- COMMIT: 2bfe12afc782a5e0f269a31b9bfb324c6d1e4fad
- FILES / SUBSYSTEMS: LICENSE, gpl-3.0.txt, MicropolisGPLLicenseNotice.md, MicropolisPublicNameLicense.md, apps/micropolis/src/lib/MicropolisSimulator.ts
- RECOMMENDED ACTION: Study the simulator as the reason L4 stays statistical. Do not import the scan. Lane recommendation PETAL-08. Hailo did not choose.
- DO NOT: Do not copy the C++ core or the TypeScript simulator.; Do not use the names SimCity or Micropolis in the game.; Do not clone SimHacker/micropolis as a substitute.
- RESEARCH DOCUMENT: docs/research/wave0/r4_review.md

## Astra index additions

## OpenCityMaker

- NAME: OpenCityMaker
- URL: https://github.com/derek-wangpch/OpenCityMaker
- SOURCE REPOSITORY: derek-wangpch/OpenCityMaker
- PURPOSE: A 4×4 procedural city 2048. Twelve cities, eleven silhouette tiers, local saves.
- LANGUAGE: TypeScript
- ENGINE: Three.js
- LAST ACTIVITY: 2026-09-21
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: LICENSE is the MIT licence, copyright 2026 Derek Wang. GitHub SPDX MIT.
- PETALWILD TARGET: PETAL-06
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: low as a note, high as an import
- EXPECTED BENEFIT: A town can read as a few silhouettes on a board.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-06
- COMMIT: dc78e7fe87809470bfe13f95cee6c90b195cd2dd
- FILES / SUBSYSTEMS: README.md, LICENSE
- RECOMMENDED ACTION: Keep the zoom idea. Do not import the board or the landmark atlas.
- DO NOT: Copy real city names or skyline models into Petalwild.
- RESEARCH DOCUMENT: docs/research/wave0/ASTRA_INDEX_PASS.md

## Melon Lab

- NAME: Melon Lab
- URL: https://github.com/Ayi1337/gpt6-astra-one-shot-games
- SOURCE REPOSITORY: Ayi1337/gpt6-astra-one-shot-games
- PURPOSE: 2D soft fruit that merges. An eighteen-point ring with edge, diameter, and area terms.
- LANGUAGE: JavaScript
- ENGINE: browser, no engine
- LAST ACTIVITY: 2026-09-05
- LICENCE: RED (none)
- LICENCE EVIDENCE: No LICENSE file in the repository. GitHub licence API returns none. Commit 4178b08.
- PETALWILD TARGET: PETAL-03
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? no
- QUALITY: medium
- INTEGRATION COST: high, and not allowed
- EXPECTED BENEFIT: None over the MIT Gloop card. No grab and no throw.
- DECISION: REJECT
- ASSIGNED PETAL LANE: PETAL-03
- COMMIT: 4178b08d569372a1492878d73c6018a90f564e5b
- FILES / SUBSYSTEMS: melon-lab/src/public/physics.js
- RECOMMENDED ACTION: Leave it. Use the Gloop scale note and the Jelly-Baby feel note.
- DO NOT: Copy physics.js or the fruit sprites.
- RESEARCH DOCUMENT: docs/research/wave0/ASTRA_INDEX_PASS.md

## Godot store pass

## Starter Kit City Builder

- NAME: Starter Kit City Builder
- URL: https://github.com/KenneyNL/Starter-Kit-City-Builder
- SOURCE REPOSITORY: KenneyNL/Starter-Kit-City-Builder
- PURPOSE: Godot 4.6 grid city builder. Place, rotate, demolish, save. Sample town included.
- LANGUAGE: GDScript
- ENGINE: Godot 4.6 project, opened on 4.8-dev6
- LAST ACTIVITY: 2026-03-12
- LICENCE: GREEN (MIT code, CC0 models/sprites/sounds, SIL OFL font)
- LICENCE EVIDENCE: GitHub SPDX MIT. LICENSE.md copyright 2025 Kenney. Store page states models, sprites, and sounds are CC0. fonts/license.txt is SIL OFL 1.1 for Lilita One.
- PETALWILD TARGET: PETAL-06
- DIRECTLY REUSABLE? yes
- PORTABLE? yes
- REFERENCE ONLY? no
- QUALITY: high for a starter grid
- INTEGRATION COST: low. Paths live under third_party/kenney_city_builder. Play opens scenes/parish.tscn.
- EXPECTED BENEFIT: A town you can place on this pin without writing a grid editor.
- DECISION: ADOPT
- ASSIGNED PETAL LANE: PETAL-06
- COMMIT: 4535092b740b378b700efd9df9e27a631815b84a
- FILES / SUBSYSTEMS: scripts/builder.gd, scenes/main.tscn, models/, sample map/map.res
- RECOMMENDED ACTION: Keep scenes/parish.tscn. Add pieces at the end of the structure array.
- DO NOT: Point run/main_scene at the parish. Drop the OFL file.
- RESEARCH DOCUMENT: docs/research/wave0/GODOT_STORE_PASS.md

## CityCrafter3D

- NAME: CityCrafter3D
- URL: https://github.com/immaculate-lift-studio/CityCrafter3D
- SOURCE REPOSITORY: immaculate-lift-studio/CityCrafter3D
- PURPOSE: Editor plugin that lays blocks, roads, and PackedScene buildings.
- LANGUAGE: GDScript
- ENGINE: Godot 4.4 addon
- LAST ACTIVITY: not vendored
- LICENCE: GREEN (MIT)
- LICENCE EVIDENCE: addons/citycrafter/LICENSE is the MIT licence, copyright 2025 immaculate-lift-studios.
- PETALWILD TARGET: PETAL-06
- DIRECTLY REUSABLE? no
- PORTABLE? no
- REFERENCE ONLY? yes
- QUALITY: medium
- INTEGRATION COST: high. Default block size is 200 and street width is 25. Generation refuses to run until building scenes are assigned.
- EXPECTED BENEFIT: None over the Kenney grid for a parish you can walk.
- DECISION: STUDY
- ASSIGNED PETAL LANE: PETAL-06
- COMMIT: not pinned. Sparse read of addons/citycrafter only.
- FILES / SUBSYSTEMS: citycrafter.gd, city_configuration.gd
- RECOMMENDED ACTION: Leave it out. The parish scene is the town.
- DO NOT: Vendor the plugin, the example gif, or the Kenney commercial city-kit blobs.
- RESEARCH DOCUMENT: docs/research/wave0/GODOT_STORE_PASS.md

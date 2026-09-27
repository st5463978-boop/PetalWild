# Kanban

Wave 0 handoff. No Hermes or Slack list was reachable from this workspace, so this file is the board the build lanes read.

The Astra second pass (`docs/research/wave0/ASTRA_INDEX_PASS.md`) did not add a card. Melon Lab is an unlicensed fruit ring. CityMaker is a readability note for PETAL-06, not a port.

A card is an opportunity. It does not replace a working controller.

## Godot grab feel

TITLE: Native jelly grab, flick, and settle

SOURCE URL: https://github.com/scottstts/Jelly-Baby

SOURCE COMMIT/TAG: 19fc6ea487262f7a32fa8935712624ae5249db68

LICENCE: GPL-3.0-only (REVIEW)

DECISION: STUDY

TARGET PETAL LANE: PETAL-03

FILES / SUBSYSTEMS OF INTEREST: `scripts/presentation/jelly_actor.gd`, `shaders/jelly.gdshader`, `scripts/presentation/grove_view.gd`. Jelly-Baby files were read only as names: `src/physics/grab.ts`, `src/physics/soft-body.js`, `src/physics/orientation-safety.js`.

EXPECTED BENEFIT: A pull lags, stretch follows the pull, and a flick throws harder than a slow drag of the same length. The landing settles instead of bouncing like a ball.

INTEGRATION COST: low, inside the existing actor

RISKS: Copying Jelly-Baby source, meshes, or constants would put GPL-3.0-only on Petalwild. A shader displacement can disagree with the grabbed silhouette.

RECOMMENDED ACTION: Rewrite the feel in `jelly_actor.gd`. Rate-limit the grab target. Stretch along the pull. Keep the pull for one or two ticks after release, then throw with that recent velocity. Damp the squash back to rest. Keep a short contact as a pet. While there, either drive a shader uniform that exists or stop setting `impact` and `push`.

DO NOT: Replace the jelly controller. Import the repository. Simulate the garden as soft bodies.

RESEARCH DOCUMENT LINK: `docs/research/JELLY_BABY_PORT_ANALYSIS.md`

## Engine spring bones

TITLE: SpringBoneSimulator3D for appendages

SOURCE URL: https://github.com/godotengine/godot

SOURCE COMMIT/TAG: 8898c2b3db32adf6f92c694ffb6dac19af672e5f

LICENCE: MIT (GREEN)

DECISION: ADOPT

TARGET PETAL LANE: PETAL-03

FILES / SUBSYSTEMS OF INTEREST: `scene/3d/spring_bone_simulator_3d.h` in the engine pin. Confirmed present at that commit.

EXPECTED BENEFIT: Crests, leaves, and lobes keep moving after the body stops, without a second jiggle solver.

INTEGRATION COST: low once a bone chain exists. The current jelly has no skeleton, so the cost is the rig, not the node.

RISKS: Calling it on stacked meshes does nothing useful. godot-vrm is a REJECT and must not be the way in.

RECOMMENDED ACTION: After an appendage has a Skeleton3D chain, add the engine node. Do this after the grab rewrite, not instead of it.

DO NOT: Vendor godot-vrm. Reimplement Verlet beside this node. Block the grab rewrite on this rig.

RESEARCH DOCUMENT LINK: `docs/research/JELLY_BABY_PORT_ANALYSIS.md`

## Resident brain

TITLE: Keep utility scoring

SOURCE URL: https://github.com/bitbrain/beehave

SOURCE COMMIT/TAG: not vendored

LICENCE: MIT (GREEN). LimboAI, the other tree, is YELLOW because its logo and demo art are CC-BY-4.0.

DECISION: STUDY

TARGET PETAL LANE: PETAL-04

FILES / SUBSYSTEMS OF INTEREST: existing resident needs and utility scoring. Do not add `addons/`.

EXPECTED BENEFIT: Avoids a second brain beside the scorer that already picks actions.

INTEGRATION COST: none if the addon stays out

RISKS: Installing Beehave, LimboAI, goap-godot-4, or Dialogue Manager to "have AI" before a multi-step action needs one.

RECOMMENDED ACTION: Leave the plugins out. If a later action must chain find-then-use, read the goap-godot-4 card first. Proximity talk still does not need Dialogue Manager.

DO NOT: Replace utility scoring. Install LimboAI's CC-BY demo art.

RESEARCH DOCUMENT LINK: `docs/research/wave0/r2_notes.md`

## Parish navigation

TITLE: Do not build an openage flow field yet

SOURCE URL: https://github.com/SFTtech/openage

SOURCE COMMIT/TAG: b23f5df on master, as read on 27 September 2026

LICENCE: GPL-3.0-or-later (REVIEW). GitHub SPDX is NOASSERTION because the grant is in `copying.md`.

DECISION: STUDY

TARGET PETAL LANE: PETAL-07

FILES / SUBSYSTEMS OF INTEREST: Godot navigation server for embodied residents. `docs/SIMULATION_LAYERS.md` for everyone else.

EXPECTED BENEFIT: Saves a portal graph on a parish that does not yet have a crowd sharing one destination.

INTEGRATION COST: none until that crowd exists

RISKS: Copying openage path classes. Linking `SFTtech/nyan`.

RECOMMENDED ACTION: Keep Godot navigation for bodies in view. Keep counts for the rest. The algorithm textbook, when the crowd exists, is Elijah Emerson, Game AI Pro chapter 23.

DO NOT: Import openage. Import nyan. Treat NOASSERTION as MIT.

RESEARCH DOCUMENT LINK: `docs/research/wave0/r2_notes.md`

## Campaign gate

TITLE: Smoke is not a picture

SOURCE URL: https://github.com/PlayableIntelligence/game-creator

SOURCE COMMIT/TAG: not used

LICENCE: none (RED). No `LICENSE` file. The repository is REJECT.

DECISION: REJECT

TARGET PETAL LANE: PETAL-08

FILES / SUBSYSTEMS OF INTEREST: `tools/run.sh`, `tests/smoke.gd`, `tools/orchestration/`

EXPECTED BENEFIT: A worker can tell a gameplay pass from a visual pass without opening an unlicensed plugin.

INTEGRATION COST: none. The gates already exist.

RISKS: Treating headless `PETAL_SMOKE_OK` as proof of the hedge. Installing Godot-MCP into the standard 4.8-dev6 binary.

RECOMMENDED ACTION: Keep the Hailo foreman. Call a change done for play only after `PETAL_SMOKE_OK`. Call it done for a picture only after a `DISPLAY=:1` shot. Say which one was observed.

DO NOT: Vendor game-creator, Godot-MCP, an agent pack, or a gym. Read game-creator as a source.

RESEARCH DOCUMENT LINK: `docs/research/wave0/r3_notes.md`

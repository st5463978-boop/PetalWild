# PetalWild reference notes

Research note for the original game PetalWild. It records licence and architecture only. No source trees were cloned into this repository, and no implementation is reproduced here.

PetalWild may reimplement behaviour and structure in original code. It may not absorb another project's source, data files, or art.

## Original-code policy

PetalWild code is MIT. GPL-family code (GPL or AGPL, including "or later" and "only" variants) is not incorporated unless the project makes an explicit decision to do so. A linking permission, a Commons Clause, or a GitHub licence badge does not count as that decision.

Third-party assets stay on their own licences. They are not relicensed to MIT by being mentioned here, and they are not copied in because a neighbouring engine is free software.

Clean-room reimplementation of an idea is allowed. Copying, translating, or closely adapting source is not.

## 1. Jelly-Baby

<https://github.com/scottstts/Jelly-Baby>

The README states the licence as GPL-3.0-only (GNU GPL version 3.0 only). The repository `LICENSE` is the GPL-3 text. GPL code must not be copied into PetalWild. That includes source and any assets that ship inside the GPL work. A clean reimplementation does not change the licence of the original.

Behaviour ideas we may reimplement cleanly, in our own simulation and presentation:

- a small tactile jelly, sized for a tabletop rather than a battlefield
- drag to stretch
- throw
- wobble that travels through the body after a pull or a landing
- hop
- a face that reacts while the body is stretched or in motion

Those are interaction goals for a close-up creature. The Jelly-Baby implementation is not a dependency.

## 2. openage

<https://github.com/SFTtech/openage>

Licence, from `copying.md` and the README (there is no standard `LICENSE` filename; GitHub therefore reports no SPDX assertion): default project code is GPL-3.0-or-later ("GPLv3 or later" / "GPL3+"). `legal/GPLv3` holds the licence text. A few listed third-party files use other terms (LGPL-2.0 and 3-clause BSD). Those exceptions do not make the engine available under MIT. GPL code must not be copied into PetalWild without an explicit decision. Original commercial game assets are not in the repository and are out of scope; the converter that reads them is not a PetalWild input.

openage is a free engine aimed at the real-time strategy model of the Genie-engine games: many units, data-defined types, and a simulation that is not the same thing as the picture on screen. The useful architectural ideas for a multi-fidelity garden sim:

- **Data-driven entities.** Unit identity lives in a hierarchical, type-checked content language (nyan), not in one class per creature. What something can do is data attached to the type: abilities such as move or gather, with the numbers those abilities need. A gameplay system interprets that data for each instance. Upgrades and variants are further data, so a new creature does not require a new engine branch.
- **Scheduling without a universal tick.** The architecture notes describe simulation time as the driver. There is no fixed simulation step that visits every entity every frame. An event system orders work by simulation time. Curves store how a property changes across time, so the sim can jump to the next moment that matters. A separate clock can run the simulation faster or slower than wall time, while presentation (animation) stays on real time.
- **Large populations.** Activity flow is defined once per type: a chain of actions advanced when an event fires (arrive, storage full, and so on). At runtime an instance only needs its current step and the events it is waiting on. The same flow serves a whole class of entities. Presenter, input, and renderer are decoupled and treated as optional, so a population can be simulated without being drawn. The project also rejects artificial selection caps as a design goal, which is the same pressure PetalWild has: many creatures, few of them on screen at full fidelity.

PetalWild can use that split. Distant or off-screen creatures advance on coarse events (travel, rest, appetite). A creature in hand gets a second, richer presentation: stretch, wobble, face. Both fidelities read the same entity data. None of this is a reason to vendor openage.

## 3. town

<https://github.com/RedPlanetHQ/town>

The `LICENSE` file is titled "Town License". GitHub reports it as Other / no SPDX assertion. The file itself grants the GNU AGPL version 3 or any later version (copyright Poozle Inc.), then adds an AGPL section 7 extra permission about combining a work that uses the library, and a Commons Clause v1.0 condition that withholds the right to sell the software. It is not plain AGPL and it is not MIT. AGPL code must not be copied into PetalWild without an explicit decision. The Commons Clause does not create a path around that rule.

The project is a walkable pixel town: people move through a shared map, and NPCs are tied to places and roles. Architectural ideas, not files to vendor:

- **Places.** A town is a set of buildings and plots. Each building variant exposes slots where an NPC can stand. Authors name the place; the server chooses a cell, a path, and the surrounding fill, and the same edit lands in the same spot because placement is seeded. Walkable space is a property of the place, not something each agent invents.
- **Jobs.** An NPC is authored against one slot: a name, a short description for anyone who walks up, and a role anchored to that place (who they are there and what they do). The role is content. The engine's job is to put that agent in the slot and let the player walk up to them.
- **Schedules.** Timed gatherings are on the project's own roadmap: a creator names a time-boxed event, people are invited, and they show up together. That is the schedule idea worth keeping — agents have somewhere to be, and a time when the place fills — even though a full day-cycle of jobs is not what the current README ships.

For PetalWild: creatures have places in the garden, a role at that place, and times when they are expected there. Pathing and "who is home" can stay coarse until the player walks up.

## 4. VivaPinataPlus

<https://github.com/VivaPinataPlus>

This is a user account with a single public repository, `VivaPinataPlus/VivaPinataPlus`, not an organisation with many repositories. That repository's `LICENSE` states the MIT License (copyright 2024 VivaPinataPlus).

It is systems and modding research only. PetalWild must use original species and original content. Species names, assets, and code from that repository are not copied, even though the stated licence is MIT. The repository was not used as a source of creature design.

## 5. TiP-Recomp

<https://github.com/SolarCookies/TiP-Recomp> exists and has a no-AI policy, so it was not inspected.

## 6. Cities: Skylines topic

<https://github.com/topics/cities-skylines>

City-sim topics were acknowledged as genre research, not as code to vendor. No repository under that topic is a dependency, and none of that code is imported.

## What this note allows

| Source | Licence we found | Allowed use in PetalWild |
| --- | --- | --- |
| Jelly-Baby | GPL-3.0-only | Original reimplementation of the tactile ideas listed above |
| openage | GPL-3.0-or-later by default | Original sim: data-driven entities, event scheduling, optional presentation |
| town | AGPL-3.0-or-later plus Commons Clause | Original model of places, roles, and timed gatherings |
| VivaPinataPlus | MIT stated on the one public repo | Systems reminder only; original species and content |
| TiP-Recomp | Not inspected | No use |
| cities-skylines topic | Not vendored | Genre context only |

Checked against public README, `LICENSE`, and `copying.md` pages on 22 September 2026. Architecture notes for openage also use that repository's own design docs (`doc/code/architecture.md`, nyan and simulation-time overviews, and the engine-core write-up), paraphrased here. If a licence file changes, re-read it before any incorporation decision.

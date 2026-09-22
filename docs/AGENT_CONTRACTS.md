# Agent contracts

PETAL-00 owns integration. Specialists may edit only their directories. Shared files (`project.godot`, `game/core/session.gd`, `game/data/*.json`, `game/world/garden.gd`) change only through PETAL-00.

| Agent | Owns | Must not touch |
| --- | --- | --- |
| PETAL-00 Executive | `game/core/`, `game/world/garden.gd`, `project.godot`, `docs/PETALWILD_MASTER_STATE.md` | Specialist folders except to merge |
| PETAL-01 Garden sim | `game/sim/garden_sim.gd` | Rendering |
| PETAL-02 Ecology | `game/sim/ecology_sim.gd`, `game/data/species.json`, `game/data/plants.json` | Jelly meshes |
| PETAL-03 Jelly | `game/jelly/`, `game/shaders/jelly.gdshader` | Economy |
| PETAL-04 Veg People | `game/residents/`, `game/data/residents.json` | Terrain |
| PETAL-05 World art | `game/world/garden_view.gd`, `game/world/mesh_kit.gd`, `game/world/terrain_field.gd` | Save format |
| PETAL-06 Shaders | `game/shaders/foliage.gdshader`, `game/shaders/water.gdshader` | Game rules |
| PETAL-07 UI | `game/ui/` | Simulation math |
| PETAL-08 Economy | shop fields in `game/data/items.json` and the buy/sell methods, via PETAL-00 review | Trust execution |
| PETAL-09 Havenbrook | `game/sim/town_sim.gd`, `game/data/venues.json`, `game/data/districts.json` | Creature physics |
| PETAL-10 Camera | `game/camera/` | UI theme |
| PETAL-11 Audio | `game/audio/` | Licensed audio dumps without provenance |
| PETAL-12 QA | `game/debug/` | Feature code except fixes |
| PETAL-13 Assets | `third_party/incoming/`, `docs/research/ASSET_HUNT.md` | Dropping raw packs into the garden scene |
| PETAL-14 City | aggregate fields inside `game/sim/town_sim.gd` | Per-citizen physics |
| PETAL-15 LOD | `game/sim/sim_lod.gd` | Raising every entity to hero fidelity |
| PETAL-16 Trust | `game/sim/trust_sim.gd`, `game/data/agents.json` | Any real external action |

## Simulation fidelity

| Level | Who | What runs |
| --- | --- | --- |
| 0 Hero | Held or inspected jelly | Spring grab, squash, face, shader wobble |
| 1 Nearby | Close creatures and Veg People | Wander, needs, schedules, animation |
| 2 District | Far side of the garden | Slower movement, same persistent record |
| 3 Off-screen | Not used while the garden is the whole loaded place | Reserved |
| 4 Aggregate | Havenbrook | Population, jobs, happiness, tourism, land value |

Records in `EcologySim` and `Session.people` are the persistent state. Bodies are rebuilt views. A resident who leaves the frame keeps their state dictionary.

## Active this wave

- PETAL-00 built the integrated garden in this branch.
- PETAL-13 wrote `docs/research/ASSET_HUNT.md` and staged the Asset Quest CC0 demo under `third_party/incoming/`.
- Research notes are in `docs/research/ARCHITECTURE_REFERENCES.md`.

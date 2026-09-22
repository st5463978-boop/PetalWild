# Agent contracts

Wave 1 was integrated by the executive agent in this branch. The tree was empty, so parallel writers would have edited the same new files. The swarm starts on the next wave, and only inside the directories below.

No agent may copy GPL source from Jelly Baby or openage, analyse TiP-Recomp, spend Higgsfield credits, publish, or take an external action. Art-direction changes that spend credits wait for the executive art lead.

| Agent | Owns | Must not touch |
| --- | --- | --- |
| PETAL-00 Executive | `docs/`, `project.godot`, `scenes/`, merge decisions | Feature folders owned below, except to integrate |
| PETAL-01 Garden sim | `scripts/garden/`, `data/plants.json` | Ecology rules, creatures |
| PETAL-02 Ecology | `scripts/ecology/`, `data/species.json` | Creature mesh, shop prices |
| PETAL-03 Jelly physics | `scripts/creatures/` | Shader files (hand a note to PETAL-06) |
| PETAL-04 Veg People | `scripts/people/`, `data/people.json` | Stall prices, camera |
| PETAL-05 World art | `scripts/world/dressing.gd`, `scripts/world/layout.gd`, `scripts/world/props.gd` | Atmosphere, UI |
| PETAL-06 Lighting / shaders | `shaders/`, `scripts/world/atmosphere.gd` | Gameplay scripts |
| PETAL-07 UI | `scripts/ui/`, `scripts/app/` | Simulation data |
| PETAL-08 Economy | `scripts/autoload/economy.gd`, `data/items.json`, `data/shop.json` | Trust |
| PETAL-09 Havenbrook / town | `data/district.json`, future `scripts/town/` | Garden soil |
| PETAL-10 Camera | `scripts/camera/` | Dressing |
| PETAL-11 Audio | `scripts/audio/` | Third-party audio without a licence row |
| PETAL-12 QA | `scripts/debug/`, `tools/` | Balance changes disguised as tests |
| PETAL-13 Asset hunt | `docs/ASSET_HUNT.md`, future `assets/third_party/` | Importing anything that is not GREEN or recorded YELLOW |
| PETAL-14 City sim | future `scripts/city/` | Replacing the garden clock |
| PETAL-15 Performance | notes in `docs/PETALWILD_MASTER_STATE.md` only, until a budget file exists | Speculative threading frameworks |
| PETAL-16 Trust | `scripts/autoload/trust.gd` | Network calls, real accounts |

`scripts/game/garden.gd` is the integrator. Only PETAL-00 edits it while a wave is merging.

## Next assignments (from the wave 1 screenshot compare)

1. PETAL-03 and PETAL-06: Bellhelp still reads as a glossy sphere. Build an authored blossom mesh and seat the seed eyes on the surface. Keep the spring grab. Do not use FEM, and do not copy Jelly Baby code.
2. PETAL-04: Replace the leek, beet, and pea capsules with silhouettes that survive a close camera: face, hands, clothing, and a stance. No vegetable-with-two-dots.
3. PETAL-05 and PETAL-06: The lawn is one green plane. Add hedge rooms, flower drifts, and ground cover that match `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`. PETAL-13 may propose CC0 foliage; PETAL-00 accepts it only after it is recoloured to this palette.

# PETAL-02 — Creature / ecology

Updated 2026-09-27.

## Census (baseline `f96457e`)

| Piece | State | Notes |
| --- | --- | --- |
| Species catalog (`data/species.json`, 9 jellies) | COMPLETE | Bellhelp chain through Gushorn. Veg people stay in PETAL-04. |
| Attraction / residency ranks | COMPLETE | `Ecology` + `EcologyRules`. Settle uses `/decide` (offline default: settle). |
| Breeding | PARTIAL | Bellhelp and Bulrush romance + one young. Other species have no pair. |
| Plant genetics | COMPLETE | `PlantGenetics` + mixed-bed readout. |
| Feeding / bite | COMPLETE | Residents bite their food plant. Pegapear keeps dusk/peach hours. |
| Habitat as data | was MISSING | Now `habitat` on plants and species. |
| Companion / crowd growth | was MISSING | `likes` / `crowd` on plants. Parish and bed name it. |
| Creature hunger | was MISSING | `Jelly.hunger`. Journal shows Hungry when low. Bite fills it. |
| Duplicate-legacy | DUPLICATE-LEGACY | `game/sim/ecology_sim.gd`, `scripts/sim/petal_sim.gd` sunburst path, `game/data/species.json`. Not the running garden. Left alone. |

## Checkpoint

- Task: player plants a neighbour or a crowded stand and sees plant growth plus creature hunger change.
- Branch: `petal/02-ecology`
- Paths: `data/plants.json`, `data/species.json`, `scripts/ecology/ecology_rules.gd`, `scripts/ecology/ecology.gd`, `scripts/garden/soil_field.gd`, `scripts/creatures/jelly.gd`, `scripts/game/garden.gd`, `scripts/ui/hud.gd`, `tools/smoke.gd`, `tests/test_systems.gd`
- Interface: `Ecology.tick(delta, world, hours=0)`, `EcologyRules.growth_factor` / `garden_line` / `need_line`, `SoilField.neighbor_ids`, world snapshot `plant_counts`, parish `ecology_line`, journal `need`
- Tests: `PETAL_RULES_OK`, `SYSTEMS_OK`, garden `PETAL_SMOKE_OK`
- Blockers: none
- Requests: PETAL-03 can tint a hungry jelly face from `mood == "hungry"`. PETAL-07 already shows the new journal/parish lines.

## Playable now

Till and plant a reed beside a meadowbell: the bed says Reed nearby, the bells grow faster, and the parish page says The meadow leans on the bank. Five meadowbells make the stand Crowded and slow. A hungry resident wants their food plant on the journal card; a bite fills them.

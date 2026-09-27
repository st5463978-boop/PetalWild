# PETAL-02 — Creature / ecology

Updated 2026-09-27. Addendum rules in effect.

## Census (baseline `f96457e`)

| Piece | State | Notes |
| --- | --- | --- |
| Species catalog (`data/species.json`, 9 jellies) | COMPLETE | Bellhelp chain through Gushorn. Veg people stay in PETAL-04. |
| Attraction / residency ranks | COMPLETE | `Ecology` + `EcologyRules`. Settle uses `/decide` (offline default: settle). |
| Breeding | PARTIAL | Bellhelp and Bulrush romance + one young. Other species have no pair. |
| Plant genetics | COMPLETE | `PlantGenetics` + mixed-bed readout. |
| Feeding / bite | COMPLETE | Residents bite their food plant. Pegapear keeps dusk/peach hours. |
| Habitat as data | COMPLETE | `habitat` on plants and species. Parish tallies stands. |
| Companion / crowd growth | COMPLETE | `likes` / `crowd` on plants. Parish and bed name it. |
| Creature hunger | COMPLETE | `Jelly.hunger`. Journal shows Hungry when low. Bite fills it. |
| Duplicate-legacy | DUPLICATE-LEGACY | `game/sim/ecology_sim.gd`, `scripts/sim/petal_sim.gd` sunburst path, `game/data/species.json`. Not the running garden. Left alone. |
| Qwen3-VL visual QA | MISSING | Not in this tree. Frames inspected directly. |

## Checkpoint

- Task: parish habitat tally + capture evidence of companion ecology.
- Branch: `petal/02-ecology`
- Paths: as before, plus `docs/screenshots/ecology_parish.png`
- Interface: `EcologyRules.habitat_line`, parish `habitat_line`, `SimLod.district_stats["habitats"]`
- Tests run: `PETAL_RULES_OK` pass, `SYSTEMS_OK` pass, garden `PETAL_SMOKE_OK` pass, `PETAL_CAPTURE_OK` pass
- Visual QA: `docs/screenshots/ecology_parish.png` shows `The meadow leans on the bank.` and `Habitats · Bank 5, Cane 3, Dusk 1, Loam 1, Meadow 4`. A close bed shot was dropped after one framing miss (camera into empty night).
- Blockers: none
- Requests: PETAL-03 can tint a hungry jelly face from `mood == "hungry"`. PETAL-08 can copy this receipt into campaign state.

## Playable now

Till and plant a reed beside a meadowbell: the bed says Reed nearby, those bells grow faster, and the Parish tab says The meadow leans on the bank plus a habitat tally. Five meadowbells make the stand Crowded and slow. A hungry resident wants their food plant on the journal card; a bite fills them.

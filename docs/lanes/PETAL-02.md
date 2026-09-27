# PETAL-02 — Creature / ecology

Updated 2026-09-27. Addendum rules in effect. Pass 2 on the integrated 08 tree.

## Census (baseline `f96457e`)

| Piece | State | Notes |
| --- | --- | --- |
| Species catalog (`data/species.json`, 9 jellies) | COMPLETE | Bellhelp chain through Gushorn. Veg people stay in PETAL-04. |
| Attraction / residency ranks | COMPLETE | `Ecology` + `EcologyRules`. Settle uses `/decide` (offline default: settle). |
| Breeding | COMPLETE | Bellhelp and Bulrush keep pair+young. Berrypatch, Reedic, Cirlark, Grapling, and Dusknip now romance when a second resident meets a nest of their food plant. Pegapear and Gushorn stay cap-1 rares. |
| Plant genetics | COMPLETE | `PlantGenetics` + mixed-bed readout. |
| Feeding / bite | COMPLETE | Residents bite their food plant. Pegapear keeps dusk/peach hours. Pouch feed fills hunger without a bite. Vale carts of that crop scent-feed matching jellies. |
| Habitat as data | COMPLETE | `habitat` on plants and species. Parish tallies stands. |
| Companion / crowd growth | COMPLETE | `likes` / `crowd` on plants. Parish and bed name it. |
| Creature hunger | COMPLETE | `Jelly.hunger`. Journal shows Hungry when low. Bite, pouch, or a vale cart fills it. |
| Duplicate-legacy | DUPLICATE-LEGACY | `game/sim/ecology_sim.gd`, `scripts/sim/petal_sim.gd` sunburst path, `game/data/species.json`. Not the running garden. Left alone. |
| Qwen3-VL visual QA | MISSING | Not in this tree. Frames inspected directly. |

## Checkpoint (pass 1)

- Task: parish habitat tally + capture evidence of companion ecology.
- Branch: `petal/02-ecology`
- Paths: as before, plus `docs/screenshots/ecology_parish.png`
- Interface: `EcologyRules.habitat_line`, parish `habitat_line`, `SimLod.district_stats["habitats"]`
- Tests run: `PETAL_RULES_OK` pass, `SYSTEMS_OK` pass, garden `PETAL_SMOKE_OK` pass, `PETAL_CAPTURE_OK` pass
- Visual QA: `docs/screenshots/ecology_parish.png` shows `The meadow leans on the bank.` and `Habitats · Bank 5, Cane 3, Dusk 1, Loam 1, Meadow 4`. A close bed shot was dropped after one framing miss (camera into empty night).
- Blockers: none
- Requests: PETAL-03 can tint a hungry jelly face from `mood == "hungry"`. PETAL-08 can copy this receipt into campaign state.

## Pass 2

Merged `petal/08-integration` @ `3402530` first. Three play-feel upgrades on that tree:

1. **Nests and more pairs.** Romance is no longer only Bellhelp and Bulrush. Five more species court when two residents meet a nest of their food plant (`romance.nest`). A ripe nest bed reads `Nest.` Parish names the courtship (`Berrypatch is courting in the canes.`).
2. **Clearer hunger and courtship.** Inspecting a hungry face names the food and offers **Feed from the pouch**. Parish shows courtship and a forage line when the kettle or pouch is holding the last of a food crop.
3. **Neighbour hooks.** PETAL-05: `forage_line` names hedge tea steeping the Meadowbell Bellhelp wants. PETAL-07: a vale cart delivered to Hollow scents matching jellies (`taste_cart`) so they taste the crop from Reedbank or Thatchmere.

- Paths: `data/species.json`, `scripts/ecology/ecology_rules.gd`, `scripts/ecology/ecology.gd`, `scripts/game/garden.gd`, `scripts/ui/hud.gd`, `tools/smoke.gd`, `tests/test_systems.gd`, `docs/screenshots/ecology_parish.png`
- Interface: `EcologyRules.courtship_line`, `forage_line`, `nest_plot_bit`, `romance.nest`; `Ecology.taste_cart`, `Ecology.feed`; garden `feed_inspected`
- Tests: nest/courtship/forage in `PETAL_RULES_OK` and `SYSTEMS_OK`; garden smoke feeds from the pouch, scents a Thatchmere cart, and nests Berrypatch
- Visual QA: recapture `ecology_parish.png` with the courtship line on the Parish tab. Qwen3-VL is not operational here.
- Did not edit `docs/PETAL_CAMPAIGN_STATE.md` (PETAL-08).

## Playable now

Till and plant a reed beside a meadowbell: the bed says Reed nearby, those bells grow faster, and the Parish tab says The meadow leans on the bank plus a habitat tally. Five meadowbells make the stand Crowded and slow. A hungry resident wants their food plant on the journal card; a bite, a pouch feed, or a vale cart of that crop fills them. Two Berrypatch in a three-bramble nest court, the ripe cane says Nest, and the parish names the courtship. Stocking the kettle while the meadow is bare tells you the tea is steeping the bells they wanted.

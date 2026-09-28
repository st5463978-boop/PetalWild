# PETAL-05 Factorio / production / economy

Updated 2026-09-27. Pass 2 on `petal/08-integration` `3402530`.

## Task

End-to-end hedge-tea chain on the existing stall tin, pouch, and crop harvest: gather peach + meadowbell, steep in the tea-house kettle, carry to the stall crate, sell for petals. The crate caps at 3. A full crate, a shut stall, or a missing crop can stop the chain; selling a cup or restocking recovers it.

## Branch / commit

- Branch: `petal/05-economy`
- Last commit: pass-2 mill (jam, sip, lane shortage) on `petal/08-integration` `3402530`
- Baseline: `cursor/dpo-cpu-decide-9cb0` (`petal-campaign-baseline-20260927`)
- PR: https://github.com/st5463978-boop/PetalWild/pull/7

## Census (before this lane)

| Piece | State |
| --- | --- |
| Petal coins, pouch, seed/fertiliser/kit shop | COMPLETE |
| Harvest into pouch, crop sell, Nessa/Bram wants | COMPLETE |
| Stall hours, tin, +1 passer sale | COMPLETE |
| Venue demand counters | PARTIAL (numbers only) |
| Recipes, kettle, crate buffer, delivery | MISSING (now added) |
| Sidelined grove shop in `scripts/sim/` | DUPLICATE-LEGACY (untouched) |

## Paths

- `data/recipes.json` — hedge-tea recipe
- `data/items.json` — `hedge_tea` goods
- `scripts/economy/parish_chain.gd` — hopper, kettle, crate, bottleneck line
- `scripts/autoload/economy.gd` — mill on the existing Economy autoload
- `scripts/autoload/content_db.gd` — recipe catalog
- `scripts/game/garden.gd` — click kettle/crate, Nessa carry decide, parish line, smoke
- `scripts/ui/hud.gd` — stall Kettle section, parish kettle line
- `scripts/world/props.gd` — kettle steam, crate cup
- `tests/test_systems.gd` — build / disrupt / recover

## Player actions

1. Tend a ripe peach and a ripe meadowbell.
2. Click the tea-house kettle (or stall → Stock the kettle).
3. Watch steam; hover the porch for the brew line.
4. Click the stall crate (or Carry tea) when a cup finishes.
5. Sell hedge tea from the crate while the stall is open.
6. A full crate, dusk, or a missing crop stops the flow; sell or harvest to recover.

## Interface

- `Economy.stock_kettle()`, `carry_tea()`, `sell_tea()`, `mill_line(open, worker)`
- `ParishChain` hopper / pot / crate, cap 3
- Offline decide default `carry` when Nessa is here in stall hours
- Save key `economy.mill`

## Tests

- `tests/test_systems.gd` — SYSTEMS_OK (genetics + brew / full crate / recover)
- garden `DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn` — PETAL_SMOKE_OK (kettle wait, steam, porch, crate cap, dusk shut, morning sale, save/load)
- `tools/smoke.gd` — PETAL_RULES_OK
- Expected leaks on garden smoke: 3 CanvasItem RIDs, 6 ObjectDB instances
- `DISPLAY=:1 PETAL_KETTLE_SHOT=1 tools/run.sh res://scenes/garden.tscn` — PETAL_KETTLE_SHOT_OK, frames `docs/screenshots/kettle_brew.png` (porch steam) and `docs/screenshots/kettle_crate.png` (stall Kettle panel: tea on crate, sell 22). Qwen3-VL is not in this tree; it was not used.

## Addendum

Director rules applied: tests are the acceptance evidence; capture complements them. Campaign state file stays with PETAL-08. No PETAL_CAMPAIGN_STATE.md on this branch.

## Requests

- PETAL-04: Nessa’s kettle walk uses `has_chore` to the stall when she carries. Filing/draft/farewell still win.
- PETAL-08: shop prices for tea live on the recipe (`sell_price` 22). Do not duplicate the mill.
- PETAL-00: parish page already shows `kettle_line`; no `project.godot` change.

## Blockers

None.

## Pass 2

Merged `petal/08-integration` (`3402530`) into `petal/05-economy` first. Three playable upgrades on the integrated mill:

1. **Cane jam at the shed.** Ripe bramble into Bram's pan (12 min), jar to the stall crate (cap 3, 16 petals). A second station shares the mill hopper and one brew slot; the pan queues after the kettle. Click the shed, or stall → Pan.
2. **Tea feeds residents.** A present person on `eat` or `social` takes one crate cup an hour (`ParishLife.sip`). Hunger and company rise; a memory records the drink. Empty crate is the new bottleneck for 04's stall visit.
3. **South Lane shortage.** After the road rumour, parish shows `South Lane waits for tea.` or `South Lane has tea on the crate.` Stall HUD names remaining brew minutes.

### Player

7. Harvest a bramble, click the shed pan (or Stock the pan).
8. Watch pan steam; click the crate (or Carry jam) when the jar is ready.
9. Sell cane jam while the stall is open.
10. Leave a cup on the crate when Lumen is stopping at the stall; she drinks it.

### Interface

- `Economy.stock_jam()`, `carry_jam()`, `sell_jam()`
- `ParishChain.JAM`, `_relight()` after a finish
- `ParishLife.sip(id, day)`
- Save key still `economy.mill` (hopper / pot / crate hold jam counts)

### Tests (this pass)

Godot 4.8-dev6, llvmpipe, dummy ALSA.

- `tools/petal_qa.sh` — PETAL_RULES_OK SYSTEMS_OK PETAL_CONTRACTS_OK FOUNDATION_OK JELLY_FEEL_OK RESIDENT_LIFE_OK TOWN_OK REGION_OK PETAL_QA_SCRIPTS_OK
- `DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn` — PETAL_SMOKE_OK (tea chain, sip from crate, pan steam, jam on crate, save/load, vale 5)
- `DISPLAY=:1 PETAL_KETTLE_SHOT=1 tools/run.sh res://scenes/garden.tscn` — PETAL_KETTLE_SHOT_OK
- Frames: `kettle_brew.png` (hover: The kettle is brewing hedge tea), `jam_pan.png` (shed while the pan runs), `kettle_crate.png` (stall: Sell hedge tea 22 (1), Pan, Sell cane jam 16 (1))
- Expected leaks: 3 CanvasItem RIDs, 6 ObjectDB
- Qwen3-VL unused. Campaign state stays PETAL-08.

### Requests

- PETAL-04: `sip` is the mill taking a crate cup; eating still walks without auto-buy from the pouch.
- PETAL-06: lane tea line only after `parish_road_rumour`.
- PETAL-08: jam `sell_price` 16 lives on the recipe. Do not duplicate the mill.

# PETAL-05 Factorio / production / economy

Updated 2026-09-27.

## Task

End-to-end hedge-tea chain on the existing stall tin, pouch, and crop harvest: gather peach + meadowbell, steep in the tea-house kettle, carry to the stall crate, sell for petals. The crate caps at 3. A full crate, a shut stall, or a missing crop can stop the chain; selling a cup or restocking recovers it.

## Branch / commit

- Branch: `petal/05-economy`
- Baseline: `cursor/dpo-cpu-decide-9cb0` (`petal-campaign-baseline-20260927`)

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

- `tests/test_systems.gd` — SYSTEMS_OK (genetics + chain)
- garden `PETAL_SMOKE=1` — PETAL_SMOKE_OK including kettle disrupt/recover
- `tools/smoke.gd` — PETAL_RULES_OK (unchanged ecology rules)

## Requests

- PETAL-04: Nessa’s kettle walk uses `has_chore` to the stall when she carries. Filing/draft/farewell still win.
- PETAL-08: shop prices for tea live on the recipe (`sell_price` 22). Do not duplicate the mill.
- PETAL-00: parish page already shows `kettle_line`; no `project.godot` change.

## Blockers

None.

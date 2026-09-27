# PETAL-06 · SimCity / Cities-scale town

Updated 2026-09-28.

## Task

Settlement that grows past Hedge Hollow without hero-detail simulation for distant folk.

## Branch / commit

- Branch: `petal/06-town`
- From: `cursor/dpo-cpu-decide-9cb0` (`petal-campaign-baseline-20260927`)
- PR: https://github.com/st5463978-boop/PetalWild/pull/9

## Census (before this lane)

| Piece | State |
| --- | --- |
| Garden plots | COMPLETE (soil cells) |
| Town plots | MISSING |
| Parish rooms | PARTIAL (meshes + 0/1 demand) |
| Grove Park | MISSING (catalog stays inactive) |
| Roads | PARTIAL (`data/road_pieces.json` décor; nobody walks the tail) |
| Districts | PARTIAL (one parish record) |
| Services | MISSING |
| Town growth | MISSING |
| Occupancy | PARTIAL (present-person flags) |
| Transport | MISSING (ripe beds counted as passers) |
| Town sim | MISSING in the live scene; DUPLICATE-LEGACY `game/sim/town_sim.gd` (Havenbrook, ignored) |
| LOD L4 aggregate | MISSING (in-frustum clamp is a stand-in) |

## Paths

- `data/town.json`
- `scripts/town/town_sim.gd`
- `scripts/autoload/sim_lod.gd` (`note_aggregate`)
- `scripts/autoload/trust.gd` (`file_park`)
- `scripts/world/layout.gd` (`PARK`)
- `scripts/world/props.gd` (hidden Grove Park lawn)
- `scripts/game/garden.gd` (tick, save, C/M, accept_park)
- `scripts/ui/hud.gd` (parish town lines, Grove Park proposal)
- `tests/test_town.gd`

Did not touch `data/venues.json` (PETAL-09) or `data/districts.json` (PETAL-14). Grove Park in the catalog stays `active: false` so existing smoke still holds.

## Playable

- Parish page (J → Parish, or C / M) shows town folk, lane houses, Grove Park, service cover, a gate-to-park path, and LOD layers.
- After the road rumour is filed, South Lane occupies named households. Vale carts bound for Hollow add to those counts. Far away they sit at aggregate; a near camera promotes two to individual records. Nobody is spawned.
- Hedge tea on the crate or pot seats lane households at the porch as property records. A near porch promotes two sitters. Nobody is poured.
- Nessa then offers Grove Park. Filing it shows a lawn, a path, and a live visitor count south of the gate. Visitors promote the same way.

## Interface

- `TownSim.tick({people, residents, quality, road, park, passers, traffic, tea, hour, weather, near_park, near_lane, near_tea, lane_fill})`
- Folk records with layers `household` / `district` / `property` / `individual`. Hierarchy in `data/town.json`: world → creature.
- `TownSim.aggregate()`, `individuals()`, `folk_ids()`, `occupancy("lane"|"grove_park"|"tea")`
- `Trust.file_park(person_id)` action `parish_park`
- `SimLod.note_town(individuals, distant)`
- Save key `town` includes folk ids so promote/demote round-trips
- `PETAL_TOWN_SHOT=1` captures `docs/screenshots/town_park.png` and `town_parish.png`

## Tests

- `tests/test_town.gd` → `TOWN_OK` (promote/demote ids, vale carts, tea porch)
- `tests/test_systems.gd` → `SYSTEMS_OK`
- `tools/smoke.gd` → `PETAL_RULES_OK`
- `DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn` → `PETAL_SMOKE_OK`
- `DISPLAY=:1 PETAL_TOWN_SHOT=1 tools/run.sh res://scenes/garden.tscn` → `PETAL_TOWN_SHOT_OK`
- Qwen3-VL assessment path is not operational here (CPU decide only). Frames were read directly.
- `tests/smoke.gd` still parse-fails on this tree (Variant `:=`); not this lane.

## Blockers

None yet.

## Pass 2

Merged `petal/08-integration` (`3402530` / campaign `29e278b`) into `petal/06-town` first.

Play-feel on the town rung:

1. **Vale carts fill the lane and lawn.** `RegionSim.traffic("hollow")` adds counted folk to South Lane and Grove Park. Parish page: `Vale carts  N bound here · they fill the lane as counts`.
2. **Hedge tea seats lane folk.** Cups on the kettle pot or stall crate pull households to the tea porch as `property` records. A near camera promotes two to `individual`. Nobody is poured. Parish page: `Tea porch  N with a cup` and `Lane cups at the porch`.
3. **Grove Park reads as a park.** Path to the gate, a third bench, and a live `ParkCount` billboard (`N on the lawn` / `the lawn is quiet`).

Still no distant bodies. Catalog `grove_park.active` stays false. C = town, M = vale.

## Requests

- PETAL-09: Grove Park in `data/venues.json` can stay inactive; town occupancy is the live park.
- PETAL-05: park lawn is a placeholder; dress it if the hedge skyline work reaches south of the gate.
- PETAL-00: no autoload added; TownSim is constructed by the garden.

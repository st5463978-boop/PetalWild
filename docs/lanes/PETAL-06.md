# PETAL-06 · SimCity / Cities-scale town

Updated 2026-09-27.

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
- After the road rumour is filed, South Lane occupies named households. Far away they sit at aggregate; a near camera promotes two to individual records. Nobody is spawned.
- Nessa then offers Grove Park. Filing it shows a lawn south of the gate. Visitors promote the same way.

## Interface

- `TownSim.tick({people, residents, quality, road, park, passers, hour, weather, near_park, near_lane, lane_fill})`
- Folk records with layers `household` / `district` / `individual`. Hierarchy in `data/town.json`: world → creature.
- `TownSim.aggregate()`, `individuals()`, `folk_ids()`
- `Trust.file_park(person_id)` action `parish_park`
- `SimLod.note_town(individuals, distant)`
- Save key `town` includes folk ids so promote/demote round-trips
- `PETAL_TOWN_SHOT=1` captures `docs/screenshots/town_park.png` and `town_parish.png`

## Tests

- `tests/test_town.gd` → `TOWN_OK` (includes promote/demote id stability)
- `tests/test_systems.gd` → `SYSTEMS_OK`
- `tools/smoke.gd` → `PETAL_RULES_OK`
- `DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn` → `PETAL_SMOKE_OK`
- `DISPLAY=:1 PETAL_TOWN_SHOT=1 tools/run.sh res://scenes/garden.tscn` → `PETAL_TOWN_SHOT_OK`
- Qwen3-VL assessment path is not operational here (CPU decide only). Frames were read directly.
- `tests/smoke.gd` still parse-fails on this tree (Variant `:=`); not this lane.

## Blockers

None yet.

## Requests

- PETAL-09: Grove Park in `data/venues.json` can stay inactive; town occupancy is the live park.
- PETAL-05: park lawn is a placeholder; dress it if the hedge skyline work reaches south of the gate.
- PETAL-00: no autoload added; TownSim is constructed by the garden.

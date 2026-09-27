# Predicted collisions (PETAL-01 … 07)

Canonical stack is the Hedge Hollow garden. Shared files will collide. PETAL-08 keeps the strongest compatible piece and drops duplicates.

## Shared hot files

| Path | Likely writers | Keep |
| --- | --- | --- |
| `scripts/game/garden.gd` | all | One scene. Merge by function, keep `PETAL_SMOKE` and `PETAL_INTEGRATE`. |
| `scripts/garden/soil_field.gd`, `soil_cell.gd`, `data/plants.json` | 01, 02 | 01 owns soil/growth fields. 02 only adds ecology reads. Genetics keys `hue`, `stature`, `crop_yield` stay. |
| `scripts/ecology/ecology.gd`, `ecology_rules.gd`, `data/species.json` | 02, 03 | 02 owns requirements and promote. 03 owns the body `Jelly` builds. |
| `scripts/creatures/jelly.gd` | 03 | 03. Ecology talks through `life`, `to_state`, `setup`. |
| `scripts/people/veg_person.gd`, `data/people.json` | 04 | 04. `want` is the shop hook. |
| `scripts/people/village_shop.gd`, `scripts/autoload/economy.gd`, `data/items.json`, `data/shop.json` | 04, 05 | 05 owns prices and tin. 04 owns who walks to the stall. Produce ids must match `plants.json`. |
| `data/venues.json`, south rooms in `garden.gd` | 05, 06 | Catalog currently marks tea house / hut / foundry / hall `active: false` while the garden already builds them. 06 should flip catalog to match the scene, not rebuild the rooms. Grove Park stays unbuilt until 06 lands a real park. |
| `data/district.json`, `data/districts.json`, `data/road_pieces.json` | 06, 07 | Live parish id is `hedge_hollow` in `district.json`. `districts.json` still says `garden_grove` (legacy). 07 owns region; do not add another worn strip. |
| `scripts/autoload/petal_decide.gd` | 08 | 08. Callers pass options only. |
| `project.godot`, `scenes/main.tscn`, `scripts/app/main.gd` | 08 only unless a lane must boot | Title → garden. |

## Duplicate-legacy (do not revive)

| Path | Census | Action |
| --- | --- | --- |
| `scripts/main.gd` + `scripts/presentation/grove_*.gd` + `scripts/sim/*` | Kenney grove. Not the running scene. Catalogs expect dict plants (`sunpetal`, Cara). Live `data/plants.json` is an array of meadowbell/peach/… | Leave on disk. Do not autoload `PetalWorld` / `PetalContent`. `tests/smoke.gd` is this stack and is broken against live JSON. |
| `game/` | Second wave behind `.gdignore` | Ignore. |
| `data/residents.json`, `data/opening.json`, `data/dialogue.json` | Kenney residents (Cara, Mia, Pod) | Live people are `data/people.json` (Lumen, Bram, Nessa). |
| `docs/HANDOFF_AGENT_20260925.md` Hailo NPU `/v1/decide` | Stale vs locked DPO CPU layer | Follow `docs/PETAL_CAMPAIGN_DECISION_LAYER.md`. |

## Contract every lane must keep

- Plant records: `id`, `name`, `seed`, `sell_price`. Optional `grow_hours`, `water_need`, `fertility_need`, `chem`.
- Species records: `id`, `name`, `requirements[]` with `type` + `label`.
- People records: `id`, `name`. Live ids: `lumen`, `bram`, `nessa`.
- Save version 1. `to_state` / `apply_state` on garden, soil cells, ecology, people, economy, clock, trust.
- Decide: `POST /decide {question, context, options[]}` → `index`. Offline when `PETAL_DECIDE` is not `1`.
- No recursive node names (`_bell_stone_strip_…`).
- Grove Park remains unbuilt until 06 ships a real venue with `active: true`.

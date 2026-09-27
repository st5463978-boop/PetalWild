# PETAL-07 · Region / vale macro

Updated 2026-09-27.

## Census (before this lane)

| Piece | State |
| --- | --- |
| Regions / settlements | MISSING (one parish record in `data/district.json`) |
| Factions / territory | MISSING |
| Regional resources / migration / inter-parish trade | MISSING (stall is garden-local) |
| Cooperation / competition / expansion | MISSING (road rumour is décor only) |
| Macro sim | MISSING. `game/sim/town_sim.gd` is DUPLICATE-LEGACY (Havenbrook, sidelined behind `.gdignore`). Not used. |
| Persistence | PARTIAL (garden save, no vale) |
| Regional LOD | PARTIAL (`SimLod` is garden distance, not parishes) |

## Now playable

Press **M** for the Vale tab (or Parish **C**, which now names the vale). Five parishes exist: Hedge Hollow plus Reedbank, Mossford, Bramble Lea, and far Thatchmere. They grow a specialty, eat a need, trickle carts along routes, and once a day each NPC faction picks hold / send a cart / ask / keep using `PetalDecide`. A cart to Hollow adds that crop to the pouch. Incoming carts raise stall demand. You can send a cart from the pouch, share seed, or welcome a walker at the hedge. F5 keeps the vale.

LOD: Hollow ticks as **district**, neighbours as **settlement**, Thatchmere as **region**. `RegionSim.fidelity()` rolls the world line. A cart warms stance when it arrives, not when it leaves.

## Branch / commit

- Branch: `petal/07-region`
- Commit: (this checkpoint)

## Addendum

- Decide is used only for bounded faction options. Architecture stayed in-lane.
- Self-play: `tests/test_region.gd` pulses six days and checks trickle plus save.
- Visual QA: `DISPLAY=:1 PETAL_VALE_SHOT=1 tools/run.sh res://scenes/garden.tscn` → `PETAL_VALE_SHOT_OK` and `docs/screenshots/vale_tab.png`. Qwen3-VL is not operational here; the frame was read directly.
- Did not write `docs/PETAL_CAMPAIGN_STATE.md` (PETAL-08).

## Paths

- `data/regions.json`
- `scripts/sim/region_sim.gd`
- `scripts/game/garden.gd` (boot, hourly pulse, save, M/C, stall demand)
- `scripts/ui/hud.gd` (Vale tab)
- `tests/test_region.gd`
- `data/district.json` note
- `docs/SIMULATION_LAYERS.md` L4 pointer

## Interface

- `RegionSim.boot(saved={})`, `pulse(day, hour, garden)`, `send_cart`, `welcome`, `share_seed`, `page()`, `headline()`, `traffic(id)`, `fidelity()`, `to_dict()`
- Garden save key `region`
- Player: `send_vale_cart(to, crop)`, `welcome_vale()`, `share_vale_seed(to, crop)`
- Shot: `PETAL_VALE_SHOT=1`
- Decide question is bounded options. Offline default is `options[0]`. Hungry factions default to `ask for a crop`. Confidence is stored on the faction and shown on the Vale tab.

## Tests

- `REGION_OK` pass — `tests/test_region.gd` (includes a six-day self-play)
- `SYSTEMS_OK` pass
- `PETAL_RULES_OK` pass
- `PETAL_SMOKE_OK` pass (`DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn`)
- `PETAL_VALE_SHOT_OK` pass → `docs/screenshots/vale_tab.png`

## Assumptions for other lanes

- Did not edit `project.godot`. `RegionSim` lives on the garden node, not an autoload.
- Did not spawn bodies for walkers (PETAL-03/04). A walker at Hollow is a Vale button plus a toast.
- `game/sim/town_sim.gd` left untouched. Do not revive Havenbrook names.
- PETAL-00: parish page now includes vale lines; stall demand includes `region.traffic("hollow")`.
- PETAL-08: carts add produce via `Economy.add`. Seed share spends `crop_seed`.
- PETAL-09: Grove Park still unbuilt.

## Blockers

None.

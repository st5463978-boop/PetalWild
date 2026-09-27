# PETAL-07 · Region / vale macro

Updated 2026-09-27. Pass 2.

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

Press **M** for the Vale tab (or Parish **C**, which now names the vale). Five parishes exist: Hedge Hollow plus Reedbank, Mossford, Bramble Lea, and far Thatchmere. They grow a specialty, eat a need, trickle carts along routes, and once a day each NPC faction picks hold / send a cart / ask / keep using `PetalDecide`. A cart to Hollow adds that crop to the pouch and sits as a crate at the south gate. Click the crate to file it in the parish book. Incoming carts raise stall demand and join TownSim gate riders. Peach or meadowbell arrivals mention the kettle. You can send a cart from the pouch, share seed, or welcome a walker at the hedge. The Vale tab asks first when a parish named a crop, and draws the five hexes. F5 keeps the vale.

LOD: Hollow ticks as **district**, neighbours as **settlement**, Thatchmere as **region**. `RegionSim.fidelity()` rolls the world line. A cart warms stance when it arrives, not when it leaves.

## Pass 2

Merged `petal/08-integration` (`3402530`) into this lane, then three play-feel upgrades on the integrated garden:

1. **Gate crate** — a delivered Hollow cart is a crate at `GardenLayout.GATE`. Click files `Trust.file_vale_cart` without raising trust. Peach and meadowbell toast the kettle (PETAL-05).
2. **Ask-first vale map** — Vale tab draws axial hexes (q, r) and puts named parish asks above the generic send list.
3. **Town riders** — `TownSim.tick` takes `vale`; carts on the gate road add riders and a parish line (PETAL-06) without changing house occupancy.

Frames: `docs/screenshots/vale_tab.png` (hex map + asks), `docs/screenshots/vale_gate.png` (crate at the gate).

## Branch / commit

- Branch: `petal/07-region`
- Merge: `898155b` Merge petal/08-integration into the vale lane.
- Pass 2: (this commit)

## Addendum

- Decide is used only for bounded faction options. Architecture stayed in-lane.
- Self-play: `tests/test_region.gd` pulses six days and checks trickle plus save. Ask rows and hex cells are asserted.
- Visual QA: `DISPLAY=:1 PETAL_VALE_SHOT=1 tools/run.sh res://scenes/garden.tscn` → `PETAL_VALE_SHOT_OK`. Qwen3-VL is not operational here; frames were read directly.
- Did not write `docs/PETAL_CAMPAIGN_STATE.md` (PETAL-08).

## Paths

- `data/regions.json`
- `scripts/sim/region_sim.gd`
- `scripts/game/garden.gd` (boot, hourly pulse, save, M/C, stall demand, gate crate)
- `scripts/ui/hud.gd` (Vale tab, hex map, ask-first)
- `scripts/world/props.gd` (hidden gate crate)
- `scripts/town/town_sim.gd` (`vale` riders)
- `scripts/autoload/trust.gd` (`file_vale_cart`)
- `tests/test_region.gd`
- `tests/test_town.gd`
- `data/district.json` note
- `docs/SIMULATION_LAYERS.md` L4 pointer

## Interface

- `RegionSim.boot(saved={})`, `pulse(day, hour, garden)`, `send_cart`, `welcome`, `share_seed`, `page()`, `headline()`, `traffic(id)`, `fidelity()`, `to_dict()`
- `page()` also returns `ask_rows`, `cart_rows`, and hex `q`/`r` on each settlement
- Garden save keys `region`, `region_stamp`, `vale_crate_crop`
- Player: `send_vale_cart(to, crop)`, `welcome_vale()`, `share_vale_seed(to, crop)`, `take_vale_crate()`
- Town: `tick({..., vale})`
- Trust: `file_vale_cart(person_id, note)` — book only, no trust bump
- Shot: `PETAL_VALE_SHOT=1` → `vale_tab.png`, `vale_gate.png`
- Decide question is bounded options. Offline default is `options[0]`. Hungry factions default to `ask for a crop`. Confidence is stored on the faction and shown on the Vale tab.

## Tests

- `REGION_OK` pass — `tests/test_region.gd` (six-day self-play, hex cells, ask-first rows, cart rows)
- `TOWN_OK` pass — vale carts join gate riders
- `SYSTEMS_OK` pass
- `PETAL_RULES_OK` pass
- `PETAL_SMOKE_OK` pass (`DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn`)
- `PETAL_VALE_SHOT_OK` pass → `docs/screenshots/vale_tab.png`, `docs/screenshots/vale_gate.png`

## Assumptions for other lanes

- Did not edit `project.godot`. `RegionSim` lives on the garden node, not an autoload.
- Did not spawn bodies for walkers (PETAL-03/04). A walker at Hollow is a Vale button plus a toast. The crate at the gate is a prop, not a person.
- `game/sim/town_sim.gd` left untouched. Do not revive Havenbrook names. Live town is `scripts/town/town_sim.gd`.
- PETAL-00: parish page includes vale lines; stall demand includes `region.traffic("hollow")` plus a sitting gate crate.
- PETAL-05: peach / meadowbell arrivals mention the kettle. They do not stock it.
- PETAL-06: vale count adds riders only; lane house occupancy is unchanged.
- PETAL-08: carts add produce via `Economy.add`. Seed share spends `crop_seed`. `file_vale_cart` does not raise trust.
- PETAL-09: Grove Park still unbuilt.

## Blockers

None.

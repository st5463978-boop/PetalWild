# Petalwild campaign state

Owned by PETAL-08 on `petal/08-integration`. Durable facts only.

## Canonical

- Repo: https://github.com/st5463978-boop/PetalWild
- Live scene: `scenes/main.tscn` → `scenes/garden.tscn` (`scripts/game/garden.gd`)
- Baseline: `cursor/dpo-cpu-decide-9cb0` `f96457e` tag `petal-campaign-baseline-20260927`
- Integration: `petal/08-integration`

## PETAL_DECISION_LAYER

Qwen3-1.7B DPO-merged Q8_0 GGUF on llama.cpp CPU. `POST /decide {question, context, options[]}` → `choice, index, scores, confidence, margin, mode, p_yes`. Offline unless `PETAL_DECIDE=1`. Chip HEF path not used. Details: `docs/PETAL_CAMPAIGN_DECISION_LAYER.md`.

## Lanes

| Lane | Branch | Tip | In 08 | Acceptance |
| --- | --- | --- | --- | --- |
| 01 | `petal/01-foundation` | `7d5097e` | ported | face inspect, Space rest, yield save |
| 02 | `petal/02-ecology` | `aab1eca` | ported | habitat tally, reed neighbour, crowd, hunger |
| 03 | `petal/03-jelly` | `c3f55dd` | ported | grab, stretch, throw, bounce; land frame still missed |
| 04 | `petal/04-residents` | `6b48d2e` | ported | households, hunger, company, ties, jobs; no porch overshoot |
| 05 | `petal/05-economy` | `b5b90a6` | ported | kettle tea chain (peach+bell, cap 3, stop/restart) |
| 06 | `petal/06-town` | `f4c63d3` | ported | South Lane, Grove Park, promote/demote, no spawned bodies |
| 07 | `petal/07-region` | `cd45eb4` | ported | Petal Vale 5 parishes, carts, district/settlement/region LOD |
| 08 | `petal/08-integration` | `29e278b` | — | all 7 lanes; full suite re-run |

Keys: **M** vale, **C** town. Save: `crate_yields`, `parish`, `town`, `region`.

## Integration

Playable canonical build. Kenney grove (`scripts/main.gd`, `scripts/sim/petal_*`, `tests/smoke.gd`) and `game/` stay duplicate-legacy.

01 foundation (`7d5097e`, PR #6): inspect / Space rest / `crate_yields` already on 08. Did not replace merged `jelly.gd` with 01's tip (that would drop JellyFeel). `FOUNDATION_OK` (bus, yield save, inspect/clear) `SYSTEMS_OK` `PETAL_RULES_OK`. `PETAL_FACE_SHOT_OK` recaptured here: `wave1_face.png` (card Bellhelp, mood happy, bond 12%, Visitor; body under stall roof). Kenney `tests/smoke.gd` not used as a live check. Baseline leak warnings remain (`FOUNDATION_OK` also logs `!is_inside_tree()` on jelly setup plus 2 ObjectDB leaks). Qwen3-VL unused.

02 ecology (`aab1eca`, PR #5): `ecology_rules.gd` / `tools/smoke.gd` match the tip. 08 `test_systems.gd` keeps mill tests plus habitat. `SYSTEMS_OK` (reed neighbour, crowd, `Habitats · Bank 1, Meadow 1`) `PETAL_RULES_OK`. Did not re-run `PETAL_CAPTURE` (it overwrites the 01 face plate). `ecology_parish.png` on this branch shows `The meadow leans on the bank.` and `Habitats · Bank 5, Cane 3, Dusk 1, Loam 1, Meadow 4`. Hungry journal line is in garden smoke (`mix_need`). Qwen3-VL unused.

05 kettle (`b5b90a6`, PR #7): mill APIs already on 08. `SYSTEMS_OK` mill cap-3 recover on this tree. `PETAL_KETTLE_SHOT_OK` recaptured here: `docs/screenshots/kettle_brew.png` (porch steam) and `kettle_crate.png` (stall: Hedge tea sits on the crate, Sell 22 (1)). Qwen3-VL unused.

06 town (`f4c63d3`, PR #9): `town.json` / `town_sim.gd` / `test_town.gd` match the tip. `TOWN_OK` (promote/demote ids), `SYSTEMS_OK`, `PETAL_RULES_OK`. `PETAL_TOWN_SHOT_OK` recaptured here: `town_park.png` (Grove Park sign, lawn, benches, no bodies) and `town_parish.png` (Town folk 7, Lane 3/6, Park open · 2, Layers household 1 · individual 4 · district 0, Near Reed/Moss/Lawn still no body). Catalog Grove Park stays `active: false`.

07 vale (`cd45eb4`, PR #11): `regions.json` / `region_sim.gd` / `test_region.gd` match the tip. `petal_qa` on this tree: `PETAL_RULES_OK` `SYSTEMS_OK` `PETAL_CONTRACTS_OK` `FOUNDATION_OK` `JELLY_FEEL_OK` `RESIDENT_LIFE_OK` `TOWN_OK` `REGION_OK` (six-day pulse) `PETAL_QA_SCRIPTS_OK`. Garden: `PETAL_INTEGRATE_OK` (5 parishes, save key `region`). `PETAL_VALE_SHOT_OK` recaptured here: `vale_tab.png` (Hollow district, Reedbank/Mossford/Lea settlement, Thatchmere region, 4 carts). Qwen3-VL unused.

03 jelly (`c3f55dd`, PR #4): 08 keeps the merged `jelly.gd` (JellyFeel + 01 inspect). `JELLY_FEEL_OK` `SYSTEMS_OK` `PETAL_RULES_OK`. `JELLY_PLAY_OK` on this tree, offline decide `bellhelp`. Held/air frames: `jelly_held.png` (HUD playful · held), `jelly_air.png` (Bellhelp spins, dizzy). 03 follow-cam land was 3-strike abandoned. 08's one new approach: `_pin_overhead` pitch 62 on a fixed pad, not a follow cam. Physics: `land_y` 0.50 finite, feel `air`, not held, not under the lawn. `jelly_land.png` still looks into crest foliage; body not in frame. No further camera variants. Qwen3-VL unused. 03's hef-dfc Berrypatch 0.834 was on that lane's host, not this run.

04 residents (`6b48d2e`, PR #10): `resident_life.gd` / `test_resident_life.gd` match the tip. 08 keeps `set_route` clearing `pause` (04 tip dropped it; porch walk overshoots without it). `RESIDENT_LIFE_OK`. Directory/HUD name household, hunger, company, ties, job. `_smoke_parish_day` plus greeting memory round-trip live in garden smoke. `wave1_residents.png`: Lumen stall house / Bram shed house, hunger 63, company 47, ties. Did not re-run `PETAL_CAPTURE` (overwrites 01 face plate). Qwen3-VL unused.

## Tests (full suite this turn, Godot 4.8-dev6 llvmpipe, dummy ALSA)

`petal_qa`: `PETAL_RULES_OK` `SYSTEMS_OK` `PETAL_CONTRACTS_OK` `FOUNDATION_OK` `JELLY_FEEL_OK` `RESIDENT_LIFE_OK` `TOWN_OK` `REGION_OK` `PETAL_QA_SCRIPTS_OK`

Garden: `PETAL_INTEGRATE_OK` `PETAL_SELFPLAY_OK` `PETAL_SMOKE_OK` (exit 0, no SCRIPT ERROR). Baseline leaks: 3 CanvasItem RIDs, 6 ObjectDB. Prior recaptures still stand: `PETAL_FACE_SHOT_OK` `JELLY_PLAY_OK` `PETAL_KETTLE_SHOT_OK` `PETAL_TOWN_SHOT_OK` `PETAL_VALE_SHOT_OK`. Playable code `29e278b`.

All 7 feature lanes accepted (PRs #4 #5 #6 #7 #9 #10 #11). No blockers. Qwen3-VL not operational.

## Remaining

- `data/venues.json` still marks tea house / hut / foundry / hall `active: false` while the garden builds them (catalog vs scene; Grove Park stays unbuilt until filed).
- Dummy ALSA audio on headless hosts.
- Do not push `main` or other lane branches.

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
| 02 | `petal/02-ecology` | `aab1eca` | ported | habitat, hunger, neighbour growth |
| 03 | `petal/03-jelly` | `c3f55dd` | ported | grab, stretch, throw, bounce |
| 04 | `petal/04-residents` | `6b48d2e` | ported | needs, tea, memories, no porch overshoot |
| 05 | `petal/05-economy` | `b5b90a6` | ported | kettle tea chain |
| 06 | `petal/06-town` | `f4c63d3` | ported | South Lane, Grove Park, near households |
| 07 | `petal/07-region` | `cd45eb4` | ported | Petal Vale carts, world fidelity |
| 08 | `petal/08-integration` | `29e278b` | — | coherent Hedge Hollow |

Keys: **M** vale, **C** town. Save: `crate_yields`, `parish`, `town`, `region`.

## Integration

Playable canonical build. Kenney grove (`scripts/main.gd`, `scripts/sim/petal_*`, `tests/smoke.gd`) and `game/` stay duplicate-legacy.

03 land frame: one new overhead pin (`_pin_overhead`, pitch 62) after the air shot. Follow-cam land was already 3-strike abandoned on 03. `JELLY_PLAY_OK` (`land_y` finite, feel `air` at 0.49). `docs/screenshots/jelly_land.png` still looks into crest foliage; body not in frame. No further camera variants.

## Tests (`29e278b`, Godot 4.8-dev6 llvmpipe, dummy ALSA)

`PETAL_RULES_OK` `SYSTEMS_OK` `PETAL_CONTRACTS_OK` `FOUNDATION_OK` `JELLY_FEEL_OK` `RESIDENT_LIFE_OK` `TOWN_OK` `REGION_OK` `PETAL_QA_SCRIPTS_OK` `PETAL_INTEGRATE_OK` `PETAL_SELFPLAY_OK` `PETAL_SMOKE_OK` `JELLY_PLAY_OK`

Qwen3-VL is not operational. Frames under `docs/screenshots/`. Baseline leak warnings remain.

## Remaining

- `data/venues.json` still marks tea house / hut / foundry / hall `active: false` while the garden builds them (catalog vs scene; Grove Park stays unbuilt until filed).
- Dummy ALSA audio on headless hosts.
- Do not push `main` or other lane branches.

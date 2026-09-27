# Petalwild campaign state

Owned by PETAL-08 on `petal/08-integration`. Durable facts only.

## Canonical

- Repo: https://github.com/st5463978-boop/PetalWild
- Live scene: `scenes/main.tscn` → `scenes/garden.tscn` (`scripts/game/garden.gd`)
- Baseline: `cursor/dpo-cpu-decide-9cb0` `f96457e` tag `petal-campaign-baseline-20260927`
- Integration: `petal/08-integration`

## PETAL_DECISION_LAYER

Qwen3-1.7B DPO-merged Q8_0 GGUF on llama.cpp CPU. `POST /decide {question, context, options[]}` → `choice, index, scores, confidence, margin, mode, p_yes`. Offline unless `PETAL_DECIDE=1`. Chip HEF path not used. Details: `docs/PETAL_CAMPAIGN_DECISION_LAYER.md`.

## Lanes (pass 2)

| Lane | Branch | Tip | In 08 | Pass-2 slice |
| --- | --- | --- | --- | --- |
| 01 | `petal/01-foundation` | `68b126b` | ported | inspect names hunger/habitat; second click shares a ripe snack |
| 02 | `petal/02-ecology` | `71573f6` | ported | nest more species; pouch/vale feed |
| 03 | `petal/03-jelly` | `7e32d11` | ported | hungry face, nuzzle on still hold, wobble sets give |
| 04 | `petal/04-residents` | `5105b63` | ported | dusk Grove Park leisure, mist stroll, lawn spacing |
| 05 | `petal/05-economy` | `3259c49` | ported | jam + tea servings, shortage line, larger steam |
| 06 | `petal/06-town` | `bfff006` | ported | lawn count, tea porch, vale carts as counts |
| 07 | `petal/07-region` | `ca50495` | ported | hex map, ask-first sends, gate crate |
| 08 | `petal/08-integration` | `e11dcc4` | — | park land + 01–07 ports + salvage + garden soil/grass restore |

Keys: **M** vale, **C** town. Save: `crate_yields`, `parish`, `town`, `region`, `vale_crate_crop`.

## Integration

Playable canonical build. Kenney grove (`scripts/main.gd`, `scripts/sim/petal_*`, `tests/smoke.gd`) and `game/` stay duplicate-legacy. Ports are surgical; do not git-merge whole 01–07 branches onto 08 (those tips still carry already-ported pass-1 commits). Cross-lane hooks kept together: inspect snack (01) plus pouch feed (02), hungry `shown_mood` (02/03), tea/jam servings into parish snacks (04/05), vale carts scent jellies (02/07) and sit as a gate crate that fills lane riders without extra houses (06/07). 08 still clears `set_route` pause so porch walks do not overshoot.

Pass-2 land: Grove Park pad, `bound=false` so `JellyFeel.clamp_pos` does not yank the body (PARK z is outside `GARDEN_MIN.z`), wait until `feel!=air` and `y<=0.14`, `_pin_overhead` pitch 62 yaw 180 distance 3.6 on the actual body, photo HUD. `JELLY_PLAY_OK` land_y=0.043 feel=bounce pos≈(3.12, 0.043, -14.94). `jelly_land.png` shows the cream body on the lawn, Photo · Esc.

Leaks: unused HUD `people_box`/`trust_box`/`place_box` were the baseline 3 CanvasItem RIDs + 6 ObjectDB. Dropped. Foundation test frees extra Clock/SaveGame. Garden smoke / integrate / selfplay / jelly-play quit with no ObjectDB or CanvasItem warnings. One `PETAL_RESIDENT_SHOT` quit printed 2 ObjectDB; a `--verbose` rerun did not dump them. Dummy ALSA `ERR_CANT_OPEN` is expected.

01 snack (`d6ced43`): inspect card names hunger, food, habitat; second face click feeds from a ripe bed; pouch Feed button stays. `FOUNDATION_OK` snack bus + `jelly.snack()`. Garden smoke shares Meadowbell. `wave1_face.png`: Hunger 22% wants Meadowbell, Meadow on the Meadowbell, Click again to share.

07 gate (`7606999`/`9de1589`): delivered Hollow carts become a clickable crate; Vale tab draws spaced hexes; named asks sit above generic sends; town riders pick up vale traffic without extra house counts. `vale_tab.png` hexes + Parish asks. `vale_gate.png` reed crate at the south gate.

03 hungry plate is shot at the stall then the body moves to Grove Park for nuzzle/land. `jelly_hungry.png` still clips under the stall roof (HUD Bellhelp · hungry · idle). `jelly_nuzzle.png` body + “Bellhelp nuzzles your hands” on the park lawn.

04 dusk park: mist is a stroll; rain stays cover; Lumen/Bram stand apart; one leisure line. `residents_park.png` two bodies, Grove Park, 2 on the lawn. Directory still names household/hunger/company/ties. Salvage GLBs: Bram is the carrot folk; Lumen is the leek folk. Town still does not spawn distant bodies.

## Salvage (director add-on, `79e3123`)

Took, no GPL:

- PR #1 `art/characters`: `assets/characters/{leek,carrot,tomato,human}.glb` plus `veg_skin`/`veg_jelly`. `VegPerson` mounts them (leek/carrot/tomato; human fallback). Procedural primitives stay if a mesh is missing.
- PR #3 `cursor/open-source-jelly-port-08dc`: original `JellyDeform` directional spring on the existing `JellyFeel` grab/throw. Test folded into `JELLY_FEEL_OK`. Jelly-Baby source not copied.
- PR #12 `cursor/wave0-recovery-dc1d`: reuse map `docs/research/PETAL_RECOVERY_MAP.md`, LICENSE_MATRIX wave-0 table, `tools/orchestration/petal_decision_layer.py`.
- PR #13 `cursor/art-desk-request-system-48c9`: `art_desk/` YAML desk. AGENT_CONTRACTS art section points at it. Decide-layer paragraph on 08 kept.

Skipped:

- Kenney Starter Kit City Builder / `scenes/parish.tscn` — empty-grid boot fights Hedge Hollow town, Grove Park, and the no-distant-bodies rule.
- Blender character pipeline, `art_preview/`, OPEN_SOURCE_CANDIDATES catalogue, KANBAN cards, Jelly-Baby analysis dump.

## Tests (Godot 4.8-dev6 llvmpipe, DISPLAY=:1, dummy ALSA) on `79e3123`

`petal_qa`: `PETAL_RULES_OK` `SYSTEMS_OK` `PETAL_CONTRACTS_OK` `FOUNDATION_OK` `JELLY_FEEL_OK` `RESIDENT_LIFE_OK` `TOWN_OK` `REGION_OK` `PETAL_QA_SCRIPTS_OK`

Garden: `PETAL_SMOKE_OK` `PETAL_INTEGRATE_OK` `PETAL_SELFPLAY_OK` `JELLY_PLAY_OK` land_y=0.029 feel=bounce pos≈(3.14, 0.029, -14.19) `PETAL_RESIDENT_SHOT_OK`

Pass-2 kettle/town/vale/face plates were already green on `831bbfd` and were not recaptured.

## Garden look audit (`e11dcc4`)

`residents_veg_folk_park.png` was Grove Park, not the garden. The green checker was `shaders/terrain.gdshader` `sin(x)*sin(z)` from Hedge Hollow `af1d576`, not a missing-texture fallback. Poly Haven leafy grass and flowered dirt have been in `assets/third_party/polyhaven/` since `1248380` but were only sampled by legacy `grove_view.gd`. Live `garden.gd` / `dressing.gd` never bound them. No HDRI exists in the tree. Kenney nature-kit trees were grove-only; dressing used cylinder cones. Overlapping “on the Grove Park lawn” labels were `VegPerson.act_label` on every resident plus park `Label3D`s.

Restored: terrain samples leafy grass / dirt; worked bed lids use dirt; lawn discs sample grass; backdrop trees use Kenney FBX; world activity labels stay off. Frames: `docs/screenshots/garden_overview.png`, `garden_beds.png`, `garden_stall.png` (1440×900).

## Remaining

- `data/venues.json` still marks tea house / hut / foundry / hall `active: false` while the garden builds them (catalog vs scene; Grove Park stays unbuilt until filed).
- `jam_pan.png` still shows the shed wall.
- `jelly_hungry.png` still crops under the stall roof.
- Dummy ALSA audio on headless hosts.
- Do not push `main` or other lane branches.

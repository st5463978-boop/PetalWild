# CURRENT_STATE

Short enough to hand to a fresh context. Updated 2026-09-29 by the executive pass.

## HEAD

`cursor/playable-jelly-body-9956` off `petal/09-art-rescue` `538269b0`.
`main` `123a7bf` is the east-chain stone tail plus the art desk. It is not the playable campaign.

## CURRENT ENGINE

Godot `4.8.dev6.official.8898c2b3d`. `tools/run.sh` forces OpenGL 3. This VM is llvmpipe. Dummy ALSA is expected.

## CURRENT PLAYABLE WORLD

`scenes/main.tscn` → `scenes/garden.tscn` (`scripts/game/garden.gd`).
Hedge Hollow garden: till, plant, water, fertilise, tend, pond scoop, home kit, stall, journal, clock, weather, save/load.
Jellies grab, nuzzle, and throw. Veg folk (leek, carrot, tomato) keep the stall and can file the road rumour.
Grove Park lawn exists in the scene and stays hidden until Nessa files `parish_park`. `data/venues.json` keeps `grove_park.active` false on purpose.

## WORKING SYSTEMS

Pass 2 from `petal/08-integration` is in this tree: inspect snack, pouch feed, hungry face, dusk park stroll, jam and tea, vale carts, ask-first map.
Approved jelly cut-outs (`assets/art/images/PETAL-08-101/`) are the resting card. Hunger, a grab, a poke, or a throw shows a simple gel icon (one body, two black eyes) instead of the petal bell. The icon turns to face the camera.
Sign-off CAM_06 still stages its own `SignoffJelly` card.
Grove Park, once Nessa files it, is a lawn with benches and one worn walk from the lawn to the hedge gate. Lumen and Bram walk through that gate to the grass and stay there. `grove_park.active` stays false.
When the road rumour is filed, six cottages stand on South Lane between the gate and the lawn. Occupied houses light a window. If the camera is near the gate, the first household (a tomato folk, surname from the lane record) stands at that door. Farther houses stay counts. `grove_park.active` stays false.

## ACTIVE AGENTS

Executive on this branch. No other agent is writing this tree in this run.

## ACTIVE BRANCHES

| Branch | What it is |
| --- | --- |
| `main` | East-chain décor plus art desk. Behind the campaign. |
| `petal/08-integration` | Playable pass-2 garden. Parent of the lanes below. |
| `petal/09-art-rescue` | Same garden plus soil, hedges, HUD, and jelly cut-outs. This branch's parent. |
| `cursor/jelly-status-icons-ffcb` | Neon activity icons. Not merged. Draft PR 17 onto 08. |
| `cursor/city-park-pond-c8ec` | Separate City Park look-dev scene. Not the live boot. Draft PR 16. |
| `cursor/water-plan-937d` | Water research doc only. Draft PR 15. |
| `petal/01` … `petal/07` | Already ported into 08. Do not merge those tips again. |

## LATEST TEST RESULT

2026-09-29, Godot 4.8-dev6, llvmpipe, `DISPLAY=:1`.

- `./tools/petal_qa.sh` → `PETAL_QA_SCRIPTS_OK` on the previous tip. This pass re-ran `tests/test_town.gd` → `TOWN_OK`.
- `PETAL_TOWN_SHOT=1 tools/run.sh res://scenes/garden.tscn` → `PETAL_TOWN_SHOT_OK`. The shot quits if the near cottage has no body.
- Dummy ALSA `ERR_CANT_OPEN` and a GLES texture leak on quit. Expected on this VM.

## LATEST SCREENSHOTS

`docs/screenshots/jelly_nuzzle.png` (1440×900). Bellhelp is a flat species-green icon with two black vertical eyes, on the Grove Park lawn.

`docs/screenshots/jelly_land.png` (1440×900). After the throw, the same icon rests on the grass beside a bench. The hedge gate and the garden are in the background. Photo mode is on.

`docs/screenshots/jam_pan.png` (1440×900). The shed pan is a copper pot of red jam with a puff of steam. The shed wall is behind it.

`docs/screenshots/residents_park_gate.png` (1440×900). Bram and Lumen walk through the hedge opening onto the park path. The garden beds and stall are behind them.

`docs/screenshots/residents_park.png` (1440×900). Bram the carrot and Lumen the leek both read as people in the open grass. Bellhelp is between them with two black eyes. The count reads “2 on the lawn.” The hedge gate and the garden are behind the lawn.

`docs/screenshots/south_lane.png` (1440×900). The near cottage has a lit window and a tomato household at the door. The sign reads South Lane. Grove Park is beyond the path.

## KNOWN REGRESSIONS

- `main` does not boot the campaign garden.
- Tea house, hut, foundry, and hall are built in the scene and marked inactive in the catalog.
- City Park pond scene and neon status icons are unmerged siblings of 08, not of 09.

## CURRENT MAJOR OBJECTIVE

One playable original-IP garden a person can tend, feed, and throw, reading as a toy garden rather than a stone rumour.

## NEXT 5 TASKS

1. Keep the kettle brew plate on the kettle, the way the pan plate stays on the pan.
2. Give the jelly icon a little gel volume that does not wash the eyes out under the sun.
3. Leave `grove_park.active` false until Nessa's existing filing. Do not add another east-chain stone.
4. When this suite stays green, make this garden the boot line. `main` is still the stone tail.
5. Cherry-pick neon status icons only if they sit on the icon and leave the eyes visible.

## DO NOT REBUILD

- The east-chain of stones and worn strips on `main`.
- Kenney city-builder boot (`scenes/parish.tscn`). It fights this garden.
- Jelly-Baby source. GPL-3.0-only. The directional spring already landed as original code.
- Pass-1 lane tips. They are already in 08.
- Placeholder art, Higgsfield, paid image calls. File `art_desk/requests/` instead.
- A second simulation beside `scripts/game/garden.gd`. `game/` and `scripts/sim/petal_*` stay legacy.

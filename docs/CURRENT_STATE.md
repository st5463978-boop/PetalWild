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
Grove Park, once Nessa files it, is a lawn with benches and one worn walk from the lawn to the hedge gate. `grove_park.active` stays false.

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

- `./tools/petal_qa.sh` → `PETAL_QA_SCRIPTS_OK`.
- `PETAL_JELLY_PLAY=1 tools/run.sh res://scenes/garden.tscn` → `JELLY_PLAY_OK`.
- Dummy ALSA `ERR_CANT_OPEN` and a GLES texture leak on quit. Expected on this VM.

## LATEST SCREENSHOTS

`docs/screenshots/jelly_nuzzle.png` (1440×900). Bellhelp is on the Grove Park lawn, HUD `happy · held`, toast “Bellhelp nuzzles your hands.” The lawn walk runs to the hedge opening, and the garden is visible beyond it. A second jelly in the same frame shows the two black eyes. Bellhelp’s near body is still a pale sunlit facet; the eyes are easy to miss at this size.

## KNOWN REGRESSIONS

- `main` does not boot the campaign garden.
- Bellhelp’s close icon still sun-lights into a pale facet, so the eyes are weaker than on the smaller jelly in the same shot.
- `jam_pan.png` still shows the shed wall.
- Tea house, hut, foundry, and hall are built in the scene and marked inactive in the catalog.
- City Park pond scene and neon status icons are unmerged siblings of 08, not of 09.

## CURRENT MAJOR OBJECTIVE

One playable original-IP garden a person can tend, feed, and throw, reading as a toy garden rather than a stone rumour.

## NEXT 5 TASKS

1. Keep the icon one colour under this sun so both eyes read on a close Bellhelp.
2. Cherry-pick neon status icons only if they attach to the icon and leave the eyes visible.
3. Re-frame `jam_pan.png` off the shed wall.
4. Leave `grove_park.active` false until Nessa's existing filing. Do not add another east-chain stone.
5. When this suite stays green, make this garden the boot line. `main` is still the stone tail.

## DO NOT REBUILD

- The east-chain of stones and worn strips on `main`.
- Kenney city-builder boot (`scenes/parish.tscn`). It fights this garden.
- Jelly-Baby source. GPL-3.0-only. The directional spring already landed as original code.
- Pass-1 lane tips. They are already in 08.
- Placeholder art, Higgsfield, paid image calls. File `art_desk/requests/` instead.
- A second simulation beside `scripts/game/garden.gd`. `game/` and `scripts/sim/petal_*` stay legacy.

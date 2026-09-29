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
Approved jelly cut-outs (`assets/art/images/PETAL-08-101/`) are the resting card. Hunger, a grab, a poke, or a throw shows a shaded gel icon: one body, two black vertical eyes, a small highlight. The eyes stay unshaded so the sun does not grey them out. The icon tips toward the camera. A grab's stretch is seated in that camera space, so the eyes stay on the front of the squashed gel instead of shearing off along the pull.
Sign-off CAM_06 still stages its own `SignoffJelly` card.
Grove Park, once Nessa files it, is a lawn with benches and one worn walk from the lawn to the hedge gate. Lumen and Bram walk through that gate to the grass and stay there. `grove_park.active` stays false.
When the road rumour is filed, six cottages stand on South Lane between the gate and the lawn. Occupied houses light a window. If the camera is near the gate, the first household (a tomato folk, surname from the lane record) stands at that door. Enter, while the camera is near that cottage, steps into the kitchen. A cup on the table holds hedge tea when the kettle has a pot or a crate of it. T drinks one serving and the cup empties when that was the last. Selling carried tea at the Petal Stall uses that same cup: a sale that leaves a crate keeps it full, and selling the last crate empties it even when the kitchen was already open. Coins still rise. G, once Grove Park is filed, walks that household from the cottage door, through the gate, onto the lawn. G again walks them home through the gate. The lawn spot survives save and load. While they stand on the grass, the Grove Park count includes them and their cottage window goes dark. The window lights again when they are at the door. Arriving on the lawn draws an existing Bellhelp to the grass, hungry, with both black eyes still showing. The same name is used in the kitchen, on the path, and on the place page. Esc steps back out. The place page says where they are: kitchen, walking, lawn, or cottage door. After a sip it also keeps “drank the hedge tea,” including across save and load. The bottom hint reads Enter cottage, T tea, G park. Clicking the household says the tea line. Farther houses stay counts. `grove_park.active` stays false.

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

- `./tools/petal_qa.sh` → `PETAL_QA_SCRIPTS_OK`. `tests/test_jelly.gd` also prints `ICON_FACE_OK`.
- Carried hedge tea already sells at the Petal Stall. `sell_tea` pays the recipe price, drops one crate, refuses the sale after dusk, and the economy save keeps coins and the crate. The shop line is `Sell hedge tea`. The sale is the same call the crate and the shop button already use.
- `PETAL_KITCHEN_SALE=1` → `KITCHEN_CUP_SOLD_OK`. The shot quits if the open kitchen cup starts empty, if a leftover crate empties it, if the last sale leaves `TeaFill` full, or if coins do not rise.
- `PETAL_TOWN_SHOT=1` still passes with the control hint visible.
- `PETAL_TOWN_SHOT=1` → `PETAL_TOWN_SHOT_OK`. The shot quits if the near cottage has no body, if Enter does not open the kitchen, if the cup does not match the kettle, if the window or the cup leaves the frame, if T does not spend one tea, if the walk misses the gate or the lawn, if the walk home misses the gate or the door, if the place page loses the lawn or the door, if reload sends them home early, if the lawn sign ignores them, if the cottage window stays lit on the lawn or dark at the door, if arrival does not bring the jelly, if reload forgets the tea, or if Esc leaves the room open.
- `PETAL_KETTLE_SHOT=1` → `PETAL_KETTLE_SHOT_OK`. The brew plate quits if the kettle leaves the frame.
- `PETAL_JELLY_PLAY=1` → `JELLY_PLAY_OK`. Hungry plate shows the gel sphere and both black eyes.
- `PETAL_RESIDENT_SHOT=1` → `PETAL_RESIDENT_SHOT_OK`. Bram, Lumen, and Bellhelp still read on the lawn.
- Dummy ALSA `ERR_CANT_OPEN` and a GLES texture leak on quit. Expected on this VM.

## LATEST SCREENSHOTS

`docs/screenshots/jelly_hungry.png` (1440×900). Bellhelp is a green gel sphere in front of the stall, with two black vertical eyes and a highlight. HUD reads `Bellhelp · hungry`.

`docs/screenshots/jelly_held.png` (1440×900). The held gel is squashed wider than it is tall. Both black eyes sit on the front. HUD reads `Bellhelp · hungry · held`.

`docs/screenshots/jelly_nuzzle.png` (1440×900). The same gel, held, still shows the black eyes on the front. The toast reads `Bellhelp nuzzles your hands.`

`docs/screenshots/jelly_land.png` (1440×900). After the throw, the same icon rests on the grass beside a bench. The hedge gate and the garden are in the background. Photo mode is on.

`docs/screenshots/kettle_brew.png` (1440×900). The dark kettle and its white steam sit on the tea-house porch. The line reads “The kettle is brewing hedge tea.”

`docs/screenshots/jam_pan.png` (1440×900). The shed pan is a copper pot of red jam with a puff of steam. The shed wall is behind it.

`docs/screenshots/residents_park_gate.png` (1440×900). Bram and Lumen walk through the hedge opening onto the park path. The garden beds and stall are behind them.

`docs/screenshots/residents_park.png` (1440×900). Bram the carrot and Lumen the leek both read as people in the open grass. Bellhelp is between them with two black eyes. The count reads “2 on the lawn.” The hedge gate and the garden are behind the lawn.

`docs/screenshots/south_lane.png` (1440×900). The near cottage has a lit window and a tomato household at the door. The sign reads South Lane. Grove Park is beyond the path.

`docs/screenshots/cottage_inside.png` (1440×900). The lit window, Moss, and a full cup. The line reads “Moss's kitchen. T drinks. Esc steps back out.”

`docs/screenshots/cottage_sipped.png` (1440×900). After T, the cup is empty and the line reads “Moss drinks the hedge tea.”

`docs/screenshots/cottage_sold.png` (1440×900). The kitchen was already open. After the last crate sold, the cup on the table is empty.

`docs/screenshots/cottage_to_park.png` (1440×900). After the walk through the gate, the household is on the Grove Park lawn. The sign reads “4 on the lawn,” one more than the sim count. Reload kept the spot.

`docs/screenshots/grove_together.png` (1440×900). Reed and a hungry Bellhelp share the lawn. The jelly shows two black eyes. The sign still reads “4 on the lawn.”

`docs/screenshots/cottage_home.png` (1440×900). G brought them back to the lit door. Above them the line reads “Reed drank the hedge tea.” The hint shows Enter, T, and G.

`docs/screenshots/town_parish.png` (1440×900). After reload the page still says “Reed is at the cottage door” and “Reed drank the hedge tea.” The near-row matches the door. Moss and the lawn visitors still read “still no body.”

## KNOWN REGRESSIONS

- `main` does not boot the campaign garden.
- Tea house, hut, foundry, and hall are built in the scene and marked inactive in the catalog.
- City Park pond scene and neon status icons are unmerged siblings of 08, not of 09.

## CURRENT MAJOR OBJECTIVE

One playable original-IP garden a person can tend, feed, and throw, reading as a toy garden rather than a stone rumour.

## NEXT 5 TASKS

1. When this suite stays green, open a PR from this garden onto `main`. Do not push `main` from the agent. PR 18 already tracks this branch onto `petal/09-art-rescue`.
2. Leave `grove_park.active` false until Nessa's existing filing. Do not add another east-chain stone.
3. A resident drinking the last stall cup, or a new pot landing on the crate, still does not refresh the open kitchen. The stall sale now does.
4. Moss and the other lawn records still have no body. The other five cottages stay closed.
5. Cherry-pick neon status icons only if they sit on the icon and leave the eyes visible.

## DO NOT REBUILD

- The east-chain of stones and worn strips on `main`.
- Kenney city-builder boot (`scenes/parish.tscn`). It fights this garden.
- Jelly-Baby source. GPL-3.0-only. The directional spring already landed as original code.
- Pass-1 lane tips. They are already in 08.
- Placeholder art, Higgsfield, paid image calls. File `art_desk/requests/` instead.
- A second simulation beside `scripts/game/garden.gd`. `game/` and `scripts/sim/petal_*` stay legacy.

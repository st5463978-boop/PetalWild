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
A neon status mark floats above the body. A hungry jelly walking to food shows the cog. A returning visitor shows the envelope until the face is clicked. A snack or a click plays the heart once, then the mark returns to whatever is still true. Two adults of one species, or a breeding state, show the locked heart. The mark stays above both black eyes. Sign-off CAM_06 still stages its own `SignoffJelly` card.
Grove Park, once Nessa files it, is a lawn with benches and one worn walk from the lawn to the hedge gate. Lumen and Bram walk through that gate to the grass and stay there. `grove_park.active` stays false.
Enter, while the camera is near the Hedge Tea House, steps into that room with the same camera path as the cottage. The one porch kettle and its steam sit on the counter while the room is open, then return to the porch on Esc. Stocking and carrying still go through the mill. Coins still move only on a sale. A carry while the room is open fills the South Lane kitchen cup. `data/venues.json` keeps `tea_house.active` false.
Enter, while the camera is near the potting shed, steps into that room on the same camera path. The shed stands in the west hedge corridor, so the room is north of that hedge. The one jam pan, the jam, and its steam sit on the bench while the room is open, then return in front of the shed on Esc. Stocking and carrying still go through the mill. Coins still move only on a sale. The potting shed is not a catalog venue. `tea_house.active` and `grove_park.active` stay false.
Enter, while the camera is nearer the Petal Stall than the shed or the tea house, steps into that room on the same camera path. The stall stands north of the bed hedge, so the room is further north of that hedge. The existing crate, the tea cup, and the jam jar slide onto the counter while the room is open, then return to the stall on Esc. Lumen, who already keeps the stall, stands at that counter until Esc puts them back outside. Selling uses the same `sell_tea` and `sell_jam` calls. Coins rise, the crate drops, and dusk still refuses. `tea_house.active` and `grove_park.active` stay false. The other cottages stay closed.
When the road rumour is filed, six cottages stand on South Lane between the gate and the lawn. Occupied houses light a window. If the camera is near the gate, the first household (a tomato folk, surname from the lane record) stands at that door. Enter, while the camera is near that cottage, steps into the kitchen. A cup on the table holds hedge tea when the kettle has a pot or a crate of it. T drinks one serving and the cup empties when that was the last. Selling carried tea at the Petal Stall uses that same cup: a sale that leaves a crate keeps it full, and selling the last crate empties it even when the kitchen was already open. Coins still rise. The same open cup follows the mill. Carrying a finished pot onto the crate fills it. A resident drinking the last crate, through the mill tick, empties it. A new pot, or Nessa carrying that pot, fills it again. There is still one seller. G, once Grove Park is filed, walks that household from the cottage door, through the gate, onto the lawn. G again walks them home through the gate. The lawn spot survives save and load. While they stand on the grass, the Grove Park count includes them and their cottage window goes dark. The window lights again when they are at the door. Arriving on the lawn draws an existing Bellhelp to the grass, hungry, with both black eyes still showing. The same name is used in the kitchen, on the path, and on the place page. Esc steps back out. The place page says where they are: kitchen, walking, lawn, or cottage door. After a sip it also keeps “drank the hedge tea,” including across save and load. The bottom hint reads Enter cottage, T tea, G park. Clicking the household says the tea line. Farther houses stay counts. `grove_park.active` stays false.

## ACTIVE AGENTS

Executive on this branch. No other agent is writing this tree in this run.

## ACTIVE BRANCHES

| Branch | What it is |
| --- | --- |
| `main` | East-chain décor plus art desk. Behind the campaign. |
| `petal/08-integration` | Playable pass-2 garden. Parent of the lanes below. |
| `petal/09-art-rescue` | Same garden plus soil, hedges, HUD, and jelly cut-outs. This branch's parent. |
| `cursor/jelly-status-icons-ffcb` | Neon activity icons. Marks are on this branch. Demo scene and gif reel stayed on draft PR 17. |
| `cursor/city-park-pond-c8ec` | Separate City Park look-dev scene. Not the live boot. Draft PR 16. |
| `cursor/water-plan-937d` | Water research doc only. Draft PR 15. |
| `petal/01` … `petal/07` | Already ported into 08. Do not merge those tips again. |

## LATEST TEST RESULT

2026-09-29, Godot 4.8-dev6, llvmpipe, `DISPLAY=:1`.

- `./tools/petal_qa.sh` → `PETAL_QA_SCRIPTS_OK`. `tests/test_jelly.gd` prints `ICON_FACE_OK`. `tests/test_jelly_activity.gd` prints `JELLY_ACTIVITY_OK`.
- Carried hedge tea already sells at the Petal Stall. `sell_tea` pays the recipe price, drops one crate, refuses the sale after dusk, and the economy save keeps coins and the crate. The shop line is `Sell hedge tea`. The sale is the same call the crate and the shop button already use.
- Carried cane jam already sells the same way. `sell_jam` pays the recipe price (16, plus a lane coin when the lane is busy), drops one jam crate, refuses the sale after dusk, and the economy save keeps the coins and the remaining jam crate. The shop line is `Sell cane jam`. `PETAL_SMOKE=1` prints `JAM_CRATE_SOLD_OK` before `PETAL_SMOKE_OK`.
- `PETAL_KITCHEN_SALE=1` → `KITCHEN_CUP_SOLD_OK`. The shot quits if the open kitchen cup starts empty, if a leftover crate empties it, if the last sale leaves `TeaFill` full, or if coins do not rise.
- `PETAL_KITCHEN_LIVE=1` → `KITCHEN_CUP_LIVE_OK`. The shot quits if the open cup starts full, if carrying a finished pot leaves `TeaFill` empty, if Lumen finishing the crate leaves it full, if a new pot leaves it empty, if Nessa's carry leaves it empty, or if coins move.
- `PETAL_TOWN_SHOT=1` still passes with the control hint visible.
- `PETAL_TOWN_SHOT=1` → `PETAL_TOWN_SHOT_OK`. The shot quits if the near cottage has no body, if Enter does not open the kitchen, if the cup does not match the kettle, if the window or the cup leaves the frame, if T does not spend one tea, if the walk misses the gate or the lawn, if the walk home misses the gate or the door, if the place page loses the lawn or the door, if reload sends them home early, if the lawn sign ignores them, if the cottage window stays lit on the lawn or dark at the door, if arrival does not bring the jelly, if reload forgets the tea, or if Esc leaves the room open.
- `PETAL_KETTLE_SHOT=1` → `PETAL_KETTLE_SHOT_OK`. The brew plate quits if the kettle leaves the frame.
- `PETAL_TEA_HOUSE_SHOT=1` → `PETAL_TEA_HOUSE_SHOT_OK`. The shot quits if Enter does not open the tea house, if the kettle leaves the frame, if carrying leaves the South Lane cup empty or moves coins, if Esc leaves the room open, or if the kettle does not sit back on the porch. `tea_house.active` and `grove_park.active` stay false.
- `PETAL_SHED_SHOT=1` → `PETAL_SHED_SHOT_OK`. The shot quits if Enter does not open the potting shed, if the pan or its steam leaves the frame, if carrying moves coins, or if Esc leaves the room open. The pan sits back in front of the shed. `tea_house.active` and `grove_park.active` stay false.
- `PETAL_STALL_SHOT=1` → `PETAL_STALL_SHOT_OK`. The shot quits if Enter does not open the stall, if the crate, cup, or jar leaves the frame, if Lumen is not at the counter, if `sell_tea` or `sell_jam` does not pay, if dusk still sells, or if Esc leaves the room open, the goods off the stall, or Lumen inside. `tea_house.active` and `grove_park.active` stay false.
- `PETAL_JELLY_PLAY=1` → `JELLY_PLAY_OK` and `JELLY_ICON_OK`. Hungry, held, and landed plates still show two separate black eyes. A hungry jelly whose food is not under it shows the cog above the gel. The last plate forces that cog and quits if the mark is not above both eyes in the frame.
- `PETAL_RESIDENT_SHOT=1` → `PETAL_RESIDENT_SHOT_OK`. Bram, Lumen, and Bellhelp still read on the lawn.
- Dummy ALSA `ERR_CANT_OPEN` and a GLES texture leak on quit. Expected on this VM.

## LATEST SCREENSHOTS

`docs/screenshots/jelly_hungry.png` (1440×900). Bellhelp is a green gel sphere in front of the stall, with two black vertical eyes and a highlight. A white cog floats above the gel. HUD reads `Bellhelp · hungry`.

`docs/screenshots/jelly_held.png` (1440×900). The held gel is squashed wider than it is tall. Both black eyes sit on the front, two dark vertical marks. HUD reads `Bellhelp · hungry · held`.

`docs/screenshots/jelly_nuzzle.png` (1440×900). The same gel, held, still shows the black eyes on the front. The toast reads `Bellhelp nuzzles your hands.`

`docs/screenshots/jelly_land.png` (1440×900). After the throw, the same icon rests on the grass beside a bench, still with two black eyes. The cog is still above the gel because the jelly is hungry and not on its food. Photo mode is on.

`docs/screenshots/jelly_icon.png` (1440×900). The same gel, still with both black eyes, and a white neon cog above it. The cog does not sit on the eyes. Grove Park and the cottage are behind.

`docs/screenshots/tea_house_inside.png` (1440×900). The tea-house room, a lit window, and the dark kettle with white steam on the counter. The line reads “Peach and meadowbell went into the kettle.”

`docs/screenshots/potting_shed_inside.png` (1440×900). The potting-shed room, a lit window, and the copper pan of red jam with white steam on the bench. The line reads “Bramble went into the pan.” The tin stays 36.

`docs/screenshots/petal_stall_inside.png` (1440×900). The stall room, a lit window, and the crate on the counter with a cup and a red jar. Lumen stands left of the counter, facing the goods. The line reads “Cane jam sat down on the crate.” The hint reads “Esc out   sell tea and jam   B stall.” The tin stays 36.

`docs/screenshots/kettle_brew.png` (1440×900). The dark kettle and its white steam sit on the tea-house porch. The line reads “The kettle is brewing hedge tea.”

`docs/screenshots/jam_pan.png` (1440×900). The shed pan is a copper pot of red jam with a puff of steam. The shed wall is behind it.

`docs/screenshots/residents_park_gate.png` (1440×900). Bram and Lumen walk through the hedge opening onto the park path. The garden beds and stall are behind them.

`docs/screenshots/residents_park.png` (1440×900). Bram the carrot and Lumen the leek both read as people in the open grass. Bellhelp is between them with two black eyes. The count reads “2 on the lawn.” The hedge gate and the garden are behind the lawn.

`docs/screenshots/south_lane.png` (1440×900). The near cottage has a lit window and a tomato household at the door. The sign reads South Lane. Grove Park is beyond the path.

`docs/screenshots/cottage_inside.png` (1440×900). The lit window, Moss, and a full cup. The line reads “Moss's kitchen. T drinks. Esc steps back out.”

`docs/screenshots/cottage_sipped.png` (1440×900). After T, the cup is empty and the line reads “Moss drinks the hedge tea.”

`docs/screenshots/cottage_sold.png` (1440×900). The kitchen is already open. The toast reads “Sold hedge tea for 22 petal.” The tin reads 80. The cup on the table is empty.

`docs/screenshots/cottage_brewed.png` (1440×900). The kitchen is already open. The toast reads “Hedge tea sat down on the crate.” The tin stays 36. The cup on the table is full.

`docs/screenshots/cottage_resident.png` (1440×900). The same open kitchen. The toast reads “Lumen Peel drank hedge tea.” The tin stays 36. The cup is empty.

`docs/screenshots/cottage_to_park.png` (1440×900). After the walk through the gate, the household is on the Grove Park lawn. The sign reads “4 on the lawn,” one more than the sim count. Reload kept the spot.

`docs/screenshots/grove_together.png` (1440×900). Reed and a hungry Bellhelp share the lawn. The jelly shows two black eyes. The sign still reads “4 on the lawn.”

`docs/screenshots/cottage_home.png` (1440×900). G brought them back to the lit door. Above them the line reads “Reed drank the hedge tea.” The hint shows Enter, T, and G.

`docs/screenshots/town_parish.png` (1440×900). After reload the page still says “Reed is at the cottage door” and “Reed drank the hedge tea.” The near-row matches the door. Moss and the lawn visitors still read “still no body.”

## KNOWN REGRESSIONS

- `main` does not boot the campaign garden.
- Tea house, hut, foundry, and hall are built in the scene and marked inactive in the catalog.
- City Park pond scene is an unmerged sibling of 08, not of 09. The neon status marks from `cursor/jelly-status-icons-ffcb` are on this branch. The icon-branch demo scene and its gif captures stayed there.

## CURRENT MAJOR OBJECTIVE

One playable original-IP garden a person can tend, feed, and throw, reading as a toy garden rather than a stone rumour.

## NEXT TASKS

1. When this suite stays green, open a PR from this garden onto `main`. Do not push `main` from the agent. PR 18 already tracks this branch onto `petal/09-art-rescue`.
2. Leave `grove_park.active` false until Nessa's existing filing. Do not add another east-chain stone.
3. Moss and the other lawn records still have no body. The other five cottages stay closed. The research hut stays a shell: nothing there can spend or send. When the mill has tea and the camera is near the tea house, the place page already names tea-porch individuals as “still no body” in the room that already opens. Do not flip `tea_house.active` or `grove_park.active`.
4. The neon marks are in. Leave the demo reel on `cursor/jelly-status-icons-ffcb`. Do not cover the eyes.

## DO NOT REBUILD

- The east-chain of stones and worn strips on `main`.
- Kenney city-builder boot (`scenes/parish.tscn`). It fights this garden.
- Jelly-Baby source. GPL-3.0-only. The directional spring already landed as original code.
- Pass-1 lane tips. They are already in 08.
- Placeholder art, Higgsfield, paid image calls. File `art_desk/requests/` instead.
- A second simulation beside `scripts/game/garden.gd`. `game/` and `scripts/sim/petal_*` stay legacy.

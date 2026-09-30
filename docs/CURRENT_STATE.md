# CURRENT_STATE

Updated 2026-09-30 by PETAL-EXEC. Pegapear sits the opening nightlantern at dusk.

## HEAD

`cursor/playable-jelly-body-9956` off `petal/09-art-rescue`. Draft PR 18 stays on that base. Do not merge to `main`. Do not merge PR 18.

`main` `4a3c428` is the east-chain stone tail plus art desk plus merged JEV-H decide routing (PR 19). This branch already routes live decide through JEV-H topics and falls offline. Do not port `main`.

## CURRENT ENGINE

Godot `4.8.dev6.official.8898c2b3d`. `tools/run.sh` forces OpenGL 3. This VM is llvmpipe. Dummy ALSA is expected.

## CURRENT PLAYABLE WORLD

`scenes/main.tscn` → `scenes/garden.tscn` (`scripts/game/garden.gd`).
Hedge Hollow garden: till, plant, water, fertilise, tend, pond scoop, home kit, stall, journal, clock, weather, save/load.
Jellies grab, nuzzle, and throw. Hunger and a grab show the approved-cut-out gel. Resting still uses PETAL-08-101 cards.
Scoops widen the live `Pond`. Bulrush can sit that rim.
At dusk, Pegapear sits the opening nightlantern when no ripe lantern stands.
Veg folk keep the stall. Tea house, potting shed, and petal stall interiors open on Enter. Leave and load drop the room toast.
Grove Park lawn stays hidden until Nessa files `parish_park`. `grove_park.active` stays false.
South Lane: one tomato household. The other five cottages stay closed.

## WORKING SYSTEMS

Pass-2 garden, gel icon, neon marks, tea/jam mill, stall sales, one South Lane kitchen, G park walk.
Clock walks that household: dusk to the west bench, night to the cottage door.
`GardenLayout.pond_rim(scoops)` is the live water radius. `GardenLayout.lantern_sit` is the dusk bulb seat.

## ACTIVE AGENTS

This Cursor agent is the only writer on this branch. Astra judges look. Hailo files receipts. Peer lanes are docs only.

## ACTIVE BRANCHES

| Branch | Action |
| --- | --- |
| `cursor/playable-jelly-body-9956` | KEEP. Playable lineage. |
| `main` | IGNORE for campaign boot. Decide routing already here. |
| `petal/09-art-rescue` | KEEP as PR 18 base. |
| `petal/08-integration` | KEEP parent. Already in this tree. |
| `cursor/jelly-status-icons-ffcb` | KEEP marks (already here). |
| `cursor/city-park-pond-c8ec` | IGNORE until the live garden still boots. |
| `cursor/water-plan-937d` | IGNORE. Docs only. |
| `petal/01` … `petal/07` | IGNORE. Already ported. |

## LATEST TEST RESULT

2026-09-30, Godot 4.8-dev6, llvmpipe, `DISPLAY=:1`.

`./tools/petal_qa.sh` → `PETAL_QA_SCRIPTS_OK` including `DUSK_LANTERN_OK` `POND_RIM_OK` `LANE_LIFE_OK` `ICON_GEL_OK`.
`PETAL_DUSK_LANTERN=1` → `PETAL_DUSK_LANTERN_OK`. Pegapear gel beside the opening lantern. Real bed, not a wireframe.

Dummy ALSA `ERR_CANT_OPEN` and a GLES texture leak on quit. Expected.

## KNOWN REGRESSIONS

- `main` does not boot the campaign garden.
- Tea house, hut, foundry, and hall are built and marked inactive.
- City Park pond is an unmerged sibling of 08.

## CURRENT MAJOR OBJECTIVE

Keep Grove Park a place without a catalog flip. Household already sits the west bench at dusk.

## NEXT TASKS

1. Do not open the other five cottages. Do not flip `grove_park.active`.
2. Do not merge PR 18. Do not merge to `main`.

## DO NOT REBUILD

- East-chain stones on `main`.
- Kenney parish boot.
- Jelly-Baby GPL source.
- Pass-1 lane tips.
- Paid image APIs / Higgsfield.
- A second sim beside `scripts/game/garden.gd`.

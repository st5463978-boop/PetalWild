# R4 licence review

PETAL-R4, 27 September 2026. Research only. No gameplay, no commit, and no copy of external sources into the game tree.

The discovery index is [bobeff/open-source-games](https://github.com/bobeff/open-source-games) (CC0-1.0). That badge is the list's licence, not the licence of any game on it. Original `LICENSE` files and `gh api repos/OWNER/REPO` were read after the index. The index's "Other lists" entry for Trilarion's catalog was used only to find Godot and permissive sims the short index does not name. Cards are in `r4_cards.json`.

Hailo `POST /decide` returned HTTP 502 for every use and lane call (`exit_code` 2, `choice` null). Grok locked each R4 card to the evidence recommendation. `options[0]` was not used. The game-creator disagreement below was accepted: that card is now RED and REJECT.

Shallow clones, local only, already gitignored by `/_research/`:

- `_research/egregoria` at `ae65c857948a905120474cf93b96dd51cec6d5f6`
- `_research/citybound` at `817de551d2bc96c90d0b7c74af4872454f42b44c`

## Sibling cards

`r1_cards.json`, `r2_cards.json`, and `r3_cards.json` were present when this review was written. Their `decision` fields are also agent recommendations. The stored payloads show Hailo `choice: null` and a 502. None of those ADOPT or REJECT values came back from the decide service.

### Agree

- SpringBoneSimulator3D `ADOPT` is the Godot MIT node already in the engine pin, not a vendored addon. Class GREEN is right. It is not a REVIEW or RED adopt.
- godot-vrm `REJECT` is right. SPDX `NOASSERTION`, MIT software text, sample models carved out.
- openage and town stay `STUDY` / `REVIEW`. SPDX `NOASSERTION` is the API result. The files are GPL-3.0-or-later, and AGPL-3.0-or-later plus Commons Clause. Do not read `NOASSERTION` as "no licence" or as MIT.
- Dwellcraft and pocket-salvage `RED` / `REJECT` match missing licence files. The Tiny5 OFL notice does not license pocket-salvage.
- LimboAI and the-free-game class `YELLOW` with SPDX `MIT` is the art split: code MIT, logo or original art CC-BY-4.0, isolation stated in `do_not`. That matches YELLOW where isolation is real. The code half is GREEN. Do not treat the art as MIT.
- Gloot, Beehave, goap-godot-4, and Dialogue Manager stay MIT `STUDY`. Gloot is the Godot inventory addon. R4 does not add a second one.

### Disagree

**PlayableIntelligence/game-creator (R3) should be RED and REJECT, not REVIEW and STUDY.**

R3's own evidence: GitHub licence API returned null, the shallow clone has no `LICENSE` file, the README claims MIT, `package.json` says ISC, and `@strudel/web` is named as AGPL-3.0. Conflicting comments are not a grant. No licence file is RED. A public GitHub tree is not free to reuse. `STUDY` still treats the repo as a source. The QA-loop idea can be restated without that tree. Do not copy skills, agents, or the AGPL audio dependency.

No R1–R3 card uses `PORT`. The only `ADOPT` is the SpringBone engine node above, which is GREEN.

No R1–R3 repository is repeated in `r4_cards.json`. openage stays on the R2 card.

## R4 recommendations

| Name | Lane (recommendation) | Class | Recommendation |
| --- | --- | --- | --- |
| IsoCity | PETAL-04 | GREEN | STUDY |
| Harvest Moon 2.0 | PETAL-01 | RED | REJECT |
| JSettlers | PETAL-08 | GREEN | STUDY |
| CorsixTH | PETAL-04 | GREEN | STUDY |
| DwarfCorp | PETAL-04 | REVIEW | STUDY |
| Space Station 14 | PETAL-08 | REVIEW | STUDY |
| Egregoria | PETAL-04 | REVIEW | STUDY |
| Citybound | PETAL-01 | REVIEW | STUDY |
| Julius | PETAL-04 | REVIEW | STUDY |
| OpenTTD | PETAL-08 | REVIEW | STUDY |
| Unknown Horizons Godot port | PETAL-08 | REVIEW | STUDY |
| MicropolisCore | PETAL-08 | REVIEW | STUDY |

Harvest Moon 2.0 is the firewall case. The MIT `LICENSE` is real and does not cover `tilesets/Pokemon tiles.png` or the unlabeled Project Utumno sheet. Class is RED. Recommendation is REJECT.

CorsixTH's API id is `NOASSERTION` because `LICENSE.txt` continues into third-party notices. The project grant is MIT. Class GREEN for that grant. Do not copy the LGPL and OFL sections or Theme Hospital data.

DwarfCorp is a modified MIT plus an explicit proprietary-art ban, and the tree contains SteamSDK. Class REVIEW.

Space Station 14 content code is MIT. Assets are CC-BY-SA 3.0, some CC-BY-NC-SA 3.0. RobustToolbox code before 13 March 2019 is GPL-3.0. Class REVIEW for the repo as reused.

OpenTTD and MicropolisCore are GPL in the files. GitHub says `NOASSERTION` because the grant is not a file the detector maps. Micropolis also carries EA section 7 terms and a separate trademark licence for the name.

## Almost included

- **Widelands** (GPL-2.0). Settlers-like worker economy. JSettlers is the MIT reading of that technique. The Widelands tree is huge.
- **Akhenaten** (AGPL-3.0). Pharaoh farming. Petalwild already has soil, water, and growth. Commercial-asset engine.
- **Mindustry** (GPL-3.0). Belt logistics, not a garden inventory.
- **permafrost-engine** (GPL-3.0). RTS pathfinding. openage is already the R2 flow-field note, and the parish grid is small.
- **Cytopia** (GPL-3.0). Another SimCity clone. MicropolisCore is the cellular original.
- **Unciv** (MPL-2.0). Civilization V remake. Not a garden hard system. Assets are CC-BY.
- **Cataclysm-DDA**. Share-alike inventory, enormous. Space Station 14 and R2's Gloot cover inventory without that grant.
- **FreeSims** and **OpenTS2** (MPL-2.0). Sims file engines. Original commercial data required.
- **Jactorio**. Factorio-style belts. MIT on a factory clone does not make the logistics a garden fit.
- **SimHacker/micropolis** (the old dump). GitHub licence `NONE`, no root `LICENSE`. Use MicropolisCore.
- **micropolisJS** (GPL-3.0 plus the EA terms). Same model as MicropolisCore.
- **OpenRCT2** (GPL-3.0). Per-guest sim is the cost the L2 cap avoids. Original RCT2 data required.
- **Freeserf** and **freeserf.net** (GPL-3.0). Original Settlers 1 data required. Duplicate of the JSettlers carrier note.
- **Koi** (`jobtalle/Koi`). Catalog says Apache-2.0 plus a non-commercial extra. Custom, not GREEN.
- **sandspiel** (MIT). Falling sand, not crop growth.
- **Tanks of Freedom** (MIT, Godot). Advance Wars. Not pathfinding, saves, inventory, or growth.
- **openage**. Already an R2 STUDY card.
- **Unknown Horizons** Python/FIFE tree. GPL-2.0. The Godot port is the card that matches this engine.

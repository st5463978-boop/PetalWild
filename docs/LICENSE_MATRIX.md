# Licence matrix

PetalWild code is MIT. Third-party assets keep their own licences. Presence in this repo does not relicense them.

| Component | Class | Licence | Notes |
| --- | --- | --- | --- |
| `scripts/`, `scenes/`, `data/`, `shaders/`, `tests/` | GREEN | MIT | Original. Copyright 2026 Scott Thompson |
| Godot 4.8-dev6 engine | GREEN | MIT | Not vendored. Pinned binary only |
| Kenney Nature Kit, Foliage Pack, Mini Forest, Interface Sounds | GREEN | CC0 1.0 | `assets/third_party/kenney/` |
| Poly Haven leafy grass, flower scattered dirt, forest leaves 02, forest leaves 03 | GREEN | CC0 | 1K JPG albedo, normal, ARM |
| OpenGameArt Forest Ambience, Slobad | GREEN | CC0 1.0 | `assets/third_party/opengameart/Forest_Ambience.mp3` |
| Asset Quest Stylized Garden demo | GREEN | CC0 1.0 | In the running garden via `scripts/world/dressing.gd`. Files stay in `third_party/incoming/assetquest-stylized-garden-demo/` |
| Inter font | GREEN | SIL OFL 1.1 | `assets/fonts/`. Reserved for the Hedge Hollow UI |
| Original veg folk (carrot, leek, tomato) and clay human | GREEN | MIT / original | `assets/characters/`. Wired into Hedge Hollow residents. Not Jelly-Baby |
| Jelly-Baby | REVIEW | GPL-3.0-only | Not imported. Behaviour reference only |
| openage | REVIEW | GPL-3.0-or-later | Not imported. Architecture notes only |
| redplanethq/town | REVIEW | AGPL-3.0-or-later plus Commons Clause | Not imported |
| VivaPinataPlus | GREEN as a repo, unused | MIT | Systems research only. No content copied |
| TiP-Recomp | RED for this project | no-AI policy | Not fetched, not analysed |
| Cities: Skylines topic | RED if assets | proprietary | Genre research only |
| Supplied concept paintings | project art | supplied by the creative director | `docs/reference/petalwild_target_*.png` |

YELLOW (CC-BY) : none accepted this wave.

No GPL program code is linked into the game. A future decision to do that has to be explicit. The Hailo wrapper escalates tasks that ask to paste GPL source.

## Wave 0 reuse rulings

27 September 2026. Full field records live on the wave0 branch. None of those GPL repositories were imported. Kenney's Starter Kit City Builder was reviewed and **not** vendored onto `petal/08-integration` because Hedge Hollow already has a town.

| Candidate | Class | Decision | Lane |
| --- | --- | --- | --- |
| SpringBoneSimulator3D (engine pin `8898c2b3d`) | GREEN | ADOPT | PETAL-03 |
| Jelly-Baby | REVIEW | STUDY, rewrite feel only | PETAL-03 |
| openage, town, DwarfCorp, Citybound | REVIEW | STUDY, copy nothing | see recovery map |
| Harvest Moon 2.0, Dwellcraft, pocket-salvage | RED | REJECT | do not fetch |
| JoltPhysics upstream | GREEN | REJECT | already in the engine module |

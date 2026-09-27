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
| Jelly-Baby | REVIEW | GPL-3.0-only | Not imported. Behaviour reference only |
| openage | REVIEW | GPL-3.0-or-later | Not imported. Architecture notes only |
| redplanethq/town | REVIEW | AGPL-3.0-or-later plus Commons Clause | Not imported |
| VivaPinataPlus | GREEN as a repo, unused | MIT | REJECT. Launcher only. No commercial game files |
| TiP-Recomp | RED for this project | no-AI policy | Not fetched, not analysed |
| Cities: Skylines topic | RED if assets | proprietary | Genre research only |
| Supplied concept paintings | project art | supplied by the creative director | `docs/reference/petalwild_target_*.png` |

YELLOW (CC-BY) : none accepted into the tree. LimboAI and the-free-game are YELLOW and STUDY. Their art stays out.

No GPL program code is linked into the game. A future decision to do that has to be explicit. The Hailo wrapper escalates tasks that ask to paste GPL source.

## Wave 0 candidates

27 September 2026. Hailo `POST /decide` returned HTTP 502, so these classes were taken from the licence files. The full field records are `docs/research/OPEN_SOURCE_CANDIDATES.md`. None of these repositories were imported.

| Candidate | Class | Decision | Lane |
| --- | --- | --- | --- |
| SpringBoneSimulator3D (engine pin `8898c2b3d`) | GREEN | ADOPT | PETAL-03 |
| Godot SoftBody3D, PositionBasedDynamics, Gloop, godot-softbody2d, Beehave, goap-godot-4, Dialogue Manager, Skelerealms, Gloot, IsoCity, CorsixTH project grant, JSettlers, Claude-Code-Game-Studios, claude-one-button-game-creation, Godot-MCP, quasar-saz, world-of-claudecraft | GREEN | STUDY | see the recovery map |
| LimboAI, the-free-game | YELLOW | STUDY | PETAL-04, PETAL-01 |
| Jelly-Baby, openage, town, DwarfCorp, Space Station 14, Egregoria, Citybound, Julius, OpenTTD, Unknown Horizons Godot port, MicropolisCore, godot-vrm | REVIEW | STUDY, except godot-vrm which is REJECT | see the recovery map |
| Harvest Moon 2.0, Dwellcraft, pocket-salvage, game-creator | RED | REJECT | do not fetch into the tree |
| JoltPhysics upstream | GREEN | REJECT | already in the engine module |
| OpenCityMaker | GREEN | STUDY | MIT. Town readability only. Not imported |
| Melon Lab (`Ayi1337/gpt6-astra-one-shot-games`) | RED | REJECT | No licence file. Soft-body fruit ring |
| hit-and-run-web | REVIEW | REJECT | MIT code text. Simpsons assets carved out |
| toy2game | REVIEW | REJECT | Noncommercial custom licence, not OSI open source |
| Orbital Garden (file inside the Astra catalogue) | REVIEW | do not copy | Catalogue is CC0. This work states no grant of its own |

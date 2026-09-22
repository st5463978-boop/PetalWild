# Licence matrix

PetalWild's own code and original art are unpublished work by Scott Thompson. All rights reserved until Scott names a licence. That choice is not made by an agent.

| Component | Licence | In the game build? | Notes |
| --- | --- | --- | --- |
| PetalWild scripts, JSON, shaders, procedural meshes | All rights reserved | Yes | Original |
| Godot Engine 4.8-dev6 | MIT | No, the binary is not committed | Fetched by `tools/fetch_godot.sh` |
| Nunito variable font | SIL Open Font License 1.1 | Yes, `third_party/fonts/Nunito.ttf` | Vernon Adams and contributors. See `third_party/fonts/OFL.txt` |
| Asset Quest Stylized Garden demo | CC0-1.0 | Instanced in the garden from `game/art/cc0_garden/`. Download record stays in `third_party/incoming/` | `game/art/cc0_garden/` |
| Jelly Baby (`scottstts/Jelly-Baby`) | GPL-3.0-only | No | Behaviour reference. No source copied |
| openage | GPL-3.0-or-later | No | Architecture notes only |
| redplanet town | See `docs/research/ARCHITECTURE_REFERENCES.md` | No | Ideas only |
| Viva Piñata Plus / TiP-Recomp | Not used | No | TiP-Recomp was not fetched, because of its no-AI policy |

## Rules for the next merge

- GREEN (CC0, MIT, BSD, Apache, OFL for fonts): may be integrated after art direction.
- YELLOW (CC-BY): may be integrated with attribution in `THIRD_PARTY_NOTICES.md`.
- REVIEW (GPL, AGPL, LGPL, ShareAlike): do not copy into the game without a written decision from Scott. Studying the idea is fine.
- RED (unclear, ripped, or commercial game extracts): delete.

GPL code is not "solved" by also shipping MIT or CC0 files beside it. Do not paste it into `game/`.

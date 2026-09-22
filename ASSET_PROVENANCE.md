# Asset provenance

| Name | Source | Creator | Licence | URL | Downloaded | Modifications | Usage | Obligations |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Nunito | Google Fonts | Vernon Adams, contributors | SIL OFL 1.1 | https://github.com/google/fonts/tree/main/ofl/nunito | 2026-09-22 | Renamed to `Nunito.ttf` so Godot's loader accepts the path | UI font | Keep `third_party/fonts/OFL.txt` with the font |
| Stylized Garden demo | itch.io | Asset Quest | CC0-1.0 | https://assetquest.itch.io/stylized-garden-asset-pack | 2026-09-22 | Copied the demo meshes into `game/art/cc0_garden/`. Built `Plants_Atlas.png` by copying `Plants_Atlas_1_Opacity.png` into the alpha channel of the basecolor. Original PNGs kept. Plant cards use one shared alpha-cut shader. Prop meshes use `Props_Basecolor.png` | Flower rows, grass cards, pond-bank plants, sunflowers, benches, table, planters, and the stall umbrella | None. Credit is optional and recorded here |
| Godot 4.8-dev6 | Godot builds | Godot Engine contributors | MIT | https://github.com/godotengine/godot-builds/releases/tag/4.8-dev6 | 2026-09-22 | None | Local engine binary, gitignored | MIT notice if the binary is ever distributed |
| Procedural audio | Original | PetalWild | All rights reserved | — | — | Synthesized in `game/audio/garden_audio.gd` | Wind, rain, chirp, UI, squish | None |
| Reference photos | Supplied by Scott | — | Project reference, not a redistributable asset pack | — | 2026-09-22 | Copied into `docs/reference/` | Art direction only | Do not treat concept frames as game textures |

The Asset Quest zip SHA-256 is `a9fd020e798d1c13590d2153bf8003d4524e5fc55d5bebda4969128c1aba55f5`. The licence text inside the zip is quoted in `third_party/incoming/assetquest-stylized-garden-demo/PROVENANCE.md`.

No Kenney, Quaternius, or Poly Haven files were downloaded this wave. Candidates are listed in `docs/research/ASSET_HUNT.md`.

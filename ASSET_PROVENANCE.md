# Asset provenance

Downloaded 2026-09-22 unless noted. Original PetalWild meshes, shaders, audio, and data have no third-party source.

| Name | Source | Creator | Licence | URL | Modifications | Usage | Obligations |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Inter Regular 4.1 | rsms/inter release zip, `extras/ttf` | The Inter Project Authors | SIL OFL 1.1 | https://github.com/rsms/inter | None. File is 411640 bytes | UI | Keep `assets/fonts/OFL-Inter.txt`. Do not sell the font alone |
| Inter SemiBold 4.1 | rsms/inter release zip, `extras/ttf` | The Inter Project Authors | SIL OFL 1.1 | https://github.com/rsms/inter | None. File is 419744 bytes | UI | Same OFL file |
| Nunito | Google Fonts | Vernon Adams and contributors | SIL OFL 1.1 | https://github.com/google/fonts/tree/main/ofl/nunito | Renamed to `Nunito.ttf` by the parallel wave | Staged. The running UI uses Inter | Keep `third_party/fonts/OFL.txt` |
| Stylized Garden demo | itch.io, upload 17272206 | Asset Quest (Melissa) | CC0-1.0 | https://assetquest.itch.io/stylized-garden-asset-pack | Unzipped only. Zip SHA-256 `a9fd020e798d1c13590d2153bf8003d4524e5fc55d5bebda4969128c1aba55f5` | Staged under `third_party/incoming/assetquest-stylized-garden-demo/`. A first cluster (poppy, cornflower, larkspur, gerbera, sunflower, garlic, cosmea, grass, bench, planter) is instanced in the garden. The FBX asked for `Plants_Atlas_1.tga`, which was not in the zip, so plants use the PNG basecolor plus opacity in `shaders/cutout.gdshader`. Bench and planter use garden timber and terracotta until the prop atlas is wired. Not the full 183-model pack | Credit is optional. The licence text in that folder is the authority |

## Explicitly not imported

| Item | Why |
| --- | --- |
| Jelly Baby source and meshes | GPL-3.0. Behaviour reference only |
| openage source | GPL. Architecture reference only |
| TiP-Recomp | No-AI policy. Not downloaded |
| Viva Piñata, Cities: Skylines, Nintendo, or other commercial extracts | RED. Not sought |
| Kenney, Poly Haven, Quaternius, ambientCG, OpenGameArt | Not downloaded yet. See `docs/ASSET_HUNT.md` |
| Higgsfield generations | None. See `docs/HIGGSFIELD_LEDGER.md` |

Reference photographs and concept stills in `docs/reference/` are Scott’s direction for this project. They are not runtime textures.

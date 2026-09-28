# docs/art: PetalWild art-rescue inputs (PETAL-09)

Staged 2026-09-28 from Scott's box so cloud agents can read them.

| File | What it is |
|---|---|
| `VISUAL_TARGET.md` | Game Art Director target **v2 (binding)**. Wins over ASTRA_PLAN on conflict. |
| `ASSET_PICKS.md` | Art Director's per-camera asset picks. Wins over ASTRA_PLAN on conflict. |
| `ASTRA_PLAN.md` | Astra (Claude Opus) art-direction plan: changes 1-5, shot list, tiers, guardrails, capture ritual. |
| `visual_target_palette.png`, `visual_target_board.jpg` | Palette and reference board. |
| `visual_target/` | `signoff_capture.gd`, `signoff_check.py`, `signoff_spec.json` (8 cameras CAM_01..CAM_08). |
| `refs/petalwild_target_garden_02.png` | Target frame used in the compare sheet. |
| `requests_outbox/` | Art-desk requests ART-DIRECTOR-001..009 plus the out-of-scope note. |

## Box paths in these docs -> repo paths
The docs were written on the box and cite box paths. In this repo use:
- `/workspace/petalwild-vp-textures/tiled/VPxx_*_tile.png` -> `assets/textures/vp/` (only the non-flagged tiles the plan/picks use)
- `/workspace/petalwild-davinci/textures/tiled/Bxx_*_tile.png` -> `assets/textures/davinci/Bxx_*_tile_1024.png` (B01, B02, B10, B19, B29, B31; 1024 px downsamples)
- `/workspace/art_library/staging/sky/polyhaven/*_2k.hdr` -> `assets/third_party/polyhaven/hdri/`
- `/workspace/petalwild-artdesk/visual_target/` -> `docs/art/visual_target/`
- `/workspace/petalwild-artdesk/visual_target/refs/petalwild_target_garden_02.png` -> `docs/art/refs/petalwild_target_garden_02.png`
- Original "playable" snapshot: `docs/screenshots/petalwild_overview.png`
- Kenney / AssetQuest / Poly Haven PBR paths cited in the docs already exist in this repo under `assets/third_party/` and `third_party/incoming/`.
Anything else under `/workspace/...` or `/home/box/...` is NOT available in the repo (other DaVinci props/concepts, Higgsfield, staging contact sheets). The marble/gold HUD kit is in `assets/ui/kit/` (CC0, project-owned generated art).

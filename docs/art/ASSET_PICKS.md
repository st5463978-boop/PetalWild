# PetalWild asset picks per sign-off camera (v2 target)

Written 28 Sep 2026 by the art desk. It builds on Hailo's inventory (`/workspace/art_library/INVENTORY.md`, 567 rows) and the staged files. **Nothing was moved, copied into the repo or committed.**

- All paths are relative to `/workspace/art_library/staging/` unless they start with `/`. Each staged file's original location is in `staging/MANIFEST.tsv`.
- I looked at every `contact_<subject>.png` sheet for these picks.
- The target is **VISUAL_TARGET.md v2**: halfway between toy and real, and it has to look like A01–A20.

**How to read the picks**
- **Seam** is the wrap-edge vs interior ratio at full resolution. It uses the same method as Hailo's scores and reproduces them (for example `pi_grass_tile` 10.38). About 1.0 means it tiles cleanly. **1.5 or more means it needs a tiling pass** (`/workspace/petalwild-davinci/make_tile.py`) first.
- **End** says which end of the halfway rule a texture comes from:
  - **toy** (VP set) gets graded *down* toward the halfway hex.
  - **real** (DaVinci/Poly Haven) gets graded *up* toward it and supplies the normal/roughness detail.
  - The target albedo hexes are in VISUAL_TARGET §3.
- **Licences:**
  - Kenney, Poly Haven and AssetQuest: CC0.
  - DaVinci: own generation (DaVinci AI credits).
  - VP: own AI generation (chat, 27 Sep, **no provenance file**).
  - Higgsfield: own plan generation.
  - Jelly-Baby: **GPL-3.0, reference only**.
- ⚠️ **REDO FIRST** marks a flagged texture. It may be listed, but it must not ship until it has been redone.

## Pick table

| Cam | Role | Pick (staged path) | Licence | Seam | End | Notes |
|---|---|---|---|---|---|---|
| **CAM_01 hero overview** (A02, A20, A14) | Lawn (primary) | `ground/polyhaven_leafy_grass_{diff,nor_gl,arm}_1k.jpg` | CC0 (Poly Haven, already on repo 08) | 1.02 | real | Diffuse mean `#978359` is too dry and golden, so tint it toward halfway lawn `#679428`. It has the only lawn normal and ARM maps |
| | Lawn break-up | `ground/VP04_meadow_tile.png` + `ground/VP05_clover_tile.png` | own AI (VP) | 1.03 / 0.94 | toy | Grade from `#74bb2a` to `#679428` and blend 20–30% as the macro and clover layer |
| | Bed soil | `soil/polyhaven_flower_scattered_dirt_{diff,nor_gl,arm}_1k.jpg` | CC0 | 1.02 | real | See CAM_02 |
| | Hedge walls | `foliage/davinci_B29_boxwood_tile.png` (normal/roughness source) + `foliage/VP24_hedge_tile.png` (albedo, graded) | DaVinci own / own AI | 1.19 / 1.12 | real / toy | Halfway hedge `#3d7725`. Needs a lumpy mesh: no box hedges (request ART-DIRECTOR-007) |
| | Path | `ground/davinci_B10_flagstone_tile.png` | DaVinci own | 1.01 | real | Lift toward halfway flagstone `#c9b79b` |
| | Trees (mid-ground) | `foliage/kenney_nk_tree_oak.glb`, `tree_default.glb`, `tree_fat.glb` | CC0 | – | toy | **Layout and background only.** Flat-shaded low-poly facets fail the halfway rule at hero distance. Replace with blob canopies (VISUAL_TARGET §3.4) |
| | Sky | `sky/polyhaven/rustig_koppie_puresky_2k.hdr` (clear), `kloofendal_48d_partly_cloudy_puresky_2k.hdr` (partly cloudy) | CC0 (Poly Haven) | – | real | Staged 01:13–01:14, **after** the inventory, so no MANIFEST row yet. Hailo's `sky_analysis.json` has rustig_koppie at RGB distance 6.0 from the v1 sky. Use exposure −0.5 EV so the zenith reads `#b7c7d2` |
| **CAM_02 beds and soil** (A12, A02) | Untilled soil albedo + PBR | `soil/polyhaven_flower_scattered_dirt_{diff,nor_gl,arm}_1k.jpg` | CC0 | 1.02 | real | Diffuse `#6e513d`, darken to halfway soil `#3d2c20`. The **only soil with normal and roughness maps** |
| | Soil detail (hero/4K) | `soil/davinci_B01_soil_tile.png` | DaVinci own | 1.30 | real | Mean `#3e3024` is almost exactly the halfway soil hex. Use it as the 2K albedo on tier a, with normal derived from height |
| | Soil (toy end) | `soil/VP01_soil_tile.png` | own AI (VP) | 1.23 | toy | Mean `#3f2b1f`. Use for the phone tier (1K) or as the blend partner |
| | Tilled rows | `soil/davinci_B02_tilled_tile.png` | DaVinci own | 1.04 | real | Halfway tilled ridge `#7b5a42` matches its mean `#7b5a40`. Pair it with geometry ridges |
| | Tilled (toy) | `soil/VP02_tilled_tile.png` ⚠️ **REDO FIRST** | own AI (VP) | 1.27 | toy | **Flagged:** obvious horizontal repeat band. Only use it after the redo. Until then, use B02 plus geometry |
| | Compost / fresh-dug | `soil/davinci_R32_compost_tile.png` | DaVinci own | 1.05 | real | Newly planted cells and the compost heap |
| | Wet / watered soil | `soil/davinci_B04_mud_tile.png`; `soil/VP15_mud_tile.png` | DaVinci own; own AI | 0.99; **1.51** | real; toy | B04 is for the rain state and puddles. **VP15 needs a tiling pass** |
| | Bed footprints | `bed/kenney_nk_crops_dirtRow.glb`, `crops_dirtDoubleRow.glb` (+ `Corner`, `End`, `Single`) | CC0 | – | toy | Good **layout and footprint** pieces. The mesh is faceted and flat, so re-skin it with the soil set and add a rolled lip. Proper beds: ART-DIRECTOR-005 |
| | Edging: mulch | `bed/davinci_B31_mulch_tile.png` | DaVinci own | 0.18 | real | The cleanest tile in the set. Halfway mulch `#9b5b32` |
| | Edging: stone | `bed/davinci_B34_drystone_tile.png` | DaVinci own | 1.07 | real | Low drystone bed walls |
| | Edging: timber | `bed/davinci_B19_planks_tile.png` | DaVinci own | 1.22 | real | Plank bed frames, halfway timber `#9f7f63`. **Do not use VP18** (flagged, baby-blue) |
| | Crops | `crop/kenney_nk_crops_leafsStageA/B.glb`, `crop_carrot.glb`, `crop_pumpkin.glb` | CC0 | – | toy | Growth-stage placeholders. They need a smooth-shaded, halfway-textured pass |
| **CAM_03 lawn and path, Viva Minera low view** (A01, A11) | Lawn close-up | `ground/polyhaven_leafy_grass_*_1k.jpg` + grass clumps | CC0 | 1.02 | real | At 1.1 m camera height the 1K set is soft. Get the 2K/4K from Poly Haven (same CC0 asset) for tier a |
| | Clover patches | `ground/davinci_B07_clover_tile.png` | DaVinci own | 1.29 | real | Or VP05 graded |
| | Moss in joints | `ground/VP06_moss_tile.png` | own AI (VP) | 1.05 | toy | Grade toward mortar `#737244` |
| | Flagstone path | `ground/davinci_B10_flagstone_tile.png` | DaVinci own | 1.01 | real | Primary |
| | Flagstone (alt) | `ground/VP09_flagstone_tile.png` ⚠️ **REDO FIRST** | own AI (VP) | 1.35 | toy | **Flagged:** its blue-grey and orange stones clash with the warm plaza. Only use it after the redo |
| | Paving (alt) | `ground/higgsfield_ground_faed0238-….png` | Higgsfield own plan | 1.07 | real | Warm paving, mean `#d2bc9f`. A good A01 match |
| | Dirt spur | `ground/VP07_dirtpath_tile.png` | own AI (VP) | 1.28 | toy | Grade from `#cda363` to halfway `#bb9260` |
| | Lawn (alt) | `ground/davinci_B05_lawn_tile.png`; `ground/higgsfield_ground_64f3361a-….png` | DaVinci own; Higgsfield | 1.21; 1.08 | real | B05 is the "real" end of the halfway lawn |
| | Stepping stones / rocks | – | – | – | – | **Gap.** Kenney `rock_*` are faceted "ice cubes". Request ART-DIRECTOR-006 |
| **CAM_04 foliage edge** (A04, A18, A20) | Hedge wall | `foliage/davinci_B29_boxwood_tile.png` + `foliage/VP24_hedge_tile.png` | DaVinci own / own AI | 1.19 / 1.12 | real / toy | As CAM_01. Crest backlight 0.25 |
| | Ivy on walls and trellis | `foliage/davinci_B30_ivy_tile.png`; `foliage/VP25_ivy_tile.png` | DaVinci own; own AI | 1.10; 1.00 | real; toy | |
| | Flower border | `foliage/assetquest_Poppy_Single_Red.fbx`, `Gerbera_1_Red.fbx`, `Larkspur_1_Purple.fbx`, `Cornflowers_Big_Cluster_Blue.fbx`, `Cosmea_Cluster_Small_1.fbx`, `Giant_Sunflower_big_1.fbx` + `assetquest_Plants_Atlas_1_{Basecolor,Opacity}.png` | CC0 (AssetQuest) | atlas (not tiling) | toy→mid | **Best flower meshes for halfway**: painted, rounded, not faceted. Covers the red, violet, blue and yellow accents (A20 `#782d22`, `#c8af42`) |
| | Flower sprites and forms | `foliage/davinci_D04_foxglove.png`, `D15_rose_trellis.png`, `D05_toadstool.png`, `D12_hollow_log.png` | DaVinci own | – | real | Form reference and billboard cut-outs (grey background) |
| | Meadow strip | `foliage/davinci_B28_wildflowers_tile.png`; `foliage/VP23_wildflowers_tile.png` | DaVinci own; own AI | 1.29; 1.15 | real; toy | |
| | Tree bark | `foliage/davinci_B17_oakbark_tile.png` (+ `VP16_oakbark_tile.png`) | DaVinci own / own AI | 1.03 / 1.01 | real / toy | Halfway bark `#89613b` |
| | Leaf litter under hedge | `foliage/polyhaven_forest_leaves_03_{diff,nor_gl,arm}_1k.jpg` (summer), `forest_leaves_02` (autumn state) | CC0 | 1.03 / 1.08 | real | This is a ground-litter texture, not canopy |
| | Shrubs (filler) | `foliage/kenney_nk_plant_bushLarge.glb`, `plant_bushDetailed.glb` | CC0 | – | toy | Background filler only (faceted). Hero hedges come from ART-DIRECTOR-007 |
| | Leaf cards | Kenney foliage-pack `foliage/kenney_foliage_*` | CC0 | – | toy | For hedge shells and grass-clump cards |
| **CAM_05 market stall** (A05, A13) | Timber | `bed/davinci_B19_planks_tile.png` | DaVinci own | 1.22 | real | Posts, counter and crates |
| | Roof: thatch | `stall/davinci_B21_thatch_tile.png` | DaVinci own | 1.15 | real | Halfway thatch `#c28c36`. **Not VP19** (seam 1.65, needs a tiling pass, and too yellow at `#dfaa35`) |
| | Pots / roof tiles | `stall/VP20_terracotta_tile.png` (albedo) + `stall/davinci_B22_terracotta_tile.png` (detail) | own AI / DaVinci own | 1.05 / 1.06 | toy / real | B22 has faint ghosting in the blend band, so use it for normal detail only |
| | Props | `stall/davinci_D09_seed_crate.png`, `D13_lantern.png`, `D14_signpost.png`, `D10_watering_can.png`, `D06_garden_shed.png` | DaVinci own | – | real | 2D cut-outs and modelling references. 3D props come from ART-DIRECTOR-003 |
| | Furniture | `stall/assetquest_Table_1.fbx`, `Bench_1.fbx`, `Sun_Umbrella_1.fbx` + `Props_Basecolor.png` | CC0 (AssetQuest, on repo 08) | – | toy→mid | Replaces the box bench now. The umbrella is a stop-gap awning |
| | Glass (greenhouse corner, A13) | `stall/davinci_B35_glass_tile.png` | DaVinci own | 1.07 | real | Optional |
| | Plaza in front | `ground/davinci_B10_flagstone_tile.png` / `ground/higgsfield_ground_faed0238-….png` | DaVinci / Higgsfield | 1.01 / 1.07 | real | |
| | Look reference only | `stall/higgsfield_stall_{69b247e7,7a1e7bde,7db4e953,aec22b31}-….png` | Higgsfield | – | – | ⛔ **Havenbrook signage** baked in. Reference only; do not ship |
| | Avoid | `stall/VP30_crepe_tile.png` | own AI | – | – | Flagged (fringe artefacts) |
| **CAM_06 jelly hero** (A10, A11) | Jelly body | – | – | – | – | **Gap: no shippable jelly.** Build from ART-DIRECTOR-001 (Grok bot bodies) |
| | Candy material reference | `jelly/davinci_R38_candy_tile.png` | DaVinci own | 0.77 | real | Gloss and translucency reference for the shader. Do not map it onto the body (striped sweets) |
| | Candy material presets | `jelly/gg_candy_{lime,lemon,strawberry,blueberry,grape,spec,eye_ink,eye_white}.tres` | own (Garden Grove port) | – | – | Starting points. Retune to the Grok palette (VISUAL_TARGET §3.6) |
| | Lawn under jelly | `ground/polyhaven_leafy_grass_*_1k.jpg` | CC0 | 1.02 | real | Soft contact shadow on the lawn |
| | Shape and face reference | `ui/grokbot-shapes-palette.png` (= `/workspace/havenbrook-art/refs/grok-avatar-anim/grokbot-shapes-palette.png`) | Grok brand material, reference | – | – | The 8 shapes, slash eyes and 11 swatches |
| | ⛔ Do not use | `jelly/reference_only/*`, `jelly/higgsfield_jelly_*` (gummy bears, pear-drop), DaVinci C01 as jelly form | GPL risk / off-target | – | – | Jelly-Baby look-alikes, or not Grok-shaped |
| **CAM_07 veg folk** (A12, A17) | Models (now) | `veg_folk/repo08_carrot.glb`, `repo08_tomato.glb`, `repo08_leek.glb` + `repo08_*_body_albedo_512.png`, `*_leaf_albedo_256.png` | own (repo, MIT project) | – | toy | Already in the game. The albedos are flat and plastic, so re-texture with real skin (VISUAL_TARGET §3.7) |
| | Blender sources | `veg_folk/artchars_carrot.blend`, `artchars_tomato.blend`, `artchars_leek.blend` | own (repo `art/characters`) | – | mid | Glossy carrot/tomato with big eyes (see `artchars_carrot_threequarter.png`): closest existing 3D to Pixar |
| | Look target | `veg_folk/higgsfield_vegfolk_{37d9fbac (onion), 4c4ec52b (pea), 52682b82 (carrot), 64eb0574 (tomato), ab9e6641 (cabbage)}-….png` | Higgsfield own plan | – | mid | **Closest to the Pixar/Ghibli brief.** Use as turnaround reference for ART-DIRECTOR-002 |
| | Skin detail | A12 crop, plus `/workspace/petalwild-davinci/textures/tiled/` leaf/veg tiles | DaVinci own | – | real | Real vegetable surface |
| | ⛔ Avoid | `veg_folk/repo08_human.glb`, `artchars_godot_human.png` | – | – | – | Human mannequin, off-brief |
| **CAM_08 phone play** (A02, A20) | Ground and beds | Same as CAM_01/02 at 512–1K: `ground/polyhaven_leafy_grass_*_1k.jpg`, `soil/VP01_soil_tile.png` (graded), `bed/davinci_B31_mulch_tile.png` (downsized) | CC0 / own AI / DaVinci | ≤ 1.23 | mixed | ASTC 6×6. On phone the toy-end VP set reads better at small size |
| | Sky | `sky/polyhaven/rustig_koppie_puresky_1k.hdr` or ProceduralSky (ART-DIRECTOR-004) | CC0 | – | real | On Compatibility-phone use the 2-stop gradient sky |
| | HUD, speed buttons | – | – | – | – | **Gap.** A UI kit is in progress at `/workspace/art_library/ui/` (`UI_STYLE.md`, awaiting Scott's pick of direction). The pause/1×/2×/4× icons are requested as ART-DIRECTOR-009 |

## Summary

- **Ready now (CC0 or own, tiles cleanly):**
  - Soil: Poly Haven `flower_scattered_dirt`, DaVinci B01/B02/R32/B04.
  - Lawn: Poly Haven `leafy_grass`.
  - Edging: B31 mulch, B34 drystone, B19 planks.
  - Path: B10 flagstone, Higgsfield `faed0238` paving.
  - Hedge and ivy: B29/B30 + VP24/VP25.
  - Flowers: AssetQuest flower FBXs and atlas.
  - Stall: B21 thatch, VP20/B22 terracotta, AssetQuest table/bench/umbrella.
  - Sky: Poly Haven pure-sky HDRIs (clear and partly cloudy).
- **The halfway rule needs grading work, not new art.** Almost every pick is either toy (VP) or real (DaVinci/Poly Haven). The halfway albedos in `palette.json` → `halfway` tell PETAL_06 what to grade to. Only Poly Haven sets have normal and ARM maps. DaVinci detail normals need deriving from height (tier a).
- **Needs a tiling pass before use (seam ≥ 1.5):**
  - VP15 mud 1.51, VP28 drystone 1.53, VP19 thatch 1.65, B11 gravel 1.72.
  - Higgsfield soils (1.63 / 3.10 / 1.77), Higgsfield grounds `309b3336` 1.64, `7b07ec06` 2.90, `a84d06ca` 1.55.
  - B24 pine needles 1.60, R39 bee fur 1.69, R36 rust metal 5.74, `pi_grass_tile` 10.38.
- **Redo flags honoured:**
  - VP02 tilled and VP09 flagstone appear only with ⚠️ REDO FIRST, and each has a non-flagged primary (B02, B10).
  - VP03 lawn, VP18 planks and VP30 crepe are not picked.
- **Kenney nature-kit GLBs** (crops, trees, bushes, rocks) are useful for layout and footprints. At hero distance they are flat-shaded, faceted toys and fail v2. They are picked only as layout or background placeholders.
- **Gaps sent to the art desk** (`requests_outbox/`):
  - Grok jelly bodies, veg folk, market stall, sky/weather, beds and edging, rocks, hedges.
  - Plus a proper tree set and HUD speed-control icons.
- **Out of art scope:** music and garden SFX (dig, water, harvest, birds, footsteps). Both are known gaps; route them to audio.

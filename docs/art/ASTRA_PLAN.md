# PetalWild: Garden Grove art-direction rescue (Astra)

> I'm not asking for a prettier prototype. The goal is a toy diorama someone would want to pick up: dark crumbly beds you want to dig, a warm stone floor, fat pillow hedges catching a 16:30 sun, and nothing on screen that the player didn't put there or can't use.

---

## 0. How to run this pass (read first)

- **Branch:** `petal/09-art-rescue`, cut from `petal/08-integration@be6adc3`. Make one commit per numbered change in §2, and run the capture ritual in §8 after every commit.
- **Paths that exist in two places.** The inventory lists `shaders/*.gdshader`, and the brief also mentions `game/shaders/jelly.gdshader`. Before editing any shader, run `grep -rn "<name>.gdshader" --include=*.tscn --include=*.tres --include=*.gd .` and edit only the copy the Garden Grove scene actually loads. Do the same for `scripts/world/garden.gd` and `scripts/world/dressing.gd`.
- **Where new art lives:**
  - VP tiles: `res://assets/textures/vp/`
  - Graded tiles: `res://assets/textures/garden/`
  - Derived detail maps: `res://assets/textures/detail/`
  - Blender GLBs: `res://assets/models/<subject>/`
  - Blender generators: `tools/blender/`
  - Texture tools: `tools/tex/`
  - Every third-party folder gets a `LICENSE.txt` (CC0 or self-generated).
- **Don't touch:** game logic, save data, or the camera rig's input handling. Every logic test must stay green. This is an art pass only.

---

## 1. Diagnosis

The original read as *playable* because it was built like a board game:
- **The camera:** high (about 50° down) and close, so the playfield filled roughly 90% of the frame and there was no horizon to compete with it.
- **Value ladder:** three clear steps. Peach flagstone border (light), straw lawn tiles (mid), dug beds (the darkest, warmest shapes on screen). The eye landed where you play.
- **Density and silhouette:** foliage was pastel, low-contrast and pushed out to the edges, so it framed the grid instead of covering it. The grid gave every cell an obvious "click me" affordance.
- **HUD:** small and tucked into a corner.

The current build turns every one of those around:
- **The camera:** it sits at about 25°, so the playfield is under 35% of the frame. The rest is sky, a hazy olive horizon and ice-cube rocks.
- **Value ladder:** the brightest things on screen are the lime pads (#8fe06a-ish, pure placeholder), and the beds, the thing you actually play with, are buried.
- **Density and silhouette:** a high-frequency red star-card thicket (full-saturation red on full-saturation lime, so the complementary colours vibrate) sits at the same mid-dark value as the hedge. The frame becomes noise with no focal point. Every silhouette is a spike or a box (cylinder hedge, box houses, cone grass, sphere crops), when this world should be pillows.
- **Haze:** additive god-ray cards lift the blacks into milk, so the frame fails chroma and reads as grey plastic.
- **HUD:** the bottom toolbar eats 11% of the height, starting with an empty slot.

**The fix is not "more art". It is to restore the value ladder, clear the floor, raise the camera, then swap placeholder shapes for chunky ones.** We keep the original's structure and throw away its colours: its straw-yellow wash and crystal shrubs were never the target.

---

## 2. The five changes with the biggest payoff (do them in this order)

### Change 1: Clear the floor (kill the thicket, the rays, the ice and the spikes)

1. **Find every emitter:**
   ```
   grep -nE "Wild_Grass_Red|leaf_card|foliage-pack|foliagePack|grass(Large)?\.glb|plant_bushTriangle|rock_tall|stone_tall|cliff|godray|god_ray|shaft|PrismMesh|CylinderMesh|BoxMesh|CapsuleMesh|SphereMesh" scripts/world/*.gd scripts/**/*.gd scenes/*.tscn
   ```
2. **The red star-leaf thicket:** delete every MultiMesh or instance loop that scatters red leaf cards (the Kenney Foliage Pack cards through `leaf_card.gdshader`, and/or AssetQuest `Wild_Grass_Red_small.fbx`) anywhere inside the hedge room.
   - New rule, enforced in `dressing.gd`: inside the hedge-room rectangle, nothing may be taller than 0.35 m except the bed-border flowers (change 2), crops, the stall, characters, and trees placed at corners.
   - `Wild_Grass_Red_small.fbx` is banned from the garden entirely.
   - Leaf cards survive in exactly one place: as a shell on the new hedge (change 4).
3. **God-ray cards:** set `visible = false` on every tier, with a single `const GODRAY_CARDS_ENABLED := false` in `atmosphere.gd`. Tier (a) gets its rays from volumetric fog (change 3).
   - After sign-off passes, tier (b) may bring back **three** cards: additive, albedo `#f2dea7`, peak alpha **0.04**, faded to zero within 6 m of the camera.
4. **Ice-cube rocks:** remove every `rock_tall*`, `stone_tall*` and `cliff*` instance. Leave the small flat rocks until change 4 replaces them (§5).
5. **Spikes:** remove every cone or prism grass MultiMesh and every Kenney `grass*.glb` scatter. The lawn texture carries the ground until the clumps in §5 land.
6. **Labels:** confirm `act_label` stays off, and demote the "Petal Stall" `Label3D` to `visible = false`. Change 4 makes it a carved board.

**Acceptance**
- `scene_audit.json` reports 0 spikes, 0 visible primitives outside `signoff_ok`, and 0 label overlaps.
- In `CAM_01` at 1440×900, pixels with hue 345–15°, S > 0.55 and V > 0.3 cover **< 2%** of the frame (only flowers are allowed to be red).
- Side by side with `00_ORIGINAL`: you can see the ground again.

### Change 2: Rebuild the ground value ladder (dark soil beds, a calm lawn, warm stone)

**Step 0: texture tools** (numpy + PIL, run once, commit the outputs)
- `tools/tex/grade_to_palette.py --in X --out Y --mean <hex> --chroma <k>`
  1. Convert to Lab and shift the mean L\*a\*b\* onto the hex.
  2. Scale chroma around the mean by *k* and scale L\* variance by 0.9.
  3. Write an sRGB PNG.
- `tools/tex/albedo_to_detail.py --in X --out-normal Y_nrm.png --out-rough Y_rgh.png --strength s --rough-min a --rough-max b`
  1. Height = luma, Gaussian σ 1.5 px, Sobel filter, OpenGL +Y normal, tile-safe with wrap padding.
  2. Roughness = inverted luma, remapped to [a, b].
  3. **This is required.** Every DaVinci and VP tile is albedo-only, so the spec's "normal from B01/B29" doesn't exist until you generate it.

**Graded textures to produce** (in `res://assets/textures/garden/`, all 1024²)

| Output | Source | Grade |
|---|---|---|
| `lawn_meadow_albedo.png` | `/workspace/petalwild-vp-textures/tiled/VP04_meadow_tile.png` | mean `#75bd27`, chroma 0.85 |
| `lawn_clover_albedo.png` | `VP05_clover_tile.png` | mean `#8cc92c`, chroma 0.85 |
| `soil_albedo.png` | `VP01_soil_tile.png` | mean `#3d291c`, chroma 0.9 |
| `mulch_albedo.png` | `VP26_mulch_tile.png` | mean `#af5d29`, chroma 0.8 |
| `flagstone_albedo.png` | `VP28_drystone_tile.png` | mean `#d2b283`, chroma 0.75 |
| `dirtpath_albedo.png` | `VP07_dirtpath_tile.png` | mean `#cfa463` |
| `gravel_albedo.png` | `VP10_gravel_tile.png` | mean `#e8d0aa` |

**Detail maps** (in `res://assets/textures/detail/`, downsampled to 1024)

| Source | Strength | Roughness range |
|---|---|---|
| DaVinci `B01_soil_tile.png` | 1.0 | 0.82–0.98 |
| DaVinci `B02_tilled_tile.png` | 1.0 | 0.80–0.95 |
| DaVinci `B29_boxwood_tile.png` | 1.0 | 0.70–0.90 |
| DaVinci `B19_planks_tile.png` | 1.0 | 0.55–0.80 |
| DaVinci `B10_flagstone_tile.png` | 1.0 | 0.65–0.85 |
| **Lawn exception:** use the real Poly Haven `assets/third_party/polyhaven/leafy_grass/leafy_grass_nor_gl_1k.jpg` | | |

**Step 1: beds.** Create `scripts/world/bed_mesh_builder.gd` (a static func returning an `ArrayMesh`) and call it from `garden.gd` in place of the lime-pad StandardMaterial3D.
- **Footprint:** the bed's cell rectangle (cell 0.92 × 0.86 m) plus 0.12 m margin, with corner radius **0.18 m** (16 segments per corner).
- **Profile, from the lawn inward:**
  - The lip rises to **+0.11 m** over a rolled edge (radius 0.06 m, 6 segments).
  - It drops to a soil surface at **+0.09 m** with a **+0.02 m** dome at the centre.
  - The soil surface is gridded at **0.05 m** so the vertex shader can raise ridges.
- **Vertex colour:** R = baked AO (0.55 in the 3 cm tuck at the lip base, 1.0 elsewhere). G = 1 on lip faces, 0 on soil.
- **UVs:** world XZ.

**Step 2: new `shaders/bed_soil.gdshader`** (spatial, `cull_back`)
- **Soil (`COLOR.g == 0`):**
  - Albedo `soil_albedo.png` at 1 repeat per 1.0 m.
  - Normal `B01_soil_nrm.png` at strength 0.5, or `B02_tilled_nrm.png` for tilled cells.
  - Roughness 0.9, specular 0.3.
- **Lip (`COLOR.g == 1`):** `mulch_albedo.png` at 1 per 0.6 m, roughness 0.85.
- **Cell state texture:** `uniform sampler2D cell_state : filter_nearest`, one texel per cell, written by `garden.gd` whenever a cell changes.
  - R = tilled.
  - G = wet: albedo × 0.7, roughness 0.45.
  - B = planted.
- **Tilled ridges:** in `vertex()`, `VERTEX.y += tilled * 0.05 * (0.5 + 0.5*cos(TAU * local_z / 0.3))`. Ridges run east–west.
- **Cell seams:** multiply albedo by 0.6 within 1.5 cm of each cell boundary, on the soil only. This is the original's readable grid, living *inside the beds*, never on the lawn.
- **Rim:** `pow(1.0 - dot(NORMAL, VIEW), 2.4) * 0.04 * #e2c77b`.

**Step 3: `shaders/terrain.gdshader`**
1. Delete any `sin()`/`cos()` pattern on UV or world position.
2. Grass layer:
   - `lawn_meadow_albedo` at 1 per 2.0 m.
   - Second sample at 0.37× scale, rotated 37°, 50/50 mix.
   - Clover through a value-noise mask (freq 1/3 m, threshold for 25% cover).
   - Macro value ±6% from a 1/5.4 m noise.
   - Normal: `leafy_grass_nor_gl` at 0.3.
   - Roughness 0.85, specular 0.25.
   - Wrap diffuse 0.3 via a custom `light()` on tiers b and c only. Tier a uses the default light.
3. Paths come from a splat texture, not polygons. Paint `res://assets/terrain/garden_splat.png` at 5 cm/px over the hedge room (grayscale-antialiased edges, 15 cm feather):
   - R = flagstone plaza and the main N–S and E–W walks (1.2 m wide) around the four beds.
   - G = dirt spurs to the stall and gate.
   - B = gravel strip (0.3 m) against the hedge foot.

   Blend: flagstone at 1 per 1.5 m, dirt at 2.0 m, gravel at 1.0 m. Joints get moss `#788433` from the dark end of the flagstone luma.

**Acceptance (CAM_02 and CAM_08)**
- Median L\* of bed-soil pixels is **≤ median adjacent-lawn L\* − 12**, and flagstone L\* is **≥ lawn L\* + 10**. Measure with the mask from `scene_audit` bed rects, or by hand-drawing 3 boxes.
- `max_flat_ground_score ≤ 0.20` on shots 1–3.
- CAM_02 hits ≥ 4 of 7. CAM_03 hits ≥ 4 of 6.
- No lime pixel (`#8fe06a` ±ΔE 10) covers more than 1% of the frame.

### Change 3: Light the diorama (one WorldEnvironment per tier)

1. **Autoload** `scripts/core/quality_tier.gd` (name `QualityTier`):
   - `tier = "a"` if `RenderingServer.get_current_rendering_method() == "forward_plus"`.
   - `"c"` if `"mobile"`, or if `"gl_compatibility"` and `OS.has_feature("mobile")`.
   - Otherwise `"b"`.
   - On `_ready()` it assigns `res://environment/env_tier_<t>.tres` to the scene's `WorldEnvironment` and `res://environment/camattr_tier_<t>.tres` to its `CameraAttributes`, and applies the sun values.
2. **Scene nodes** in the Garden Grove scene (`scenes/main.tscn` or the garden scene, whichever `garden.gd` roots):
   - `Environment/WorldEnvironment`
   - `Environment/Sun` (DirectionalLight3D): `rotation_degrees (-35,-45,0)`, `light_color #f2dea7`, `light_energy 1.6`, `light_angular_distance 1.5`, `shadow_enabled true`, `shadow_blur 1.5`, `shadow_opacity 0.85`, `light_bake_mode BAKE_DYNAMIC`.
   - `Environment/BounceFill` (DirectionalLight3D, **tiers b and c only**; hidden on a): `rotation_degrees (35,135,0)` (pointing up and south-west, a fake ground bounce), `light_color #e2c77b`, `light_energy 0.18`, `shadow_enabled false`, `light_specular 0`.
3. `atmosphere.gd` keeps driving time of day, but it must **lerp from** these values and must not overwrite them with its own procedural palette at 16:30.
4. **Sky ground colours:** `ground_horizon_color #85894a` and `ground_bottom_color #576423`, so gaps read as lawn.
5. Full per-tier numbers are in §6.

**Acceptance**
- Clipped white ≤ 0.5%, crushed black ≤ 1%, and mean chroma ≥ 18 on all 8 shots.
- CAM_01 hits `#c1defb` and at least 4 other hexes.
- Shadows are brown-green and never grey. Spot-check the shadow under the stall: it should sit within ΔE 14 of `#34470d` on lawn.

### Change 4: Pillow hedge walls and a real skyline

1. **Hedge.** Run `blender -b -P tools/blender/make_hedge.py -- --out assets/models/hedge/` (spec in §5) and replace the stacked-cylinder hedge in `garden.gd` with:
   - MultiMesh rows of `hedge_seg_A/B/C.glb` (2.0 m each), chosen at random with per-instance Y-scale 0.92–1.08.
   - `hedge_corner.glb` at the corners.
   - `hedge_low_A.glb` (0.6 m) for inner hedges.
2. **Hedge material:** `shaders/hedge.gdshader`, extended so it is fully triplanar (no UVs needed).
   - Albedo `VP24_hedge_tile.png`, graded to mean `#2f9d2b`, at 1 per 1.2 m.
   - Normal `B29_boxwood_nrm.png` at 0.5.
   - Roughness 0.8.
   - Value gradient: multiply toward `#0b5d12` at the base and `#6fcc38` at the crest, driven by `COLOR.b` (a height mask baked in Blender).
   - Backlight 0.25 (`BACKLIGHT = vec3(0.19,0.31,0.08)`) on tier a. Wrap 0.3 on b and c.
   - Rim 0.08 tinted `#cee5fd`, doubled on normals with Y > 0.6.
3. **Trees:** place 6–8 **Kenney Nature Kit** `tree_oak.glb`, `tree_fat.glb` and `tree_default.glb` just outside the hedge (from `assets/third_party/kenney/nature-kit/Models/GLTF format/`).
   - Uniform scale 2.2–3.0.
   - Canopy surface override `res://materials/canopy.tres`: triplanar VP24 tinted to `#80863e`, roughness 0.85, backlight 0.25.
   - Trunk override: `VP16_oakbark_tile.png` at 1 per 1.0 m, roughness 0.9.
   - One tree inside, at the NW corner of the hedge room, for CAM_04.
4. **Backdrop:** a ring of 12 more Kenney trees at 25–40 m, plus one low hill made with `blender tools/blender/make_backdrop_hill.py`: a 60 m arc, 3 m high, smooth. Use terrain lawn material with fog. Once the art-desk strip `PETAL-08-106` is delivered, add it as an unshaded, fog-affected cyclorama band behind them.
5. Leaf cards (Kenney Foliage Pack) may be used as a sparse shell on the hedge crest only: ≤ 120 cards per 2 m segment, tinted `#6fcc38`, alpha-scissor 0.5.

**Acceptance**
- CAM_04 hits ≥ 4 of 7, including `#9e9521` and `#34470d`.
- The silhouette test: the hedge top line has at least 6 visible bumps per 10 m of screen-visible hedge and no straight horizontal run longer than 8% of frame width.
- The audit reports 0 `CylinderMesh`.

### Change 5: Frame it like the original (camera, houses, HUD)

1. **`camera_rig.gd` (PETAL_10):** change only the *default* values: pitch **−48°**, yaw **35°** (looking north-west from the south-east, so the sun rakes from the left), orbit distance **13 m** to `ANCHOR_BEDS`, FOV **40°**, zoom clamp 7–22 m. Input handling stays the same.
   - Result: the horizon sits at or above the top 10% of the frame, so the playfield is back to about 85% of the screen.
2. **Houses:** move the resident cottages out of the south foreground to a cluster north-east of the hedge (X +8…+14, Z −10…−16), where only their roofs show over the hedge in CAM_01.
   - If residents path to hard-coded house coordinates, update those constants in the same commit and run the resident logic tests.
   - Meshes get replaced in §5. The move alone removes about 20% of the frame's grey boxes.
3. **HUD** (the scene with the top bar and the toolbar):
   - Delete the empty first toolbar slot and centre the 10 buttons.
   - Toolbar height 64 px at 900 p (min tap target 44 px).
   - Panel fill `#f5dbb4` at 92% alpha. Text `#3a2a1c`. Active tool `#2f6b2a` with cream text.
   - Top bar stays, but shrinks to a 44 px pill.
   - World labels are culled if their screen rect intersects any HUD `Control` rect (see §8).
4. **Cursor ring:** keep the original's hover ring. Use a flat torus-ish decal, `#f2dea7`, emission 0.6, radius 0.42 m, snapped to the cell.

**Acceptance**
- CAM_08 at 1266×585: a first-time viewer can count the bed cells and point to the stall within 2 s.
- Beds and plaza fill ≥ 55% of the frame. Sky is ≤ 10%.
- 3 of 5 hexes hit, and 0 label overlaps.
- The side-by-side with `00_ORIGINAL` has the same "board game" read.

---

## 3. Shot list per camera (in priority order)

Use the positions, rotations and FOVs from VISUAL_TARGET §6, relative to `ANCHOR_BEDS`, `ANCHOR_STALL` and `ANCHOR_HEDGE_W`. PETAL_00 adds the markers first.

| Priority | Camera | Frame must show | PASS read | FAIL read (reject on sight) |
|---|---|---|---|---|
| 1 | **CAM_08_PHONE_PLAY** (1266×585, HUD on) | Four beds with cell seams, the plaza, the stall front at the top third, 1–2 jellies, 1 veg person | Dark beds are the first thing you see. Every label is legible and none overlap. The toolbar doesn't cover a bed | Horizon in the middle third. A lime or grey pad anywhere. Any label over another label or a panel |
| 2 | **CAM_01_HERO_OVERVIEW** | The whole hedge room, 4 beds, a flagstone walk, the stall in the back third, trees and haze beyond, sky ≤ 15% | Hedge ring gives the diorama edge. Warm side light from the left. The far park goes golden-soft (depth fog). Matches target 02's composition | Red noise field. God-ray milk. Box houses in the foreground. Cylinder hedge |
| 3 | **CAM_02_BEDS_SOIL** | Tilled, planted and empty cells side by side, the rolled mulch lip, flowers ringing the planted bed, grass clumps at the lip | Soil crumbs visible (about 2–3 cm). Ridges catch light on their south faces. Seams between cells. `#322116`/`#543a2d` hit | Flat brown plane. Sharp furrows. Checker. A grass multiply on the soil |
| 4 | **CAM_03_LAWN_PATH** | Lawn clumps and clover in the foreground, the flagstone walk running north with mossy joints, a feathered path edge, the far hedge softened | You can tell lawn from path by texture *and* value. Clumps are rounded, not spikes | Tiling visible within 4 m. A straight polygon edge along the path |
| 5 | **CAM_05_MARKET_STALL** | Cream/slate striped awning, fat posts, worn counter with crates and packets, lantern, carved sign, plaza stones | Timber reads as wood grain. The awning glows cream where the sun hits. Clipped white ≤ 0.5% (it's 10.2% today) | Floating Label3D. Sphere row as goods. Parasol cone. Box bench |
| 6 | **CAM_04_FOLIAGE_EDGE** | Lumpy hedge wall with a lit crest, one tree, a flower border in 2–3 hexes (coral + mauve + periwinkle) | Crest glows `#9e9521`. Shade face `#34470d`. Petals backlit | Flat-topped wall. Red star cards. A single flat green |
| 7 | **CAM_06_JELLY_HERO** | One jelly filling a third of the frame height, far depth of field, lawn contact shadow | Glossy highlight, translucent edge, glowing core, bead eyes with one catch-light | Matte clay look (roughness 0.94). Visible faceting. A black contact shadow |
| 8 | **CAM_07_VEG_FOLK** | One veg person, full body, label clear | Skin reads glossy (tomato), waxy or satin. Chunky nubs. Label above the head and clear of everything | Thin limbs. Stacked speech plus action labels |

---

## 4. Which existing assets go where (and what NOT to use)

**Use**

| Where | Asset (absolute or repo path) | How |
|---|---|---|
| Lawn albedo | `/workspace/petalwild-vp-textures/tiled/VP04_meadow_tile.png` plus `VP05_clover_tile.png` | Graded (change 2) |
| Lawn normal | repo `assets/third_party/polyhaven/leafy_grass/leafy_grass_nor_gl_1k.jpg` | 0.3 |
| Bed soil | `VP01_soil_tile.png` (albedo) plus DaVinci `textures/tiled/B01_soil`, `B02_tilled` (derived normal/roughness) | 0.5 |
| Bed lip | `VP26_mulch_tile.png` | Graded to `#af5d29` |
| Plaza and walks | `VP28_drystone_tile.png` (graded) plus DaVinci `B10_flagstone` (derived normal) | 1.5 m repeat |
| Spurs, gravel | `VP07_dirtpath_tile.png`, `VP10_gravel_tile.png` | |
| Shady lawn and joints | `VP06_moss_tile.png` | Splat |
| Hedge | `VP24_hedge_tile.png` plus DaVinci `B29_boxwood` (derived normal) | Triplanar |
| Bark | `VP16_oakbark_tile.png` | |
| Trees | Kenney Nature Kit `tree_oak`, `tree_fat`, `tree_default` (`assets/third_party/kenney/nature-kit/Models/GLTF format/`) | Material overrides |
| Bed-border flowers | AssetQuest `third_party/incoming/assetquest-stylized-garden-demo/FBX/Gerbera_1_Red.fbx`, `Poppy_Single_Red.fbx`, `Cosmea_Cluster_Small_1.fbx`, `Larkspur_1_Purple.fbx`, `Cornflowers_Big_Cluster_Blue.fbx`, `Giant_Sunflower_big_1.fbx` with `Plants_Atlas_1_Basecolor/Opacity.png`; Kenney `flower_*.glb` | Scale ×1.4 so heads are ≥ 1/3 of stem height. 2–3 species per bed. Max 1 clump per 0.3 m of bed edge |
| Crops | Kenney `crop_carrot/melon/pumpkin/turnip.glb`, `crops_leafsStageA/B.glb`, `crops_cornStageA–D.glb`, `crops_wheatStageA/B.glb` | Scale ×1.5. Material override to the palette (carrot `#e67828`, leaf `#43a443`, pumpkin `#e48c24`, stem `#677c45`), roughness 0.55 |
| Planters, seating | AssetQuest `Planter_1_Terracotta.fbx`, `Bench_1.fbx`, `Table_1.fbx` plus `Props_Basecolor.png` | Bench_1 replaces every box bench (including Grove Park) |
| Fences (garden gate only) | Kenney `fence_simple*.glb`, `fence_gate.glb` | Override albedo `#936942` plus B19 normal |
| Veg folk | repo `assets/characters/{carrot,leek,tomato}.glb` plus albedos | Keep. `veg_skin.gdshader` values per VISUAL_TARGET §3.7 |
| Stall and prop reference | DaVinci `props/D09_seed_crate.png`, `D13_lantern.png`, `D06_garden_shed.png`, `D10_watering_can.png`, `D11_wheelbarrow.png`, `concept/A05_cosy_seed_shop.png` | Blender modelling reference |
| Jelly look | DaVinci `creatures/C01_puddlepup.png`, `C02`, `C05`, `C15`, `C17`; `textures/R38_candy.png`; `R37_felt.png` (fuzzy species normal) | Reference and normal |
| UI SFX (already in) | Kenney Interface Sounds | Unchanged |

**Do NOT use**
- `VP03_lawn`, `VP02_tilled`, `VP09_flagstone`, `VP18_planks`, `VP30_crepe`.
- DaVinci `B32`, `B36`–`B39` (superseded), and DaVinci brick, cobble, picket and terracotta tiles as detail maps (ghosting).
- Any DaVinci tile **as albedo**. They're too grey; use them for detail only.
- `Wild_Grass_Red_small.fbx`, and Kenney `grass*.glb`, `plant_bushTriangle*`, `tree_pine*`, `tree_cone*`, `tree_palm*`, `tree_thin*`, `rock_tall*`, `cliff*`.
- Kenney `crops_dirt*.glb` (faceted orange tiles; our bed builder replaces them) and AssetQuest `Sun_Umbrella_1.fbx` (reads as a cone).
- Kenney Foliage Pack cards anywhere except the hedge crest shell.
- Everything in `/workspace/garden-grove-pack/tiles/` and `docs/reference/havenbrook_*` (Havenbrook).
- Higgsfield gummies, Grok-branded jellies and Jelly-Baby EXRs (reference only, GPL or look-alike).
- The Higgsfield cartoon sky `71b6b40b` (LDR cartoon, and it clashes with near-photoreal light).
- The Higgsfield soils `b429f85c` and `d4ac7637` (not seamless, and VP01 wins anyway).
- The FAL sticker stash. The Pi `grass_tile.png` (not seamless).

---

## 5. What to model or replace

All Blender generators are headless, e.g. `blender -b -P tools/blender/<script>.py -- --out <dir>`, and export GLB with `export_colors=True`.

**Common rules:**
- Bevel modifier (width ≥ 8% of the smallest dimension, ≥ 2 cm, 3 segments, `harden_normals`), smooth shading.
- Vertex AO bake: Cycles, 16 samples, `bake(type='AO', target='VERTEX_COLORS')` into `COLOR.r`.
- Tier-b LODs made with the `Decimate` modifier to the budgets in VISUAL_TARGET §4.
- Shaders multiply albedo by `mix(0.55, 1.0, COLOR.r)`.

| Thing | Approach | Spec |
|---|---|---|
| **Red leaf-card thicket** | **Delete** (change 1) and replace with bed-border planting (§4) | Nothing taller than 0.35 m inside the hedge room except allowed items |
| **Hedge** | Blender: `make_hedge.py` | Segment 2.0 L × 1.6 H × 0.9 D m. 9–13 overlapping subdivided icospheres (radius 0.35–0.6 m, crest ones 20% smaller), then voxel remesh 0.04 m, smooth ×2 and decimate to 3k tris (tier a) or 800 (b/c). `COLOR.b` = normalised height. Variants A, B, C, `hedge_corner`, `hedge_end`, `hedge_low_A` (0.6 m H, 0.5 m D). The crest must undulate ±0.12 m |
| **Houses** | Blender: `make_cottage.py` (3 variants) | Walls 2.6 × 2.2 × 1.9 m rounded box (bevel 0.10 m), plaster `#e1deb9` with B19 normal at 0.2 on the timber frame `#936942`. Rolled-eave roof (eave radius 0.15 m, overhang 0.3 m): thatch `VP19_thatch_tile.png` (`#ecb12a`) on 2 variants, terracotta `VP20` (`#f0845b`) on 1. Arched door `#6e4d32` (0.9 × 1.4 m). Round window, emission `#f8c04b` at dusk only. Stubby chimney 0.35 m. About 6k tris |
| **Crops** | Kenney swap plus overrides (§4). Any crop still a sphere or capsule becomes a Kenney stage | Growth = Kenney stages A→D. Mature crops at 1.5× so they read at phone size |
| **Rocks** | Blender: `make_boulders.py` | 6 boulders, 0.15–0.6 m: icosphere subdiv 3, noise displace 0.08, smooth, squash Y 0.6. Albedo `VP28` graded to `#a8916b`, moss cap `#788433` on normals with Y > 0.7. Max 10 in the whole garden, at path corners and the hedge foot |
| **Paths** | Shader (splat, change 2) on all tiers. Tier a adds `make_flagstones.py` geometry | Tier a: 8 pillow stones 0.35–0.6 m, 5 cm thick, bevel 3 cm, gaps 3–5 cm, scattered by MultiMesh along the R splat; the splat underneath supplies moss. Tiers b and c: texture only |
| **Beds** | GDScript procedural mesh (change 2) | As specified: corner radius 0.18, lip +0.11, roll radius 0.06, ridge 5 cm / 0.3 m |
| **Stall** | Blender: `make_stall.py` → `assets/models/stall/petal_stall.glb` | 2.0 W × 1.0 D m. Posts 0.14 m square with bevel 0.02. Counter top 0.9 m high, 0.08 thick, `#b68d73`, roughness 0.5. Awning 7 stripes 0.20 m wide, cream `#f5dbb4` and slate `#6d645a`, with a rolled front edge and 7 round scallops (radius 0.1 m). Sign board 1.1 × 0.32 × 0.06 m, `#e2af64`, with "Petal Stall" as extruded text (Inter Bold, 4 mm deep, `#6e4d32`); no Label3D. Lantern after D13 (glass emission `#f8c04b`, energy 1.5, frame `#3a2a1c`). 2 seed crates after D09 (0.45 × 0.3 × 0.22 m) holding packet cards textured from art-desk request `PETAL-08-104`. 2 burlap sacks (`#906c47`/`#cca473`, lumpy). One terracotta pot. The sphere "goods" row is deleted. Timber shader: B19 normal at 0.4, roughness 0.7 |
| **Grass clumps** | Blender: `make_grass_clump.py` | 3 variants: 5–7 blades, 0.12–0.22 m tall, blade width ≥ 1/5 of height, bent 20–40°, rounded tips, vertex colour `#409d31` at the root to `#91cb2b` at the tip. Existing `lawn_tuft.gdshader` handles sway (±3 cm, phase from world XZ). Tier a: 150k with LOD. b: 40k (opaque). c: 12k, fading out at 15 m. Densest within 0.4 m of bed lips and path edges; none on paths |
| **Leek (Lumen)** | Blender edit of `leek.blend` from the `art/characters` branch | Scale the body 1.5× in X/Z to hit a 1 : 1.3 ratio, and fatten the limbs into nubs. Re-export the GLB with the same node names |
| **Jelly** | Shader (`jelly.gdshader`) plus mesh segment counts | VISUAL_TARGET §3.6 exactly: roughness 0.22, specular 0.5, clearcoat 0.6/0.15, SSS 0.6, transmittance = core, depth 0.25, backlight body × 0.5, rim 0.28, opaque. Tier b/c fallback: wrap, `pow(max(0,dot(-L,V)),3) × body`, rim, vertex-colour core. ≥ 64 segments on a, 24 on phone. Blob-shadow decal (`#1c2c08` at 35%) under each jelly on b/c |

---

## 6. Materials and lighting per tier

Put these in `res://environment/env_tier_{a,b,c}.tres` and `camattr_tier_{a,b,c}.tres`. Project settings use feature-tag overrides (`.web`, `.mobile`).

| Setting | **(a) Forward+ 4K** | **(b) Compatibility / browser** | **(c) Mobile / phone** |
|---|---|---|---|
| Background / sky | `BG_SKY`. Sky shader `shaders/sky_garden.gdshader` (below), `radiance_size 256` | `ProceduralSkyMaterial`: top `#c1defb`, horizon `#eef3fe`, `sky_curve 0.12`, ground horizon `#85894a`, ground bottom `#576423`, `sun_angle_max 30`, `sun_curve 0.15`. `radiance_size 32` | Same as b. On Compatibility phones, a 2-stop gradient sky shader instead |
| Ambient | Sky source, `sky_contribution 0.85`, energy 0.6, colour `#c9dee7` | Same | Same |
| Tonemap | `TONE_MAPPER_ACES`, exposure 0.95, white 6.0 | Same | Same |
| Adjustments | `adjustment_enabled`, brightness 1.0, contrast 1.05, saturation 1.12. No colour-correction LUT in v1 | Same | Saturation 1.15 |
| Depth fog | `fog_enabled`, exponential, colour `#c9dee7`, density 0.004, sky affect 0.3, aerial perspective 0.45, height fog off | Same | Same, density 0.005 |
| Volumetric fog | On: density 0.008, albedo `#f2dea7`, anisotropy 0.6, length 64 | Off. God-ray cards off (change 1) | Off |
| GI | SDFGI: 4 cascades, `min_cell_size 0.15`, occlusion on, `bounce_feedback 0.4` | LightmapGI baked at 16:30 on Scott's GPU PC after change 4 lands (texel scale 1.0, sun dynamic). Until then: vertex AO plus `BounceFill` | LightmapGI texel 0.5, plus `BounceFill` |
| SSAO | radius 0.6, intensity 1.8, power 1.5, detail 0.5, light affect 0.1 | Off (test on 4.8-dev6 before enabling) | n/a |
| SSIL | radius 3, intensity 0.8 | Off | n/a |
| SSR | Off (ReflectionProbe 30×8×30 m over the garden, update once) | Off | Off |
| Glow | Intensity 0.6, strength 1.0, bloom 0.05, HDR threshold 1.0, levels 3–5 | Intensity 0.4 | Intensity 0.3 |
| Depth of field | `CameraAttributesPractical` far blur on CAM_01 and CAM_06 only: amount 0.06, far distance 2.5× subject distance, transition = subject distance | Off | Off |
| Shadows | Size 8192, 4 splits, max distance 60 m, soft filter **High**, angular distance 1.5 | 2048, 2 splits, 30 m, **Soft Low** | 2048, 2 splits, 20 m, **Soft Very Low**. Blob decals under characters |
| AA | MSAA 4× (`msaa_3d=2`) plus alpha-to-coverage on foliage. TAA off | MSAA 2× plus FXAA | MSAA 2×, FXAA off, FSR1 at 3D scale 0.7 |
| Textures | Ground and hedge 1024² in v1 (the VP sources are 1024). 2048 detail normals only if CAM_02/03 look soft at 4K. Anisotropy 16× | 1024² ground and hedge; props and characters 512² | 1024² ground; 512² everything else; ASTC 6×6; anisotropy 4× |
| Foliage | Grass 150–300k clumps. Hedge crest cards on. Backlight or SSS on leaves, petals, jelly, veg | 30–60k opaque clumps. No crest cards. Wrap plus rim | 10–20k clumps, fade at 15 m. No crest cards. Character rim ×1.5 |

**Faking the HDRI until a real one exists (tier a)**
- `shaders/sky_garden.gdshader` (`shader_type sky`):
  - Upper hemisphere: a gradient from `#eef3fe` at the horizon to `#c1defb` at the zenith (curve 0.12), plus a soft fbm cloud band between 6° and 22° elevation (colour `#eef3fe`, max alpha 0.45, scrolling at 0.002/s).
  - Sun disc tinted `#f2dea7`.
  - Lower hemisphere: `#85894a` → `#576423`.
  - Uniforms: `uniform sampler2D hdri : source_color, filter_linear;`, `uniform float hdri_mix = 0.0;`, `uniform float hdri_energy = 1.0;`.
- **The real HDRI to fetch** (free, CC0): Poly Haven **`kloofendal_48d_partly_cloudy_puresky`**, 2k EXR, saved as `assets/third_party/polyhaven/hdri/kloofendal_48d_partly_cloudy_puresky_2k.exr` with a CC0 `LICENSE.txt`.
  - Once it's in, set `hdri_mix = 0.65` for the upper hemisphere only. The lower hemisphere stays the green gradient, and 35% gradient stays in the mix so `#c1defb` still passes sign-off.
  - Rotate the panorama so its sun sits at azimuth SW.
  - Tiers b and c never load the EXR.

---

## 7. Art-desk requests to file (lane A, in-chat, zero spend)

These are **21 images**, well under the 45/hour and 120-left/day caps. Run `imgquota.py check 21` first. File each one as `art_desk/requests/<id>.yaml`.

For every tile: if a 1:1 request comes back 16:9, the desk centre-crops 576², runs `petalwild-davinci/make_tile.py`, and upscales to 1024 with Lanczos.

```yaml
id: PETAL-08-101
pass: PETAL-08
kind: texture
subject: "Stylised lawn grass tile (VP03 redo): dense soft blades seen from above, clumped, a few clover leaves"
style: >
  Viva Piñata painterly, saturated but not neon. Mean colour #75bd27, highlights #91cb2b,
  shadows #409d31. Readable as GRASS BLADES, not pebbles or leaf scales. No flowers, no light
  direction, no vignette. Seamless on all four edges.
count: 4
size: 1024x1024
due: 2026-10-02
lane_hint: A
refs: [/workspace/petalwild-vp-textures/tiled/VP04_meadow_tile.png, /workspace/petalwild-vp-textures/tiled/VP05_clover_tile.png]
```

```yaml
id: PETAL-08-102
pass: PETAL-08
kind: texture
subject: "Warm flagstone plaza tile (VP09 redo): rounded pillow-edged sandstone slabs with mossy joints"
style: >
  Chunky toy-diorama stone. Slabs #e0bd87 to #ccab79, joints #8e7f60 with moss #788433.
  NO blue or grey stones, no orange-blue clash. Top-down, flat even light, seamless all edges.
count: 4
size: 1024x1024
due: 2026-10-02
lane_hint: A
refs: [/workspace/petalwild-vp-textures/tiled/VP28_drystone_tile.png, /workspace/petalwild-davinci/concept/A01_circular_stone_plaza.png]
```

```yaml
id: PETAL-08-103
pass: PETAL-08
kind: texture
subject: "Warm timber planks tile (VP18 redo) for stall and cottages"
style: >
  Planed, slightly worn timber with visible grain, base #936942, shadow #6e4d32, planed edges
  #d5bc9a. Unpainted. Absolutely no blue paint. Planks run vertically, seamless all edges, flat light.
count: 3
size: 1024x1024
due: 2026-10-02
lane_hint: A
refs: [/workspace/petalwild-davinci/props/D09_seed_crate.png, /workspace/petalwild-davinci/props/D06_garden_shed.png]
```

```yaml
id: PETAL-08-104
pass: PETAL-08
kind: image
subject: "Sheet of 8 seed-packet fronts in a 4x2 grid (sunflower, tulip, carrot, tomato, pea, lettuce, foxglove, poppy)"
style: >
  Hand-painted vintage seed packets, cream paper #f5dbb4, a painted illustration of the plant on each,
  a short one-word name. Warm palette from the PetalWild target sheet. Flat-lit, front-on, each packet
  in an equal cell with a 16 px gutter of flat #6d645a. No brand names, no Havenbrook.
count: 3
size: 1024x1024
due: 2026-10-02
lane_hint: A
refs: [/workspace/petalwild-davinci/concept/A05_cosy_seed_shop.png, /workspace/petalwild-davinci/props/D09_seed_crate.png]
```

```yaml
id: PETAL-08-105
pass: PETAL-08
kind: image
subject: "HUD tool icon sheet, 10 icons in a 5x2 grid: tiller, seed bag, rain can, fertiliser sack, tending hand-trowel, scoop net, home, open hands, journal, market stall"
style: >
  Chunky rounded toy-like icons, soft painted shading, outline-free, palette from the PetalWild sheet
  (timber #936942, leaf #43a443, terracotta #f0845b, cream #f5dbb4). Each icon centred in an equal
  cell on flat solid #ff00ff for chroma keying. Readable at 48 px.
count: 3
size: 1024x1024
due: 2026-10-03
lane_hint: A
refs: [/home/box/art_library/staging/ui/]   # desk: use the Grok-bot shape/palette sheet as shape reference only
```

```yaml
id: PETAL-08-106
pass: PETAL-08
kind: image
subject: "Distant park horizon strip: soft rounded tree canopies and a golden hazy meadow, seen at eye level from a garden"
style: >
  Painterly, soft, low contrast, golden late-afternoon haze. Canopies #80863e / #595c24, haze toward
  #c9dee7 and #eef3fe near the top edge, which fades to flat #eef3fe. No sky detail, no buildings, no
  people. Must wrap seamlessly left-to-right.
count: 4
size: 1024x512
due: 2026-10-03
lane_hint: A
refs: [/workspace/petalwild-artdesk/visual_target/refs/petalwild_target_garden_02.png]
```

(Not requested on purpose: HDRI, which comes free from Poly Haven. Tilled rows, awning and bed soil, which are geometry, procedural or existing VP01. Music and SFX, which are a separate audio brief.)

---

## 8. Guardrails and the capture-and-compare ritual

**Never again:**
1. **No vertex-colour-only or untextured materials** on any ground, hedge, bed, path, building or stall surface. Every such material samples a graded albedo and a detail normal. Vertex colour is allowed only as AO/masks (R, G, B as defined above).
2. **No procedural checker, grid or `sin()`/`cos()` pattern** on world position or UV in any ground shader. The grid lives only as cell seams inside beds.
3. **No primitive meshes** (`Box`, `Cylinder`, `Prism`, `Capsule`, `Sphere`, `Plane`, `Quad`) visible in the garden unless the node is in group `signoff_ok`. That includes MultiMesh meshes.
4. **No cones, prisms or single-triangle spikes** for grass or plants.
5. **No red leaf-card thicket and no `Wild_Grass_Red_small`**, and no scatter taller than 0.35 m inside the hedge room except the allowed items.
6. **No full-screen additive haze** (god-ray cards) on tiers b and c before sign-off, and never above 0.04 alpha.
7. **No Label3D for signage** (use carved or painted geometry), no always-on `act_label`, and at most one speech bubble on screen. Labels hide by priority: speech > name > act. Any label whose rect overlaps a HUD `Control` is culled.
8. **No albedo brighter than `#f5dbb4` or darker than `#1f130b`**, and no pure white or black.
9. **No DaVinci tile used as albedo, and no flagged VP tile** (VP02, VP03, VP09, VP18, VP30).
10. **Never "fix" a look by changing the tonemapper, exposure or saturation away from spec.** Fix the albedo or the light.
11. **Logic green is not done.** A PR that touches `garden.gd`, `dressing.gd`, `atmosphere.gd`, `camera_rig.gd` or `shaders/` is not mergeable without an attached compare sheet and a `signoff_check.py` PASS for the tier it was captured on.

**Enforce them in CI** with `tools/ci/art_lint.sh`, which exits 1 on any hit:
```bash
grep -nE "sin\(|cos\(" shaders/terrain.gdshader shaders/bed_soil.gdshader && exit 1
grep -rnE "Wild_Grass_Red|VP0[239]_|VP18_|VP30_|havenbrook" scripts scenes shaders materials && exit 1
grep -rnE "act_label\s*=\s*true" scripts && exit 1
exit 0
```
Also add `tests/test_art_audit.gd`, a headless test that loads the garden and fails on any rule 1, 3, 4 or 7 violation. It reuses the audit logic in `signoff_capture.gd`.

**Ritual, after every commit in §2:**
```bash
# 1. capture (tier b on the VM; tier a on Scott's GPU PC before merge)
DISPLAY=:1 godot --path . -s res://tools/signoff_capture.gd -- --scene=res://scenes/garden.tscn --out=/tmp/signoff/$(git rev-parse --short HEAD) --hour=16.5
# 2. score
python3 /workspace/petalwild-artdesk/visual_target/signoff_check.py /tmp/signoff/$(git rev-parse --short HEAD)
# 3. compare sheet: ORIGINAL | this commit CAM_08 | previous commit CAM_08 | target_garden_02, all at 1440x900
python3 tools/art/compare_sheet.py \
  docs/screenshots/petalwild_overview.png \
  /tmp/signoff/<this>/CAM_08_PHONE_PLAY.png /tmp/signoff/<prev>/CAM_08_PHONE_PLAY.png \
  /workspace/petalwild-artdesk/visual_target/refs/petalwild_target_garden_02.png \
  --out docs/screenshots/compare/<this>.png
```

- `compare_sheet.py` is a PIL 2×2 montage with labels. It also prints three numbers under each tile: mean chroma, % clipped, and the bed-vs-lawn L\* delta.
- **Regression rule:** if any number moves the wrong way against the previous commit, or any section visible in the previous sheet has vanished, revert that commit before continuing.
- **Done means:**
  1. All 8 shots PASS on tier b, then on tier a.
  2. CAM_08 beats `00_ORIGINAL` on the board-game read.
  3. The Art Director signs off, side by side with `21_target_board.jpg`.
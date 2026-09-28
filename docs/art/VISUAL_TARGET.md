# PetalWild visual target (Garden Grove)

Owner: Game Art Director (art desk). v1 written 28 Sep 2026 at Hailo's request, because the integrated build (`petal/08-integration`) had lost its look. **v2 written 28 Sep 2026 after Scott's seven binding decisions.**
Status: **target v2, binding**. Every lane that touches what the player sees (PETAL_00 environment, 03 jelly, 04 veg folk, 05 dressing, 06 shaders, 10 camera) builds to this page. The camera sign-off set in section 6 is how we decide "done". The v1 text is kept at `/tmp/VISUAL_TARGET.md.v1` on the box.

### Scott's binding decisions (v2)

| # | Decision | Where it lands |
|---|---|---|
| D1 | **The DaVinci A01–A20 concept set is the look.** The two repo `petalwild_target_garden_0x` shots are now secondary (composition only) | Board, section 5, per-camera `must_hit` hexes in section 6 |
| D2 | **Halfway between toy and real.** Not Viva Piñata toy plastic, not photoreal: literally the midpoint | Section 1 (Lab-midpoint rule), halfway albedos in 3.2–3.5 |
| D3 | **Weather and time of day are states**, not one frozen 16:30: clear, overcast, rain, night, dawn/dusk, frost/snow, driven by **live local weather and the system clock** | Section 3.1 state table and live-sync rules |
| D4 | **Sims-style speed controls**: pause / 1× / 2× / 4× | Section 3.1 "Time controls" |
| D5 | **Camera layers**: garden ring → drop into a character → Viva Minera low view → world/builder view → free cam | Section 6 "Camera layers" |
| D6 | **Jellies are Grok bots**: the Grok icon shapes with slash eyes, candy translucency, the Grok picker palette, and the MorphCycle states | Section 3.6 |
| D7 | **Veg folk are Pixar/Ghibli surreal fruit-and-veg people** (real vegetable skin, appealing faces) | Section 3.7 |

Companion files (all on the box, in `/workspace/petalwild-artdesk/`):

| File | What it is |
|---|---|
| `visual_target_palette.png` | Labelled swatch sheet of every v2 hex (groups, weather states, halfway rows, Grok jelly palette) |
| `visual_target_board.jpg` | **4×5 labelled board of A01–A20**, each tile titled with what it is the reference for |
| `visual_target/sample_palette.py` + `samples.json` | PIL/numpy k-means sampler. v2 adds A01–A20 band samples (`concept.Axx.top/mid/ground/accent`) and real-scan samples (`real.Bxx_*`) from the DaVinci tiled textures |
| `visual_target/palette.py` + `palette.json` | The chosen palette (version 2): hex, role, source sample, plus the computed halfway rows |
| `visual_target/board.py` | Builds the 4×5 board |
| `visual_target/calibrate_v2.py` + `calibration_v2.json` | Rebuilds each camera's `must_hit` list from its mapped A scenes, and proves the A scenes pass while the current build fails |
| `visual_target/signoff_capture.gd` | Godot script: freezes clock and weather into the test state, screenshots each `CAM_*` view and audits the scene for placeholders, cone grass, checker textures and overlapping labels. v2 adds `--weather=` |
| `visual_target/signoff_check.py` + `signoff_spec.json` | Scores the PNGs: palette tolerance, flat or checker ground, clipping, greyness, and the scene audit |
| `visual_target/refs/` | Repo targets (chrome cropped), jelly reference crop, four current-build screenshots used to calibrate the checker |
| `ASSET_PICKS.md` | Concrete staged files picked per sign-off camera, with licences |
| `IMAGE_SPRAWL.md` | Where every PetalWild / Garden Grove image on the box lives (read-only survey, nothing moved) |
| `requests_outbox/*.yaml` | Art-desk requests for the gaps (not yet filed in the repo) |

Out of scope, on purpose: **Havenbrook art.** That rules out `/workspace/havenbrook-art/` (except the Grok icon refs in `refs/grok-avatar-anim/`, which are Grok brand material, not Havenbrook art), the repo's `docs/reference/havenbrook_*.png`, the eight `garden-grove-pack/tiles/*.png` and `petalwild-shots/havenbrook_*` (all carry Havenbrook signage). Havenbrook **code** is referenced for the speed controls only. No new images were generated for this document.

---

## 1. The one-line target

**A garden diorama exactly halfway between a toy and the real thing: rounded, chunky, readable shapes, surfaces that look like real soil, leaves, timber and candy, lit like the A-series (soft real sunlight, real weather), with colour that is rich but earthy, never neon.**

### D2: the halfway rule (how "halfway" is measured)

v1 split the work (toy shapes, candy albedo, real light). Scott's decision is stronger: **every surface sits at the midpoint.** It is defined numerically so nobody argues by eye:

- **Albedo.** For each material, take the stylised VP hex (toy) and the matching DaVinci B-series scan hex (real), convert both to CIELAB and take the midpoint. Those are the "halfway albedos" in `palette.json` (group `halfway`), for example soil `#3d2c20` (VP01 `#322116` ↔ B01 scan), lawn `#679428` (VP04 `#75bd27` ↔ B05 scan), hedge `#3d7725` (VP24 `#2f9d2b` ↔ B29 scan). v1's raw VP albedos are **retired**: they were the toy end.
- **Shape.** Silhouettes stay chunky and bevelled (toy side), but proportions move toward life: flower heads ≥ 1/4 of stem height (v1: 1/3), bevels ≥ 5% of smallest dimension (v1: 8%), hedges lumpy but leafy rather than pillow-smooth.
- **Surface detail.** Normal/roughness from the DaVinci scans at **strength 0.6–0.8** (v1: 0.3–0.5). Poly Haven CC0 PBR sets are allowed where they exist (soil, lawn, leaves).
- **Light.** Physically plausible (A-series), with tilt-shift DOF kept only on hero/close shots. The miniature feel now comes from framing and DOF, not from plastic materials.
- **The test.** Put the frame next to its mapped A scene on the board. If the frame looks more like a toy than the A scene, push toward real; if it looks like a photo of a real garden, push back toward toy.

### Pillars

1. **Halfway, everywhere.** Readable toy shapes, believable real surfaces. Nothing plastic, nothing photographic.
2. **Living light.** The garden follows real weather and the real clock. Every weather state is designed, not an afterthought.
3. **Colour tells the game.** Saturated flowers, Grok jellies and veg folk pop against earthy greens and browns (A20 is the saturation ceiling).

---

## 2. Global rules (every area)

### Banned, everywhere, at every tier
- **Checker, grid, UV-test or "prototype" textures.** The ground in the current build is a placeholder, not a style.
- **Cone or spike grass**: single-cone blades, `CylinderMesh` with `top_radius ≈ 0`, and `PrismMesh` blades.
- **Box placeholders**: raw `BoxMesh`, `CylinderMesh` or `PlaneMesh` benches, hedges, stalls or signs with flat untextured materials. The box hedges, box benches and flat tan ground in the current screenshots are exactly this.
- **Stacked or overlapping labels.** World labels must never overlap each other or a HUD panel. Details in camera shot 8.
- **Pure `#ffffff` or pure `#000000` albedo.** The brightest albedo allowed is `#f5f1ea` (Grok jelly white, capped). The darkest is `#1a120c` (halfway soil crevice). A lit frame may not clip more than 0.5% of its pixels to white.
- **Hard ink outlines on world geometry.** The edge cue is a soft fresnel rim, not a line.

### Shape language (applies to all meshes)
- **Bevel everything.** Every hard edge needs a rounded bevel of at least 5% of the object's smallest dimension (v2 halfway rule; v1 was 8%), and never less than 1.5 cm at garden scale. Bevels should catch the rim light.
- **Build from pillows, spheres and capsules**, and overlap them. A hedge is a row of lumpy pillows. A tree canopy is 3–7 overlapping blobs. A flower head is 5–8 rounded petals.
- **Chunky proportions.** Thick stems (at least 1/12 of stem height), generous flower heads (diameter at least 1/4 of stem height), fat fence posts, thick counter tops.
- **Scale.** The garden cell is about 0.92 × 0.86 m (`docs/ASSET_HUNT.md`). Proposed proportions (please confirm): a Grok jelly is 0.35–0.45 m tall, a veg-folk character is 0.9–1.1 m, and the stall counter is 0.9 m.
- **Silhouette test.** At phone size, the silhouette alone must tell you what the thing is.

### Material model (shared)
- Albedo comes from the **halfway** rows of the palette (section 1). Normal, roughness and AO detail comes from the matching DaVinci scan in `/workspace/petalwild-davinci/textures/tiled/` (or the Poly Haven CC0 set where one is picked in `ASSET_PICKS.md`), at **normal strength 0.6–0.8**.
- **Rim.** Fresnel rim `pow(1 - N·V, 2.2–2.6)`, tinted by the current weather state's sky mid colour (clear: `#b7c7d2`) for foliage and ground, or by the object's own highlight hex for characters. Strength 0.04–0.10 on ground, 0.15–0.30 on characters.
- **Texel density.** Tier (a) 512 px/m for ground and 1024 px/m for hero props. Tier (b) half that. Tier (c) a quarter. The texture scales below are world metres per texture repeat.
- **Outline: none**, except the phone-tier readability rim boost described in section 4.

---

## 3. The look, area by area

v2 hexes were sampled with PIL (numpy k-means) from A01–A20 (band samples `concept.Axx.*`) and the DaVinci real scans (`real.Bxx_*`); halfway rows are computed (section 1). Sample ids match `visual_target/samples.json`. Two kinds of value:
- **Albedo**: the material base colour you type into Godot.
- **Screen**: what a lit, tonemapped frame should read. The sign-off checker compares against these within ΔE 14 (Lab).

### 3.1 Overall garden, light, weather and time

**Look.** The A-series world: a walled hedge garden with raised beds, stone plaza and stall (A01, A02, A05, A14), lush borders (A04, A20), and creature life (A10, A11). The garden's mood follows the weather state; the **sign-off test state is clear, 16:30** (below).

**Clear-day light (A01/A02/A14/A20).**

| Role | Hex | Source |
|---|---|---|
| Sky zenith (screen) | `#b7c7d2` | concept.A20.top / A14.top |
| Sky mid / horizon haze (screen) | `#cfdbe1` | concept.A02.top |
| Warm horizon (screen) | `#f7deb1` | concept.A01.top |
| Highlight cream (screen) | `#fcf2d5` | concept.A20.top |
| Sun key colour | `#e3ca82` | concept.A01.accent |
| Golden bounce / fill | `#b39a4d` | concept.A14.mid |
| Darkest allowed shadow (screen) | `#1d250d` | concept.A01.ground |

A-scene frame measurements (daytime): mean Lab chroma 18–36, clipped white ≤ 0.3%, crushed black 0.2–1.5% (A05 interior 3.3%, A18 canopy 2.7%). Hence `max_crush_black_pct` is now 1.5.

**Lighting (Godot).** Owner PETAL_00. One WorldEnvironment `.tres` per tier; weather states are applied on top by a `WeatherLook` resource per state (tweened over 20–60 s of game time).

- **Sun (clear, 16:30).** `rotation_degrees = Vector3(-35, -45, 0)`, `light_color = #e3ca82`, `light_energy = 1.6`, `light_angular_distance = 1.5°`, `shadow_blur = 1.5`, `shadow_opacity = 0.85`. Sun rotation is driven by the clock (see below): elevation = solar elevation for the garden's latitude (default London 51.5°N), clamped to −10…60°.
- **Sky.** `ProceduralSkyMaterial` driven per state (table below), or the picked Poly Haven CC0 pure-sky HDRIs as the clear/partly-cloudy base (see `ASSET_PICKS.md`; request ART-DIRECTOR-004 covers the per-state procedural sky). `ground_horizon_color = #61661a`, `ground_bottom_color = #343a12` so gaps read as far lawn.
- **Ambient.** Sky source, `sky_contribution 0.85`, `energy 0.6`, colour = state fog tint.
- **Fog.** Depth fog, colour = state fog tint, density per state, `fog_aerial_perspective 0.45`. Tier a volumetric fog `albedo = sun colour`, anisotropy 0.6.
- **Tonemap: ACES on every tier**, `exposure 0.95` (per-state offsets below), `white 6.0`. Grade `contrast 1.05`, `saturation 1.08` (v1 1.12; halfway rule). No teal grade.
- **GI / SSAO / SSIL / glow / DOF.** As v1: SDFGI on tier a, LightmapGI on b and c (lightmaps baked for clear 16:30 only; other states tint ambient), SSAO `radius 0.6 intensity 1.8`, SSIL `radius 3 intensity 0.8`, glow intensity 0.6 levels 3–5, tilt-shift DOF only on hero and close cameras.

**Weather and time-of-day states (D3).** Every state is a designed look with an A-scene reference.

| State | A ref | Sun (elev / colour / energy) | Sky top → horizon | Fog tint / density | Ambient energy | Exposure | Extras |
|---|---|---|---|---|---|---|---|
| **Clear day** (test state) | A01, A02, A20 | 35° / `#e3ca82` / 1.6 | `#b7c7d2` → `#cfdbe1` | `#cfdbe1` / 0.004 | 0.6 | 0.95 | — |
| **Overcast** | A14 (hazy), A07 | 35° / `#c4d2bd` / 0.7, shadow_opacity 0.5 | `#b7c7d2` → `#c4d2bd` | `#c4d2bd` / 0.008 | 0.9 | 1.05 | Cloud cover 0.8 in sky shader |
| **Rain** | A07 | 30° / `#97a77b` / 0.45, shadow_opacity 0.35 | `#97a77b` → `#c4d2bd` | `#c4d2bd` / 0.015 | 1.0 | 1.1 | GPUParticles rain (streak cards, 3–6 k tier a, 800 tier c), puddle decals; **wet materials**: albedo × 0.75, roughness × 0.5 on soil, stone, timber, leaves (global `wetness` shader uniform, ramps over 10 game-minutes) |
| **Dawn / dusk** | A03 (dawn), A15 (golden) | 6–10° / `#e4d7b8` dawn, `#c39042` dusk / 0.6–0.9 | `#c39042` → `#e4d7b8` | `#e4d7b8` / 0.006 | 0.45 | 1.0 | Lanterns fade in below 8° |
| **Night** | A06 | Moon DirectionalLight `#466177` / 0.15 | `#12272f` → `#466177` | `#12272f` / 0.006 | 0.25 | 1.2 | Lantern OmniLights `#e7984c` energy 1.5, glow `#24a4c6` on glowbugs and jelly cores (emission 0.3), stars in sky shader |
| **Frost / snow** | A09 | 15° / `#e2dbd6` / 1.0 | `#98a1a4` → `#e2dbd6` | `#e2dbd6` / 0.01 | 0.8 | 0.9 | Global `frost` uniform: top-facing surfaces blend to `#e2dbd6` (normal.y > 0.6), roughness 0.6; snow particles; shadow tint `#424c46` |
| **Autumn** (season tint, combines with any state) | A08 | as state | as state | as state | as state | as state | Foliage albedo lerps 40% toward `#eecd82` / `#ae4c11`; leaf-fall particles |

A06 (13.5) and A09 (7.6) are legitimately low-chroma; the chroma floor applies to the clear test state only.

**Live weather and clock sync (D3).**
- **Clock.** Game time follows the system clock by default (`live_sync = true`): hour = local wall-clock hour, sun elevation from latitude and date.
- **Weather.** Poll a real local weather API (Open-Meteo is key-free; Met Office DataHub as an alternative for UK) every 15 real minutes, using the device's coarse location or a player-set town. Map WMO codes: 0–1 → clear, 2–3 → overcast, 45–48 → overcast + fog ×2, 51–67 / 80–82 → rain, 71–77 / 85–86 → frost/snow, 95–99 → rain (heavy). Offline or denied: fall back to a scripted seasonal cycle (the existing `scripts/autoload/clock.gd` golden/rain/mist/clear script on `petal/08-integration`).
- **Player override.** Settings toggle "Follow my real weather / time" (on by default); off uses the game's own clock and scripted weather.
- Existing nodes to wire: `scripts/autoload/petal_clock.gd` (`paused`, `time_scale`), `scripts/sim/world_state.gd:77` (`time_scale`), `scripts/autoload/clock.gd` (weather script), all on `petal/08-integration`.

**Time controls (D4, Sims-style).**
- HUD buttons: **Pause ‖, 1× ▶, 2× ▶▶, 4× ▶▶▶**, top-right, with the current speed highlighted; hotkeys Space (pause toggle), 1 / 2 / 3.
- Speeds set `time_scale` to 0 / 1 / 2 / 4 (replace the current halve/double code in `scripts/main.gd` lines 259–261, which clamps 0.25–8). Any speed other than 1× (or pause) turns `live_sync` off until the player presses "Back to now".
- Reference implementation lives outside GitHub on Scott's PC: `C:\Users\scott\Downloads\Havenbrook\src\lib\havenbrook-port\clock.ts` and `src\components\hud\pause-menu.tsx` (Havenbrook; code reference only, not art). No Havenbrook repo is on GitHub, and the box copies (`/workspace/havenbrook/world-store.ts`, `runtime.ts`) have pause but no speed multiplier.

**Sign-off test state.** All sign-off captures run with `weather = clear`, `hour = 16.5`, `live_sync = false`, `time_scale = 1` (in `signoff_spec.json` → `test_state`). `signoff_capture.gd` forces this (`--weather=clear --hour=16.5`) and records it in `scene_audit.json`, so live weather can never fail or pass a capture by accident. Other states get a human check against their A ref, not the automated palette gate.

### 3.2 Beds and soil (A02, A12)

**Look.** Raised, rounded soil beds with a rolled lip, filled with chunky, crumbly, dark chocolate soil (A02, A12). Tilled rows are soft ridges, not sharp furrows. Planted beds keep a ring of leaves and flowers. The edging is mulch or low, rounded timber.

| Role | Hex | Source |
|---|---|---|
| Soil base (albedo, halfway) | `#3d2c20` | halfway(VP01, real.B01_soil) |
| Soil clod, lit (albedo, halfway) | `#5c4435` | halfway(VP01, real.B01_soil) |
| Crumb highlight (albedo) | `#846444` | concept.A02.ground |
| Soil gap / crevice (albedo, halfway) | `#1a120c` | halfway |
| Tilled ridge (albedo, halfway) | `#7b5a42` | halfway(VP01 crumb, real.B02_tilled) |
| Bed soil in sun (screen) | `#644728` | concept.A02.accent |
| Mulch edging (albedo, halfway) | `#9b5b32` | halfway(VP26, real.B31_mulch) |

- **Material.** Albedo: Poly Haven `flower_scattered_dirt` diffuse (CC0, has normal + ARM) tinted to the halfway soil hex, or `VP01_soil_tile.png` graded to `#3d2c20`. Normal and roughness from Poly Haven or DaVinci `B01_soil` / `B02_tilled` at 0.7. See `ASSET_PICKS.md` CAM_02. Roughness 0.9, specular 0.3, no subsurface. Wet soil after rain or watering: albedo × 0.7 and roughness 0.45.
  - Tilled rows are geometry or a vertex-displaced ridge (height 4–6 cm, period 0.3 m), **not** the flagged VP02 texture.
- **Texture scale.** 1 repeat per 1.0 m, so each crumb reads at about 2–3 cm.
- **Shape.** Bed mound 8–12 cm above the lawn, lip bevel radius 6 cm, corners rounded (radius at least 15 cm). No square-cut boxes. No thin plank frames.
- **Rim.** 0.04, tinted `#e2c77b`. **Outline:** none.

### 3.3 Ground: lawn and paths (A01, A11)

**Look.** The lawn is a soft, dense, springy carpet with clumps and clover patches, not a flat colour or a checkerboard (VP04, VP05, target 02). Paths are warm, pillow-bevelled flagstones with mossy joints (A01, target 02), plus worn dirt spurs and gravel edges.

| Role | Hex | Source |
|---|---|---|
| Lawn base (albedo, halfway) | `#679428` | halfway(VP04, real.B05_lawn) |
| Lawn highlight (albedo, halfway) | `#82a834` | halfway |
| Lawn shadow (albedo, halfway) | `#447826` | halfway |
| Clover light (albedo) | `#9fd82d` | lawn.VP05_clover |
| Moss dark (albedo) | `#236b1b` | lawn.VP06_moss |
| Lawn far, golden (screen) | `#85894a` | lawn.far_T2 |
| Lawn sun patch (screen) | `#c8b961` | lawn.far_T2 |
| Lawn near (screen) | `#576423` | lawn.mid_T2 |
| Flagstone lit (screen) | `#e0bd87` | path.plaza_T2 |
| Flagstone base (albedo, halfway) | `#c9b79b` | halfway(VP08, real.B10_flagstone) |
| Flagstone joint (screen) | `#8e7f60` | path.plaza_T2 |
| Cobble pale (albedo) | `#f3daaf` | path.VP08_cobble |
| Mossy mortar (albedo, halfway) | `#737244` | halfway |
| Dirt path (albedo, halfway) | `#bb9260` | halfway(VP07, real.B02_tilled) |
| Gravel (albedo) | `#f2dab6` | path.VP10_gravel |

- **Lawn material.** Until VP03 is redone, the terrain shader uses Poly Haven `leafy_grass` (CC0, with normal) or `VP04_meadow_tile.png` graded to the halfway lawn hexes as the grass layer, with `VP05_clover_tile.png` blended in through a low-frequency noise mask (20–30% cover). Normal from DaVinci `B05_lawn` at 0.3. Roughness 0.85, specular 0.25. Subsurface: none on the terrain. A wrap-lighting term (0.3) stops the lawn going muddy on the shaded side.
  - Break up tiling with a second sample at 0.37× scale, rotated 37°, plus macro colour variation of ±6% value.
- **Lawn texture scale.** 1 repeat per 2.0 m, plus the macro layer at 1 per 5.4 m.
- **Paths.** Flagstones are geometry (each stone a pillow, bevel 3 cm, gaps 3–5 cm filled with moss `#737244`) on tier a. On tiers b and c they are a texture with baked AO. Albedo `VP08_cobble_tile.png` for cobble walks; `VP28_drystone` and `VP07_dirtpath` for spurs. Roughness 0.75, no subsurface.
  - Texture scale: flagstone 1.5 m, dirt 2.0 m, gravel 1.0 m.
- **Edges.** Where lawn meets path, use a feathered blend with grass clumps overhanging the edge. Never a hard straight polygon line.
- **Rim.** 0.04. **Outline:** none.

### 3.4 Foliage: grass, flowers, shrubs, trees (A04, A18, A20)

**Look.** Lush, rounded, layered planting like A20 and target 01. Oversized blooms in coral, mauve, sunflower yellow and periwinkle over calm mid-greens. Hedges are deep, lumpy walls with a warm lit crest.

| Role | Hex | Source |
|---|---|---|
| Hedge base (albedo, halfway) | `#3d7725` | halfway(VP24, real.B29_boxwood) |
| Hedge shadow (albedo) | `#1a811e` | hedge.VP24 |
| Leaf-tip highlight (albedo, halfway) | `#80b64a` | halfway |
| Hedge core (albedo, halfway) | `#194110` | halfway |
| Hedge sunlit top (screen) | `#9e9521` | hedge.lit_T1 |
| Hedge mid face (screen) | `#535e13` | hedge.front_T1 |
| Hedge shade face (screen) | `#34470d` | hedge.front_T1 |
| Rose coral | `#e48d63` | flower.A20_rose |
| Petal peach | `#f5be9e` | flower.A20_rose |
| Poppy orange-red | `#c84b1d` | flower.A20_rose |
| Tulip red | `#b11a19` | flower.D02_tulip |
| Foxglove mauve | `#9b5a7c` | flower.A20_foxglove |
| Foxglove pink | `#dba3ab` | flower.A20_foxglove |
| Sunflower yellow | `#e6c643` | flower.D01_sunflower |
| Sunflower amber | `#b57a07` | flower.D01_sunflower |
| Periwinkle | `#6a7cce` | flower.VP23 |
| Marigold | `#e48c24` | flower.VP23 |
| Daisy cream | `#e1deb9` | flower.VP23 |
| Clover pink | `#e5a5bc` | lawn.VP05_clover |
| Stem / leaf | `#677c45` | flower.D01_sunflower |
| Leaf (screen) | `#666a31` | leaf.A20 |
| Canopy lit / mid / core | `#80863e` / `#595c24` / `#363211` | tree.D03_apple |
| Apple red | `#a52b21` | tree.D03_apple |
| Bark base (halfway) / ridge / crevice | `#89613b` / `#bf9159` / `#492813` | halfway(VP16, real.B17_oakbark) / tree.VP16_bark |

- **Grass (the fix for the spike cones).** Grass is **clumps**: 3–7 curved, rounded-tip blade cards per clump. Each blade is at least 1/5 as wide as it is tall and bends 20–40°. Blades are coloured with a gradient from `#447826` at the root to `#82a834` at the tip (halfway).
  - Place clumps with MultiMesh, denser at bed and path edges.
  - Wind: a 2–4 cm sway in the vertex shader, phase-offset by world position.
  - Alpha-scissor cards on tier a use alpha-to-coverage with MSAA. Tiers b and c use opaque bent-quad blades (no alpha).
  - Roughness 0.7. Subsurface or backlight transmission 0.3 on tier a (`backlight = #82a834 × 0.3`); wrap lighting on b and c. **No cones, no prisms, no single-triangle spikes.**
- **Flowers.** Head diameter at least 1/3 of stem height. 5–8 rounded, slightly cupped petals. Petal roughness 0.55, subsurface 0.4 on tier a (backlit petals glow, as in A20). Petal albedo from the flower hexes. Stems `#677c45`. Mix 2–3 flower hexes per bed: one accent (coral, red or yellow) and one cooler partner (mauve or periwinkle).
- **Shrubs and hedges.** Build from lumpy pillow volumes with a leaf-card shell or a leaf-normal-mapped surface. Albedo `VP24_hedge_tile.png` graded to the halfway hedge hexes (or DaVinci `B29_boxwood` albedo lifted toward them), normal from `B29_boxwood` at 0.7, texture scale 1 per 1.2 m. Roughness 0.8. Subsurface or backlight 0.25 so the crest glows in low sun. The crest is rounded and uneven, **never a box with a flat top**.
  - Hedge height 1.4–1.8 m for the room walls; low inner hedges 0.6 m.
- **Trees.** Lollipop or cloud canopies of 3–7 overlapping blobs, as in D03 and the target backdrop. Chunky trunk tapering 1 : 0.6. Bark `VP16_oakbark_tile.png` at 1 per 1.0 m (vertical), roughness 0.9. Canopy albedo from `#80863e` / `#595c24` / `#363211`, or leaf cards tinted with the hedge albedos.
  - Backdrop trees beyond the hedge are simpler impostors or low-poly blobs, softened by fog.
- **Rim.** 0.08 on foliage, tinted `#cee5fd` (sky), strongest on hedge crests. **Outline:** none.

### 3.5 Market stall (Petal Stall)

**Look (A05, A13).** A small, sturdy, hand-built timber stall with a striped awning (cream `#baac74` and rust `#c06427` from A05, or v1 cream and slate), a thick worn counter, seed crates and sacks, a lantern and a painted sign (target 02, A05, D09). It feels cosy and toy-like: fat posts, rounded roof edges, a slightly wonky, hand-made charm.

| Role | Hex | Source |
|---|---|---|
| Timber base (halfway) | `#9f7f63` | halfway(stall.D09_crate, real.B19_planks) |
| Timber shadow (halfway) | `#6c543e` | halfway(D09, real.B19_planks) |
| Planed edge / highlight | `#d5bc9a` | stall.D09_crate |
| Worn counter top | `#b68d73` | stall.wood_A05 |
| Awning cream | `#f5dbb4` | awning, target 02 (median cut) |
| Awning stripe slate | `#6d645a` | awning, target 02 (median cut) |
| Sign board | `#e2af64` | sign, target 02 (median cut) |
| Lantern glow | `#f8c04b` | stall.lantern_A05 |
| Lantern amber | `#e28d17` | stall.lantern_A05 |
| Terracotta pot or roof (halfway) | `#d17e58` | halfway(VP20, real.B22_terracotta) |
| Thatch or straw (halfway) | `#c28c36` | halfway(VP19, real.B21_thatch) |

- **Timber material.** Albedo tinted from the timber hexes. Normal and roughness from DaVinci `B19_planks` (tiled) at 0.4. **Do not use VP18 planks** (flagged: baby-blue paint). Roughness 0.7, counter top 0.5 (worn smooth). Texture scale 1 per 1.0 m along the grain.
- **Awning material.** Fabric, roughness 0.9, subsurface or backlight 0.3 so sun glows through the cream stripes. Stripes are 18–22 cm wide. The scalloped front edge is rounded, not zig-zag. Replace the current flat sky-blue and white slabs with cream `#f5dbb4` and slate `#6d645a`.
  - If PETAL_05 wants a candy accent, use terracotta `#f0845b` instead of slate. Never pure white.
- **Lantern.** Emission `#f8c04b` at energy 1.5 when the stall is open (glow picks it up), `#e28d17` for the frame's warm tint. Glass stays under 250 in every channel on screen (this matches the clamp rule in `docs/VISUAL_GAP.md`).
- **Props.** Seed crates (D09), burlap sacks (`#906c47` body, `#cca473` lit fold, sampled from target 02), terracotta pots, a watering can. All bevelled and chunky. **No box bench.** Seating is a rounded log or a plank bench with thick, bevelled legs and a seat radius of at least 3 cm.
- **Shape.** Posts 12–15 cm thick. Roof edge rolled. The sign is a thick rounded board with painted lettering (a texture, not a floating Label3D).
- **Rim.** 0.06, tinted `#e2c77b`. **Outline:** none.

- **Palette additions from A05/A13 (screen):** shop wood `#653d15`, warm wood `#8c4c1e`, planed `#c38d57`, lamp `#ec9a35`, rust awning `#c06427`, awning cream `#baac74`, seed-packet blue `#2f638c`.

### 3.6 Jelly creatures = Grok bots (D6)

**Look.** The jellies are the **Grok bot icons come to life**: one of the eight Grok icon silhouettes, extruded into a soft, thick gummy body, with the two **diagonal slash eyes**, candy translucency (light passes through the thin parts, the core glows), and a soft wobble. They are *not* animals or pear-shaped blobs (today's `scripts/presentation/jelly_actor.gd` pear forms and matte `shaders/jelly.gdshader`, ROUGHNESS 0.94, are what we are replacing).

**Canonical sources (the original bots, reference for shape, face and behaviour):**
- Icon sheet: `/workspace/havenbrook-art/refs/grok-avatar-anim/grokbot-shapes-palette.png` (8 white shapes with slash eyes, 11 swatches), plus `bloub-states.png`, `bloub-demo.gif` in the same folder (copies in `/workspace/refs`, `/workspace/soft-grok-bot-seed/public`, `/workspace/garden-grove-pack/soft-grok`).
- Altar-v1 (private, unmerged branches):
  - `cursor/grok-bot-jelly-cast-69cf` (PR #3): `jelly-baby/src/graphics/grok-shapes.ts` — the 8 shapes **circle, oblong, square, pill, triangle, hexagon, cloud, teardrop**, `GROK_PALETTE`, `GROK_HEIGHT = .04`; `grok-slime.ts`, `cast-table.ts`.
  - `cursor/grok-icon-jelly-cloud-cdfb` (PR #7): `jelly-baby/docs/living-grok.md` (cloud-icon softbody, slash eyes, **MorphCycle idle → thinking → working → waiting → blocked → done**), `src/graphics/icon-face-layout.ts`, `face-expression.ts`, `jelly-flavors.ts`, `refractive-light.js`, `src/game/morph-cycle.ts`, `morph-muscles.ts`.
  - `cursor/grok-jelly-icons-3d-92b6`: `jelly-flavors.ts` with the 11 Grok picker colours and Beer–Lambert absorption.
- Box Godot port: `/workspace/petalwild-fold/merged/addons/gg_groks/` (`jelly_grok.gd`, `grok_ball/blob/cube/pill/pyramid/hex/cloud/teardrop.gd`, `body_builder.gd`, `candy_catalog.gd`); web seed `/workspace/soft-grok-bot-seed/src/SoftGrokBot.ts`.
- **Licence warning:** the Altar-v1 jelly code sits in a `jelly-baby/` tree derived from `scottstts/Jelly-Baby` (GPL-3.0). Use it as **behaviour and look reference only**; do not copy source, meshes, cages or EXRs into PetalWild. The Higgsfield gummies in `art_library/staging/jelly/reference_only/` look like Jelly-Baby and are reference only.

**Grok palette (sampled from the icon sheet).** Body = translucent surface albedo; core = body darkened ~45% in Lab for thick parts (Beer–Lambert).

| Flavour | Body | Notes |
|---|---|---|
| White | `#f5f1ea` | capped (no pure white) |
| Teal (**default**) | `#00a592` | Hailo note / icon sheet |
| Blue | `#0e74e0` | |
| Purple | `#804ee0` | |
| Magenta | `#e02a88` | |
| Red | `#e02135` | |
| Orange | `#ff6700` | |
| Gold | `#ff9800` | |
| Green | `#009957` | |
| Brown | `#855c36` | |
| Grey | `#777777` | allowed on jellies only (exempt from the forbid list via group `jelly`) |
| Eye ink (slashes) | `#1b1b1f` | |

**Shape rules.**
- Base silhouette = one of the 8 icon shapes, as a rounded extrusion: depth 0.55–0.7 × width, edge radius ≥ 25% of depth, the bottom slightly flattened and widened so it sits heavily. Height 0.35–0.45 m.
- **Face:** two diagonal slash eyes (capsule grooves or decals in `#1b1b1f`), placed per `icon-face-layout.ts` proportions; no mouth by default. Expressions are the eye tilt/scale changes from `face-expression.ts`.
- **Motion:** softbody wobble (tier a: vertex shader or spring-mass; tier c: sine squash-stretch ≤ 6%). MorphCycle states map to garden AI: idle (sat, slow breathe), thinking (lean, eye squint), working (bouncy hop), waiting (sway), blocked (flatten), done (happy bounce).
- ≥ 64 segments around on tier a, 24 on phone. No visible facets.

**Material (tier a).** `ROUGHNESS 0.18`, `SPECULAR 0.5`, `CLEARCOAT 0.7` / `0.12`, `SSS_STRENGTH 0.7` with transmittance = core, depth 0.3, `BACKLIGHT = body × 0.6`, fresnel rim in body colour 0.25, thickness mix body→core, optional sugar-frost noise 0.04. Opaque (no alpha sorting). Night state: core emission 0.3 in body colour.
**Tiers b and c.** Wrap diffuse, `max(0, dot(-L,V))^3 × body` backlight, rim, baked vertex-colour thickness; one Blinn highlight at roughness 0.25.

### 3.7 Veg folk = Pixar/Ghibli surreal fruit and veg people (D7)

**Look.** Surreal, appealing fruit-and-veg people: the whole body *is* the vegetable (real skin: waxy tomato, ridged carrot, veined cabbage leaves, papery onion), with a Pixar-readable face (large expressive eyes, small mouth) and Ghibli softness (gentle, a little odd, never grotesque). Halfway rule: skin is real (A12 surface), proportions are toy (big head-body, nub limbs).

**References.**
- Closest to the target: the Higgsfield vegfolk sprites in `/workspace/art_library/staging/veg_folk/` (onion `37d9fbac`, pea `4c4ec52b`, carrot `52682b82`, tomato `64eb0574`, cabbage `ab9e6641`; own Higgsfield plan, look reference).
- Existing models: PetalWild `art/characters` branch (PR #1): `art/characters/carrot.blend`, `tomato.blend`, `leek.blend`, `build_carrot.py`, `previews/carrot_front.png`, `carrot_threequarter.png`, `tomato_threequarter.png`, `godot_folk.png`. `petal/08-integration`: `assets/characters/carrot.glb`, `tomato.glb`, `leek.glb`, `scripts/people/veg_person.gd`, `game/residents/veg_body.gd`, `shaders/veg_skin.gdshader`, `docs/screenshots/04_veg_person.png`.
- Seed cast shapes: `/workspace/petalwild-veg-seed/previews/` (lineup, leafy_lotte, pip_tomato, nubbin_carrot, berry_blink, pod_and_pea); `veg_people_factory.gd`.
- Surface: A12 (vegetable allotment), A17 (beehive, warm rustic).

| Character | Base | Highlight | Shadow | Source |
|---|---|---|---|---|
| Lettuce / cabbage | `#48a758` | `#6ed278` | `#377e42` | veg.lotte |
| Tomato | `#d23732` | `#f0786e` | `#8a2220` | veg.tomato |
| Carrot | `#e67828` | | `#974716` | veg.carrot |
| Carrot, real (A12) | `#743d1d` | | | concept.A12.accent |
| Strawberry | `#dc2e46` | seed `#fbca73` | | veg.berry |
| Pea pod | `#59ac44` | `#8bd15a` | | veg.pea |
| Leaf tops (all) | `#43a443` | | | veg.carrot |
| Real-lettuce light | `#acca64` | | | veg.A12_lettuce |

Halfway rule: pull each base 30–50% in Lab toward its A12 real sample when grading.

- **Materials.** Tomato roughness 0.30, clearcoat 0.5, SSS 0.4; strawberry 0.40 with seed bumps; carrot 0.65 with ring grooves, SSS 0.2; lettuce/cabbage 0.50, veins, SSS 0.5; pea 0.45 satin; onion 0.35 with papery outer layer (roughness 0.8). `shaders/veg_skin.gdshader` stays the base.
- **Face.** Eyes are glossy, slightly oversized (Pixar), set wide; brows optional as leaf or skin folds; mouth small and soft. No human teeth, no hair other than leaves.
- **Shape.** Body 1 : 1.1–1.4, nub hands and feet, clothing optional (thick felt apron, `R37_felt`). 0.9–1.1 m tall.
- **Outline:** none. Name labels follow shot 8's rule.

### 3.8 Garden creatures (look reference)

On-vibe DaVinci creatures (`/workspace/petalwild-davinci/creatures/`): **C02_bumblefluff** (bee), **C03_mossnib (the hedgehog)**, **C09_pondlark (the duck)**, **C10_brambleboar** (crop the baked wooden base). What they share: needle-felt realism at toy scale (halfway), a plant or garden motif, chunky rounded forms.

Off-vibe, and why: C01 generic plush dog; C04 plain bunny ears, not tulip petals; C05 snail-bunny hybrid; C06 costume-gag humanoid frog; C07 generic worm; C08 realistic, spiky moth; C11 thin insect legs and wings; C12 realistic claws and baked base; C13 no garden identity; C14 realistic spiky crest; C15 off-theme elephant-pig; C16 thin, spiky mantis on a baked rock; C17 fine but generic sheep; C18 a fox, not a garden creature; C19 muddy blobs in a baked nest; C20 decorated eggs, not a creature. **Common faults to avoid:** thin or spiky limbs, baked bases, real-animal realism without a plant motif.

---

## 4. Quality tiers

The repo's `project.godot` currently says `forward_plus`, but `docs/ENGINE_VERSION.md` records that the build VM has no GPU and renders through Compatibility on llvmpipe with shadows off. **Captures from that VM are tier (b) captures. Tier (a) sign-off must be captured on a real GPU**, such as Scott's PC.

| | **(a) 4K high-end PC** | **(b) Browser build** | **(c) Phone** |
|---|---|---|---|
| Renderer | Forward+ | **Compatibility** (the only option for web export) | Mobile (native Android/iOS). Compatibility on older devices |
| Output | 3840×2160, native, 60 fps (RTX 3070 class) | 1600×900 canvas, 3D scale 1.0 (0.8 on HiDPI), 60 fps on an integrated-GPU laptop | 2532×1170-class screen, 3D render scale 0.7 with FSR1, 30 fps locked (60 on flagships) |
| Anti-aliasing | MSAA 3D 4× plus alpha-to-coverage on foliage. TAA off (it ghosts on wobbling jellies) | MSAA 3D 2× plus FXAA | MSAA 2× (cheap on tile GPUs). FXAA off |
| Global illumination | **SDFGI**: 4 cascades, `min_cell_size 0.15`, occlusion on, `bounce_feedback 0.4` | **LightmapGI** baked at 16:30 (indirect plus AO; sun `bake_mode = Dynamic`, so direct sun stays real-time). Texel scale 1.0 | LightmapGI as for b, texel scale 0.5 |
| Screen-space effects | SSAO + SSIL on. SSR only if the pond is in shot (otherwise a ReflectionProbe) | SSAO off (recent docs list it for Compatibility; test on 4.8-dev6 before enabling). No SSIL or SSR | None (Mobile has no SSAO, SSIL or SSR) |
| Fog | Depth fog plus volumetric fog (god rays) | Depth fog only. God rays faked with 3–5 additive gradient cards | Depth fog only. No ray cards |
| Shadows | Directional 8192, 4 splits, 60 m, `soft_shadow_filter_quality High`, `angular_distance 1.5` | 2048, 2 splits, 30 m, Soft Low | 2048, 1–2 splits, 20 m, Soft Very Low. Compatibility-phone uses blob decals under characters |
| Glow | Full (levels 3–5) | On. Compatibility glow hides levels, strength and mix, so set intensity 0.4 | On, low (intensity 0.3) |
| Depth of field | Tilt-shift on hero and close-up cams | Off, or far blur low-quality if it works on Compatibility | Off |
| Tonemap and grade | ACES, exposure 0.95, contrast 1.05, saturation 1.12 | Same numbers | Same numbers. Saturation 1.15 to make up for small-screen washout |
| Subsurface | Real SSS on Grok jellies, veg, petals, leaves | None; wrap lighting plus backlight term plus rim (section 3.6) | Same as b |
| Texture sizes | 2048² ground, hedge and stall sets; 1024² props and characters; BPTC/BC7; anisotropy 16× | 1024² ground and hedge; 512² props and characters; S3TC/BPTC plus ETC2/ASTC (both imported, already enabled in the project) | 512² (1024² for ground only); ASTC 6×6; anisotropy 4× |
| Texel density | 512 px/m ground, 1024 px/m hero | 256 / 512 | 128 / 256 |
| Triangles on screen | ≤ 3 M | ≤ 400 k | ≤ 200 k |
| Draw calls | ≤ 3000 | ≤ 400 | ≤ 150 |
| Per-asset triangles | Jelly 20–40 k (smooth wobble), veg folk 15–25 k, stall 40 k, tree 30 k plus cards | Jelly 6–8 k, veg 5 k, stall 10 k, tree 6 k | Jelly 4–6 k, veg 3 k, stall 5 k, tree 3 k (impostors past 20 m) |
| Grass instances in view | 150–300 k clumps with LOD | 30–60 k | 10–20 k, distance fade at 15 m |
| Download (textures) | n/a | ≤ 60 MB | ≤ 120 MB on-device |

**What the web and phone builds lose, and how to fake it**

- **Bounce light and contact shadow.** SDFGI, SSIL and SSAO are gone. Fake them with:
  - LightmapGI baked from a Forward+ editor (baking needs RenderingDevice; Compatibility can only *render* lightmaps)
  - **vertex AO** baked into `COLOR.r` on every prop and character (multiplied into albedo in the shader), with dark tucks under benches, stall, beds and creatures
  - a soft blob decal under each moving creature
- **Soft golden haze and god rays.** Volumetric fog is gone. Fake it with depth fog tinted `#c9dee7`, additive gradient cards in the tree gaps, and a gentle warm full-screen vignette (a full-screen quad, which Compatibility supports).
- **Sky.** Use the same `ProceduralSkyMaterial` hexes (it works on all renderers) with `radiance_size 32`. On Compatibility-phone, use a 2-stop gradient sky shader (`#c1defb` → `#eef3fe`).
- **Translucent jellies and glowing petals.** No SSS. Fake it with wrap, backlight and rim (section 3.6). Keep the same hexes so the sign-off still passes.
- **Grass density.** Fewer clumps, but each one wider and fuller, so the lawn still reads as soft carpet. The lawn texture carries the rest. Never swap the lost density for cones.
- **Readability rim boost (phone only).** Character rim strength ×1.5 and a slight saturation lift. This replaces any temptation to add ink outlines.

- **Weather on web/phone.** Rain particles ≤ 800, frost via the `frost` uniform only (no extra textures), night lanterns capped at 4 OmniLights (others are emissive cards).

## 5. Reference table

✅ reference. ⚠️ partial. ⛔ flagged, don't use as-is. The board (`visual_target_board.jpg`) shows A01–A20 in order.

### The A-series (D1: the look)

| Status | Absolute path | Reference for |
|---|---|---|
| ✅ | `/workspace/petalwild-davinci/concept/A01_circular_stone_plaza.png` | Plaza, flagstones, low sun; CAM_03 |
| ✅ | `/workspace/petalwild-davinci/concept/A02_aerial_three_quarter.png` | **Primary garden overview**: beds, crumb soil, fence, pond; CAM_01, 02, 08 |
| ✅ | `/workspace/petalwild-davinci/concept/A03_a_pond_at_dawn.png` | Dawn state, pond |
| ✅ | `/workspace/petalwild-davinci/concept/A04_wildflower_meadow.png` | Foliage density, backlit petals; CAM_04 |
| ✅ | `/workspace/petalwild-davinci/concept/A05_cosy_seed_shop.png` | Market stall materials and lantern; CAM_05 |
| ✅ | `/workspace/petalwild-davinci/concept/A06_night_garden.png` | Night state |
| ✅ | `/workspace/petalwild-davinci/concept/A07_rainy_afternoon.png` | Rain / overcast state, wet materials |
| ✅ | `/workspace/petalwild-davinci/concept/A08_autumn_garden.png` | Autumn tint |
| ✅ | `/workspace/petalwild-davinci/concept/A09_winter_frost.png` | Frost / snow state |
| ✅ | `/workspace/petalwild-davinci/concept/A10_a_creature_home.png` | Creature close-up framing; CAM_06 |
| ✅ | `/workspace/petalwild-davinci/concept/A11_creature_courtship.png` | Creature life on lawn; CAM_03, 06 |
| ✅ | `/workspace/petalwild-davinci/concept/A12_vegetable_allotment.png` | Soil rows, veg skin realism; CAM_02, 07 |
| ✅ | `/workspace/petalwild-davinci/concept/A13_greenhouse_interior.png` | Stall/greenhouse timber and glass; CAM_05 |
| ✅ | `/workspace/petalwild-davinci/concept/A14_garden_seen_from.png` | Garden-ring overview framing; CAM_01 |
| ✅ | `/workspace/petalwild-davinci/concept/A15_cityscape_at_golden.png` | Tilt-shift DOF; world/builder view; dusk |
| ⚠️ | `/workspace/petalwild-davinci/concept/A16_rocky_desert.png` | Rock forms only (for the rock request); biome is off-theme |
| ✅ | `/workspace/petalwild-davinci/concept/A17_beehive_and.png` | Rustic props, warm palette; CAM_07 |
| ✅ | `/workspace/petalwild-davinci/concept/A18_tree_canopy.png` | Tree canopy, dappled light; CAM_04; Viva Minera low view |
| ⚠️ | `/workspace/petalwild-davinci/concept/A19_muddy_bog.png` | Mud and wet soil only |
| ✅ | `/workspace/petalwild-davinci/concept/A20_hero_key_art.png` | **Saturation ceiling**, flower palette; CAM_01, 04, 08 |
| ⚠️ | `/workspace/petalwild-artdesk/visual_target/refs/petalwild_target_garden_01.png`, `_02.png` | Composition only (hedge room, stall placement). No longer the colour target |

### Textures, props, characters

| Status | Absolute path | Reference for |
|---|---|---|
| ✅ | `/workspace/art_library/staging/<subject>/` + `ASSET_PICKS.md` | **The concrete files to use per camera** (licences listed there) |
| ✅ | `/workspace/petalwild-davinci/textures/tiled/` (B01, B02, B05, B10, B19, B29, B31, B34 …) | Normal/roughness detail at 0.6–0.8 and the "real" end of the halfway rule. Avoid the ghosting brick, cobble (B09), picket and terracotta tiles for detail |
| ✅ | `/workspace/petalwild-vp-textures/tiled/` (VP01, VP04–VP08, VP10, VP24–VP28) | The "toy" end of the halfway rule; albedo only after grading to halfway hexes |
| ✅ | `/workspace/petalwild-davinci/props/` D01–D16 | Prop forms (sunflower, tulips, foxglove, apple tree, toadstool, shed, crate, lantern, signpost) |
| ✅ | `/workspace/havenbrook-art/refs/grok-avatar-anim/grokbot-shapes-palette.png` | **Grok jelly shapes, slash eyes, palette** |
| ✅ | `/workspace/petalwild-davinci/textures/R38_candy.png`, `R37_felt.png` | Candy gloss; felt |
| ✅ | `/workspace/art_library/staging/veg_folk/` (Higgsfield vegfolk sprites) and `/workspace/petalwild-veg-seed/previews/` | Veg folk look and shapes |
| ✅ | `/workspace/petalwild-davinci/creatures/C02_bumblefluff.png`, `C03_mossnib.png` (hedgehog), `C09_pondlark.png` (duck), `C10_brambleboar.png` (crop base) | On-vibe garden creatures |
| ⛔ | `/workspace/petalwild-davinci/creatures/C01`, `C04`–`C08`, `C11`–`C20` | Off-vibe (section 3.8) |
| ⛔ | `/workspace/art_library/staging/jelly/reference_only/*`, `/workspace/Jelly-Baby-clone/**` | GPL-3.0 Jelly-Baby or look-alikes: reference only, never ship |

### Flagged for redo (⛔ don't use as-is)

| Status | Absolute path | Problem |
|---|---|---|
| ⛔ | `/workspace/petalwild-vp-textures/VP03_lawn.png` (and `tiled/VP03_lawn_tile.png`) | Reads as pebbles or leaf scales, not grass, and too neon (`#44b711`). Use VP04 until it is redone |
| ⛔ | `/workspace/petalwild-vp-textures/VP02_tilled.png` (and tile) | Obvious horizontal repeat band. Build tilled rows as geometry instead |
| ⛔ | `/workspace/petalwild-vp-textures/VP09_flagstone.png` (and tile) | Blue-grey and orange stones clash with the warm plaza (`#818b90` against `#dfaa6a`). Use VP08 or VP28 until it is redone |
| ⛔ | `/workspace/petalwild-vp-textures/VP18_planks.png` (and tile) | Baby-blue painted planks (`#8dc2dc`) that don't match the stall timber |
| ⛔ | `/workspace/petalwild-vp-textures/VP30_crepe.png` (and tile) | Crepe fringe artefacts. Also fights the jelly look |
| ⛔ | DaVinci `B32`, `B36`, `B37`, `B38`, `B39` | Superseded by the `R32`–`R39` rerolls (per `PLAN.md`) |
| ⛔ | `/workspace/garden-grove-pack/tiles/*.png`, repo `docs/reference/havenbrook_*` | Havenbrook branding. Different game |
| ⛔ | `/workspace/petalwild-artdesk/visual_target/refs/current_build_*.png`, `/workspace/petalwild-davinci/creatures/C01_puddlepup.png` as jelly form (v1) | The current look, kept only to calibrate the checker. **This is what we are fixing** |
| ⛔ | `/workspace/art_library/staging/stall/higgsfield_*` stall scenes | Havenbrook branding painted in; look reference only |
| ⛔ | Kenney nature-kit `rock_*` / `stone_*` GLBs as garden rocks | Faceted "ice-cube" look; replaced via ART-DIRECTOR-006 |

---

## 6. Cameras

### Camera layers (D5)

| Layer | What the player does | Prototype to build from | Sign-off cams |
|---|---|---|---|
| **1. Garden ring** (default) | Orbit a ring around the plot (Viva Piñata), zoom, pan within the hedge room | PetalWild `scripts/camera/garden_camera.gd` (orbit yaw/pitch/distance, intro fly-in, RMB orbit, wheel zoom, WASD pan) and `scripts/presentation/camera_rig.gd` (`title_pose` ring orbit, `play_pose`, `focus_on`) on `main` / `petal/08-integration`; box: `/workspace/petalwild-fold/merged/scripts/00_merge/orbit_camera.gd`, `addons/gg_face/orbit_camera.gd` | CAM_01, CAM_02, CAM_04, CAM_08 |
| **2. Drop into a character** | Click a jelly or veg person: camera swoops to an over-the-shoulder follow at 0.8–2.5 m | `camera_rig.gd` `focus_on`; `/workspace/petalwild-builder-scaffold/scripts/camera_rig.gd` (`enter_character_view`) | CAM_06, CAM_07 |
| **3. Viva Minera low view** | Ground-level, creature's-eye camera 0.3–1.2 m high, looking along lawn and paths | New; derived from layer 2 with pitch near 0° and FOV 55 | CAM_03 |
| **4. World / builder view** | High, tilt-shift overview for building and the wider world (streets, stall row) | `/workspace/petalwild-builder-scaffold/scripts/camera_rig.gd` (`enter_builder_view`, B toggles; `WORLD_BUILDER.md`); layout grid `/workspace/petalwild-fold/merged/addons/gg_terrain/scripts/garden_layout.gd` | CAM_05 (street/stall framing) |
| **5. Free cam** | Photo mode: unconstrained fly, DOF controls, hides HUD | None yet (dev free-fly only) | not signed off |

No dedicated "soil tiles + orbiting camera ring" Viva Piñata prototype exists on GitHub; the orbit rigs above are the closest. The GG-10 camera-polish and GG input/camera agents pushed to a Cursor-managed scratch repo, not GitHub (see `IMAGE_SPRAWL.md` / consolidation index). The web variant is `/workspace/garden-grove-playable/src/main.ts` (drag to orbit).

### Sign-off set

**Coordinates** as v1: garden-relative metres, origin `ANCHOR_BEDS`, +X east, −Z north. Anchors `ANCHOR_BEDS`, `ANCHOR_STALL`, `ANCHOR_HEDGE_W`; character shots use the first node in group `jelly` / `resident`. 1920×1080 except shot 8. **Test state: clear, 16:30, live sync off, 1×.**

| # | Camera | Layer | Position → target | Godot | Must show | A refs | `must_hit` (screen, ΔE 14) | min |
|---|---|---|---|---|---|---|---|---|
| 1 | `CAM_01_HERO_OVERVIEW` | Ring | BEDS+(7,9,11) → BEDS+(0,0,−2) | `rot (−31.4, 28.3, 0)`, FOV 42, far DOF | Whole hedge room, all beds, path, stall in back third, sky ≤ 15% | A02, A20, A14 | `#644728` `#67651f` `#997431` `#29280b` `#cd9441` `#e8d5b9` `#ab9574` | 4/7 |
| 2 | `CAM_02_BEDS_SOIL` | Ring (zoomed) | BEDS+(0,3.2,3.6) → BEDS+(0,0,0.2) | `rot (−43.3,0,0)`, FOV 45 | Tilled, planted and empty cells; crumb soil, bed edging, grass clumps | A12, A02 | `#644728` `#4c6f21` `#e8d5b9` `#6c6a42` `#ab9574` `#261c0d` `#9d6837` | 5/7 |
| 3 | `CAM_03_LAWN_PATH` | Viva Minera | BEDS+(0.4,1.1,7) → BEDS+(0,0.2,1) | `rot (−8.5,3.8,0)`, FOV 55 | Lawn clumps and clover (no cones), path stones, soft edge, far fog | A01, A11 | `#69601d` `#9c872c` `#1d250d` `#585838` `#948860` `#aa3e36` `#d4bea1` | 4/7 |
| 4 | `CAM_04_FOLIAGE_EDGE` | Ring | HEDGE_W+(4.5,1.8,2.5) → HEDGE_W+(0,1,0) | `rot (−8.8,60.9,0)`, FOV 45 | Leafy hedge with lit crest, a tree, flower border, backlit petals | A04, A18, A20 | `#61661a` `#8f8927` `#192407` `#574f26` `#bd9c5c` `#782d22` `#c8af42` | 4/7 |
| 5 | `CAM_05_MARKET_STALL` | Builder/street | STALL+(0.8,1.7,4.2) → STALL+(0,1.1,0) | `rot (−8.0,10.8,0)`, FOV 40 | Striped awning, timber, counter with crates and packets, lantern, painted sign, no box bench | A05, A13 | `#653d15` `#a16639` `#292e13` `#706924` `#2f638c` `#baac74` `#c06427` | 4/7 |
| 6 | `CAM_06_JELLY_HERO` | Drop-in | jelly+(0.7,0.45,1.2) → +(0,0.25,0) | `rot (−8.2,30.3,0)`, FOV 35, far DOF | One **Grok-shaped** jelly, ⅓ frame height: slash eyes, gloss, translucent edge, glowing core, contact shadow | A10, A11 | `#60571a` `#818125` `#28240d` `#b09b5a` `#aa3e36` `#d4c343` | 4/6 |
| 7 | `CAM_07_VEG_FOLK` | Drop-in | resident+(0.5,1.1,2.2) → +(0,0.75,0) | `rot (−8.8,12.8,0)`, FOV 38 | One veg person full body, real skin, Pixar face, label clear | A12, A17 | `#6b5a25` `#4c6f21` `#3d311e` `#743d1d` `#9d6837` `#b6b04e` | 4/6 |
| 8 | `CAM_08_PHONE_PLAY` | Ring (default) | Default gameplay camera, **HUD on**, incl. speed buttons | 1266×585 | Every label readable, no overlaps, jellies and beds recognisable | A02, A20 | `#644728` `#67651f` `#978b2c` `#29280b` `#e8d5b9` | 3/5 |

The jelly and veg `must_hit` lists deliberately cover the **surroundings** (lawn, soil, warm light) sampled from the A scenes, because the A-series has no Grok jelly; the jelly itself is judged by criteria 9–11 below.

**Calibration** (`calibration_v2.json`): every mapped A scene passes its own camera's list (hits 5–7 of 6–7). All four current-build screenshots fail every list (0–4 hits; best is 4/7 on CAM_02 against a minimum of 5).

**Pass/fail criteria.** As v1 criteria 1–4 and 6 (no checker/flat ground ≤ 0.20 flat score, no placeholder primitives, no cone grass, no overlapping labels, forbidden colours ≤ 4%), plus:

5. **Palette.** Per-camera lists above (`signoff_spec.json`), a hex present when ≥ 1% of pixels are within ΔE 14.
7. **Exposure.** ≤ 0.5% clipped white, **≤ 1.5% crushed black** (v2, from A-scene measurements).
8. **Colour.** Mean Lab chroma ≥ 18 in the clear test state.
9. **Readable at phone size (human).** 640 px wide, subject named within 2 s.
10. **Art Director eyeball.** Side by side with the frame's mapped A scenes on the board, it must look like the same world, at the halfway point (section 1 test).
11. **Character checks (human).** CAM_06: silhouette is one of the 8 Grok shapes, two slash eyes, palette flavour from 3.6. CAM_07: whole body reads as a real vegetable with an appealing face.
12. **Test state recorded.** `scene_audit.json` must show `test_state = {weather: clear, hour: 16.5, live_sync: false, time_scale: 1}`.

**Automated capture.**
- `visual_target/signoff_capture.gd` (SceneTree script): loads the scene, then `_freeze_time` turns off `live_sync` on any `Clock`, `WeatherSync` or `PetalWorld` node, sets hour and weather, stops `running`, and writes `audit["test_state"]`. Then it captures each `CAM_*` (existing Camera3D or built from the table), hides the HUD except shot 8, and saves `CAM_*.png` plus `scene_audit.json`. Smoke-tested on Godot 4.8-dev6 (Compatibility, llvmpipe, Xvfb): prints `PETAL_SIGNOFF_CAPTURE_OK`.
- `visual_target/signoff_check.py <dir>` scores against `signoff_spec.json`, writes `signoff_report.json`, exits 1 on any failure.

```bash
DISPLAY=:1 godot --path . -s res://tools/signoff_capture.gd -- --scene=res://scenes/garden.tscn --out=/tmp/signoff --hour=16.5 --weather=clear
python3 /workspace/petalwild-artdesk/visual_target/signoff_check.py /tmp/signoff
python3 /workspace/petalwild-artdesk/visual_target/calibrate_v2.py   # re-derive must_hit lists if the A-set changes
```

---

## 7. Who does what (suggested next requests)

| Lane | Change |
|---|---|
| PETAL_00 | WorldEnvironment per tier with 3.1 numbers; `WeatherLook` resources per state; live weather/clock sync node with offline fallback; `ANCHOR_*` markers |
| PETAL_05 | Replace box hedges, bench, flat ground, cone grass and faceted rocks using `ASSET_PICKS.md` and the new art-desk requests; halfway albedos |
| PETAL_06 | Jelly shader to 3.6 (Grok candy); `wetness` and `frost` global uniforms; terrain shader with halfway lawn and Poly Haven normals; grass clumps |
| PETAL_03 | Grok jelly bodies: 8 icon shapes, slash eyes, MorphCycle states (clean-room, no GPL code) |
| PETAL_04 | Veg folk to 3.7 (Pixar/Ghibli); retopo carrot/tomato/leek to budgets |
| PETAL_07 / 10 | Camera layers 1–5; speed buttons pause/1×/2×/4× on the HUD; label de-overlap; default framing passes shot 8 |
| Art desk | File `requests_outbox/ART-DIRECTOR-*.yaml`; redo VP02, VP03, VP09, VP18, VP30 once Scott OKs the quota |

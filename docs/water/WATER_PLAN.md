# PetalWild water plan

Research only. No gameplay or shader implementation in this change. Target: Godot **4.8-dev6 Forward+**, Windows PC.

**Primary look:** Viva Piñata (Rare, Xbox 360, 2006) and *Trouble in Paradise* (2008) garden ponds. A **high-realism, sparkly water surface** over a **cartoony, painterly, high-quality bed**. That contrast is the effect. The approved city-park pond concept is our instance of the same split.

**Supporting:** Road to Vostok for Godot-4 lake technique. Pen Pen TriIcelon for creature-in-water interaction.

Licence firewall is the same as `docs/research/REFERENCES.md` and `docs/LICENSE_MATRIX.md`. MIT / CC0 only in the tree. Do not vendor Road to Vostok, Viva Piñata, or TiP-Recomp (no-AI policy; not inspected). House style is already “Viva Piñata-style, painterly, saturated, chunky and toy-like” (`docs/AGENT_CONTRACTS.md`); this plan is how that applies to **water**.

Nested worlds share one water stack; each body gets a `WaterProfile`, not a unique shader.

## 1. The layered look (ship this first)

Two layers, two materials. Do not paint the bed inside the water shader.

```
sun / sky / jelly / willow     ← reflected and sparkled on the SURFACE
────────────────────────────────  WaterSurface  (realistic, sparkly, mostly clear)
  painterly sediment, stones,    ← readable THROUGH the water
  pads, toy-scale weeds
────────────────────────────────  PondBed       (stylised, saturated, hand-painted quality)
```

If the surface is cartoony, it is Wind Waker. If the bed is photogrammetry mud, it is a real pond. Piñata is **realistic top, toy bottom**. The realistic sheet makes the toy bed pop.

v1 success test (parish pond or city-park canal, close camera):

1. Surface **glints** in the sun (tight specular + bloomed sparkles).
2. Surface **reflects** sky and a nearby creature, at least as a readable highlight.
3. Looking down, the **bed is a painted picture**, not a dark teal void and not Poly Haven dirt.
4. Shore is **wet sediment**, not a white foam ring.
5. Water is **clear enough** that (3) is obvious. Murky beer-law absorption is the wrong default.

The live shader (`shaders/water.gdshader`) already has a cheap world-space sparkle and a bowled mesh. Keep the sparkle *idea*; replace the implementation. Flatten the surface to a rest plane. The basin stays in the terrain, with a new bed material.

| World | Water | v1 quality |
| --- | --- | --- |
| Hedge Hollow parish pond | ~3–6 m scooped still pond, Bulrush/Reedic wade | Full layered look |
| Grove Park / city-park canal | Hero look from the concept (bridge, pads, lamps, jelly reflection) | Full when that world is loaded |
| Petal Vale / distant | Set dressing | LOD: probe + colour, no sparkle RT, no ripple |

## 2. Reference games

### 2.1 Primary look — *Viva Piñata* (2006) and *Trouble in Paradise* (2008)

Rare, Xbox 360. Custom on-team engine, ~50 people, 30 fps in a busy garden. Ponds are **dug holes** in the tessellated “diggable surface,” filled with water, used to attract aquatic piñatas (Quackberry, Newtgat, Lickatoad, Dragumfly, Swanana, Chippopotamus, …). TiP made lakes faster to draw and, per players, **clearer and shinier** with nicer reflections ([GameFAQs thread](https://gamefaqs.gamespot.com/boards/946126-viva-pinata-trouble-in-paradise/45255605)).

#### What Rare actually documented

**Michael Boulton, SIGGRAPH 2007** — *Tessellation in Viva Piñata*, Advances in Real-Time Rendering ([PDF](https://advances.realtimerendering.com/s2007/Boulton-PinataTessellation(Siggraph07).pdf), [course index](https://advances.realtimerendering.com/s2007/index.html)):

- Cartoon look, expensive GPU: unified shadows, volumetric rendering, long draw distances, **microcode shaders**.
- Garden floor is a **16×16 tessellated lattice**. Vertex-shader memory export writes tessellation factors from screen-space edge length (~50 px). Off-screen quads drop to minimum. Pixel shaders were so heavy that extra triangles hurt.
- Attributes are **not interpolated** across tessellated verts (swimming artefacts). A separate **attribute texture** is fetched in vertex and pixel shaders (grass, contact occlusion, height).
- **Ponds, in so many words:** “To avoid artefacts around pond banks, filtering was used in the vertex shader. When transitioning to the **sediment texture layer**, the height value was read directly from the attribute texture.” Vertex kill punches holes (grass vs ground).

That is the bed/surface split in engine terms: the pond is a **hole in the garden mesh** with a **sediment material**, not a water shader pretending to be dirt.

**Michael Boulton, GDC 2007** — *The Look of Viva Pinata: A Detailed Tour Of The Graphics Engine* ([GDC Vault](https://www.gdcvault.com/play/732/The-Look-of-i-Viva), [preview](https://www.gamedeveloper.com/game-platforms/gdc-adds-i-assassin-s-creed-viva-pinata-elite-beat-agents-i-lectures)). Topics: “how the shaders were designed to achieve the look,” lighting and shadowing, edge-based tessellation. Full video is Vault-locked; no public water-shader slide deck. Treat water internals below as **reconstruction from the tessellation talk + HDR practice + footage**, not leaked source.

**Ali Eslami, Xbox 360 HDR** — *A Brief Introduction to High Dynamic Range Lighting on the Xbox 360* ([PDF](https://arkitus.com/files/tm-09-eslami-hdr.pdf)). Uses **Viva Piñata frames as the HDR example**, and lists bloom as part of the 360 HDR story. Sparkles on water are HDR values that bloom, not a white albedo.

**Ed Bryan (lead artist)** — [Rare Gamer interview](https://www.raregamer.co.uk/games/interview-with-viva-pinata-lead-artist-ed-bryan/): a “solid and coherent world,” extreme close-up detail, weather (sun, night, storms, morning mist), 30 fps in a full garden. Maya / Bodypaint / Photoshop textures; particle tools dating back to Banjo-Tooie.

Gameplay shape of a pond: [pinataisland.info/Pond](https://pinataisland.info/viva/Pond), [fandom Shovel](https://vivapinata.fandom.com/wiki/Shovel). Level 7 Pond Shovel Head; TiP lets you stamp a polygon. Piñatas drink from it. Aquatic species live in the volume.

#### Footage analysis (how it reads)

Press and play footage (links in §2.1.1). No Rare water-shader source.

| Cue | What you see | Likely how (360, 2006) |
| --- | --- | --- |
| Surface vs bed | Horizontal **sheet**. Under it: painted sand/green **sediment**, stones, weeds. The sheet is the realistic part. | Water is a **separate plane**. Bed is the tessellated garden with the sediment layer. You see the bed because the plane is clear, not because the water shader paints a fake floor. |
| Sparkle | Tight, dancing **sun glints**, bloomed, especially at a shallow grazing angle. Feels “wetter than the grass.” | Dual scrolling normals + **very tight Blinn/Phong** + a high-frequency sparkle mask. Specular **> 1** into an HDR buffer; bloom turns dots into sparkles (Eslami). Not a tiled caustic atlas as the main trick. |
| Reflections | Sky, trees, houses, **piñatas** sit in the water, fairly crisp in TiP. Distorted a little by the chop. | **Planar reflection** (mirror camera into a RT) was the 360 default for small lakes (same family as Source/HL2 water). Cube/env for sky fill. SSR did not exist as a standard 360 pass. |
| Transparency / refraction | Looking **down**: bed is obvious, lightly tinted. Looking **across**: more sky. Stones and pads kick only a little. | Strong **Fresnel**. Light tint, not murky absorption. Mild UV-offset of the scene behind, not a hard Snell IOR. The “refraction” is often just seeing the real terrain through alpha. |
| Bed colour | Saturated, **illustrative** dirt and moss. Toy scale. No photogrammetry grit. | Sediment **texture layer** (Boulton). Painted albedo, maybe a wet-darker variant near the waterline. |
| Foam / edges | Soft **wet bank**, sediment creeping up. Almost no white foam. | Vertex-shader **filtering** at the bank; height from the attribute texture so the lip does not crawl. Not a foam ring in the water shader. |
| Caustic-like hits | Bright moving highlights. More **on the surface** than classic pool-floor caustics. | Mostly sparkle/spec. A scrolling additive on the bed is optional and secondary. |
| Creatures | Quackberry swims **on** the sheet; others wade. Drink. Splash on entry. Ripples are small. | Particle splashes (Banjo-era particle tools). A few ripple decals or a scrolling normal, not a 256² heightfield. Pond is gameplay volume (pinometers of water). |
| Motion | Garden pond: **tiny chop**, not Gerstner swell. | Dual normal scrolls. Geometry stays a plane. |

**Take for PetalWild:** two materials; HDR sparkle into the existing glow; keep the bed painterly and the water **clear**; banks are sediment, not foam; planar reflection is how they got creature copies in the pond. Do not copy species, textures, or code.

#### 2.1.1 Screenshots and footage (links only)

Rare / Microsoft stills are copyrighted. They are **not** copied into this repo (`ASSET_PROVENANCE.md`). Use these while researching; do not vendor them.

| What | URL |
| --- | --- |
| Official E3 2006 **Water Park** demo (WMV) | [Microsoft Download Center archive](https://legacyupdate.net/download-center/download/9980/viva-pinata-movies-water-park) (`Pinata_WaterPark_Med.wmv`) |
| Same demo, stream | [Gamersyde, 2:55](https://www.gamersyde.com/video_viva_pinata_e3_water_park-2639_en.html) |
| Rare Gamer write-up of that demo | [E3 2006 Garden Demos – Water Park](https://www.raregamer.co.uk/games/viva-pinata-e3-2006-garden-demos-water-park/) |
| Promo stills, including “Wallpaper … Water” | [MobyGames promo](https://www.mobygames.com/game/25261/viva-pinata/promo/) |
| In-game screenshot set | [MobyGames screenshots](https://www.mobygames.com/game/25261/viva-pinata/screenshots/) |
| “A quackberry in the lake” | [Giant Bomb images](https://www.giantbomb.com/viva-pinata/3030-20537/images/) |
| TiP press shots | [XboxAchievements](https://www.xboxachievements.com/game/viva-pinata-trouble-in-paradise/screenshots/), [Neoseeker](https://www.neoseeker.com/viva-pinata-trouble-in-paradise/screenshots/) |
| Rare staff playing a finished garden (ponds in a live garden) | [IGN Plays: Rare Replay garden](https://www.ign.com/videos/rare-replay-cultivating-a-pimped-out-viva-piata-garden-ign-plays) |
| SIGGRAPH tessellation slides (pond banks called out) | [Boulton PDF](https://advances.realtimerendering.com/s2007/Boulton-PinataTessellation(Siggraph07).pdf) |

PetalWild’s own look target (original art, allowed in-tree): the attached city-park pond close-up, and `docs/reference/petalwild_target_garden_01.png` (willow water in the back of the hedge). Match **that** lighting to the Piñata *split*, not to Piñata’s characters.

### 2.2 Supporting — Road to Vostok (surface realism on Godot 4)

Hardcore survival FPS. **Godot 4** after a Unity port. Public notes: Godot **4.6.1 Forward+**. Same renderer family as us.

Use it for: still-water *scale*, a cheap reflection toggle, weather as shader globals, “do not turn on Environment SSR on transparent water.” Do **not** use it for colour. RTV lakes are tannin and dark. That murk would hide the painterly bed and kill the Piñata split.

Sources: [site](https://roadtovostok.com/), [Public Demo 1 v2](https://www.youtube.com/watch?v=2HePkuTN6hs) (Water System; swimming off for polish), [PC settings](https://www.switchbladegaming.com/road-to-vostok/best-pc-settings/) (Water Reflection = low cost), [Peter’s Immersion](https://modworkshop.net/mod/56778) (clarity / fish). Architecture names only at [dwoodruff83/RoadToVostokMods](https://github.com/dwoodruff83/RoadToVostokMods) — not a source.

### 2.3 Supporting — *Pen Pen TriIcelon* (~75% name match)

Dreamcast penguin racer (1998/99). “Pen Pen Dorif” → *Pen Pen ToraiAisuron*. “Pennerith” matched nothing. Use it for **splash, drip-off, body-in-water**, not lighting. If the owner meant water-quality rather than penguin, the runner-up is **Wave Race: Blue Storm** (planar-ish reflections, wakes). Hydro Thunder, Surf’s Up, ABZÛ sit behind that. Palia / Penumbra / Penrith / Dorfromantik are phonetic dead-ends.

Sources: [Wikipedia](https://en.wikipedia.org/wiki/Pen_Pen_TriIcelon), [HG101](https://www.hardcoregaming101.net/pen-pen-triicelon/), [IGN 1999](https://www.ign.com/articles/1999/09/09/pen-pen-tri-icelon).

## 3. What exists in PetalWild today

- `shaders/water.gdshader`: fresnel tint, `ROUGHNESS` 0.08, a **sine sparkle**, 1–2 cm vertex chop. No depth, no real specular sparkle, no bed layer.
- Mesh: 14×28 **bowl** (`dressing.gd`). UVs already world XZ. Group `parish_pond`.
- Terrain basin exists (`layout.gd`). Bed colour `#1e5c56` — too dark and too “real.” Poly Haven dirt on the garden must **not** continue under the water.
- Land jellies bounce off; Bulrush/Reedic stand on the bowl. No splash.
- `atmosphere.gd`: SSAO, **glow already on**, exponential fog, filmic, procedural sky. No SSR, no probes. MSAA 2×. Glow is the bloom path the sparkles need.

## 4. v1 stack — sparkly surface over painted bed

Goal: the Piñata split on a garden pond, ~1 ms GPU at 1080p. No ocean sim.

### 4.1 Scene layout (two materials, one API)

```
WaterBody (Node3D, group `water_body`)
├─ Surface          MeshInstance3D   PlaneMesh, ~64 subdiv, rest Y = shoreline
├─ Bed              MeshInstance3D   basin / clipped terrain, PondBed material
├─ Probe            ReflectionProbe  box-projected, slow update
├─ RippleCam        SubViewport      256² heightfield (or compute)
├─ Splash           GPUParticles3D
└─ Volume           Area3D
```

Later children (do not rename the above): `PlanarCam` (stage 2 — how Piñata got creature copies), `FlowMap` (stage 2 canal).

`WaterProfile` authors **both** layers (surface uniforms + bed colours). Garden pond and city-park canal are two resources, one shader pair.

**Mesh rules:**

- Surface is a **horizontal rest plane**. Displacement is additive (`rest + wave + ripple`). Drop the bowled water mesh.
- World XZ UVs on both layers.
- Bed is real geometry (the existing terrain bowl is fine as a starting mesh). Shoreline = where bed meets plane, with vertex/height filtering in the *bed* shader (Boulton’s bank trick), not a foam strip on the water.
- Subdivision on the plane prepaid for later Gerstner (~64² on an 8 m pond). v1 does not displace.

### 4.2 WaterSurface shader

Transparent pass (`hint_screen_texture`, `hint_depth_texture`). **Environment SSR off** ([docs](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html), [issue 90094](https://github.com/godotengine/godot/issues/90094)).

```
#define WATER_SPARKLE      // v1 on — the Piñata glint
#define WATER_REFRACTION   // v1 on, mild
#define WATER_SSR          // v1 on, cheap; miss → probe
#define WATER_RIPPLE_RT    // v1 on
// #define WATER_FOAM       // default OFF — Piñata banks are sediment
// #define WATER_CAUSTICS   // v1 optional, additive on the BED, not the sheet
// #define WATER_PLANAR     // stage 2
// #define WATER_FLOWMAP
// #define WATER_GERSTNER
// #define WATER_FFT
// #define WATER_UNDERWATER
```

| Group | Uniform | v1 | Notes |
| --- | --- | --- | --- |
| Colour | `shallow_tint`, `deep_tint`, `absorption_color` | yes | **Light.** Bed must read. Default beer_law low. |
| Colour | `depth_meters`, `beer_law`, `fresnel_power` | yes | Fresnel does the “sky vs bed” split. |
| Surface | `normal_a`, `normal_b`, scales, scrolls, `normal_strength` | yes | Small chop. Not ocean swell. |
| Surface | `roughness` (~0.04), `specular` | yes | Tighter than today’s 0.08. |
| Sparkle | `sparkle_tex` (or procedural), `sparkle_scale`, `sparkle_scroll` | yes | High-frequency noise. |
| Sparkle | `sparkle_power` (64–128), `sparkle_intensity`, `sparkle_threshold` | yes | `pow(NdotH, power) * mask` → **EMISSION** so glow blooms it. |
| Refraction | `refract_strength`, `refract_max` | yes | Mild. Depth-fade so distant trees do not smear. |
| Reflection | `ssr_steps` (12–24), `ssr_travel`, `ssr_mix`, `ssr_edge_fade` | yes | |
| Reflection | `planar_tex` | reserved black | Stage 2. |
| Interaction | `ripple_tex`, `ripple_strength`, `ripple_rect` | yes | Distorts normals, not the bed albedo. |
| Reserved | `flow_map`, `wave_displace_tex` | blank | |
| Globals | `wind_dir`, `wind_strength` | shader globals | RTV-style. |

Fragment order (surface):

1. Dual normals + ripple slope.
2. Reconstruct bed depth at refracted `SCREEN_UV`. Forward+ NDC z is `[0,1]`.
3. Sample the **already-drawn bed** from the screen (the bed is opaque, drawn first). Apply a **light** absorption tint. Do not lerp to a solid deep colour until depth is metres, not centimetres.
4. Fresnel mix toward probe / SSR / sky.
5. Sun specular (tight) + **sparkle emission**.
6. Optional faint foam only if a profile asks; default off.
7. `ALPHA` near 1 after compositing the screen sample, so lily pads sort less badly. `ROUGHNESS` low. Emission **only** on glints.

Vertex v1: none (or a millimetre sine). Gerstner stays behind a flag.

### 4.3 PondBed shader (the stylised layer)

This is half of v1. A photoreal bed will make the sparkly surface look like a puddle on mud.

| Uniform | Intent |
| --- | --- |
| `sediment_albedo` (sampler or colour) | Painted sand / moss. Saturated. Soft brush, not scan data. |
| `sediment_tint` | Warm green-gold in shallows, slightly deeper olive in the bowl. |
| `wetness` | Darken a band just above the waterline (Boulton’s sediment transition). |
| `detail_scale` | Large, readable blobs. Toy scale. |
| `caustic_tex`, `caustic_strength` | Optional additive, sampled in **bed XZ**, sun-masked. Secondary to surface sparkle. |

Do **not** bind Poly Haven `flower_scattered_dirt` under water. If we lack a painted map, a **shader-only** sediment (two colour ramps + cheap fbm, clamped saturation) is closer to Piñata than a photo. Art desk can replace that with a real paint later.

Banks: smoothstep the bed shading into the garden grass using world-XZ distance to the shoreline, with a filtered height sample so the lip does not crawl when the water plane is a millimetre off. That is the Boulton pond-bank note, on our side of the licence line.

### 4.4 Textures

| Map | Spec | Plan |
| --- | --- | --- |
| `normal_a/b` | 1K–2K OpenGL, small chop | Procedural FBM or CC0. Not photogrammetry swell. |
| `sparkle_tex` | 256–512 high-frequency | Procedural dots / cellular. Threshold in shader. |
| `sediment_albedo` | 1K painted or procedural | Art desk if we want a hero paint. No VP pixels. |
| `caustic_tex` | optional | Procedural Voronoi, or Calinou [CC0 caustics](https://opengameart.org/content/caustic-textures). |
| `ripple_tex` | 256² R16F runtime | WaterBody. |
| HDRI | optional | Helps the probe. Procedural sky is dull in reflections. |

### 4.5 Reflections

| Path | Role in the Piñata look |
| --- | --- |
| Glow + HDR sparkle | The “wetter than the world” glint. v1 must. |
| ReflectionProbe | Sky / willow when SSR misses. v1. |
| Custom SSR | Nearby trees, lamps. v1, 12 steps. |
| Environment SSR | **Off.** |
| Planar camera | **How Rare likely put piñatas in the pond.** Stage 2, but the node exists disabled in v1. Half-res, clip below the plane, one live camera per loaded world. |

v1 can look like Piñata **without** planar if sparkle + clear bed + probe are right. The jelly’s inverted copy in the city-park concept is the reason planar is next, not optional forever.

### 4.6 Interaction API (not in `jelly.gd`)

```
class_name WaterBody
signal body_entered_water(body, pos, speed)
signal body_exited_water(body, pos)

func impulse(world_pos: Vector3, velocity: Vector3, radius: float) -> void
func sample_height(world_pos: Vector3) -> float
func depth_at(world_pos: Vector3) -> float
func is_submerged(world_pos: Vector3, radius := 0.0) -> bool
```

v1 height = plane Y + ripple. Waders (Bulrush) call `sample_height()`. Thrown jelly: one `impulse` + splash particles (Pen Pen). Rain: same RT. Land jellies still bounce the rim until a swim stage.

Ripple: 256² compute (official [water_plane](https://github.com/godotengine/godot-demo-projects/tree/master/compute/texture/water_plane), MIT) or a SubViewport blob. Distorts **surface normals** so sparkles break up around a wader. Do not ripple the bed albedo.

## 5. Roadmap

| Stage | Add | Do not change |
| --- | --- | --- |
| **v1** | **PondBed + sparkly WaterSurface**, light absorption, mild refraction, probe + cheap SSR, ripple RT, splash | Profile fields, `WaterBody` API, plane + basin, world XZ UVs |
| **2** | **Planar reflection** on the hero pond (Piñata creature copy); wetness on feet/stones; more drip-off (Pen Pen); flow map on the canal; optional bed caustics | Uniform names. Bind `planar_tex`. |
| **3** | 2–4 Gerstner tones; better SSR; underwater volume; LOD drops sparkle/SSR in Vale | `sample_height()` includes Gerstner |
| **4** | FFT only for a Vale ocean ([2Retr0](https://github.com/2Retr0/GodotOceanWaves), [tessarakkt](https://github.com/tessarakkt/godot4-oceanfft), MIT) | Pond profiles stay on sparkle + plane |

RTV stays the Godot-lake checklist. Pen Pen stays splash. Wave Race sits with planar/wakes in stage 2–3. Piñata is the look bar for every stage: if a pass makes the bed photoreal or the surface matte, it failed.

## 6. Performance (Windows PC, Forward+)

Floor **1080p 60**. Comfortable 1440p on an RTX 2060 class. Rare held 30 fps on a 2006 GPU with much heavier unique shaders; our garden is smaller.

| Item | Budget |
| --- | --- |
| WaterSurface + PondBed | ≤ 1.0 ms at 1080p |
| Sparkle | Folded into the surface pass (a few extra samples) |
| Custom SSR | 12 steps default, 24 high |
| Ripple RT | 256², only if someone is near |
| Splash | ≤ 64 particles |
| Probe | 128³–256³, ≤ 0.5 Hz |
| Planar (stage 2) | 50% res, one camera |

Glow is already on; sparkles ride it. Do not add volumetric fog or engine SSR to “help” water. Feature flags baked per profile, not runtime variants. Compute ripples need Forward+. Nested worlds: only the loaded world’s hero water is full quality.

## 7. Open-source Godot 4 water (licences)

Prefer an original PetalWild pair of shaders with our names. MIT/CC0 study only.

| Project | Licence | Use |
| --- | --- | --- |
| [Malido absorption water](https://godotshaders.com/shader/absorption-based-stylized-water/) | **CC0** (code) | Dual normals, optional SSR, screen composite. **Tone down** its absorption so the bed pops. |
| [marcelb/GodotSSRWater](https://github.com/marcelb/GodotSSRWater) | **MIT** | Transparent SSR. |
| [Binbun Godot Water](https://binbun3d.itch.io/godot-water-shader) | **CC0** | World-space caustics; NDC z note. |
| [godot-demo water_plane](https://github.com/godotengine/godot-demo-projects/tree/master/compute/texture/water_plane) | **MIT** | Ripple RT. |
| [smart_planar_reflector](https://github.com/KipJM/smart_planar_reflector) / [gd_planar_reflection](https://github.com/risingthumb/gd_planar_reflection) | **MIT** | Stage 2 planar. |
| LesusX Gerstner, 2Retr0 / tessarakkt FFT, REBOOT16 SWE | **MIT** | Later stages. |
| Crest, Unity water, RTV PCK, Viva Piñata | proprietary | **Do not vendor.** |

No built-in WaterBody in 4.8-dev6.

## 8. Open questions for the owner

1. **Look bar.** Treat Piñata’s split as the pass/fail for v1 (sparkle + painted bed, clear water). City-park concept is the camera we grade against. Confirm.
2. **Planar in v1 or 2?** Sparkle+bed can ship without it. The jelly reflection in the concept really wants planar. Prefer stage 2 unless you want the extra camera now.
3. **Bed paint.** Shader-only sediment for v1, or an art-desk painted map before the shader lands?
4. **Bowl vs plane.** Recommend plane + terrain basin. Confirm we drop the bowled water mesh.
5. **Pen Pen vs Wave Race** as the interaction/water-racer supporting title (~75% Pen Pen on the name).
6. **Swim / underwater.** v1 is wading + splash. When does a jelly fully submerge?
7. **HDRI** for the probe, or procedural sky for v1?
8. **Rain ripples** on the same RT as character impulses?
9. **Compat / llvmpipe.** Windows Forward+ only?

## 9. Sources

- Viva Piñata: Boulton SIGGRAPH 2007 tessellation PDF; GDC 2007 *Look of Viva Pinata* (Vault); Eslami Xbox 360 HDR PDF; Ed Bryan interview; E3 Water Park WMV; MobyGames / Giant Bomb / XboxAchievements stills; GameFAQs TiP water note; pinataisland pond page. Links in §2.1 and §2.1.1.
- Road to Vostok: §2.2.
- Pen Pen / Wave Race: §2.3. Wave Race write-ups: [Aguas](https://aguaspoints.com/2023/02/02/some-thoughts-on-nintendos-wave-race-blue-storm/), [IGN Blue Storm](https://www.ign.com/articles/2001/11/07/wave-race-blue-storm-2).
- Godot: screen-reading shaders, [reflection probes](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/reflection_probes.html), [compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html), issues 90094 / 93725, proposal 7274.
- Technique background (not v1): Tessendorf *Simulating Ocean Water*; GPU Gems ch. 1 Gerstner; Source/HL2 planar water as the 360-era cousin of Piñata’s likely reflection path.
- Shaders / addons: §7.

PetalWild files: `shaders/water.gdshader`, `scripts/world/dressing.gd` `_water`, `scripts/world/layout.gd` pond helpers, `scripts/world/atmosphere.gd`, `scripts/creatures/jelly.gd` `_stand_y`, `project.godot`, `docs/ENGINE_VERSION.md`.

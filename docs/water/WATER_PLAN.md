# PetalWild water plan

Research only. No gameplay or shader implementation in this change. Target: Godot **4.8-dev6 Forward+**, Windows PC.

Three high-end, one-to-one **material** references, one per material. Water is the deliverable in this doc. Snow and sand are future, but they share one weather/deform framework (§10).

| Material | Role | Working title | Confidence |
| --- | --- | --- | --- |
| **Water** | **Primary look:** Viva Piñata / *Trouble in Paradise* — sparkly realistic **surface** over a cartoony painted **bed**. **Named Godot surface/interaction ref:** *Penitent* (devmar), [Devlog 19](https://youtu.be/DfKsxQaY63Y). **High-end ballpark:** Hellblade II. | *Penitent* | **Confirmed** (owner link) |
| **Snow** | Future. *Road to Vostok* (Godot 4.6.1 Forward+). | RTV | Given |
| **Sand** | Future. *Clair Obscur: Expedition 33* / Sandfall Interactive (“Sandfire”). | Expedition 33 | ~65% |

**Primary look (water):** Viva Piñata (Rare, Xbox 360, 2006) and *Trouble in Paradise* (2008) garden ponds. That contrast is the effect. The approved city-park pond concept is our instance of the same split. *Penitent* tells the **Godot sheet** how to ripple, splash, and stay reflective around a character. Hellblade II is the **quality ceiling** for wetness/flow, not the named title. Neither replaces the painted bed.

Licence firewall is the same as `docs/research/REFERENCES.md` and `docs/LICENSE_MATRIX.md`. MIT / CC0 only in the tree. Do not vendor Road to Vostok, Viva Piñata, TiP-Recomp (no-AI policy; not inspected), Hellblade II / Fluid Flux, Expedition 33, Kmitt’s *Sandfire*, or *Penitent*. House style is already “Viva Piñata-style, painterly, saturated, chunky and toy-like” (`docs/AGENT_CONTRACTS.md`); this plan is how that applies to **water**.

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

### 2.2 Surface / interaction — *Penitent* (devmar), confirmed

Owner linked the water bit: [Devlog 19, flooded map](https://youtu.be/DfKsxQaY63Y) (`DfKsxQaY63Y`). That is **this** *Penitent*, a Godot 4 solo project (devmar / Devinthewater). Official [Godot 4.0 beta 2](https://godotengine.org/article/dev-snapshot-godot-4-0-beta-2/) used a Penitent still as the hero shot. It sits **under** Piñata (look), not instead of it.

Hellblade II / Forbidden West were **good ballparks** for one-to-one wetness. Keep them as the quality ceiling (§2.2.1). They are not the named title.

*Road to Vostok* is snow (§10.1). *Sandfire* is sand (§10.2). *Pen Pen TriIcelon* stays a mistaken first guess.

Do **not** vendor Penitent, Hellblade II, or Fluid Flux. Study only.

#### What Devlog 19 actually shows (Godot)

Half-immersed third-person in a **flooded** map. Floating debris, wading, a jet-ski demon, later an underwater camera. Lessons, in his words, reconstructed from the video — not leaked source.

1. **Sheet:** “world’s simplest water shader” — scrolling **normal map** for chop. Low roughness, high spec.
2. **Reflection vs see-through:** proximity fade needs `ALPHA`. In Godot, **alpha kills default reflections** (probe/GI) even at roughness 0. He dropped fade and kept reflectivity. He also **wanted murk** (“I don’t really care what’s under the surface… more disturbing when you can’t see into it”). That murk is **wrong for Piñata**. We still steal the engine fact: if we rely on built-in reflections, alpha will dump them. v1 **composites the bed from the screen first**, then keeps `ALPHA` near 1 so sparkle and probe/SSR still work *and* the painted bed reads.
3. **Creature-in-water without a heavy mesh:** full vertex fluid on a tight grid was too expensive. Instead: a **follow-player plane**, viewport texture in the **NORMAL** slot. A camera looks at a particle emitter (noisy blobs). Idle = large particles; moving = small ones join. Emitter follows the actor → a **trail of broken reflections**. Height displace from the same viewport is optional; he skipped it. This is the Godot cousin of our 256² ripple RT.
4. **Splash:** `GPUParticles3D`, velocity-gated. Animated **sprite-sheet** splashes (After Effects → Photoshop atlas). Extra burst on jump-land. SFX carry the feel. Amounts are tiny.
5. **SDFGI:** looks great in the water, but **no dynamic occluders**. Moving rocks leave stale GI blobs in the sheet. Workaround: disable GI on movers, turn it back on when they rest. We are on Forward+ with a probe + custom SSR, not SDFGI — same class of bug if we ever turn VoxelGI/SDFGI on for water.
6. **Underwater camera:** a plane in front of the camera slides up with pitch; vertex waves + fragment refraction. Stage 3 (`WATER_UNDERWATER`), not v1.
7. **Buoyancy / boats:** hinge/trailer, sink on death. Our `WaterBody.sample_height` / `is_submerged` is the garden-scale stand-in. Not a jet-ski sim.

| Cue | What you see | Take for our WaterSurface |
| --- | --- | --- |
| Specular | Tight, reflective sheet. Glints from SDFGI + spec. | Low roughness, HDR sparkle into glow. |
| Murk | Bed hidden on purpose. | **Do not copy.** Light absorption. Painted PondBed must read. |
| Interaction | Follow-player viewport → normals, wake of highlights. | Ripple RT (compute or SubViewport) distorts **normals** on the main plane. One sheet, not a second overlay if we can help it. |
| Splash | Few animated particles + land burst + audio. | `impulse` → sprite-sheet or GPUParticles. Budget ≤ 64. |
| Alpha / fade | Soft edge *or* reflections, not both, on a default material. | Screen-composite then `ALPHA` ≈ 1. No proximity-fade as the shoreline (Boulton wet sediment instead). |
| Camera in water | Refracting fullscreen plane. | Reserved underwater pass. |
| Movers in GI | Stale reflections. | Keep Environment SSR **off**. Probe slow-update. Don’t enable SDFGI on the pond. |

**Take for PetalWild:** Penitent is the **Godot recipe** for a character in a reflective sheet (follow-field normals, cheap splash, alpha/reflection trap). Piñata is the **picture** through that sheet. Combine them: Penitent interaction on a *clear* Piñata pond, not a flooded tannin volume.

##### Footage (links only)

| What | URL |
| --- | --- |
| **Owner link — Devlog 19** (flooded map, water breakdown) | [youtu.be/DfKsxQaY63Y](https://youtu.be/DfKsxQaY63Y) |
| r/godot post of the same | [Devlog 19 thread](https://www.reddit.com/r/godot/comments/yzzoeq/i_added_a_new_type_of_map_that_is_entirely/) |
| Godot 4.0 beta 2 hero still | [engine blog](https://godotengine.org/article/dev-snapshot-godot-4-0-beta-2/) |
| Channel | [devmar](https://www.youtube.com/@actualdevmar) |

#### 2.2.1 High-end ballpark — *Senua’s Saga: Hellblade II*

Owner: the earlier Hellblade / Forbidden West picks were **good ballparks**. Use HB2 for how wet a **one-to-one** surface can get, not as the named game.

[Digital Foundry interview](https://www.digitalfoundry.net/articles/digitalfoundry-2024-the-big-senuas-saga-hellblade-2-tech-interview): Houdini **flowmaps** on rock (chunked single-layer water); **Fluid Flux** 2D shallow-water sim + shoreline **wetness** field; lake-drain setpiece. Photogrammetry is their *world*, not our PondBed.

Steal later: `WATER_FLOWMAP` on the canal, global `wetness` on banks/feet, ripple RT as the cheap heightfield cousin. Do not vendor Fluid Flux. Do not scan the parish mud.

### 2.3 Closed name guesses (water)

- ***Pen Pen TriIcelon*** — first ASR (“Pen Pen Dorif”). Owner ruled it out. Splash now from Piñata particles + Penitent sprite-sheets.
- Using ***Expedition 33*** as the water game — previous pass; owner assigned Sandfall to **sand**.
- Using ***Hellblade II*** as the *name* — ballpark only; owner confirmed *Penitent* via Devlog 19.
- *Wave Race: Blue Storm* — planar/wake footnote for stage 2–3, not a named ref.

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
| Reserved | `flow_map`, `wave_displace_tex` | blank | Hellblade-ballpark flow on canal/wet rock, stage 2. |
| Reserved | `deform_tex` | blank | Same RT family as `ripple_tex`; later snow/sand footprints (§10). |
| Globals | `wind_dir`, `wind_strength`, `wetness` | shader globals | Shared weather. `snow_cover` reserved 0. RTV lakes taught us: **Environment SSR off** on transparent water. |

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
| `wetness` | Darken a band just above the waterline (Boulton’s sediment transition). Driven by global `wetness` + shoreline distance so snow/sand materials can read the same value later. |
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

v1 height = plane Y + ripple. Waders (Bulrush) call `sample_height()`. Thrown jelly: one `impulse` + splash particles (Piñata-style; Penitent sprite-sheet if we want a chunkier hit). Rain: same RT. Land jellies still bounce the rim until a swim stage.

Ripple: 256² compute (official [water_plane](https://github.com/godotengine/godot-demo-projects/tree/master/compute/texture/water_plane), MIT) or a SubViewport blob — same idea as Penitent’s follow-player viewport in the **normal** slot. Distorts **surface normals** so sparkles break up around a wader. Do not ripple the bed albedo. The same blit pattern is reserved as `deform_tex` for snow compression and sand footprints (§10).

## 5. Roadmap

| Stage | Add | Do not change |
| --- | --- | --- |
| **v1** | **PondBed + sparkly WaterSurface**, light absorption, mild refraction, probe + cheap SSR, ripple RT, splash | Profile fields, `WaterBody` API, plane + basin, world XZ UVs |
| **2** | **Planar reflection** on the hero pond (Piñata creature copy); wetness on feet/stones (Hellblade ballpark); more drip-off; flow map on the canal; optional bed caustics; Penitent-style jump-land splash | Uniform names. Bind `planar_tex`. |
| **3** | 2–4 Gerstner tones; better SSR; underwater volume (Penitent camera-plane refraction); LOD drops sparkle/SSR in Vale | `sample_height()` includes Gerstner |
| **4** | FFT only for a Vale ocean ([2Retr0](https://github.com/2Retr0/GodotOceanWaves), [tessarakkt](https://github.com/tessarakkt/godot4-oceanfft), MIT) | Pond profiles stay on sparkle + plane |
| **later** | Snow (RTV) and sand (Expedition 33) on the shared weather + `deform_tex` framework | §10. Do not rename v1 water uniforms. |

Penitent is the Godot interaction check (follow-field normals, cheap splash, no alpha-vs-reflection trap). Hellblade II is the wetness/flow ballpark. Piñata is the look bar for every water stage: if a pass makes the bed photoreal, hides the bed in murk, or makes the surface matte, it failed. Snow and sand must keep the same globals and the same deform-RT idea.

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
| Crest, Unity water, Fluid Flux, RTV PCK, Viva Piñata, Hellblade II, Expedition 33, *Sandfire*, *Penitent* | proprietary | **Do not vendor.** |

No built-in WaterBody in 4.8-dev6.

## 8. Open questions for the owner

1. **Look bar.** Treat Piñata’s split as the pass/fail for v1 (sparkle + painted bed, clear water). City-park concept is the camera we grade against. Confirm.
2. **Planar in v1 or 2?** Sparkle+bed can ship without it. The jelly reflection in the concept really wants planar. Prefer stage 2 unless you want the extra camera now.
3. **Bed paint.** Shader-only sediment for v1, or an art-desk painted map before the shader lands?
4. **Bowl vs plane.** Recommend plane + terrain basin. Confirm we drop the bowled water mesh.
5. **Names.** Water = *Penitent* Devlog 19 (**confirmed**). Hellblade II stays a quality ballpark. Sand = Expedition 33 / Sandfall (~65%, “Sandfire”). Snow = RTV (given). Pen Pen is closed.
6. **Swim / underwater.** v1 is wading + splash. When does a jelly fully submerge?
7. **HDRI** for the probe, or procedural sky for v1?
8. **Rain ripples** on the same RT as character impulses?
9. **Compat / llvmpipe.** Windows Forward+ only?

## 9. Sources

- Viva Piñata: Boulton SIGGRAPH 2007 tessellation PDF; GDC 2007 *Look of Viva Pinata* (Vault); Eslami Xbox 360 HDR PDF; Ed Bryan interview; E3 Water Park WMV; MobyGames / Giant Bomb / XboxAchievements stills; GameFAQs TiP water note; pinataisland pond page. Links in §2.1 and §2.1.1.
- *Penitent* (devmar, water, **confirmed**): [Devlog 19](https://youtu.be/DfKsxQaY63Y); r/godot thread; Godot 4.0 beta 2 blog. §2.2.
- Hellblade II (water **ballpark**): §2.2.1. DF tech interview; Fluid Flux public docs (ideas only).
- Road to Vostok (snow, not water): §10.1. Site / Steam; shader globals from [dwoodruff83/RoadToVostokMods](https://github.com/dwoodruff83/RoadToVostokMods) architecture table — not a source dump.
- Expedition 33 / Sandfall (sand): §10.2. DF; Breton ArtStation; Gestral Beach guides; Wikipedia. Journey sand (technique cousin): [Edwards GDC Vault](https://www.gdcvault.com/play/1017742/Sand-Rendering-in), [Zucconi](https://www.alanzucconi.com/2019/10/08/journey-sand-shader-1/).
- Closed water guesses: §2.3. Wave Race (planar/wake footnote): [Aguas](https://aguaspoints.com/2023/02/02/some-thoughts-on-nintendos-wave-race-blue-storm/), [IGN Blue Storm](https://www.ign.com/articles/2001/11/07/wave-race-blue-storm-2).
- Godot: screen-reading shaders, [reflection probes](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/reflection_probes.html), [compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html), issues 90094 / 93725, proposal 7274. Snow deform pattern: [goeshard](https://goeshard.org/2025/05/20/snow-deformation/).
- Technique background (not v1): Tessendorf *Simulating Ocean Water*; GPU Gems ch. 1 Gerstner; Source/HL2 planar water as the 360-era cousin of Piñata’s likely reflection path.
- Shaders / addons: §7.

PetalWild files: `shaders/water.gdshader`, `scripts/world/dressing.gd` `_water`, `scripts/world/layout.gd` pond helpers, `scripts/world/atmosphere.gd`, `scripts/creatures/jelly.gd` `_stand_y`, `project.godot`, `docs/ENGINE_VERSION.md`.

## 10. Future materials (snow, sand) and shared weather

Not v1. Names and a Godot sketch so water, snow, and sand do not grow three different weather systems.

### 10.0 Shared framework

One set of **shader globals** (RTV already does this in Godot 4.6.1: `Winter`, `Snow`, `Rain`, `Wind`). Ours, with our names:

| Global | v1 water | Later snow | Later sand |
| --- | --- | --- | --- |
| `wind_dir`, `wind_strength` | chop / sparkle breakup | drift, sparkle anisotropy | ripple direction, glitter |
| `wetness` | banks, stones, jelly feet | slush, darker snow | dark damp sand at the waterline |
| `snow_cover` | 0 | accumulation 0–1 | 0 |
| `rain` | drives ripple impulses | wet snow | crater pocks |

One **interaction heightfield** idea, three bindings: water `ripple_tex` (v1), snow compression, sand footprints. Same 256² compute/SubViewport blit around the jelly, world-XZ. `WaterBody.impulse` grows a generic `GroundImpulse(pos, vel, radius, medium)` later; do not put it in `jelly.gd` now.

Garden materials (grass, PondBed, future SnowSheet, SandSheet) all sample `wetness` and the deform RT they care about. Feature flags stay per-profile so a Vale snow pass cannot rename pond uniforms.

### 10.1 Snow — *Road to Vostok*

Finnish-border survival FPS. **Godot 4.6.1 Forward+**, same renderer family as us. Owner: this is the **snow material**, not the lake. Public: summer/winter modes, `Snow` / `Winter` / `Rain` / `Wind` shader globals, items freeze, water accelerates freeze ([Steam](https://store.steampowered.com/app/1963610/Road_to_Vostok/), [site](https://roadtovostok.com/), architecture names only at [RoadToVostokMods](https://github.com/dwoodruff83/RoadToVostokMods)). Screenshots: [roadtovostok.com/screenshots](https://roadtovostok.com/screenshots). Do not vendor the PCK.

**What makes it convincing:** snow is a **volume you walk through**, not a white albedo. Cover sits on every material (ground, roof, pine, crate) from one winter switch. It sparkles like a dielectric (tight spec, same family as our water glints). Footfalls and bodies leave **lasting compression**. Weather is globals, not a unique shader per mesh. Lakes go dark and should be ignored for our water colour.

**Godot approach (when we do it):** a `SnowSheet` (or a snow layer in the terrain shader) that adds a world-XZ cover using `snow_cover`, sparkles into the existing **glow** (reuse water sparkle code with a different threshold), and displaces/occludes via `deform_tex` written by an ortho blit of jelly contact (same pattern as [goeshard snow deform](https://goeshard.org/2025/05/20/snow-deformation/), MIT-study, rewrite). `wetness` turns cover to slush near the pond. No RTV assets, no extra Environment SSR.

### 10.2 Sand — *Clair Obscur: Expedition 33* (“Sandfire”)

**Sandfire ≈ Sandfall.** High-end UE5, painted world, Gestral Beach dunes and shallows, Flying Waters seabed sand. Working pick **~65%**. Exact-title alt: Kmitt’s Godot *Sandfire* (desert souls-like, not a sand-shader showcase). Technique cousin, not the named ref: *Journey* ([Edwards GDC](https://www.gdcvault.com/play/1017742/Sand-Rendering-in) — glitter specular, ocean specular, diffuse contrast, detail heightmaps). *Dune: Awakening* is one-to-one dune sim if we ever need storms; weaker name. Do not vendor any of them.

**What makes it convincing (E33):** sand reads as **illustrative pigment that still lights like grains** — saturated, readable, not photogrammetry grit (same split as PondBed). In shallows you see it **through** water. Beaches are broad, toy-scale dunes, not a noise tile. Journey’s extra lesson, which E33’s sparkle shares in spirit: sand wants a **glitter lobe** and a wide “ocean” spec so it feels a little liquid, which is what makes footprints and surfing satisfying.

**Godot approach (when we do it):** a `SandSheet` on world XZ: painted/procedural albedo (art desk, no E33 pixels), glitter + ocean spec into glow (Edwards/Zucconi ideas, our code), `wetness` darkening at the pond, `deform_tex` for jelly footprints and thrown-jelly craters (same RT as snow, different restore rate — sand slumps back slower than snow, faster than a puddle ripple). Wind scrolls a fine normal. Keep it toy-scale; a Dune storm sim is out of scope.

Q5 if this is the wrong Sandfire.

# PetalWild water plan

Research only. No gameplay or shader implementation in this change. Target: Godot **4.8-dev6 Forward+**, Windows PC. House look: materials halfway between toy and real, matching the approved city-park pond (clear water, caustics on the bed, lily pads, a sharp creature reflection). Nested worlds share one water stack; each body gets a profile, not a unique shader.

Licence firewall is the same as `docs/research/REFERENCES.md` and `docs/LICENSE_MATRIX.md`. MIT / CC0 only in the tree. Road to Vostok is a study reference, not a source. Do not vendor its `Water.gd` or shaders.

## 1. Look target

Approved pond concept (attached city-park close-up, also the art-desk city-park pond):

- Horizontal **clear** surface, not a dyed bowl.
- **Caustics** on stones and bed, brightest in the shallows.
- **Reflections** of the jelly, willow, lamps, sky; a readable inverted copy, slightly softened.
- **Refraction**: lily pads and stones kick sideways under the surface.
- Green-gold **depth colour** that still lets the bed show in the shallows.
- Soft mossy shoreline, not a white foam ring.
- Dragonflies, duck, pads sit *in* the water, not stamped on a plane.

Today’s live pond (`shaders/water.gdshader` + `GardenDressing._water`) is a vertex-sine bowl with fresnel tint and a sparkle. No depth, refraction, normals, foam, caustics, or interaction. The bowl-down mesh was a look hack because the shader could not read bathymetry. **v1 should make the surface a rest plane** (tiny waves on top). The basin stays in the terrain.

Worlds that will use this:

| World | Water | v1 quality |
| --- | --- | --- |
| Hedge Hollow parish pond | ~3–6 m scooped still pond, Bulrush/Reedic wade | Full |
| Grove Park / city-park canal | Hero look from the concept (bridge, pads, lamps) | Full when that world is loaded |
| Petal Vale / distant | Lakes as set dressing | LOD: probe + colour, no SSR, no ripple RT |

One shader. `WaterProfile` per body.

## 2. Reference games

### 2.1 Road to Vostok (confirmed)

Hardcore survival FPS, Finnish–Russian border wetlands. Solo developer Antti. **Godot 4** after a mid-production Unity port (~600 hours, 2024). Public modding notes put the Early Access build on **Godot 4.6.1, Forward+, D3D12**. That is the same renderer family as PetalWild’s Windows target, one minor version behind our 4.8-dev6 pin.

Why the water reads:

- **Still, cold lakes**, not an ocean. Dark tannin / steel, big sky and pine reflections. PetalWild wants clearer garden water, but the *scale* (pond/lake, not swell) matches.
- A dedicated **Water system** shipped in Public Demo 1 v2 ([devlog](https://www.youtube.com/watch?v=2HePkuTN6hs)). Swimming and fishing were turned off in that demo for polish, so interaction exists in the project and was not yet the selling point.
- Graphics menu exposes **Water Reflection** as a cheap, high-value wetland toggle ([settings write-up](https://www.switchbladegaming.com/road-to-vostok/best-pc-settings/)). That is probe / SSR class, not a second full scene.
- **Water clarity** (see-through to fish) is a known tweak in the visual-overhaul mod community, which implies depth absorption + underwater tint, not a solid plane ([Peter’s Immersion](https://modworkshop.net/mod/56778)).
- Weather is global shader state (`Rain`, `Wind`, `Winter`, `Snow`, player position) in the public architecture notes. Water is expected to listen to those, not own a private clock.
- Godot’s built-in **SSR does not run on transparent materials**. Any water that both refracts and reflects is either a custom ray-march in the water shader, a reflection probe, or a planar camera. RTV almost certainly uses some mix of those; we must not copy their code.

Take for PetalWild: **Godot Forward+ lake water is a solved shape** — depth colour, a reflection toggle, weather globals, keep swimming/wading as a later polish pass. Do not chase RTV’s boreal darkness; our pond is ornamental and clear.

### 2.2 Second title: *Pen Pen TriIcelon* (most probable)

**Confidence: ~75% that this is the game the owner meant. ~40% that it is the water-quality reference they would pick if shown a shortlist.**

| Guess | Match |
| --- | --- |
| “Pen Pen Dorif” | Japanese title **ペンペントライアイスロン** (*Pen Pen ToraiAisuron*). Europe shipped it as **Pen Pen**. “Dorif” is a plausible mishear of *TriIcelon* / triathlon, or of Japanese **ドリフト** (*dorifuto*, drift) after watching a swim/slide race. |
| “Pennerith” | No game, studio, or shader author by that name turned up. Closest dead-ends: Penrith (UK town), Penumbra, Palia, Prophesy of Pendor. None are water showcases. |
| Penguin or water game | Dreamcast launch racer (1998 JP / 1999 WW) by General Entertainment / Team Land Ho. Penguin-like **Pen Pen** waddle, belly-slide, and **swim**. |

Sources: [Wikipedia](https://en.wikipedia.org/wiki/Pen_Pen_TriIcelon), [Hardcore Gaming 101](https://www.hardcoregaming101.net/pen-pen-triicelon/), [IGN 1999](https://www.ign.com/articles/1999/09/09/pen-pen-tri-icelon), [GameVortex](https://www.gamevortex.com/gamevortex/soft_rev.php/1404/pen-pen-triicelon-dreamcast.html), [Retro Replay](https://retro-replay.com/db/dreamcast/pen-pen-triicelon/).

What the water actually does (footage / reviews, not a published shader talk — none exists):

- Dreamcast PowerVR2: cheap alpha, **environment-mapped surface**, scrolling water textures, modest vertex chop. Not PBR, not FFT.
- Swim sections are **full body-in-water**: camera can go under, sunken toys/ships stay readable, characters stroke through a volume rather than skating on a plane.
- **Splashes and drip-off** are the sell. Reviews call out droplets when a Pen Pen surfaces and a shake-off after a dive. Particle + animation, not a fluid sim.
- Toy palette, crystal-clear water, props sitting in the swim lane (shampoo bottles on Toys, mines on Sweets). That is closer to PetalWild’s jelly-in-a-garden-pond than RTV’s wetlands.
- Four racers in the water at once; draw-distance / LOD kept it smooth.

Take for PetalWild: **interaction feel**, not surface shading. Jellies, Bulrush, and Reedic should splash, wake, and look wet. Underwater as a later stage. Do not treat Pen Pen’s env-map puddle as the lighting model.

### 2.3 Runner-up candidates (if the owner meant “great water”, not “penguin”)

Ranked by how well they fit the guesses **or** the water brief.

| Rank | Title | Why it is on the list | Why it is not pick 1 |
| --- | --- | --- | --- |
| 1 | **Wave Race 64** / **Wave Race: Blue Storm** (N64 / GameCube) | The generation’s “look at this water” racer. Vertex wave field, buoyancy, full-scene reflections on Blue Storm, jet-ski wakes that deform the surface. [Aguas](https://aguaspoints.com/2023/02/02/some-thoughts-on-nintendos-wave-race-blue-storm/), [IGN Blue Storm](https://www.ign.com/articles/2001/11/07/wave-race-blue-storm-2), [GamesFirst](https://gamesfirst.com/articles/2001/wave-race-blue-storm-gc/). Same era/platform neighbourhood as Pen Pen (Sega hardware adjacent; Hydro Thunder on DC). | Name is not Pen Pen. Study it for **wakes and planar-ish reflections**, not as the mystery title. |
| 2 | **Hydro Thunder** (Dreamcast) | Same box as Pen Pen, water was the screenshot. Heavy env-map + spray. | Not a penguin game; arcade boats. |
| 3 | **Surf’s Up** (2007) | Actual penguins on water; Ubisoft wave/surf tech. | Name is not close. CG-film look. |
| 4 | **ABZÛ** / **The Pathless** (Giant Squid) | Best stylized “creature in water” lighting this side of Wind Waker. | Names are not Pennerith. Use as a *look* extra, not the ID. |
| 5 | **Club Penguin** / Island | Penguin + water, toy. | Weak water tech; name only shares “Pen”. |
| 6 | **Ecco the Dolphin** | Classic swim-through-volume. | Dolphin, not penguin. |
| 7 | **Palia**, **Penumbra**, **Penrith**, **Dorfromantik** | Phonetic leftovers (“Pennerith”, “Dorif” ≈ Dorf). | Palia is Unreal cozy; Penumbra is horror; Penrith is a town; Dorfromantik has no water tech. Rejected. |

**Owner check:** if the second reference was meant as *water quality* rather than *penguin*, swap Pen Pen for **Wave Race: Blue Storm** and keep Pen Pen as the interaction mood board.

## 3. What exists in PetalWild today

- `shaders/water.gdshader`: `blend_mix`, `cull_disabled`, two colours, fresnel alpha, `ROUGHNESS` 0.08, a world-space sparkle. Vertex `sin`/`cos` ~1–2 cm.
- Mesh: 14 rings × 28 segments, **bowled down** to match `GardenLayout.pond_surface` (`dressing.gd`). UVs are already **world XZ**. Group `parish_pond`.
- Terrain already cuts a basin (`layout.gd` `height_at`). Bed colour `#1e5c56`.
- Interaction: land jellies **bounce off** the pond; Bulrush/Reedic **stand on the bowl** (`jelly.gd` `_stand_y`, `JellyFeel.bounce_prop`). No splash, no wake, no wetness.
- Atmosphere (`atmosphere.gd`): SSAO, glow, exponential fog, filmic tonemap, procedural sky. **No SSR, no reflection probes, no volumetric fog.** MSAA 2× in `project.godot`.
- Engine pin: 4.8-dev6 Forward+ on the Windows target. This agent VM is llvmpipe / Compatibility — do not tune water against that.

## 4. v1 stack (stylised, convincing, cheap)

Goal: the city-park close-up on a garden-scale pond, ~1 ms GPU at 1080p, no ocean sim.

### 4.1 Scene layout (forward-compatible)

Do **not** keep a unique bowl mesh as the water. Bathymetry lives in terrain; water is a rest plane with optional displacement.

```
WaterBody (Node3D, group `water_body`)
├─ Surface          MeshInstance3D   PlaneMesh, ~64 subdiv, clipped to shoreline AABB
├─ Probe            ReflectionProbe  box-projected, interior, once-dirty or 2–4 s update
├─ RippleCam        SubViewport      256², orthographic, heightfield (or compute, see below)
├─ Splash           GPUParticles3D   droplets + a short ring; off until an impulse
└─ Volume           Area3D           overlap for wading / splash triggers
```

Later stages add children, they do not rename these: `PlanarCam` (stage 2), `FlowMap` texture slot (stage 2), Gerstner/FFT displace on the same `Surface` mesh (stage 3).

`WaterProfile` (Resource) is the only authored look. Garden pond and city-park canal are two resources, one shader.

**Mesh rules that keep later stages unboxed:**

- World-space XZ UVs (already true).
- Rest pose is a **horizontal plane** at shoreline Y. Vertex displacement is additive (`rest + wave + ripple`).
- Subdivision high enough for later Gerstner (~64² on a 8 m pond). v1 waves are normal-map only, so this is prepaid, not used.
- Shoreline clip by mesh bounds + shader depth foam, not by baking the basin into the surface.
- One material per body; feature flags in the shader, not duplicated files.

### 4.2 Shader (ubershader, flags off until paid for)

`render_mode` spatial, **do not write engine-SSR-friendly opaque**. We need `hint_screen_texture` + `hint_depth_texture`, which forces the transparent pass. **Leave Environment SSR off** while this material is in the frame ([Godot docs](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html), [issue 90094](https://github.com/godotengine/godot/issues/90094), [proposal 7274](https://github.com/godotengine/godot-proposals/discussions/7274)).

```
#define WATER_SSR          // custom ray march, v1 on, cheap step count
#define WATER_REFRACTION   // v1 on
#define WATER_FOAM         // v1 on
#define WATER_CAUSTICS     // v1 on
#define WATER_RIPPLE_RT    // v1 on
// #define WATER_PLANAR     // stage 2, samples planar_tex
// #define WATER_FLOWMAP    // stage 2
// #define WATER_GERSTNER   // stage 3 vertex
// #define WATER_FFT        // stage 4 vertex / sample
// #define WATER_UNDERWATER // stage 3 camera volume
```

**Uniforms (v1 live, later reserved).** Group them so the inspector stays readable.

| Group | Uniform | v1 | Later |
| --- | --- | --- | --- |
| Colour | `shallow_color`, `deep_color`, `absorption_color`, `fresnel_color` | yes | same |
| Colour | `depth_meters`, `beer_law` | yes | same |
| Surface | `normal_a`, `normal_b` (sampler2D) | yes | same |
| Surface | `normal_scale_a/b`, `normal_scroll_a/b`, `normal_strength` | yes | flow map distorts UVs |
| Surface | `roughness`, `specular` | yes | same |
| Refraction | `refract_strength`, `refract_max` (depth fade so far objects do not smear) | yes | IOR later |
| Foam | `foam_color`, `foam_depth`, `foam_noise`, `foam_noise_scale` | yes | flow / Gerstner peak foam |
| Caustics | `caustic_tex` (2D or 2DArray), `caustic_scale`, `caustic_strength`, `caustic_speed` | yes | bed decal pass |
| Reflection | `ssr_steps` (12–24), `ssr_travel`, `ssr_mix`, `ssr_edge_fade` | yes | better march |
| Reflection | `planar_tex` | bound black / unused | stage 2 |
| Interaction | `ripple_tex`, `ripple_strength`, `ripple_rect` (XZ AABB → UV) | yes | same |
| Reserved | `flow_map`, `flow_strength` | default blank | stage 2 |
| Reserved | `wave_displace_tex` | default blank | Gerstner/FFT |
| Globals | `wind_dir`, `wind_strength`, `wetness_clock` | via shader globals, like RTV | rain ripples |

Fragment, in order:

1. Dual scrolling normals, unpack, mix. Add `ripple_tex` slope.
2. Reconstruct **scene depth** at refracted `SCREEN_UV`; convert to world; `water_depth = water_y - bed_y`. Handle Forward+ NDC z `[0,1]` (Compatibility would need `depth * 2 - 1` — keep a comment, do not ship a compat water path).
3. **Absorption:** `screen - absorption_color * beer(depth)` then lerp toward `deep_color`. This is the Malido trick ([CC0 shader](https://godotshaders.com/shader/absorption-based-stylized-water/)).
4. **Caustics:** sample at **bed XZ**, not surface XZ, so patterns sit on stones. Fade by depth and by `NdotL` of the sun. Two scaled layers, subtractive mix.
5. **SSR:** reflect view about the mixed normal, march in view space against `DEPTH_TEXTURE`, fade at screen edge and on miss. Miss falls through to the **ReflectionProbe** via a low roughness / high specular write *or* a cubemap mix. Do not enable Environment SSR.
6. **Fresnel** to `fresnel_color` / sky.
7. **Foam** where `water_depth < foam_depth`, broken up by noise. No hard ring.
8. Write `ALBEDO` as the composed colour, `ALPHA` near 1 (we already sampled the screen — treat as “opaque composite” so sorting fights lily pads less). `ROUGHNESS` low. Do not put the bed in `EMISSION` except a tiny caustic boost.

Vertex v1: almost none (a millimetre sine is optional). Leave `VERTEX.y +=` behind a `WATER_GERSTNER` flag.

### 4.3 Textures

| Map | Spec | Source plan |
| --- | --- | --- |
| `normal_a`, `normal_b` | 1K or 2K, OpenGL, seamless, small chop | Procedural FBM or CC0 (ambientCG / similar). Not photogrammetry swell. |
| `foam_noise` | 512–1K cellular | Procedural or CC0 noise. |
| `caustic_tex` | 1K tile or 16-slice array | Prefer **procedural Voronoi interference** in v1 (no asset). Else Calinou’s [CC0 caustics](https://opengameart.org/content/caustic-textures). |
| `ripple_tex` | 256² R16F runtime | WaterBody. |
| `flow_map` | RG, authored | Empty in v1. Canal later. |
| HDRI | optional | Probe currently sees the procedural sky. A Poly Haven CC0 HDRI would help reflections; not required for v1. |

Art desk: only if a painted foam/caustic is wanted. Do not generate placeholder maps.

### 4.4 Reflections, v1 choice

| Path | Use |
| --- | --- |
| ReflectionProbe, box projected, on the pond AABB | Always-on fallback. Update rarely. Captures willow / houses when they are off-screen. |
| Custom SSR in the water shader | Hero glints: jelly, lamps, bridge, sky band. 12–24 steps. |
| Engine Environment SSR | **Off.** Fights `hint_screen_texture`. |
| Planar camera | Stage 2, **small ponds only**, half-res, clip below the plane. This is what will make the jelly’s reflection match the concept. |

v1 is probe + cheap custom SSR. Budget the planar camera as a child node that stays disabled so stage 2 is a flag, not a rewrite.

### 4.5 Caustics and foam

- Caustics are **projected onto the reconstructed bed**, mixed into the refracted colour. That reads through the water (concept: stones and pads).
- Stage 2 can add a **Decal** or a second bed material so caustics still show from underwater. Leave a `caustic_decals: bool` on the profile.
- Foam is depth + noise only. No mesh ribbon. Shoreline moss stays on the terrain shader.

### 4.6 Interaction API (do not put this in `jelly.gd`)

```
class_name WaterBody
signal body_entered_water(body, pos, speed)
signal body_exited_water(body, pos)

func impulse(world_pos: Vector3, velocity: Vector3, radius: float) -> void
func sample_height(world_pos: Vector3) -> float   # rest Y + ripple (+ waves later)
func depth_at(world_pos: Vector3) -> float
func is_submerged(world_pos: Vector3, radius := 0.0) -> bool
```

v1 `sample_height` = plane Y + ripple sample + optional millimetre sine. Callers (jelly, Bulrush, thrown bodies, rain) never branch on shader internals.

Ripple field: **256² ping-pong height** over the pond AABB.

- Preferred: Godot **compute** ripple (same idea as the official [water_plane demo](https://github.com/godotengine/godot-demo-projects/tree/master/compute/texture/water_plane), MIT). Forward+ / RenderingDevice only — our Windows target.
- Fallback if compute is awkward on 4.8-dev6: a SubViewport drawing additive blobs into a damping shader. Same `ripple_tex` slot.
- `impulse()` stamps a blob scaled by `velocity.length()` and `radius`. Wading (Bulrush) stamps every few metres of travel at low energy. A thrown jelly stamps once on impact.
- `GPUParticles3D` splash when `speed` exceeds a threshold (enter / throw). Small count (~24). No fluid sim.

Land jellies still bounce at the rim until a later swim stage. Water species keep using `sample_height()` instead of `GardenLayout.pond_surface`.

Rain: the same ripple RT, a few random impulses per second while `weather == rain`. Do not spawn a second system.

## 5. Roadmap (same material, same mesh, same API)

| Stage | Add | Do not change |
| --- | --- | --- |
| **v1** | Dual normals, depth absorption, screen refraction, probe + cheap SSR, depth foam, bed caustics, ripple RT, splash particles | Profile fields, `WaterBody` API, plane mesh, world XZ UVs |
| **2** | Flow map on the canal; **planar reflection** camera for the hero pond (half-res, disabled when the camera is far); wetness darkening on stones / feet; more splash / drip-off (Pen Pen) | Uniform names. Bind `planar_tex` and `flow_map` that already exist. |
| **3** | 2–4 Gerstner tones behind `WATER_GERSTNER`; better SSR (interpolated step, like Malido); underwater camera volume (fog, caustic on the view, flip cull); LOD: distant bodies drop SSR and ripples | `sample_height()` adds Gerstner so waders stay on the surface |
| **4** | FFT / Tessendorf only if a Vale *ocean* appears ([2Retr0](https://github.com/2Retr0/GodotOceanWaves), [tessarakkt](https://github.com/tessarakkt/godot4-oceanfft), both MIT). Shoreline SWE ([REBOOT16](https://reboot16.itch.io/godot-rsw), MIT) only if we need breaking waves on a beach | Pond profiles stay on Gerstner/normals. FFT is a third profile, not a rewrite of v1. |

Wave Race’s lesson sits in stage 2–3: **wakes are heightfield impulses**, reflections are a second camera or a strong env-map, buoyancy reads `sample_height()`. Pen Pen’s lesson is stage 2 particles + a wetness mask. RTV’s lesson is already v1 (Godot lake, reflection toggle, weather globals).

## 6. Performance and platform

Windows PC, Forward+, Vulkan (RTV also ships D3D12; we follow whatever 4.8-dev6 uses on Windows). Floor: **1080p 60**. Comfortable: 1440p on a mid GPU (RTX 2060 class), in line with how RTV treats Water Reflection as *low* cost.

| Item | Budget |
| --- | --- |
| Water shader (garden pond on screen) | ≤ 1.0 ms at 1080p |
| Custom SSR | 12 steps default, 24 high |
| Ripple RT | 256², one dispatch / viewport blit per frame, only if someone is near |
| Splash particles | ≤ 64 live |
| ReflectionProbe | 128³ or 256³, update ≤ 0.5 Hz or on teleport |
| Planar cam (stage 2) | 50% res, culled below the plane, **one** live camera in the loaded world |
| Distant / Vale LOD | no screen texture, no ripple, albedo + probe |

Notes:

- **Do not turn on Environment SSR, SSIL, or volumetric fog just to make water pretty.** Probe + custom SSR is cheaper and does not black out refraction ([issue 93725](https://github.com/godotengine/godot/issues/93725)).
- MSAA 2× is already on. Custom SSR in the water shader is compatible. Engine SSR is happier with TAA — another reason to leave it off.
- Shader compile stutters are a Godot 4 fact (RTV players hit this). Keep feature flags as `#define` baked per-profile, not runtime branches that explode variants.
- Only the **loaded world’s** hero water runs full quality. Nested worlds do not keep a hidden planar camera warm.
- Compute ripples need RenderingDevice (Forward+). If a future Compatibility shipping target appears, fall back to the SubViewport blob path; the uniform stays `ripple_tex`.

## 7. Open-source Godot 4 water (licences)

Study and, where MIT/CC0, reuse ideas or snippets. Prefer an **original PetalWild shader** with our uniform names so we are not stuck with someone else’s inspector. Do not import GPL.

| Project | Licence | Use |
| --- | --- | --- |
| [Malido — Absorption Based Stylized Water](https://godotshaders.com/shader/absorption-based-stylized-water/) | **CC0** (code; images not) | Closest v1 recipe: beer-law absorption, dual normals, optional SSR, player waves, caustics. Read it. Rewrite into `WaterProfile`. |
| [marcelb/GodotSSRWater](https://github.com/marcelb/GodotSSRWater) (AssetLib 2152) | **MIT**, Godot 4.3+ / 4.4.1 | Transparent-surface SSR + fake refraction. Steal the march, not the demo scene. |
| [Binbun Godot Water](https://binbun3d.itch.io/godot-water-shader) | **CC0** | World-space caustics, foam, compat depth warning. Good comment on NDC z. |
| [LesusX/Water-Shader](https://github.com/LesusX/Water-Shader) | **MIT** | Gerstner + caustics + foam. Stage 3 reading. |
| [godot-demo-projects `compute/texture/water_plane`](https://github.com/godotengine/godot-demo-projects/tree/master/compute/texture/water_plane) | **MIT** | Ripple heightfield on RenderingDevice. v1 interaction. |
| [KipJM/smart_planar_reflector](https://github.com/KipJM/smart_planar_reflector) | **MIT** | Stage 2 planar cam, dynamic near plane. |
| [RisingThumb/gd_planar_reflection](https://github.com/risingthumb/gd_planar_reflection) (AssetLib 2930) | **MIT** | Simpler planar. Same stage. |
| [2Retr0/GodotOceanWaves](https://github.com/2Retr0/GodotOceanWaves) | **MIT** | FFT ocean. Stage 4 only. |
| [tessarakkt/godot4-oceanfft](https://github.com/tessarakkt/godot4-oceanfft) | **MIT** | FFT + CDLOD + buoyancy. Stage 4. |
| [REBOOT16 shoreline / SWE](https://reboot16.itch.io/godot-rsw) | **MIT** code, CC0 assets, Godot 4.7+ | Breaking shore. Not a garden pond. |
| Calinou [caustic textures](https://opengameart.org/content/caustic-textures) | **CC0** | If procedural caustics look cheap. |
| Crest, Unity water, RTV PCK | various / proprietary | **Do not vendor.** |

Godot still has **no built-in WaterBody** in 4.8-dev6. Compositor effects can move underwater post to a callback later; v1 stays in the surface shader.

## 8. Open questions for the owner

1. **Second reference.** Is *Pen Pen TriIcelon* the intended title (~75%)? If you meant “the water racer”, we should study **Wave Race: Blue Storm** instead and keep Pen Pen as interaction-only.
2. **Bowl vs plane.** Recommend plane + terrain basin, which matches the concept and unlocks planar reflections. Confirm we can drop the current bowled mesh.
3. **v1 reflection bar.** Probe + 12-step SSR, with planar camera in stage 2. Or pay for planar on the parish pond in v1 (extra camera, half-res).
4. **Swim / underwater.** Pen Pen puts the camera in the volume. v1 only does wading + splash. When should a jelly fully submerge?
5. **Caustics on moving bodies** (jelly, pads) vs bed only?
6. **City-park canal flow.** v1 still water. Is a painted flow map wanted for Grove Park in stage 2?
7. **HDRI.** Procedural sky makes probe reflections bland. Approve a CC0 Poly Haven sky?
8. **Rain ripples** on the same RT as character impulses — yes/no?
9. **Compat / llvmpipe.** Windows Forward+ only, or must water degrade on Compatibility?

## 9. Sources

- Road to Vostok: [site](https://roadtovostok.com/), [game page](https://roadtovostok.com/game), [Public Demo 1 v2](https://www.youtube.com/watch?v=2HePkuTN6hs), [PC settings](https://www.switchbladegaming.com/road-to-vostok/best-pc-settings/), [Peter’s Immersion](https://modworkshop.net/mod/56778), public architecture notes at [dwoodruff83/RoadToVostokMods](https://github.com/dwoodruff83/RoadToVostokMods) (script *names* only; not a source).
- Pen Pen TriIcelon: Wikipedia, HG101, IGN 1999, GameVortex, Retro Replay (links in §2.2).
- Wave Race: Aguas, IGN Blue Storm, GamesFirst (links in §2.3). Digital Foundry / John Linneman on Wave Race 64 as early GPU wave simulation is the usual secondary cite.
- Godot: [screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html), [reflection probes](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/reflection_probes.html), [compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html), issues [90094](https://github.com/godotengine/godot/issues/90094), [93725](https://github.com/godotengine/godot/issues/93725), proposal [7274](https://github.com/godotengine/godot-proposals/discussions/7274).
- Technique background (not to implement in v1): Tessendorf *Simulating Ocean Water*; GPU Gems ch. 1 Gerstner; Sea of Thieves water GDC talks; Jeschke et al. *Water Surface Wavelets*.
- Shaders / addons: §7.

PetalWild files this plan is written against: `shaders/water.gdshader`, `scripts/world/dressing.gd` `_water`, `scripts/world/layout.gd` pond helpers, `scripts/world/atmosphere.gd`, `scripts/creatures/jelly.gd` `_stand_y`, `project.godot`, `docs/ENGINE_VERSION.md`.

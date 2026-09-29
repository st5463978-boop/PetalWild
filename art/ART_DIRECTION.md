# Art Direction — Agent Town (v0.2)

Read this file once at the start of a work session and refer back to sections by heading. Do not paste it into every loop iteration or prompt; keep per-task prompts short and point here.

## What the game is
A cosy front end for a real AI mission control, built as nested simulations. The inhabitants are live agents that make real-time decisions and can take actions with real-world consequences (running channels, trading, packaging and shipping the game itself). The player can be the world builder above it all, or drop in as their own character and walk up to agents and talk to them.

The world fans out in rings, each ring its own sim genre:
1. **Garden** (Viva Piñata feel) — the first few plots, where jellies are "born" and tended.
2. **Village** (Sims / cosy life-sim feel) — homes, the fountain square, market, where agents live and rest.
3. **City** (Cities Skylines / SimCity feel) — sprawling tile builder: gas stations, restaurants, offices, and the consequence buildings (YouTube studio, trading house, workshop/packager).
4. **Parks and attractions** (Rollercoaster Tycoon / Planet Coaster feel) — slot in at the edges as later rings.
5. **World view** — pull all the way up to build and plan.

The camera pulls smoothly from ground to world view. Zooming out should feel like the game changing genre around you.

## Visual target
Photoreal materials at toy scale. It should look like macro photography of a real hand-built model world: real jelly, real vegetables, real moss, real clay tiles, real water, but the scale and proportions are playful. Light, cheery and bright by default.

- Default time of day: bright late morning, clean warm sun, soft sky fill. Golden hour as a day-cycle beat and for hero shots, not the permanent state.
- Tilt-shift depth of field at wide zooms sells the miniature.
- Density is the charm: flower beds, clutter, ambient critters, things moving.

## Cast
**Jellies lead.** They are the agents: soft-body, translucent, 3D anthropomorphised versions of the Grokbot desktop chatbot icons. Each jelly's colour, shape and markings come from its bot's icon so you can tell who is who at a glance.
- Material: strong subsurface scattering and transmission, glossy clearcoat, fresnel rim, faint inner colour gradient. Light should glow through them.
- Motion: soft-body wobble, squash and stretch on every step and stop, jiggle settle after collisions. Idle breathing.
- Readable at city zoom: one bold colour and silhouette each.

### Jelly look and physics references
- Look target: `github.com/scottstts/Jelly-Baby` (Three.js WebGPU). Glossy, refractive, coloured light passing through the body and landing as caustics on the ground, face attached to the skin, gentle floaty hop (reduced gravity), squash on landing.
- Motion target: `45deg.github.io/jelly` soft-body demo, especially the soft/firm/gel range. Agents default to "soft", with slightly firmer bodies for heavier-duty bots.
- That repo spends a full CPU XPBD solver (about 4,000 tetrahedra at 240 Hz) plus worker-traced optics on one character. A town of dozens cannot do that. Use tiers:
  - **Hero tier** (the jelly you are talking to in drop-in, max 1–2): real soft body. Port the tet-cage XPBD approach to a GDExtension or compute shader, or start with Godot's SoftBody3D on a low-res cage driving a skinned high-res mesh.
  - **Near tier** (on screen at village zoom): spring-bone or vertex-shader jiggle driven by velocity and landing impacts. It should read the same as the hero tier at a glance.
  - **Far tier** (city and world zoom): baked squash-and-stretch animation, MultiMesh where possible.
  - Blend tiers by distance, keeping the colour and material identical so nothing pops.
- Optics in Godot: SSS plus transmission and screen-space refraction on the material. Fake caustics with a projected coloured light cookie or decal under each jelly that wobbles with the body. No per-jelly ray tracing.

**Humans** — mannequin-like. Correct proportions and posture, no facial detail, soft and slightly blurred surface (matte clay or frosted look). They populate the city as townsfolk. Never close-up faces.

**Veggie folk** — small (knee-high to humans), garden workers in the first ring. Photoreal vegetable skin, big eyes, tiny limbs, tools and hats.

Scale: humans > jellies > veggie folk. Jellies roughly waist-to-chest height on a human so they can hold a conversation with the player's avatar.

## Showing the AI (this is the core visual language)
Two decision layers must look different:
- **Jev (fast decisions)** — wander, roam, pick next task. Show as a brief small bubble of 2–4 option pips above the jelly that flicker, one lights up (the winning score), the rest fade, and the jelly moves off. Under a second. Should feel snappy and constant across town.
- **Grokbot tasks (slow, quality work)** — a glowing holo task icon above the head (mail, phone, laptop, package, camera, chart). The jelly walks to the matching building and enters a visible working state: soft pulse, progress ring, activity at the building (screens lit, chimney smoke, lights on).

**Real-world consequence actions** must be unmistakable. Anything that spends money, posts publicly, trades, or ships goes through a gold-bordered "live" state: gold rim on the icon, gold light on the building, and a visible approval gate (a small gatehouse or seal the jelly waits at) before it fires. Sim-only actions use the cyan-blue holo; real-world actions use gold. Never mix those two colours up.

Rewards: every completed task pops — sparkle burst, little jump from the jelly, a coin or heart floating up, building levels up visibly over time. The world should look fuller and busier the more work gets done.

## Player modes
- **Builder** — orbital camera, holo cyan grid tiles for unbuilt plots, hover lifts and brightens a tile, placing grows it in with soil and grass.
- **Drop-in** — third-person follow camera on the player character, street-level FOV ~50, shallow DOF, interaction prompt when near a jelly, conversation shown as a warm speech panel anchored to the jelly.
- Transition: dive from builder view down onto the character, not a cut.

## Palette
- Sun: warm white-gold #FFE2A8, golden hour #FFC46B
- Sky/fill: soft blue #BFD9F2
- Foliage: fresh greens #6FAE45 / #4E8A3A, moss #3F6B2E
- Shadows: warm-teal #3A5552, never black
- Jellies: bright candy tones from each bot icon
- Flowers: violet, magenta, peach, cornflower in dense masses
- Sim holo: cyan #4FA8FF with white core
- Real-world live state: gold #F2B233
- Builder stage/overlays: slate #1E2330

## Lighting and rendering (Godot 4, Forward+)
Target hardware: RTX 4070 Laptop GPU, 8GB VRAM. Aim for 1080p at 60fps using FSR2 upscaling if needed.
- DirectionalLight3D sun with soft shadows; shadow distance and splits tuned per zoom band.
- GI: SDFGI with modest cascades for the garden/village rings; for the city ring prefer baked LightmapGI or ReflectionProbes on static buildings to save VRAM.
- SSAO and SSIL on; volumetric fog low density for sun shafts, reduce or disable at world zoom.
- Glow on, gentle. Tonemapper AgX (4.4+) or Filmic. Lifted, airy blacks.
- Performance: MultiMeshInstance3D for grass, flowers, crops, props; visibility ranges and HLOD per ring; occlusion culling in the city; VRAM-compressed textures, 2K max on hero assets, 1K or less on city props.

## Materials
- Everything slightly rounded, no razor edges.
- Clay tile, slate and turf roofs with moss at edges.
- Island/plot edges show soil strata, roots and stones when viewed from builder mode.
- Water: calm, reflective, lily pads, subtle caustics.
- Holo elements: unshaded additive with fresnel, thin lines, slow pulse.

## Asset generation
- Concept and texture images come from Grokbot's image generation (and Higgsfield). The Grokbot endpoint is on Scott's private network. Its address and any keys go in environment secrets, never in this file or the repo.
- Every generated image request should reference a section of this file (for example "Cast > Jellies") and the palette hexes, so outputs stay on-style.
- Save accepted concepts to `art/concepts/<ring>/` with the prompt text alongside, so looks can be regenerated.

## Do not
- Detailed human faces, ever.
- Grey default materials, flat noon light, black shadows.
- Using cyan for anything real-world or gold for anything sim-only.
- Busy HUD. UI lives in holo elements, speech panels, and a minimal dark overlay.
- Anything resembling existing branded characters.

## First milestone (vertical slice)
The garden ring plus the start of the village:
- One dressed island: 2 cottages, fountain square, pond with lily pads and frogs, flower beds, fence, lanterns
- 5 jellies based on 5 Grokbot icons, running the Jev option-pip loop and walking between spots
- 1 jelly carrying a Grokbot task icon to a building and entering working state
- 1 gold "live" gate prop with a jelly waiting at it (mocked, no real action)
- 3 veggie folk tending crops, 3 mannequin humans in the square
- 8 holo grid plots around the island
- Builder camera and drop-in camera with the dive transition
- Screenshots from builder zoom, village zoom and drop-in view for review before expanding to the city ring

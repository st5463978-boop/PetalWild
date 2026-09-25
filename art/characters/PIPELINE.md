# Veg villager pipeline

CPU-only Blender script → glTF. Look rules are in `art/ART_DIRECTION.md`. This file is only the build steps.

## Conventions

- Godot **4.8-dev6**. Do not bump it.
- **1 Blender unit = 1 metre.**
- **Cast > Veggie folk** are knee-high to a human (about 0.45 m). Photoreal vegetable skin, big eyes, tiny limbs, tools and hats. They are not jellies.
- **Cast > Jellies** are the agents: waist-to-chest on a human (about 1.0–1.2 m), candy colours from the bot icon, SSS and transmission. The carrot mesh at 1.18 m with `shaders/veg_jelly.gdshader` is a near-tier jelly body, not a finished veggie-folk worker.
- Scale order: humans > jellies > veggie folk. See **Cast**.
- Face the character **+Y in Blender** (front view). The glTF exporter writes Y-up; the preview scene aims a camera at the imported face.
- Sources live in `art/characters/` (that folder has a `.gdignore` so Godot does not try to import the `.blend`). Exported `.glb` lives in `assets/characters/`. Preview-only Godot files live in `art_preview/`. Do not edit `scenes/main.tscn`, `scenes/garden.tscn`, or gameplay scripts to preview a mesh.
- Jelly deformation is a **Godot shader**, not a Blender soft-body bake. The mesh stays firm. The shader wobbles vertices from `move_velocity`.

## Build the carrot

Blender 4.2 LTS (bundled Python) on this VM:

```bash
~/.local/blender/blender-4.2.9-linux-x64/blender -b -P art/characters/build_carrot.py
```

Or `art/characters/build.sh`. Writes:

| output | what |
| --- | --- |
| `assets/characters/carrot.glb` | mesh, armature, `idle` + `walk` |
| `art/characters/carrot.blend` | generated source |
| `art/characters/textures/carrot/` | albedo high/low |
| `art/characters/previews/carrot_*.png` | Cycles-CPU stills |
| `art/characters/build_stats.json` | tri count, height, action names |

Target: **under 5k tris** for the whole character so many can stand on a garden tile.

## Preview in Godot

```bash
DISPLAY=:1 PETALWILD_ART_SHOT=1 ./tools/run.sh res://art_preview/carrot_preview.tscn
```

Headless import / compile check (no window):

```bash
"$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64" --headless --path . --import --quit
```

The preview scene instances the glb twice (idle + walk), applies `shaders/veg_jelly.gdshader` to the jelly mesh, and drives `move_velocity` from `art_preview/carrot_actor.gd`. Gameplay actors are unchanged.

## Next villager (turnip, pea-pod, tomato, leek)

Copy `build_carrot.py` to `build_<id>.py` and change the `SPECIES` block plus the body profile. Keep the armature names (`Root`, `Body`, `Head`, `Arm_L`, `Arm_R`, `Leg_L`, `Leg_R`, `LeafTop`) and the action names (`idle`, `walk`) so `carrot_actor.gd` can load any of them.

| villager | body | notes |
| --- | --- | --- |
| carrot (this file) | chubby inverted teardrop, orange | two leafy stems |
| turnip | squat sphere, purple-white | leafy top, short legs |
| pea-pod | three stacked peas or one long pod | vine arms, no leaf bone motion needed beyond a sway |
| tomato | sphere, saturated red | straw hat is a separate mesh, not skinned to `LeafTop` |
| leek | tall stacked cylinders, cream → green | `LeafTop` is the ribbon crown; lengthen `Head` |

Shape recipe:

1. Replace `BODY_PROFILE` with `(radius, z)` rings. Spin it with `lathe()`.
2. Retint `SPECIES` colors. Bake new albedos (`bake_body_albedo` / `bake_leaf_albedo`).
3. Reuse `capsule()` for stubby limbs. Parent face parts to `Head`, foliage to `LeafTop`.
4. Keep weights in `jelly_weights()` keyed off height and `|x|` so arms/legs still peel off the body.
5. Export to `assets/characters/<id>.glb`. Point `art_preview/carrot_actor.gd` `glb_path` at it, or duplicate the preview scene.

Do not add a factory or a species registry until a second villager actually exists.

## Texture LOD

Albedos are painted by the build script (no Substance, no paid baker).

| variant | body | leaf | use |
| --- | --- | --- | --- |
| high | 512 | 256 | hero / close-up, baked into the glb |
| low | 128 | 64 | crowds, far garden tiles |

Guidance when you add more maps:

- **Close-up (LOD0, < 6 m):** 512 body, 256 leaf. Keep roughness/SSS in the Godot shader, not in a 1k ORM pack.
- **Garden crowd (LOD1):** 128 body. The jelly shader already supplies rim and wobble; a 128 orange gradient reads at tile scale.
- **Town / city billboard (LOD2):** skip the glb. A card or the existing procedural veg body is enough.
- Do not ship 1k or 2k character albedos. These bodies are smooth jelly; extra texels do not add readable detail.
- Vertex color is enough for blush. A second UV set is not needed.
- If a later villager needs a printed pattern (pea specks, tomato hat band), keep it on its own 256 atlas and leave the jelly body on the gradient.

Godot import: leave `meshes/generate_lods=true` on the `.glb.import` (the Kenney meshes already do this). Do not extract materials unless you are editing them in-editor.

## Shader contract

`shaders/veg_jelly.gdshader` is preview-only until PETAL_03 / PETAL_04 wire it to a gameplay actor.

Uniforms the actor must set:

- `deep_color`, `shallow_color`, `rim_color` — species palette
- `move_velocity` — world-space metres/second from the last frame
- `wobble_amount` — idle shimmer; keep ≤ 0.05 or the silhouette melts

Leaves, eyes, and mouth stay on the imported principled / standard materials.

## What this lane does not do

- Does not push `main`.
- Does not edit garden sim, HUD, or `project.godot`.
- Does not call image-generation APIs or Higgsfield.
- Does not touch Havenbrook.

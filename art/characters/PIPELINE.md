# Veg villager pipeline

CPU-only Blender script → glTF. Look rules are in `art/ART_DIRECTION.md`. This file is only the build steps.

## Conventions

- Godot **4.8-dev6**. Do not bump it.
- **1 Blender unit = 1 metre.**
- **Cast > Veggie folk** are knee-high to a human (about 0.45 m). Photoreal vegetable skin, big eyes, tiny limbs, tools and hats. They are not jellies.
- **Cast > Jellies** are the agents: waist-to-chest on a human (about 1.0–1.2 m), candy colours from the bot icon, SSS and transmission. `shaders/veg_jelly.gdshader` is the near-tier jelly material. Do not put it on veggie folk.
- **Cast > Humans** are faceless clay mannequins, about 1.7 m. `art/characters/build_human.py`.
- Scale order: humans > jellies > veggie folk. See **Cast**.
- Face the character **+Y in Blender** (front view). The glTF exporter writes Y-up; the preview scene aims a camera at the imported face.
- Sources live in `art/characters/` (that folder has a `.gdignore` so Godot does not try to import the `.blend`). Exported `.glb` lives in `assets/characters/`. Preview-only Godot files live in `art_preview/`. Do not edit `scenes/main.tscn`, `scenes/garden.tscn`, or gameplay scripts to preview a mesh.
- Jelly deformation is a **Godot shader**, not a Blender soft-body bake. The mesh stays firm. The shader wobbles vertices from `move_velocity`.

## Build

Blender 4.2 LTS (bundled Python) on this VM. `art/characters/build.sh` builds carrot, tomato, leek, then the human.

One villager:

```bash
~/.local/blender/blender-4.2.9-linux-x64/blender -b -P art/characters/build_carrot.py -- tomato
~/.local/blender/blender-4.2.9-linux-x64/blender -b -P art/characters/build_human.py
```

| id | prop | output |
| --- | --- | --- |
| carrot | watering can on `Arm_L` | `assets/characters/carrot.glb` |
| tomato | straw hat on `Head` | `assets/characters/tomato.glb` |
| leek | rake on `Arm_R` | `assets/characters/leek.glb` |
| human | none, no face | `assets/characters/human.glb` |

Each folk run also writes `art/characters/<id>.blend`, `textures/<id>/`, `previews/<id>_threequarter.png`, and `build_stats_<id>.json`. The mesh is sculpted near 1.18 m and scaled to 0.45 m before the actions, so bone rotations stay valid.

Target: **under 5k tris** for the whole character so many can stand on a garden tile.

## Preview in Godot

```bash
DISPLAY=:1 PETALWILD_ART_SHOT=1 ./tools/run.sh res://art_preview/carrot_preview.tscn
```

Headless import / compile check (no window):

```bash
"$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64" --headless --path . --import --quit
```

The preview scene lines up the human and the three folk. `art_preview/carrot_actor.gd` applies `shaders/veg_skin.gdshader` to the body mesh only. The human stays on the imported clay material. Gameplay actors are unchanged.

## Next villager

Add a block to `FOLK` in `build_carrot.py` (`prop` is `can`, `hat`, or `rake`) and a `(radius, z)` profile. Keep the armature names (`Root`, `Body`, `Head`, `Arm_L`, `Arm_R`, `Leg_L`, `Leg_R`, `LeafTop`) and the action names (`idle`, `walk`).

| villager | body | prop |
| --- | --- | --- |
| carrot | chubby inverted teardrop, orange | watering can |
| tomato | sphere, saturated red, speckled albedo | straw hat |
| leek | tall thin column, cream at the root, green at the crown | rake |
| turnip | squat sphere, purple-white | hat or none |
| pea-pod | three stacked peas or one long pod | none |

`fit_layout()` places eyes and limbs from the face radius, so a thinner body does not keep the carrot's arm span.

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
- Do not ship 1k or 2k character albedos. These bodies are smooth; extra texels do not add readable detail.
- Tomato speckles are painted into the 512 albedo. A second UV set is not needed.

Godot import: leave `meshes/generate_lods=true` on the `.glb.import` (the Kenney meshes already do this). Do not extract materials unless you are editing them in-editor.

## Shader contract

Veggie folk use `shaders/veg_skin.gdshader` (albedo, roughness, a little SSS, a tiny breath). Leaves, eyes, mouth, hats, and tools stay on the imported materials.

`shaders/veg_jelly.gdshader` is the near-tier jelly material, for **Cast > Jellies** only. Its actor sets `deep_color`, `shallow_color`, `rim_color`, and `move_velocity`. Keep `wobble_amount` ≤ 0.02 or the silhouette melts. Jellies are blocked until the five Grokbot icons exist.

## What this lane does not do

- Does not push `main`.
- Does not edit garden sim, HUD, or `project.godot`.
- Concept art may use Grokbot or Higgsfield. Addresses and keys stay in environment secrets, never in the repo.
- Does not touch Havenbrook.

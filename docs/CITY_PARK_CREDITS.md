# City Park credits and licences

All of this layer is CC0, original PetalWild, or already in the tree. Nothing paid.

## Code (original, this pass)

Park scene, cameras, shaders, and procedural meshes under `scripts/park/`, `scenes/city_park.tscn`, `shaders/park_*.gdshader`.

Ring-orbit behaviour restored from `game/camera/garden_camera.gd` (commit `c140089` / `ac8fdbe`). Square-tile idea restored from `game/world/terrain_field.gd` and `scripts/presentation/grove_view.gd`.

## Textures

| Asset | Author | Source | Licence | Use |
| --- | --- | --- | --- | --- |
| Leafy Grass 1K | Charlotte Baglioni | https://polyhaven.com/a/leafy_grass | CC0 | Lawn |
| Flower Scattered Dirt 1K | Dimitrios Savva | https://polyhaven.com/a/flower_scattered_dirt | CC0 | Soil / sand tint |
| Cobblestone Floor 13 1K | Poly Haven | https://polyhaven.com/a/cobblestone_floor_13 | CC0 | Streets, flagstone |
| Gravel 1K | Poly Haven | https://polyhaven.com/a/gravel | CC0 | Park paths |
| Rocks Ground 02 1K | Poly Haven | https://polyhaven.com/a/rocks_ground_02 | CC0 | Pond rim, bed edging |
| Brick Wall 001 1K | Poly Haven | https://polyhaven.com/a/brick_wall_001 | CC0 | Townhouses, clock tower |
| Roof 09 1K | Poly Haven | https://polyhaven.com/a/roof_09 | CC0 | Roofs, gazebo |
| Wood Planks 1K | Poly Haven | https://polyhaven.com/a/wood_planks | CC0 | Gazebo, stall, benches |
| Rusty Metal 02 1K | Poly Haven | https://polyhaven.com/a/rusty_metal_02 | CC0 | Lamp posts, railings |
| Forest Leaves 02 / 03 | Rob Tuytel / Dimitrios Savva | already in tree | CC0 | Reserved, not on the leaf cards |
| LeafSet017 1K | ambientCG | https://ambientcg.com/view?id=LeafSet017 | CC0 | Alpha-cut foliage cards, willow curtain |
| Clock face, awning stripes | PetalWild generated (this pass) | `assets/park/generated/` | original | Clock discs, stall cloth |

ambientCG licence: https://docs.ambientcg.com/license/ (CC0).

Water surface and painted pond bed (`shaders/park_water.gdshader`, `shaders/park_bed.gdshader`) are original and follow `docs/water/WATER_PLAN.md` from PR #15. That plan is not on this branch.

Poly Haven licence: https://polyhaven.com/license (CC0).

## Meshes already in the tree

| Pack | Author | Licence | Use in this scene |
| --- | --- | --- | --- |
| Kenney Nature Kit 2.1 | Kenney | CC0 1.0 | Crops, wood bridge, pots, hanging moss |
| Kenney Foliage Pack | Kenney | CC0 1.0 | Willow strand cards (`foliagePack_leaves_002.png`) |
| Kenney Fantasy Town Kit 2.0 | Kenney | CC0 1.0 | Townhouse walls, windows, doors, roofs, chimneys, gazebo posts, clock tower |
| Asset Quest Stylized Garden demo | Melissa / Asset Quest | CC0 1.0 | Flowers, benches, terracotta planter |

## Not used

Viva Piñata, Jelly-Baby, Cities: Skylines, Nintendo, Higgsfield paid, DaVinci paid video. Quaternius Stylized Nature is CC0 but only offered as a Google Drive folder, so it is not vendored. Foliage uses ambientCG LeafSet017 and the Kenney Foliage Pack instead.

Jelly creatures and veg folk are spawn markers only. Art requests: `art_desk/requests/PETAL-08-101.yaml` … `PETAL-08-104.yaml`.

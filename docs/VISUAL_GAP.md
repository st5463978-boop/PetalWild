# Visual gap

Compared on 2026-09-22. Game shots are in `docs/screenshots/`. Targets are `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`.

The playable grove has a hedge ring, Kenney trees, a west pond and bridge, flower clumps, a blue-striped stall, a white shed with a red roof, soil and grass plots, and a paper HUD. Golden-hour, night, and rain shots change the sky. Cara stands at the stall as a carrot cone. Sunburst reads as a glossy green body with a face.

## Three largest gaps

1. **Composition and density.** The target is a sunken garden of mature hedge rooms, flower rows, vegetable beds, and a deep tree mass. The build is a gridded terrace with a hedge perimeter and a ring of stylised trees. Ground cover is thin, and the plots still read as game tiles. Owner: PETAL_05, with PETAL_13 for CC0 path and hedge meshes.

2. **Cast and stall.** The concept veg people are small authored figures among the plants. Cara is a cone with leaves. Sunburst does not yet have a strong non-spherical silhouette. The stall is a box with a stripe texture, not the built blue-and-white hut. Owners: PETAL_04 for veg people, PETAL_03 for jelly forms, PETAL_05 for the stall mesh.

3. **Light.** The concept is warm, shadowed, and hazy, with sun on the leaves. This machine renders with llvmpipe and the GL Compatibility renderer, so shadows are off. Golden hour is a sky gradient and an orange directional light, without contact shadows or sun shafts. Owner: PETAL_06, limited to what the compatibility renderer can do. Do not turn on Forward+ features that this pin cannot run.

These gaps are assigned by the executive because the local Hailo router had no device to score. See `tools/orchestration/MODEL_SELECTION.md`.

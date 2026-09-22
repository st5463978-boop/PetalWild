# PetalWild master state

Updated 22 September 2026 after the CC0 garden dressing pass.

## Build

- Active build: playable garden, Godot project at the repo root.
- Branch: `main`
- Engine: Godot `4.8.dev6.official.8898c2b3d` (see `docs/ENGINE_VERSION.md`)
- Smoke: `PETALWILD_SMOKE_OK` — 8 mature Sunpetal, Sunburst reaches repeat visitor, pollinated soil appears, save round-trip holds, trust 0 refuses, trust 4 holds without executing.
- Latest screenshots: `docs/screenshots/01_title.png` through `08_night.png`

## Working

- Title, new game, three save slots, pause, volume, reduce-motion, UI scale.
- Orbit camera, pan, zoom, focus, photo mode.
- Till, plant, water, fertilise, tend/harvest, pond scoop, home kit.
- Four plants and an ecology chain: Sunpetal → Sunburst → Thimble compost → Moonvine → Puffcap → Pegapouch in rain at night. Dewberry needs pollinated soil. Bellwisp needs Sunburst plus pools. Circlark needs a resident Bellwisp. Sapling watches garden quality.
- Grab, stretch, drop, and throw a jelly. Mood and bond change.
- Quin Hearth, Lumen Barrow, and Neeve Allium with schedules and needs. Quin opens Petal Stall after Sunburst visits. Blob can knock corn back and Quin complains.
- Havenbrook aggregate stats. Trust ledger with a Media Foundry proposal that cannot spend or publish.
- Original procedural ambience. Dummy audio device in this VM; the streams still build.
- Asset Quest CC0 plants and props are in the live garden: flower rows, grass cards, pond-bank plants, sunflowers, benches, a table, planters, and the stall umbrella. Gameplay plots are still the sim's own meshes.

## Broken or thin

- No Vulkan device here, so lighting is GL Compatibility on llvmpipe. Shadows exist; glow and depth of field do not.
- Hedges are solid blocks and trees are still trunk-plus-sphere clusters. They are not leaf meshes.
- No navigation mesh. People walk in straight lines.
- Breeding, variants, and photo depth of field are named in the design and not simulated yet.
- External tools are intentionally unwired.

## Agents

| Agent | State |
| --- | --- |
| PETAL-00 | This integration |
| PETAL-13 | Asset hunt written. The CC0 demo is now instanced in the garden |
| Research scribe | `docs/research/ARCHITECTURE_REFERENCES.md` |

Ownership: `docs/AGENT_CONTRACTS.md`.

## Assets and credits

- Sources and licences: `ASSET_PROVENANCE.md`, `docs/LICENSE_MATRIX.md`
- Higgsfield spent: 0. Balance read: 367.46 credits.

## Performance

Software GL, 1440×900, populated garden. The eight-frame capture finished in about 36 seconds on llvmpipe after the CC0 meshes were added. The debug overlay still reports FPS, process time, draw calls, and primitives during play. No separate GPU profile yet. The smoke test does not render.

## Visual comparison

Against `docs/reference/petalwild_target_garden_01.png` and `02`:

1. Hedges and trees are still primitive volumes. The flower rows are atlas cards, but the enclosing hedge is a run of green boxes and the canopies are spheres. Next: a CC0 tree and hedge kit, scaled and recolored to this palette.
2. Ground, paths, and the stall court are vertex colors and flat pavers. The concept's irregular flagstones, rich soil, and timber stall are not in the meshes yet.
3. Light is a warm directional sun on the compatibility renderer. There are no sun shafts, translucent canopy, or depth of field until a Vulkan device is available.

## Next integration

1. Bring in a permissive tree and hedge kit and replace the box hedge and sphere canopies without touching `GardenSim`.
2. Keep the plot tools, the ecology chain, and the CC0 flower rows.
3. Add a second wave of CC0 audio only with a licence file in the download.

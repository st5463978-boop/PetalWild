# PetalWild master state

Updated 22 September 2026 after integration wave 1.

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

## Broken or thin

- No Vulkan device here, so lighting is GL Compatibility on llvmpipe. Shadows exist; glow and depth of field do not.
- CC0 stylized props are staged and not instanced. The garden is still procedural.
- No navigation mesh. People walk in straight lines.
- Breeding, variants, and photo depth of field are named in the design and not simulated yet.
- External tools are intentionally unwired.

## Agents

| Agent | State |
| --- | --- |
| PETAL-00 | This integration |
| PETAL-13 | Asset hunt written, one CC0 demo staged |
| Research scribe | `docs/research/ARCHITECTURE_REFERENCES.md` |

Ownership: `docs/AGENT_CONTRACTS.md`.

## Assets and credits

- Sources and licences: `ASSET_PROVENANCE.md`, `docs/LICENSE_MATRIX.md`
- Higgsfield spent: 0. Balance read: 367.46 credits.

## Performance

Software GL, 1440×900, populated garden (hedges, trees, flowers, grass, one jelly in the close-up shot). The debug overlay reports FPS, process time, draw calls, and primitives. No separate GPU profile yet. The smoke test does not render.

## Visual comparison

Against `docs/reference/petalwild_target_garden_01.png` and `02`:

1. Foliage is instanced blobs, not leaf-level plants. The CC0 demo meshes should replace flowers, grass, and the bench.
2. The stall is boxes and a label, not a timber shop with a striped awning that sits in a stone court.
3. Light is a warm directional sun and fog, not sun shafts through a mature canopy.

## Next integration

1. Art-direct the Asset Quest demo into the garden: one material, one scale, flowers only where beds are.
2. Keep the plot tools and the ecology chain. Do not replace `GardenSim`.
3. Frame the close-up jelly and Quin in gameplay, not only in the shot script. That already works if the player presses F.
4. Add a second wave of CC0 audio only with a licence file in the download.

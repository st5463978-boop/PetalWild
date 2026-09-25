# Agent contracts

Directory ownership for parallel work. Stay inside the owned paths. Integration (`PETAL_00`) is the only lane that edits `project.godot`, `scenes/main.tscn`, and `scripts/main.gd`.

The Hailo foreman in `tools/orchestration/` is studio tooling. It must not be imported by the game. That directory is owned by the executive lane, not by a creature or town agent. System-1 choices call the Pi decide service at `HAILO_DECIDE_URL` (default `http://100.126.22.71:8766/v1/decide`; MagicDNS `http://piai-1:8766/v1/decide` is the same Pi), model `Qwen3-1.7B.hef`. See `tools/orchestration/STATUS.md`.

| Lane | Owns | Does not touch |
| --- | --- | --- |
| PETAL_00 | `scripts/main.gd`, `scenes/main.tscn`, `project.godot`, `scripts/sim/`, `docs/PETALWILD_MASTER_STATE.md` | third-party zips |
| PETAL_01 | soil, water, and growth inside `scripts/sim/petal_sim.gd`, `data/plants.json` | presentation |
| PETAL_02 | `data/species.json`, ecology checks in `scripts/sim/` | jelly meshes |
| PETAL_03 | `scripts/presentation/jelly_actor.gd` | `grove_ui.gd` |
| PETAL_04 | `scripts/presentation/person_actor.gd`, `data/residents.json`, `data/dialogue.json` | economy prices |
| PETAL_05 | dressing in `scripts/presentation/grove_view.gd`, `scripts/presentation/prop_kit.gd` | sim rules |
| PETAL_06 | `shaders/` | JSON catalogs |
| PETAL_07 | `scripts/presentation/grove_ui.gd` | world meshes |
| PETAL_08 | prices and shop flow in `scripts/sim/petal_sim.gd`, `data/items.json` | shaders |
| PETAL_09 | `data/venues.json` town venues | city population math |
| PETAL_10 | `scripts/presentation/camera_rig.gd` | UI theme |
| PETAL_11 | `scripts/autoload/petal_audio.gd` | models |
| PETAL_12 | `tests/` | content JSON except fixtures |
| PETAL_13 | `assets/third_party/`, `docs/research/ASSET_HUNT.md`, licence notes | gameplay scripts |
| PETAL_14 | `data/districts.json` | hero jelly physics |
| PETAL_15 | performance notes and caps in `grove_view.gd` software limits, by review only | new content |

`grove_view.gd` is shared. PETAL_05 owns dressing. Actor spawn changes need PETAL_03 or PETAL_04 review before they land.

New work branches use the prefix `cursor/` and the suffix `-5bfd`. This integration stays on `main` until a lane has something to merge.

Do not copy GPL or AGPL implementation into any of these directories. TiP-Recomp is not a source.

## Concept art

Hailo produces every PetalWild image with its built-in generator. Do not generate concept art or visual assets in this repo (no image-generation tools or APIs, and no Higgsfield).

To request art, add `art_requests/<yyyymmdd>-<short-slug>.md` with what the asset is for, the subject, the composition, the aspect ratio (`1:1`, `4:3`, `3:4`, `16:9`, or `9:16`), the number of images, and the target path in the repo. End the turn with a final-report section headed exactly `ART REQUEST` that lists those files. Hailo generates the images and returns them as attachments under `uploads/`. Move them to the target path and commit.

House style: a dreamy but photographic 3D render; a blue-green forget-me-not palette with gold trim; soft Ghibli-style veg people mixed with Grok buddies (small rounded chrome-and-teal robots) and real people; a psychedelic, agentic motif of glowing gold threads connecting stars, like Astra's logo.

Caps, Scott's own: 30 images per rolling hour and 150 per rolling day, warning at 80%. Batch requests and ask only for the images the work needs. If a request would exceed a cap, Hailo refuses it or defers it until the window rolls over.

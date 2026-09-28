# City Park / Pond

Standalone playable scene: `res://scenes/city_park.tscn`.

This restores the **square-tile garden** and **Viva Piñata ring camera** that the Hedge Hollow integration stopped booting, then dresses a city-park pond layer to match the three approved concept frames (ring overview, pond-edge golden hour, top-down builder).

## Run

```bash
# from repo root, pinned Godot 4.8-dev6
# default driver is OpenGL3 (Compatibility)
DISPLAY=:1 ./tools/run.sh res://scenes/city_park.tscn

# Forward+ on Vulkan. On a real GPU this is the look preset (SSAO, SDFGI, volumetric fog).
# This VM's lavapipe device reports itself as llvmpipe, so SDFGI and volumetric fog stay off.
DISPLAY=:1 PETAL_RENDER=forward ./tools/run.sh res://scenes/city_park.tscn
```

Or from the title screen, **City Park**.

Headless smoke (needs a display for the 3D tree, same as garden smoke):

```bash
DISPLAY=:1 PETAL_PARK_SMOKE=1 ./tools/run.sh res://scenes/city_park.tscn
# prints PETAL_PARK_OK
```

Screenshots (1920×1080):

```bash
DISPLAY=:1 PETAL_RENDER=forward PETAL_PARK_SHOT=1 \
  PETAL_PARK_SHOT_DIR=/workspace/docs/screenshots/city-park \
  ./tools/run.sh res://scenes/city_park.tscn
```

Writes `park_ring.png`, `park_builder.png`, `park_pond_edge.png`.

## Cameras

| Key | View |
| --- | --- |
| **F1** | Ring orbit (default). Viva Piñata crawl around the pond. Right-drag to orbit, wheel zoom, WASD pan, Q/E yaw. |
| **F2** | Builder. High tilt-shift overview of the square plots. |
| **F3** | Pond edge. Low golden-hour bank view. |
| **F4** | Free cam. WASD fly, right-drag look, Q/E down/up, Shift faster. |
| **C** | Cycle the four views. |
| **O** | Toggle depth of field (on by default for the pond-edge shot). |
| **P** | Save a PNG to `user://park_shots/`. |
| **Esc** | Back to the title. |

The ring rig is the high-orbit camera from `game/camera/garden_camera.gd` (`c140089` / `ac8fdbe`, pitch ~0.88 rad, auto-yaw). Hedge Hollow’s live camera (`scripts/camera/garden_camera.gd`) is the shallow 18° orbit that buried the plots.

## Time and weather

Compatible with the existing `Clock` autoload.

| Key | Speed |
| --- | --- |
| **Space** | Pause / resume |
| **1** | 1× (`Clock.scale = 6`) |
| **2** | 2× |
| **3** | 4× |

The scene boots paused at **16:30 golden**, matching the sign-off hour. Unpausing lets `Clock.weather_for` run. Lanterns brighten as the sun drops.

## What was restored (git)

Nothing deleted the tile or orbit scripts. Three commits took them off the boot path; later Hedge Hollow work hid the remaining cell squares under a meadow lid.

| SHA | What |
| --- | --- |
| `c140089` | Playable 14×10 square-cell garden, elliptical hedge ring, orbit camera. |
| `ac8fdbe` | Retune to the high diorama pose (pitch 0.9 rad, distance 19). |
| `1248380` | Kenney grove: 1.2 m tiles, title-pose ring spin (`camera_rig.gd`). |
| `af1d576` | Hedge Hollow camera wins (later 18° pitch). |
| `ac279ba` | `game/.gdignore` parks the 14×10 board. |
| `419eae2` | Boot scene back to Hedge Hollow; grove lasts about eight minutes. |
| `5699254` / `256e559` | Empty then planted cells join one meadow lid. The squares disappear. |
| `8019f1b` | Live pitch 24° → 18°. |
| `be6adc3` | HEAD of `petal/08-integration`. Bed close-up only. |

This scene does **not** re-enable `game/` as the running game. It copies the ring-orbit behaviour and draws a new square-tile park beside Hedge Hollow.

## Layout

1 m cells on a 24×24 board. Pond is a kidney bowl at the origin. Ring gravel, cardinal flagstone, cobbled street, stone-edged soil plots, gazebo, greenhouse, stall, playground, willow, townhouses and a clock tower.

Character art is still incoming: `jelly_spawn` and `veg_spawn` are ground rings, not blob stand-ins. Requests live in `art_desk/requests/PETAL-08-10*.yaml`.

## Honest gaps vs the three concepts

Sign-off frames are 1920×1080, captured with **Forward+** (`PETAL_RENDER=forward`, Vulkan). The device is lavapipe and Godot names it llvmpipe, so the software preset ran: ACES, golden-hour sun, fog, glow, SSAO. SDFGI and volumetric fog are on only when the adapter is not software. Environment SSR stays off on every GPU; water v1 fakes the sky with Fresnel. A real GPU using the same `PETAL_RENDER=forward` path gets SSAO, SSIL, SDFGI, volumetric fog, and shadows.

The approved paintings are not in `docs/reference/city-park/` (that folder is empty), so these frames are the sign-off set rather than a baked side-by-side composite.

- Foliage is alpha-cut leaf cards (ambientCG LeafSet017) with wind sway, plus Kenney Foliage Pack strands on the willow. Quaternius Stylized Nature is Drive-only and is not vendored. The willow is a trunk, leaning limbs, and a hanging card curtain, not a scanned tree.
- Plot edges are pillow-stone kerbs and corner stones on CC0 rock, over turf, soil, and gravel. The 1 m squares stay readable. They are not the concept's heavy bevelled stone photography.
- Lily pads are notched, curled meshes with a clearcoat. Flowers are an 8-petal mesh plus a yellow center. Reeds are thin cards with cattail heads. They are still generated, not `PETAL-08-103` sculpts.
- Townhouses, the clock tower, and the gazebo posts are Kenney Fantasy Town Kit modules (walls, shuttered windows, doors, overhangs, gable and point roofs) with the pack colormap. The gazebo roof is still the octagonal hip. The greenhouse and stall are still built from primitives.
- Water v1 follows the PR #15 plan: a low-roughness sheet, two scrolling normals, Fresnel sky, and sparse emissive glints aimed at the glow pass, over a separate painted pond bed. No planar reflection, no ripple simulation, no screen refraction.
- The footbridge is still four Kenney narrow decks. Railings are a short run of posts.
- Jellies and veg folk are spawn rings (`PETAL-08-101`, `102`), hidden in the sign-off frames.
- Builder view is a steep orbit, not a locked orthographic camera.

Captures: `docs/screenshots/city-park/park_ring.png`, `park_builder.png`, `park_pond_edge.png`.

## Credits

See `docs/CITY_PARK_CREDITS.md` and the root `CREDITS.md`.

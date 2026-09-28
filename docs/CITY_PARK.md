# City Park / Pond

Standalone playable scene: `res://scenes/city_park.tscn`.

This restores the **square-tile garden** and **Viva Piñata ring camera** that the Hedge Hollow integration stopped booting, then dresses a city-park pond layer to match the three approved concept frames (ring overview, pond-edge golden hour, top-down builder).

## Run

```bash
# from repo root, pinned Godot 4.8-dev6
DISPLAY=:1 ./tools/run.sh res://scenes/city_park.tscn
```

Or from the title screen, **City Park**.

Headless smoke (needs a display for the 3D tree, same as garden smoke):

```bash
DISPLAY=:1 PETAL_PARK_SMOKE=1 ./tools/run.sh res://scenes/city_park.tscn
# prints PETAL_PARK_OK
```

Screenshots (1920×1080):

```bash
DISPLAY=:1 PETAL_PARK_SHOT=1 PETAL_PARK_SHOT_DIR=/workspace/docs/screenshots/city-park \
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

These 1920×1080 frames are llvmpipe / OpenGL3. Forward+ (SDFGI, volumetric sunbeams, SSR, DOF) is wired for a real GPU and will not show in VM captures.

- Kenney Nature Kit has no colormap in this tree, so trees are re-tinted green low-poly, not photoreal willows/oaks.
- Gazebo, greenhouse, clock tower and townhouses are procedural PBR boxes, not hero-sculpted meshes.
- The wood bridge is a pillow-plank arch, not the carved stone/timber footbridge in the concepts.
- Lily pads are discs plus Kenney meshes; pink blooms are spheres until `PETAL-08-103`.
- Iron railings and the golden-hour willow curtain are lighter than concept 2.
- Jellies and veg folk are spawn rings, not characters (`PETAL-08-101`, `102`).
- Builder view is a high orbit, not a locked orthographic Sims camera.
- Square plots read, but the stone edging is simpler than the concept's pillow-bevelled beds.

Captures: `docs/screenshots/city-park/park_ring.png`, `park_builder.png`, `park_pond_edge.png`.

## Credits

See `docs/CITY_PARK_CREDITS.md` and the root `CREDITS.md`.

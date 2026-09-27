# PETAL-03 Jelly / tactile physics

Updated 2026-09-27.

## Census

| Piece | State | Notes |
| --- | --- | --- |
| Live `scripts/creatures/jelly.gd` | PARTIAL → repaired | Grab/drop/throw/squash existed. Missing CCD, prop bounce, creature bump, recovery, lift, selection halo. Reduce-motion used to freeze a held jelly. Young scale used to wipe squash. |
| `scripts/creatures/jelly_feel.gd` | NEW | Cheap spring-mass-on-kinematic kernel. Headless-tested. |
| Live `shaders/jelly.gdshader` | PARTIAL | Wobble + ripple. Deform is on the Body node, not a shader rewrite (PETAL-06 owns shaders). |
| `scripts/presentation/jelly_actor.gd` | DUPLICATE-LEGACY | Grove scene. Now shares `JellyFeel.body_scale`. Not the running garden. |
| `game/jelly/jelly_body.gd` | DUPLICATE-LEGACY | Behind `game/.gdignore`. Left alone. |
| `art/characters` (PR #1) | unrelated | Veg people / clay human. No jelly physics. |

## Task

Player can pick up, stretch, squash, throw, bounce, and recover representative jellies without tunnelling or broken held state.

## Branch / commit

- Branch: `petal/03-jelly`
- Last commit: pass 2 (hungry face, species give, nuzzle)
- Baseline: `cursor/dpo-cpu-decide-9cb0` (`petal-campaign-baseline-20260927`)
- PR: https://github.com/st5463978-boop/PetalWild/pull/4

## Paths

- `scripts/creatures/jelly_feel.gd` (kernel)
- `scripts/creatures/jelly.gd` (live body)
- `scripts/ecology/ecology.gd` (`bump`)
- `scripts/game/garden.gd` (hands pick, lift, halo, smoke)
- `scripts/presentation/jelly_actor.gd` (shared squash)
- `tests/test_jelly.gd`

## Interface

- `Jelly.grab(point)` / `release()` unchanged.
- New: `Jelly.feel` (`idle|held|air|bounce|recover`), `hit_radius()`, `touch_radius()`, `set_select(on, grabbed)`.
- Pass 2: `Jelly.is_hungry()`, `shown_mood()`, `nuzzled` / `pet_time`. `reacted` also emits `nuzzle`.
- `JellyFeel.tune(definition)` from wobble/shape (optional `give` / `bounce`).
- `Ecology.bump()` separates nearby L0/L1 bodies. Held bodies stay put; the other slides.
- Hands: mouse height lifts the body (bottom of screen = low, top = high). Drag samples become throw velocity, capped at 11.
- Halo on hover / held / focus. Hungry hover uses an amber ring.

## Tests

- `tests/test_jelly.gd` → **JELLY_FEEL_OK**
- `tests/test_systems.gd` → **SYSTEMS_OK**
- `tools/smoke.gd` → **PETAL_RULES_OK**
- `DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn` → **PETAL_SMOKE_OK** (includes `_smoke_jelly_feel`: grab lift, stretch, throw, no tunnel, separate, stall bounce, species give, hungry face, nuzzle)
- `tests/smoke.gd` is a pre-existing parse warning-as-error on Variant inference (line 89). Not this lane.

## Visual QA

`PETAL_JELLY_PLAY=1 PETAL_DECIDE=1` ran on this machine.

- Decide: **hef-dfc CPU** llama.cpp Q8_0, choice `berrypatch`, confidence **0.83362**. Not an NPU path.
- `docs/screenshots/jelly_held.png`: Berrypatch in hands, HUD `playful · held`.
- `docs/screenshots/jelly_air.png`: body airborne and squashed, toast `Berrypatch spins, dizzy.`
- Land still: **not committed**. Three camera follow attempts looked into crest foliage and missed the body. Physics check still passes (`land_y` finite, not held, not under the lawn). Qwen3-VL is not operational here.

Wave1 capture is unchanged.

## Pass 2

Built on `petal/08-integration` merged at `e897ed1`. Kernel kept. Three feel upgrades:

1. **Hungry face** (PETAL-02). `hunger < 0.28` or `mood == hungry` droops the lids, flattens the mouth, tints the irises amber, and slightly squashes an idle body. Grab still sets `mood` to playful; HUD uses `shown_mood()` so hunger still reads while held.
2. **Species give**. `JellyFeel.tune` derives spring / stretch / bounce from existing `wobble` and `shape`. Optional `give` / `bounce` keys if 02 adds them. Hold damp stays `0.76` so lift does not regress.
3. **Still-hold nuzzle** (ecology bond). Stretch under 0.18 for ~0.9s emits `nuzzle`, ticks bond, toasts, and calls `ecology.try_promote`. Stretch over 0.4 cancels. Halo `no_depth_test` so the ring stays readable.

### Tests

- `JELLY_FEEL_OK` — species give, hungry read, nuzzle threshold / yank
- `SYSTEMS_OK`
- `PETAL_RULES_OK`
- `PETAL_SMOKE_OK` — grab lift, stretch, throw, no tunnel, separate, stall bounce, grapling softer than reedic, hungry face, still-hold nuzzle / yank. Leaks **3 CanvasItem / 6 ObjectDB** (baseline).
- `JELLY_PLAY_OK` — offline decide `bellhelp`. Land camera is still 08's `_pin_overhead`. No new land framing.

### Visual QA

`DISPLAY=:1 PETAL_JELLY_PLAY=1 tools/run.sh res://scenes/garden.tscn` (offline decide).

- `docs/screenshots/jelly_hungry.png`: stall clearing, HUD `Bellhelp · hungry · idle`, flattened yellow cup. Amber iris is in the live face; this plate looks down on the bell so the organs stay on the far side.
- `docs/screenshots/jelly_held.png`: HUD `Bellhelp · hungry · held`, body lifted and stretched.
- `docs/screenshots/jelly_nuzzle.png`: toast `Bellhelp nuzzles your hands.`, HUD `happy · held`.
- `docs/screenshots/jelly_air.png`: airborne squash, toast `Bellhelp spins, dizzy.`
- `docs/screenshots/jelly_land.png`: 08 overhead pin. Physics `land_y` ~0.54, feel `air`, finite, not held, not under the lawn. Frame still looks into crest foliage. No further land camera from this lane. Qwen3-VL unused.

### Requests

- PETAL-02: optional `give` / `bounce` on a species row is already read; wobble is enough without a schema change.
- PETAL-08: land still is the same overhead miss; not a 03 follow-cam retry.

## Requests

- PETAL-06: optional `push` / `impact` on the live jelly shader if vertex slime should match the sidelined `game/shaders/jelly.gdshader`.
- PETAL-00: F3 debug now prints held jelly feel.

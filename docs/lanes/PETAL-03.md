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
- Last commit: `965b46d` Keep grab spring strength when the body substeps.
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
- `Ecology.bump()` separates nearby L0/L1 bodies. Held bodies stay put; the other slides.
- Hands: mouse height lifts the body (bottom of screen = low, top = high). Drag samples become throw velocity, capped at 11.
- Halo on hover / held / focus.

## Tests

- `tests/test_jelly.gd` → **JELLY_FEEL_OK**
- `tests/test_systems.gd` → **SYSTEMS_OK**
- `tools/smoke.gd` → **PETAL_RULES_OK**
- `DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn` → **PETAL_SMOKE_OK** (includes `_smoke_jelly_feel`: grab lift, stretch, throw, no tunnel, separate, stall bounce)
- `tests/smoke.gd` is a pre-existing parse warning-as-error on Variant inference (line 89). Not this lane.

## Visual QA

`PETAL_JELLY_PLAY=1` runs a grab → stretch → throw → land loop and writes `docs/screenshots/jelly_held.png`, `jelly_air.png`, `jelly_land.png`. Species is a bounded `PetalDecide` choice (bellhelp / berrypatch / cirlark). Qwen3-VL is not used; it is not operational here. Wave1 capture is unchanged.

## Requests

- PETAL-06: optional `push` / `impact` on the live jelly shader if vertex slime should match the sidelined `game/shaders/jelly.gdshader`.
- PETAL-00: F3 debug now prints held jelly feel.

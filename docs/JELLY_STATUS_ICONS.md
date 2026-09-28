# Jelly status icons

Neon line icons that float above a jelly's head. They are live state, not decoration. Empty heads stay empty.

## Trigger

Gameplay talks to the jelly, not the mesh:

```
jelly.set_activity(JellyActivity.EMAIL)
jelly.set_activity(JellyActivity.IDEA)
jelly.set_activity(JellyActivity.WORKING, 1.4)  # intensity spins the gear
jelly.set_activity(JellyActivity.HAPPY)         # one-shot heart
jelly.set_activity(JellyActivity.NONE)
```

Helpers used by the live garden:

| Call | Icon | When |
| --- | --- | --- |
| `jelly.offer_mail()` | envelope | Repeat visitor arrives with news. Stays until handled. |
| `jelly.handle_mail()` | pops out | Face inspect or a snack. |
| `jelly.pulse_happy()` | heart | Poke, snack, nuzzle, gentle pet. Plays once, then yields. |
| `jelly.work_intensity = n` then `refresh_activity()` | gear | Hungry jelly walking to its goal. `n` is 0.75–1.65 from hunger. |
| `jelly.mood = "restless"` then `refresh_activity()` | bulb | Garden conditions are slipping. |
| `jelly.force_activity(kind)` / `clear_force()` | any | F3 debug buttons, or keys on the demo scene. |

The overlay is `JellyStatusIcon`. `Jelly.setup()` mounts one and billboards it at the camera. You can also `add_child(JellyStatusIcon.new()); icon.bind(any_node3d)` on a placeholder.

## Priority

One icon at a time. Highest wins:

1. **HAPPY** — positive event. Preempts whatever is showing, double-beats, floats up, fades. Then the next derived activity returns.
2. **EMAIL** — unread mail. Envelope pops in with overshoot and pulses until `handle_mail()`.
3. **WORKING** — active work. Gear spins; speed follows `work_intensity` when that value exists.
4. **IDEA** — restless insight. Bulb fades in with a bright flash, then flickers.
5. **NONE** — no icon.

Transitions kill the current tween, fade the old stroke, then pop the next one in. They are loop-safe and interruptible.

## Demo

```
DISPLAY=:1 PETALWILD_GODOT=$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64 \
  tools/run.sh res://scenes/debug/jelly_status_icons.tscn
```

`1` email, `2` idea, `3` working, `4` happy, `5` none, `C` cycle, `[` `]` work intensity.

Shots: `docs/screenshots/jelly_status_icons/`.

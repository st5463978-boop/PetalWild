# Jelly status icons

Neon line icons that float above a jelly's head. They are live state, not decoration. Empty heads stay empty.

## Trigger

Gameplay talks to the jelly, not the mesh:

```
jelly.set_activity(JellyActivity.EMAIL)
jelly.set_activity(JellyActivity.IDEA)
jelly.set_activity(JellyActivity.WORKING, 1.4)  # intensity spins the gear
jelly.set_activity(JellyActivity.HAPPY)         # one-shot heart
jelly.set_activity(JellyActivity.ROMANCE_INTERESTED)
jelly.set_activity(JellyActivity.ROMANCE_LOCKED)
jelly.set_activity(JellyActivity.NONE)
```

Helpers used by the live garden:

| Call | Icon | When |
| --- | --- | --- |
| `jelly.offer_mail()` | envelope | Repeat visitor arrives with news. Stays until handled. |
| `jelly.handle_mail()` | pops out | Face inspect or a snack. |
| `jelly.pulse_happy()` | heart | Poke, snack, nuzzle, gentle pet. Plays once, then yields. |
| `jelly.show_interest()` | heart, dim | Early attraction. Soft, slow pulse. Sets `romance = "interested"`. |
| `jelly.lock_romance()` | heart, bright | Confirmed romance. Faster double-beat, more bloom and light. Sets `romance = "locked"`. Morphs from interested in place and bursts mini hearts. |
| `jelly.clear_romance()` | — | Clears both heart tiers. |
| `jelly.work_intensity = n` then `refresh_activity()` | gear | Hungry jelly walking to its goal. `n` is 0.75–1.65 from hunger. |
| `jelly.mood = "restless"` then `refresh_activity()` | bulb | Garden conditions are slipping. |
| `jelly.force_activity(kind)` / `clear_force()` | any | F3 debug buttons, or keys on the demo scene. |

`romance` is `""`, `"interested"`, or `"locked"`. `set_activity(ROMANCE_INTERESTED)` / `ROMANCE_LOCKED` stamps that field the same way. HAPPY does not touch `romance`.

The overlay is `JellyStatusIcon`. `Jelly.setup()` mounts one and billboards it at the camera. You can also `add_child(JellyStatusIcon.new()); icon.bind(any_node3d)` on a placeholder.

Garden stamps romance each frame: young and leaving jellies stay empty; a breeding species or two adults of the same kind lock in; a lone resident whose species has a romance table shows interest.

## Priority

One icon at a time. Highest wins:

1. **HAPPY** — positive event. Preempts whatever is showing, double-beats, floats up, fades. Then the next derived activity returns.
2. **ROMANCE_LOCKED** — looping heart, full intensity. Brighter, faster double-beat, more bloom and OmniLight wash.
3. **EMAIL** — unread mail. Envelope pops in with overshoot and pulses until `handle_mail()`.
4. **ROMANCE_INTERESTED** — looping heart, soft intensity. Dimmer, slower pulse.
5. **WORKING** — active work. Gear spins; speed follows `work_intensity` when that value exists.
6. **IDEA** — restless insight. Bulb fades in with a bright flash, then flickers.
7. **NONE** — no icon.

Transitions kill the current tween, fade the old stroke, then pop the next one in. Interested→locked is the exception: the same heart morphs in place, ramps energy and bloom, and may burst five mini hearts. All of it is loop-safe and interruptible.

## Demo

```
DISPLAY=:1 PETALWILD_GODOT=$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64 \
  tools/run.sh res://scenes/debug/jelly_status_icons.tscn
```

`1` email, `2` idea, `3` working, `4` happy, `5` interested, `6` locked, `7` none, `C` cycle, `[` `]` work intensity. Press `5` then `6` to watch the morph.

Shots: `docs/screenshots/jelly_status_icons/`

- `lineup.png` — five jellies: envelope, bulb, gear, interested heart, locked heart
- `envelope.gif` / `.mp4` / `_strip.png` — overshoot pop and pulse
- `bulb.gif` / `.mp4` / `_strip.png` — fade-in flash and flicker
- `gear.gif` / `.mp4` / `_strip.png` — spin, speeding with intensity
- `heart.gif` / `.mp4` / `_strip.png` — HAPPY one-shot: double-beat, then float and fade
- `heart_interested.gif` / `.mp4` / `_strip.png` — soft slow pulse
- `heart_locked.gif` / `.mp4` / `_strip.png` — morph from interested, mini-heart burst, locked double-beat

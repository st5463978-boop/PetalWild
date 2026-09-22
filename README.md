# PetalWild

A living garden in Hedge Hollow. You till, plant, and water. Creatures visit when the beds meet their needs. Lumen Peel sells from Petal Stall, but she will not spend the parish tin unless you agree.

This is the first integrated build. It is playable. It is not the lush garden in `docs/reference/` yet.

## Run

Install the pinned engine. The exact build is in `docs/ENGINE_VERSION.md`: Godot **4.8-dev6**, version string `4.8.dev6.official.8898c2b3d`. Do not substitute 4.7 or a newer 4.8 snapshot.

```sh
export GODOT="$HOME/opt/godot/Godot_v4.8-dev6_linux.x86_64"
./tools/run.sh
```

Headless checks:

```sh
PETAL_SMOKE=1 "$GODOT" --headless --path . res://scenes/garden.tscn --quit-after 800
"$GODOT" --headless --path . --script res://tools/smoke.gd
```

Both print `PETAL_SMOKE_OK` or `PETAL_RULES_OK`.

Screenshots of the current garden:

```sh
DISPLAY=:1 PETAL_CAPTURE=1 "$GODOT" --path . res://scenes/garden.tscn
```

That writes `docs/screenshots/wave1_*.png`.

## Play

Title screen, three save slots, then the garden.

| Input | Action |
| --- | --- |
| Right mouse | Orbit |
| Middle mouse | Pan |
| Wheel | Zoom |
| WASD | Move the view |
| Q E | Turn |
| Left click | Use the selected tool |
| H | Hands, for grabbing a jelly |
| 1–8 | Tools |
| J | Journal |
| F3 | Debug overlay |
| Esc | Pause |

Tools: Tiller, Seed, Raincan, Fertilize, Tend, Pond Scoop, Home Kit, Hands.

Plant three mature Meadowbells and a Bellhelp comes to look. Buy fertiliser from the stall. Save, quit, and continue. The beds and the coin tin come back.

## Project shape

Data lives in `data/`. The garden scene is built by `scripts/game/garden.gd`. Species, plants, people, and the stall are JSON. Saves are version 1 under `user://saves/`.

State of the build, licences, and who owns which folder: `docs/PETALWILD_MASTER_STATE.md`.

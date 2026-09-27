# PetalWild art desk

Passes cannot generate images. They file a request here. The **Game Art Director** agent watches `art_desk/requests/`, produces the art, writes the files into the Godot tree, and commits.

House style for every request: **Viva Piñata-style, painterly, saturated, chunky and toy-like.**

## Who files

Campaign lanes (PETAL-01 … PETAL-08). Older `PETAL_00`–`PETAL_15` ids in `docs/AGENT_CONTRACTS.md` are a previous wave; do not mix them:

| `pass` | Role |
| --- | --- |
| `PETAL-01` | Foundation / Garden |
| `PETAL-02` | Creature / Ecology |
| `PETAL-03` | Jelly / Tactile physics |
| `PETAL-04` | Residents / life sim |
| `PETAL-05` | Production / Economy |
| `PETAL-06` | Town |
| `PETAL-07` | Region / macro sim |
| `PETAL-08` | Integration / QA |
| `WAVE-0` | Open-source catalogue / licence firewall |
| `OSS-JELLY` | Open-source jelly port (no GPL import) |

## How a pass files a request

1. Copy `requests/_EXAMPLE.yaml` to `art_desk/requests/<id>.yaml`. The file name must match `id`. Files starting with `_` are ignored.
2. Fill the schema below. Use a unique id (`<pass>-<seq>`, for example `PETAL-03-012`). Set `status: requested`.
3. Set `target` to a path under **`assets/art/`** (Godot: `res://assets/art/...`). That is the live import root, next to `assets/third_party/` and `assets/fonts/`. Concept stills that are not in-game may use `docs/reference/` instead.
4. Commit the YAML. Do not drop placeholder PNGs in `assets/`. Do not call image APIs, Higgsfield, OpenRouter, or Hailo's generator.

Do not edit a request once the desk has picked it up (`status: in_progress`). File a new id (for example `PETAL-03-012b`).

## How a pass learns it was delivered

The Game Art Director:

1. Sets `status: in_progress` on the request.
2. Writes the asset(s) to `target` and commits them.
3. Moves the YAML to `art_desk/done/<id>/request.yaml` with `status: delivered` (or `rejected`, with a note in `subject` or a sibling `note.txt`). Paid video spend is a line in `ledger.md`.

The pass is done when **all** of these are true:

- `art_desk/requests/<id>.yaml` is gone
- `art_desk/done/<id>/request.yaml` exists with `status: delivered`
- the file(s) exist at `target` (Godot will write `*.import` sidecars on next editor run)

`status: rejected` means do not wait for files. File a new id if you still need the art.

## Request schema

```yaml
id: PETAL-03-012              # unique; must match the file name
pass: PETAL-03                # PETAL-01..PETAL-08 | WAVE-0 | OSS-JELLY
kind: image                   # image | texture | video
subject: "Whirlm idle pose, front 3/4 view"
style: >                      # extra notes; house style is assumed
  papercraft/piñata look, soft rim light, transparent background
size: 1024x1024               # WxH px; textures must be powers of two
count: 4                      # variants (images/textures) or clips (video)
priority: normal              # high | normal | low
target: assets/art/images/PETAL-03-012/whirlm_idle.png
status: requested             # requested | in_progress | delivered | rejected
due: 2026-10-02               # optional ISO date
duration_s: 4                 # video only, optional
fps: 24                       # video only, optional
lane_hint: A                  # optional: A|B|C|D; the desk decides
refs: []                      # optional paths or URLs
```

`kind: texture` → default under `assets/art/textures/`. `kind: video` → `assets/art/video/`. `kind: image` → `assets/art/images/` (or `docs/reference/` for paintings).

## Lanes (Game Art Director only)

| Lane | What | Covers | Limits |
| --- | --- | --- | --- |
| **A** | Director's own still/texture generator | Concept art, stills, textures | Director-side quota. Passes never call it. |
| **B** | Blender (local render) | Turntables, dummy walk cycles, texture tests | Free. Prefer this for video. |
| **C** | ffmpeg | Stills-to-clips, Ken Burns, flipbooks | Free. Prefer this for video. |
| **D** | Paid DaVinci credits (~**102** left) | Video Blender/ffmpeg cannot do | **VIDEO ONLY.** Scott must approve each use. Log it in `ledger.md`. |
| ✗ | **Higgsfield** | Nothing | **0 authorized.** Never call it. Never flip Unlimited. |

Image or texture → A. Video → B or C first. D only with written approval and a ledger line saying why B/C cannot do the shot. No OpenRouter paid models. No API keys live in this repo.

## Layout

- `art_desk/requests/` — open YAML
- `art_desk/done/<id>/` — finished or rejected request YAML
- `art_desk/ledger.md` — DaVinci / Higgsfield balances
- `assets/art/` — Godot delivery root (`res://assets/art/`)

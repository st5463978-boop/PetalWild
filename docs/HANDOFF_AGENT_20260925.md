# Handoff for the next PetalWild agent

Written 2026-09-25. The living-world goal is not finished. Do not mark it complete.

## Purpose and current state

PetalWild is an original-IP Godot game: a living garden that should grow toward a town, a city, and an agent civilisation. Recovered work (Garden Grove, Hedge Hollow, Havenbrook, Moonwolf, Jelly Baby as reference only) already lives in this tree. Do not start over.

Playable loop on `main` (`6d218f4`): till, plant, water, fertilise, tend, pond scoop, home kit, jelly grab/throw, stall, journal, weather, clock, audio, save/load. Cast on the Hedge Hollow scene: Lumen Peel, Bram Cobble, Nessa Pod. Species include Bellhelp and Meadowbell. `scenes/main.tscn` boots `scripts/app/main.gd`, which changes to `scenes/garden.tscn` (`scripts/game/garden.gd`).

What is still untrue:

- Grove Park is not built. `ContentDB.venues.grove_park.active` stays false.
- There is no town or city beyond the named rumour, and no agent civilisation.
- The visual north star (lush golden-hour garden) is not reached. See `docs/VISUAL_GAP.md` and `docs/reference/`.
- Trust levels are specified 0–5. Only 0 and 1 exist. External actions never execute. Legendary is not a rank.
- Simulation LOD (L0 hero/held through L4 aggregate) is mandatory. See `docs/SIMULATION_LAYERS.md`.

The current construction wave is the Road Rumour east chain, south of the end stone, along `z = -19.35`. Pieces appear only while `Trust.has_action("parish_road_rumour")` is set, via `_sync_road_stones()`. Nobody walks there. The tail on `main` is a low stone at `Vector3(75.8, 0.07, -19.35)`, variable `pace_east_far_end_bell_stone`, same box as the end stone (`0.46 × 0.07 × 0.32`, albedo `#4a4038`, `rotation.y = 0.3`). Its group is `parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone`. No new parish page line. Smoke printed `PETAL_SMOKE_OK` after that commit.

## Build and run

Pin: Godot `4.8.dev6.official.8898c2b3d`. Binary is not in git. Local path: `~/.local/godot/Godot_v4.8-dev6_linux.x86_64`. Download only that zip from the 4.8-dev6 release. Details: `docs/ENGINE_VERSION.md`.

```bash
chmod +x tools/run.sh
./tools/run.sh
```

`tools/run.sh` forces `--rendering-driver opengl3`. This VM has no Vulkan device. Use `DISPLAY=:1`. The adapter is Mesa llvmpipe. Audio falls back to the dummy driver (ALSA has no card). That is expected.

East-chain smoke (the check the road work must pass):

```bash
DISPLAY=:1 PETAL_SMOKE=1 tools/run.sh res://scenes/garden.tscn
```

Success is a process exit 0 and the line `PETAL_SMOKE_OK`. Pre-existing exit leaks are normal: 3 CanvasItem RIDs and 6 ObjectDB instances.

README headless smoke (separate from the garden east-chain smoke):

```bash
"$HOME/.local/godot/Godot_v4.8-dev6_linux.x86_64" --headless --path . --script res://tests/smoke.gd
```

Shots need a display: `PETALWILD_SHOT=overview ./tools/run.sh` with modes `overview`, `golden`, `creature`, `person`, `shop`, `night`, `rain`. Do not commit a shot that clips nightlantern bulbs to 255.

Play: 1 till, 2 seed, 3 water, 4 fertilise, 5 tend, 6 pond, 7 home kit. R cycles seed or home prop. Right-drag orbits. Scroll zooms. WASD pans. Drag a jelly to pet or throw. E stall, J journal, M map, C town, P photo, Space pauses, F5 saves, F9 loads, F3 debug.

## Project rules

`docs/AGENT_CONTRACTS.md` is the lane contract. Summary:

- Stay inside the owned paths. `PETAL_00` is the only lane that edits `project.godot`, `scenes/main.tscn`, and `scripts/main.gd`.
- `tools/orchestration/` is studio tooling. The game must not import it.
- `grove_view.gd` is shared. Actor spawn changes need PETAL_03 or PETAL_04 review.
- New feature branches use prefix `cursor/` and suffix `-5bfd`. This integration has been landing on `main`.
- Do not copy GPL or AGPL code. Jelly Baby is reference only (GPL-3.0-only). TiP-Recomp is not a source and has a no-AI policy.
- Original IP. Havenbrook and Moonwolf names stay out of new gameplay copy unless a recovery doc already records them as inactive.

Other docs a fresh agent should read first: `docs/PETALWILD_MASTER_STATE.md`, `docs/SIMULATION_LAYERS.md`, `docs/ENGINE_VERSION.md`, `docs/RECOVERY_MATRIX.md`, `docs/LICENSE_MATRIX.md`, `docs/HIGGSFIELD_LEDGER.md`, `docs/VISUAL_GAP.md`, `tools/orchestration/README.md`, `tools/orchestration/STATUS.md`.

## Hailo decide

System-1 choices go to Scott's Pi (`piai-1`, Hailo-10H), model `Qwen3-1.7B.hef` (Ollama tag `qwen3:1.7b`). No auth on the decide service. Do not call MinoJEV, an RLCD policy, a local CPU Qwen, or `/v1/chat/completions` for these choices. Do not recompile the HEF.

Addresses:

- Tailscale: `http://100.126.22.71:8766` (MagicDNS `http://piai-1:8766`). Device name `piai-1`.
- Port `8766`.
- Health: `GET /health`. Expect `ok: true`, device `Hailo-10H`.
- Decide: `POST /v1/decide` and `POST /decide`. Body `{"question": "...", "options": ["...", "..."]}` with at least two options. The client tries `/decide` then `/v1/decide`.
- Response fields that matter: `choice`, `index`, `scores`, `latency_ms`, `model`, `raw`, `presented_index`, `shuffle_order`, `hailo_total_duration_ns`. The integer `index` wins even when `raw` is a different letter, because the server shuffles options. Map with `index`, not with the raw letter.
- Client timeout in `tools/orchestration/petal_dispatch/hailo_backend.py` is 75s.

URL resolution (`tools/hailo_decide_url.py`), wired into `decide_url()` and into a single retry inside `post_decide()`:

1. Fetch the ntfy discovery topic and take the last `https://` line. Topic URL: `https://ntfy.sh/petalwild-hailo-decide-b71128b262bf79cd/raw?poll=1&since=latest`. Override name: `HAILO_DECIDE_DISCOVERY_URL`.
2. Health-check `<base>/health`. If ok, set `HAILO_DECIDE_URL` to `<base>/v1/decide`.
3. Else keep the existing `HAILO_DECIDE_URL`.
4. Else `http://100.126.22.71:8766/v1/decide`.

Startup: `decide_url()` and `service.py` `main()`. After a decide failure: `resolve_decide_url(force=True)` and retry once if the origin changed. Shell form: `eval "$(python3 tools/hailo_decide_url.py --export)"`.

Related env names, values not recorded here: `HAILO_DECIDE_URL`, `HAILO_DECIDE_DISCOVERY_URL`, `HAILO_GENAI_URL`, `HAILO_MODEL_DIR`. The decide service itself has no auth header.

Tailscale on a new VM: `tailscale` is installed at `/usr/bin/tailscale`. This cloud VM was already logged into the tailnet (`tailscale status` shows this node and `piai-1` at `100.126.22.71`). No Tailscale auth-key env var was present in the process environment (no `TS_AUTHKEY`). Do not invent one. If `tailscale status` shows the VM logged out, join with `tailscale up` using Scott's tailnet auth; the secret name was not available in this environment. A connmark iptables warning on `tailscale status` (`unknown option "--nfmask"`) did not block HTTP to the Pi.

On 2026-09-25 the published tunnel base was `https://colleges-impressive-mathematics-females.trycloudflare.com`. Treat that host as perishable. After a Pi reboot, rediscover. A long decide can return HTTP 502 at about 20s from both the tunnel and Tailscale while `/health` is still 200. Retry the same body on Tailscale `/v1/decide`. Do not take `options[0]` for an HTTP 502. The TimeoutError rule is different: on `TimeoutError` only, use `options[0]` once and append a line to `tools/orchestration/runtime/decide-receipts.jsonl`. That file is tracked even though `tools/orchestration/runtime/` is gitignored; `git add` of the directory fails, `git add` of the file works when it is already tracked.

Commit messages for a Hailo world change name the piece in the subject and put index, latency, raw, model, shuffle, and presented_index in the body. No AI attribution trailer.

## Art requests

Hailo generates every image with its built-in generator. Do not call image-generation tools, image APIs, or Higgsfield.

Write `art_requests/<yyyymmdd>-<short-slug>.md` with: what the asset is for, subject, composition, aspect ratio (`1:1`, `4:3`, `3:4`, `16:9`, or `9:16`), number of images, and the target path in the repo. End the turn with a section headed exactly `ART REQUEST` listing those files. Hailo returns attachments under `uploads/`. Move them to the target path and commit.

House style: a dreamy but photographic 3D render; a blue-green forget-me-not palette with gold trim; soft Ghibli-style veg people mixed with Grok buddies (small rounded chrome-and-teal robots) and real people; glowing gold threads connecting stars, like Astra's logo.

Caps are Scott's, not the vendor's: 30 images per rolling hour, 150 per rolling day, warn at 80%. Batch, and ask only for images the work needs. Hailo refuses or defers a request that would exceed a cap.

## Last 15 commits on main before this handoff

- `6d218f4` A low stone stands one pace east of the far-strip bell.
- `23c74ac` Record the Hailo-only concept art request workflow.
- `db62f66` Resolve the Hailo decide URL from the ntfy tunnel topic.
- `52f1858` A short meadowbell stands at the east end of the far-bell strip.
- `7a4c915` The journal keeps the strip east of the far bell stone.
- `d9ed29e` The parish page names the strip east of the far bell stone.
- `7f218b9` A worn strip steps east of the far bell stone.
- `eb67004` The parish page names the far bell stone.
- `3845734` A low stone stands east of the last-strip's stone bell.
- `8cf26f1` A short meadowbell stands at the east end of the last-strip's stone strip.
- `2ca4e66` The journal keeps the strip east of the last-strip's stone.
- `cf02dda` The parish page names the strip east of the last-strip's stone.
- `193ae30` A worn strip steps east of the last-strip's stone.
- `64468a8` A low stone stands east of the last-strip's bell.
- `c6675e1` A short meadowbell stands at the east end of the last-strip.

## Open tasks and next step

Immediate next step, already decided, not built. Hailo index 1, latency 1461.2 ms, raw `B`, model `Qwen3-1.7B.hef`, shuffle `[0, 1]`, presented_index 1. The index is a worn strip, not the page line.

Question: "A low stone stands one pace east of the meadowbell at the east end of the far-bell strip, still south of the end stone, while the road rumour is filed. Grove Park stays unbuilt. What should change next?"

Chosen option: "A worn strip one pace east of that stone, still south of the end stone, same worn strip as the road, only while the road rumour is filed. Nobody walks there. No new page line."

Place it at `x = 77.0`, `y = 0.02`, `z = -19.35` (one 1.2 m pace east of the stone at 75.8). Copy the previous worn strip: size `Vector3(1.2, 0.03, 1.05)`, albedo `#6a5e4c`, roughness 0.96, specular disabled, shadow off, `visible = false` until the rumour sync. Append `_strip` to the stone's group. Add the count function (x within 0.2 of 77.0, x not below 76.2, north edge not south of the end stone, z within 0.2 of -19.35, not inside plots, albedo match). Thread `!= 0` and `!= 1` into the four smoke lines next to the stone count. Extend the unique far-bell sentence in `docs/PETALWILD_MASTER_STATE.md` (2 copies) and `docs/SIMULATION_LAYERS.md` (1 copy), not every meadowbell sentence in those files. Append the decide receipt. Smoke, commit, push `main`.

This receipt was not written yet. The stone receipt is the last line of `decide-receipts.jsonl`.

After that strip, ask Hailo again. The usual fork is a parish page line while the new piece is showing, versus the next physical pace (meadowbell at the east end, about `x = 77.6`). Keep Grove Park unbuilt. One Hailo choice per wave.

The larger goal remains: one playable original-IP world from this garden toward town, city, and agent civilisation, with causal ecology, life states, trust, and the lush garden art direction. Do not shrink that to the east-chain pace.

WIP that was not on `main`: Godot `.import` sidecars for six screenshots and `.uid` files for presentation scripts plus `tests/probe_mesh.gd`. They are on `wip/handoff-20260925` only. Do not merge that branch unless you mean to keep those generated files. `scripts/game/garden.gd` had no uncommitted diff at handoff; the stone is already in `6d218f4`.

## Known pitfalls

- Godot 4.8-dev6 parse-fails on `:=` inference from an untyped Variant. Annotate the variable. A parse error can leave a hung Godot process; kill it before the next smoke.
- Reusing a variable name further east (`pace_east_end_bell_stone` was already used at an earlier x) is a parse error. Name the new node from the new pace.
- A short doc sentence such as "A short meadowbell at the east end of that strip..." is shared by many paces. Anchor the replace on the unique preceding sentence or you will rewrite the whole road.
- Smoke checks are single very long lines. Insert the new count beside the previous piece's count for both the hidden (`!= 0`) and filed (`!= 1`) asserts. There are four lines.
- Count functions must keep the x lower bound (`pos.x < min` returns -1) and the north-edge test. Dropping either makes the smoke pass a stone that sits in the wrong place.
- `resolve_decide_url(force=True)` will keep a tunnel whose `/health` is 200 even when `/v1/decide` is 502. If the retry is still 502, call Tailscale `http://100.126.22.71:8766/v1/decide` directly.
- `index` wins over `raw`.
- Nightlantern bulbs must not be committed clipped to 255.
- Do not generate images in this repo.
- Do not print tokens, Tailscale auth material, or `CURSOR_AUTH_TOKEN`. The decide service needs none of them.
- Clone URL, no credentials: `https://origin.cursor.com/git/sjt1/tmp-6533b848ef80885a.git`.

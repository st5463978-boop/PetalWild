# PETAL-R3 notes — agent tooling, QA, orchestration

Research only, 2026-09-27. Indexes were discovery indexes. Licences below are from each original repository (`gh api` or a `LICENSE` file), not from the index that linked them. Nothing here was copied into `scripts/`, `scenes/`, `data/`, or `shaders/`. Shallow clones, if any, sit in gitignored `_research/`.

The Hailo decide service returned HTTP 502 (`backend_unavailable`) for every reuse call and every lane call. Grok locked each card to its evidence recommendation. `options[0]` was not used. Tooling cards are PETAL-08. the-free-game is PETAL-01.

## What the campaign already has

`tools/orchestration/` is the studio foreman. The game does not import it. It already routes `build_failed`, `test_failed`, `visual_qa_failed`, `merge_conflict`, and `agent_failed`, and it escalates GPL paste, creative-direction changes, and simulation rewrites. Improvements belong in that foreman and in `tools/run.sh`. They do not replace the garden and they do not add an agent framework under the Godot tree.

Lane contracts in `docs/AGENT_CONTRACTS.md` still name PETAL_08 as shop flow. This wave's PETAL-08 is the executive / QA / orchestration brief. Shop code was not the subject.

## Indexes

- [awesome-gpt-6-astra](https://github.com/MartinDelophy/awesome-gpt-6-astra) — catalogue licence CC0-1.0. That grant is the list, not the games. Useful originals with public source: [the-free-game](https://github.com/LucasMarquesShiva/the-free-game) (carded). Last Beacon is MIT Canvas tower defense with an iteration log; not carded. Dwellcraft has no GitHub licence; not inspected further. Several colony and fishing clones have no public source and look like commercial recreations; they were not fetched.
- [awesome-ai-built-games](https://github.com/lappemic/awesome-ai-built-games) — catalogue licence CC0-1.0. Six originals followed: Godot-MCP, quasar-saz, pocket-salvage, world-of-claudecraft, Unity-MCP, viber3d.

## Orchestration patterns worth keeping

**One next step.** game-creator's multi-session skill keeps a short state file: phase, last concrete action, one next step, blockers. The 2026-09-25 handoff already does this in prose. A machine-readable line next to the foreman queue would let the next worker start without re-reading the east road. Do not import their template.

**Gates, not a studio org chart.** Claude-Code-Game-Studios (MIT) names director gates (pillars, architecture, QA coverage, phase exit) and writes a verdict. Petalwild does not need 49 Claude agents. The foreman already has the events. Use the index as a checklist: a story is not done without smoke, a visual claim is not done without a display shot, and a creative-direction change still escalates.

**Independent workers, human land.** The one-button workflow (MIT) generates ten games in isolated contexts, smoke-tests the batch, and stops. Ranking and publishing are a separate human request. For this campaign: parallel lanes do not edit the same garden file, the smoke gate is mandatory, and merge stays with integration. Do not start a generator of new games.

**Text before pixels.** game-creator exposes a function that returns game state as text so an agent need not interpret a screenshot. Petalwild smoke already prints counts. One JSON line (trust, rumour filed, plot moisture, who is embodied) would let a worker check the sim when the picture is ambiguous. Write it in our smoke. The plugin's licence is ambiguous (README says MIT, `package.json` says ISC, no `LICENSE` file, Strudel audio is AGPL), so the code stays unread as a source.

## QA mechanisms

| Check | Where it already lives | Gap |
| --- | --- | --- |
| Parse / script load | headless `tests/smoke.gd` | Keep it. A parse error can leave a hung Godot process. |
| East-chain gameplay | `PETAL_SMOKE=1` and `PETAL_SMOKE_OK` | This is the gameplay gate. Do not weaken the count lines. |
| Picture | `PETALWILD_SHOT` on `DISPLAY=:1`, llvmpipe | Headless success is not a picture of the hedge. |
| Lane ownership | `docs/AGENT_CONTRACTS.md` | Foreman escalates vision and GPL. It does not yet refuse a worker that edits outside its paths. |

Godot-MCP (Apache-2.0) can validate GDScript and capture a viewport or an isolated node, but only inside a mono editor, and the default connection is the ai-game.dev cloud. Our pin is the standard 4.8-dev6 binary. Do not install the addon. Isolated shots are the right later tool for PETAL-03 (Bellhelp throat) and PETAL-05 (hedge skyline in `docs/VISUAL_GAP.md`).

Unity-MCP is the same author's sibling (Apache-2.0, commit `e4af84e5`). It has the same screenshot families and the same cloud login. Wrong engine. Not a card beyond that.

quasar-saz (MIT) is a Godot game whose README describes a gate: unit tests, scene linters, and scripted input before a change ships. It vendors gdUnit4 (MIT, Mike Schulze) inside the tree. Do not take that copy. If the test lane wants gdUnit4 later, use the upstream project under its own decision.

pocket-salvage has no repository licence (RED). Its test note says headless pixel checks are not hardware-renderer proof. That sentence matches this VM. The repository is rejected; the distinction is restated here and not taken from their files.

Claude-Code-Game-Studios tells agents to capture Godot with a visible window and a frame sequence, and not to treat headless as the picture. Same rule as `tools/run.sh`: smoke may be headless; shots need `DISPLAY=:1`.

## Self-play

World of ClaudeCraft (MIT) runs one sim in the browser and again as a headless Gymnasium process (`reset` / `step`). That is the shape worth remembering: the agent plays the real sim, not a second simplified model. The repository also ships an optional Solana token and wallet link. Do not import the game, the env server, the Python bindings, or the token.

A Petalwild version, later and original: a process outside the game steps needs, growth, and the rumour clock with drawing off, and scores a policy against that same sim. The harness is PETAL-08. The needs and jobs it reads are PETAL-01. Not this wave. No Gymnasium dependency.

## Village sim (PETAL-01, from the Astra index)

the-free-game (Godot 4.7.2) splits a fixed-step village sim from the 3D view. Places create jobs. Idle people gather. The player does not order every body. That matches `docs/SIMULATION_LAYERS.md`: most of a town is numbers, a few bodies near the camera are real. Code is MIT. Original art is CC BY 4.0. Do not copy either into this tree, and do not move off the 4.8-dev6 pin. Their `tools/dev.py` (doctor, test, export) is the same idea as `tools/run.sh`. Extend the script we have.

## Followed and not carded

viber3d (`instructa/viber3d`, MIT, commit `ad11dfd3`, last activity 2025-03-16) is a React Three Fiber starter. It is not Godot and not an orchestration system. No reuse.

## Concrete campaign changes (not done here)

1. Leave the Hailo foreman in place. Do not vendor game-creator, Claude-Code-Game-Studios, Godot-MCP, or a gym.
2. Keep one Hailo choice and one physical or page change per wave. Parallel agents get different files.
3. Treat `PETAL_SMOKE_OK` as the gameplay gate and a `DISPLAY=:1` shot as the only visual gate. Say so in the run result: observed, or not verified.
4. The eight reuse rulings are locked from the licence evidence. A later Hailo answer is advisory. It must not flip a REVIEW or RED reject, and it must not be taken from `options[0]`.

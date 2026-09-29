# Jelly-Baby port analysis

Checked 27 September 2026 against <https://github.com/scottstts/Jelly-Baby> (`main`, last push 14 September 2026). The README and `LICENSE` state GPL-3.0-only. No Jelly-Baby source, mesh, texture, or kernel was copied into PetalWild.

The live creature is `scripts/creatures/jelly.gd`, driven by `scripts/game/garden.gd`. Grabbing already lives there: hands tool, `_pick_jelly`, `Jelly.grab`, `hold_target` each frame, `Jelly.release` on mouse-up. This note layers a spring on that controller. It does not replace it.

## What the original actually does

Jelly-Baby is a browser toy (TypeScript, JavaScript, a C kernel compiled to WebAssembly, Three.js, WebGPU). The body is a 7 cm soft solid, not a squash pose.

| Piece | Where it lives | What it is |
| --- | --- | --- |
| Cage | `scripts/model-cage.mjs`, `src/physics/baby-cage.ts` | A 7.5 mm lattice over an implicit solid, split into tetrahedra. The visible mesh is embedded with barycentric weights. About 980 particles and 4,026 tetras. |
| Solver | `src/physics/soft-body.js`, `scripts/native/soft-body-kernel.c` | Fixed 240 Hz step. Predict positions, then three XPBD iterations of a coupled neo-Hookean distortion and volume constraint, plus an orientation barrier so tetras do not invert. |
| Material | `src/physics/constants.js` | Density 1050, shear 1200 Pa, bulk 65000 Pa, damping 3, gravity 2.4 m/s², restitution 0.065. The wobble is the elasticity. The bounce height is small on purpose. |
| Grab | `src/physics/grab.ts` | A triangle hit becomes barycentric weights, then cage-node weights. The solver pulls those nodes with a compliant XPBD constraint and a force cap. On release, the last target is kept for one or two substeps so a flick still carries momentum. |
| Locomotion | `src/app/locomotion.ts` | Forces on the same particles: turn, posture, alternating stride. Not a canned walk cycle. A grip suppresses those forces. |
| Surface | `src/physics/deform-surface.js` | Every visible vertex is the current tetrahedron. The face is attached to that deformed skin. |
| Recovery | kernel plus `docs/soft-body-and-interaction.md` | If a grab would invert elements, the step keeps a previously valid cage and only accepts an admissible move. |

That stack is why a pull, a throw, and a landing all read as one material. It is also why it does not belong in a garden of many creatures: hundreds of tetras per body, a 240 Hz solver, and a GPL program.

## What is technique, and what is theirs

General technique, safe to reimplement in original code:

- a soft body returns to its rest shape after a pull
- stretch follows the pull, not a single vertical squash
- volume stays roughly constant (long axis grows, the waist shrinks)
- a landing is a short squash plus a wave, not a high bounce
- a flick at the end of a drag still adds speed
- the face rides the body, slightly late

Project-specific, not ported:

- the implicit jelly-baby sculpture, the generated cage, and the checked-in mesh
- the neo-Hookean energy, the tetrahedral XPBD iterations, and the orientation-repair kernel
- WebGPU caustics, the tabletop facilities (bed, swing, trampoline), and the flavor palette
- their constants, force cap, and substep schedule

## PetalWild equivalent

| Jelly-Baby | PetalWild | Why |
| --- | --- | --- |
| Tetrahedral XPBD cage | Not used | Too expensive for the parish, and the source is GPL. |
| Grab constraint on cage nodes | Existing `grab` / `hold_target` spring in `jelly.gd` | Already the grip. Left in place. |
| Flick kept for 1–2 substeps | `JellyDeform.release_flick` | Adds at most 0.8 m/s from the leftover pull. A short pet adds nothing, so the pet / drop / throw thresholds still mean what they meant. |
| Directional elastic stretch | `JellyDeform.basis_for` on the `Body` node | Lengthens along the pull and pinches the waist. Landing squash on the root scale is unchanged. |
| Wave through the skin | `stretch` and `stretch_dir` on `shaders/jelly.gdshader` | A small normal wave. At rest both uniforms are zero, so the old idle shader is the same. |
| Secondary mass | `lag` on `Body` | The mesh trails the pull by at most 10 cm and springs back. |
| Skeleton jiggle addons | Not used | These jellies are sphere clusters. They have no `Skeleton3D`. |
| Godot `SoftBody3D` | Not used | It would replace a controller that already walks, sleeps, and bonds. |

Files:

- `scripts/creatures/jelly_deform.gd` — the spring
- `scripts/creatures/jelly.gd` — calls it from the existing full-detail step
- `shaders/jelly.gdshader` — surface wave
- `tests/jelly_deform.gd` — headless check of stretch, recovery, landing, and the flick cap
- `scripts/game/garden.gd` — still owns the pointer. No grab rewrite.

`scripts/presentation/jelly_actor.gd` is the other presentation path. The running scene is `scenes/garden.tscn` → `scripts/game/garden.gd` → `Jelly`. The actor was not retargeted.

## Licence

Jelly-Baby is GPL-3.0-only. PetalWild code is MIT. Copying or translating their solver, cage builder, or assets would make that derivative GPL, which this project has not decided to do.

The Pi decide service (`Qwen3-1.7B.hef`) returned `DIRECT_IMPORT` for Jelly-Baby. That recommendation was rejected. The Cursor review is `PORT_TECHNIQUE`: original spring, no imported source. The same override applies to any later `DIRECT_IMPORT` on GPL or AGPL.

## Performance

One jelly, full detail, costs a few vector updates and one 3×3 basis. No per-vertex constraint loop. Distant jellies (`tier >= 2`) call `_rest_deform` and skip the spring. Reduced motion clears it and sets the body basis back to identity.

The affine stretch is a cheap stand-in for the cage. It will not fold, self-collide, or preserve volume the way their tetras do. That is the trade that keeps the parish on one frame.

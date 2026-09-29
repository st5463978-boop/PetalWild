# Jelly-Baby port analysis

Study note for PETAL-03. Jelly-Baby is GPL-3.0-only. Decision default is STUDY. Nothing in this note is a licence to copy its source, mesh, cage, or constants into Petalwild.

The decision service returned HTTP 502 (`backend_unavailable`) for every candidate and every lane question. No Hailo choice is recorded. Grok locked the cards from the inspection below. `options[0]` was not used.

| Candidate | Decision | Class |
| --- | --- | --- |
| Jelly-Baby | STUDY | REVIEW |
| Godot SoftBody3D | STUDY | GREEN |
| SpringBoneSimulator3D | ADOPT | GREEN |
| godot-softbody2d | STUDY | GREEN |
| PositionBasedDynamics | STUDY | GREEN |
| Gloop | STUDY | GREEN |
| JoltPhysics | REJECT | GREEN |
| godot-vrm | REJECT | REVIEW |

## What you inspected (commit SHA, licence evidence)

Shallow clone of <https://github.com/scottstts/Jelly-Baby> at `19fc6ea487262f7a32fa8935712624ae5249db68` (2026-09-14, "mobile optimizations"). Clone path `/workspace/_research/Jelly-Baby` is gitignored.

Licence evidence:

- `README.md` states GPL-3.0-only.
- `LICENSE` is the GNU GPL version 3 text.
- GitHub licence API: `spdx_id` `GPL-3.0` (the API does not encode "only"), `pushed_at` 2026-09-14, language JavaScript.

Class: REVIEW. Do not adopt the source into Petalwild core.

Files read for behaviour (names only):

- Interaction: `src/physics/grab.ts`, `src/app/input.ts`, `src/app/locomotion.ts`, `src/app/fixed-step.ts`
- Deformation: `src/physics/soft-body.js`, `src/physics/deform-surface.js`, `src/physics/baby-cage.ts`, `src/physics/constants.js`
- Recovery: `src/physics/orientation-safety.js` and the acceptance path in `src/physics/soft-body.js`
- Feel: `src/graphics/character/face-expression.ts`, plus the locomotion and grab files above

The JavaScript solver was read in full. The WebAssembly kernel is a faster twin of that solver; it was not treated as a second algorithm. Project docs were used as a map, not copied.

## How interaction works

The visible triangle that the pointer hits is the same deformed surface the solver writes. A hit becomes a grip by mixing that triangle's barycentric weights with each corner's precomputed link to the mechanical cage, then merging duplicate cage nodes. If the reconstructed anchor does not sit on the visible hit, the grip is rejected.

The grip is a soft point constraint. Each step it pulls those cage nodes toward a target, with compliance so the flesh lags, and a hard cap so a violent drag stretches the body instead of dragging every node to the cursor. Up to a small number of grips can exist together; extra pointers are refused once the cap is hit. A mouse keeps a single grip. Touch may add more.

The target lives on a plane facing the camera, passing through the grab point. If that plane would put the target through the table, the target stays on the pointer ray and switches to a floor plane. Pointer motion eases toward the desired point quickly, but a single event cannot command an absurd jump, and the target itself has a speed limit. The camera orbit is frozen for the whole grip.

On pointer-up the last sample is kept. The constraint stays alive for one further physics step, or two if the grip never saw a step, so a flick still accelerates the flesh. Then the grip is deleted and the body keeps the velocity the constraint already wrote. Throw speed is the recent motion of the target, not the distance back to where the grab started.

Walking is separate. It applies forces toward a turned rest pose. Feet are stiffer. A simple alternating stride shifts the rest targets. A jump adds a stronger upward kick on the lower nodes so the top follows a moment later. Those forces drop out while a grip exists and fade back in over about half a second after release. The soft solver still owns contact and shape.

## How deformation works

The rendered mesh is not a squash pose. A coarse tetrahedral cage (on the order of a thousand nodes and a few thousand tets for a body a few centimetres tall) is the mechanical object. Each render vertex is baked, once, into one tet with four weights. Every frame the vertex is the weighted sum of those four current nodes. Normals come from the same neighborhood's deformation, so lighting follows the squash.

Each step, at a high fixed rate (a few hundred hertz, a handful of iterations):

1. Light air drag, then a gentle gravity, then a position prediction.
2. For every tet, two coupled constraints: one resists shearing and stretching, one resists volume change. They are solved together so the undeformed shape does not push on itself.
3. A barrier discourages a tet from turning inside out.
4. Grips and floor contacts run in the same iteration loop.
5. Floor contacts that actually pushed get a friction correction in the tangent plane.
6. Orientation recovery (below).
7. Velocity is taken from the position change. A landing adds a very small bounce only when the incoming downward speed is meaningful.
8. Along each cage edge, relative motion along the edge is damped in equal-and-opposite pairs, so the body loses wobble energy without being dragged to a stop as a rigid object.

There is no self-collision and no tearing. The render mesh is never a second, shader-only shape.

## How recovery works

Opposing grips can flip tets. The solver does not rewind the clock and does not shrink the step.

It first tries a small, fixed number of local repairs on the worst tet. If the cage is still inverted, it starts from the last pose that was known to be valid and walks the nodes toward the proposed pose, forward and then backward. A node only moves as far as its neighboring tets can accept without flipping. The mass center of the attempted pose is kept, with a lift if the body would sit through the floor. Independent nodes may still move. Only a valid result is stored as the next recovery reference. A failed repair is never promoted to "last good pose".

Sleep is separate. If locomotion allows it, the body is on the floor, the step was not cut short, and the motion stays tiny for a fraction of a second, velocities are cleared and later steps leave positions alone. A grip, a move, or a jump wakes it.

## What creates the tactile feel

- The cursor drives a target. The flesh chases the target. The hand does not set the vertex positions.
- A force cap turns a hard pull into stretch.
- One or two extra constraint steps after release turn a flick into momentum. A slow drag that ends at the same place does not throw as hard.
- Gravity is much softer than Earth, and the bounce off the table is tiny. The visible motion after a landing is the elastic wave, not a ball rebound.
- Edge damping removes that wave and then stops. There is no looping wobble animation on the body.
- The face eases into a strained shape while held, and if the hold lasted long enough it plays a short pleased reaction in the second or so after release.
- Walking forces yield during a grab and return gradually, so a throw is not immediately corrected by the gait.

## General technique vs implementation-specific

General, and fair to reimplement in original code:

- Compliant, force-limited grab on a local cluster, with a rate-limited target.
- Hold the constraint across one or two steps after pointer-up so release velocity is real.
- Couple shape-keeping and volume-keeping so rest has no internal stress.
- Recover from inverted elements by accepting only a valid pose, without rewinding time.
- Damp internal motion, then sleep. Keep bounce small.
- Drive appendages and gait with forces or secondary motion, and let the body solver (or its cheap stand-in) own the squash.
- Tie the face to hold duration and a short post-release window.

Specific to this project, and not portable as an artifact:

- The tetrahedral cage, the baked surface bindings, the optical proxy, and the high-resolution mesh.
- The WebAssembly kernel and its fixed memory layout.
- The exact material numbers, iteration counts, and force caps.
- Multi-grip limits, facility contacts, world travel, and the flavor/face skin.
- Any file in the repository. GPL-3.0-only stays on that work.

## Godot reproduction: what is physics, skeleton/springs, shader, or fake

Petalwild is Godot 4.8-dev6 (`8898c2b3d`). `project.godot` does not select a 3D physics engine. Godot 4.6 and later default new projects to Jolt; confirm that in the editor before relying on soft-body behaviour, because the GodotPhysics and Jolt soft-body backends in that commit are different solvers.

| Job | Where it belongs |
| --- | --- |
| Wander, hop, pet, mood, pathing | Keep `scripts/presentation/jelly_actor.gd`. |
| Idle shimmer, colour, rim | Keep `shaders/jelly.gdshader`. It is a normal wobble, not a grab deformer. |
| Grab lag, stretch direction, flick | Fake, on the existing actor: a target, a directional scale, a short post-release oscillation. This is the first feel win and stays cheap for the whole garden. |
| Crests, leaves, lobes | Skeleton springs. `SpringBoneSimulator3D` is already in this Godot pin (Verlet tails on a bone chain, plus child collision shapes). Call it. Do not write a second jiggle solver and do not import `godot-vrm`. |
| One creature in the hand, if the scale squash is not enough | A tiny original cluster (tens of points, not a thousand): distance keeping plus a volume or shape-matching pull toward a rotated rest pose. That is the permissive stand-in for the tet solve. Run it only at close fidelity. |
| Engine `SoftBody3D` | Physics, already in-tree, including a Jolt backend with pressure, damping, pins, and sleep. The official MIT demo (`godotengine/godot-demo-projects` `15d4fcd`, `3d/soft_body_physics`) shows pinning and per-point impulses, and also that soft bodies do not collide with each other. That demo caps placed bodies for performance. Use it for a single prop experiment, not for the garden population. |
| Full neo-Hookean tet cage | Do not build it for these creatures. The cost and the recovery problem exist to serve one hero mesh. |

Dead wiring to fix while touching feel: `jelly_actor.gd` sets shader parameters `impact` and `push`. `jelly.gdshader` has `wobble` and `ripple` only. The grab currently cannot show up in the shader. Either drive a real uniform from the same pull the actor uses, or stop setting the unused names. Do not let a shader displace invent a different silhouette from the one that was grabbed.

## What PETAL-03 should port as a native technique, and what it must not copy

Port the behaviour, in original GDScript, inside the current actor. Do not replace the controller.

Original sketch of the grab, at creature scale:

```
target starts at the body
while the pointer is down:
    desired = hit on the camera-facing plane, kept above the ground
    if desired leads the grabbed point by more than a short distance:
        pull desired back onto that lead
    ease target toward desired, with a cap on target speed
    stretch from how far target sits from the body, along that direction
on pointer up:
    keep the pull for one or two ticks so the last motion becomes velocity
    a very short gesture stays a pet (the actor already does this)
    otherwise throw with the recent target velocity and a small lift
after release:
    let wide/tall oscillate a couple of times under damping, then rest
    sleep the extra motion once it is quiet
```

Original sketch of inversion safety, only if a point cluster exists:

```
if a cell would flip inside out:
    start from the last valid points
    move each point only part of the way toward the proposal
    stop that point early when a neighbor would flip
    keep the center of mass of the proposal, and clear the floor
    store the pose only when it is valid
never rewind the frame
```

Also port these feel rules, without their numbers:

- Stretch follows the pull. The current actor always widens in XZ and shortens in Y.
- Throw speed follows the end of the gesture. The current throw uses the net drag since the press, so a slow long drag and a fast flick of the same length throw alike.
- Landing quiver, then rest. The current ballistic bounce is a bouncy ball (strong gravity, large vertical rebound, horizontal bleed, then a hard stop).
- Face strain while held, and a short pleased beat after a hold that lasted long enough to read.
- Gait yields while held.

Appendages: add `SpringBoneSimulator3D` on crests, leaves, and lobes. Recommendation: ADOPT the engine node. Lane default PETAL-03 because the lane call escalated.

Close-up cluster, only if the directional scale is still too stiff: write an original shape-matching or distance-plus-volume loop sized like Gloop's ring (a few dozen points), using the public Müller-style idea that `InteractiveComputerGraphics/PositionBasedDynamics` implements under MIT. Recommendation for that library: STUDY. Do not vendor it.

Must not copy:

- Any Jelly-Baby source, shader, asset, cage binary, kernel, or tuned constant block.
- The 7 cm hero mesh and its tens of thousands of triangles.
- `appsinacup/godot-softbody2d` (MIT, but 2D rigid bodies and joints; wrong cost and dimension).
- The `jrouwe/JoltPhysics` repository. Godot 4.8 already contains `modules/jolt_physics`. Adding the upstream repo forks the engine.
- `V-Sekai/godot-vrm`. Spring bone behaviour is already in the engine. Sample models in that repo are under separate terms, and GitHub reports `NOASSERTION`.
- Gloop's player script. Read the scale. Do not drop a 2D platformer blob into the garden.

## Comparison to the current jelly_actor.gd / jelly.gdshader

`scripts/presentation/grove_view.gd` instances `scripts/presentation/jelly_actor.gd`. `scripts/main.gd` grabs that actor. `game/` is present in git and carries `game/.gdignore`, so Godot does not import it. It is not the running tree.

What the actor already solves:

- Pointer plane grab, short contact as a pet, longer contact as a toss, mood, wander, hop, night squash, face posing.
- A single material shared by the blob parts, with idle shader wobble.

What is still a uniform fake:

- `hold_at` teleports the whole node to the pointer and sets one scalar squash from distance since the press, clamped hard. There is no lag, no force cap, and no directional stretch. `_squash` always scales X and Z up and Y down. The pull direction is only sent as `push`, which the shader does not declare.
- `release` builds velocity from the net displacement since the press, times a constant, plus a fixed lift. Flicks and slow drags of equal length match.
- In the air, gravity, a large vertical bounce, and horizontal damping run until the speed is small, then scale snaps to rest. Nothing carries a wave through the body after the landing.
- The shader displaces along the normal with a time sine. It does not know about the grab. `ripple` is never set by the actor. `impact` and `push` are set and ignored.

That split is the right architecture for a garden: one cheap actor, a richer presentation while held. PETAL-03 should thicken the held presentation. It should not swap in Jelly-Baby, `SoftBody3D`, or a tet solver as the creature controller.

Permissive references worth more than the GPL tree:

- `SpringBoneSimulator3D` in `godotengine/godot` at `8898c2b3d` (MIT). Call it for appendages.
- `ShapeMatchingConstraint`, XPBD distance, and XPBD volume in `InteractiveComputerGraphics/PositionBasedDynamics` `Simulation/Constraints.h` at `10a70bc` (MIT). Study, then write a tiny original cluster.
- `idreesaziz/Gloop` at `aa53ebe` (MIT). A 2D ring of masses, pressure, and distance repairs, drawn with a spline. Proof that a creature reads as soft with tens of points. Study only.

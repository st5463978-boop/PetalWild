# PetalWild

PetalWild is an original living-world game. It starts as a garden: soil, plants, Grokbot jellies, and Veg People. The town of Havenbrook sits beyond the hedge as an aggregate simulation, so the garden can grow into a district later without simulating every citizen at full fidelity.

The garden loop is playable in Godot **4.8.dev6.official.8898c2b3d**.

## Play

```bash
tools/fetch_godot.sh
tools/godot/godot --path . --rendering-driver opengl3
```

Headless simulation check:

```bash
tools/godot/godot --headless --path . --script res://game/debug/smoke.gd
```

A passing run prints `PETALWILD_SMOKE_OK`.

## Controls

- 1–7 tools: Tiller, Seed Pouch, Raincan, Fertilise, Tend, Pond Scoop, Home Kit
- Left click the ground to use the tool. Left click a jelly to grab it; release to pet, drop, or throw
- WASD or arrows pan. Right-drag orbits. Wheel zooms. F focuses
- J journal, B Petal Stall, P photo, Esc pause, F3 debug
- Time scale 1×, 1.5×, 3×

New games start at dusk on day 1 with Sunpetal seeds, Petal Corn seeds, fertility packs, one home kit, and 28 petals.

## What the garden does

Till a bed, plant Sunpetal, water it, and wait. Four mature heads bring Sunburst, a pear-shaped jelly. Sunburst pollinates beds. Thimble follows Sunburst and leaves compost, which is the only soil Moonvine accepts, and only at night. That chain is data in `game/data/species.json` and `game/data/plants.json`, not a hardcoded quest list.

Quin Hearth opens Petal Stall once Sunburst is visiting. Saves are versioned JSON in slot files under the Godot user directory.

Trust stays at 0. The Media Foundry can draft a plan. Approving it at trust 4 records a hold. Nothing is sent, spent, or published.

## Layout

- `game/core/` session, content, save
- `game/sim/` garden, ecology, town, trust, fidelity levels
- `game/world/` terrain and dressing
- `game/jelly/` `game/residents/` `game/ui/` `game/camera/` `game/audio/`
- `docs/` engine pin, recovery, agent contracts, master state
- `third_party/` Nunito (OFL) and a staged CC0 prop demo

## Licence

Original PetalWild code is unpublished, all rights reserved, until a licence is chosen. Third-party terms are in `THIRD_PARTY_NOTICES.md`. Jelly Baby and openage were read as references and were not copied; both are GPL.

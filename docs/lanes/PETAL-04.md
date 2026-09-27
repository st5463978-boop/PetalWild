# PETAL-04 Resident / Sims-like life

Updated 2026-09-27.

## Census (baseline `cursor/dpo-cpu-decide-9cb0`)

| Piece | Status |
| --- | --- |
| Identities (Nessa, Bram, Lumen) | COMPLETE — `data/people.json`, `VegPerson` |
| Jobs / scripted chores | PARTIAL — Bram waters/feeds, Nessa files, Lumen stalls; still scripted in `garden.gd` |
| Day/night/rain routes | PARTIAL — hardcoded in `_apply_shift` |
| Shop wants | PARTIAL — `VillageShop` + `/decide` |
| Needs | PARTIAL — energy/belonging/purpose barely ticked; hunger/social/memories were grove-only |
| Households, motives, neighbour ties | MISSING on the live parish |
| Daily activity pick | MISSING on the live parish (shop buy/want only) |
| LOD for veg people | MISSING — `SimLod` counted jellies only |
| Grove Cara/Mia/Pod/Bran/Oshi | DUPLICATE-LEGACY data in `data/residents.json` (grove WorldState / `person_actor.gd`, not the running garden) |
| `game/data/residents.json` Quin/Neeve | DUPLICATE-LEGACY behind `.gdignore` |

## This checkpoint

Task: persistent parish lives on Nessa, Bram, and Lumen.
Branch: `petal/04-residents`

### Paths
- `scripts/people/resident_life.gd` — needs, motives, activity pick, memories, ties, LOD-cheap data
- `scripts/people/veg_person.gd` — hunger/social/activity label, tired walk, L3/L4 cheap move
- `scripts/game/garden.gd` — tick, walk to stall/tea when not on a chore, save/load
- `scripts/ui/hud.gd` — directory shows hunger, company, household, last memory, neighbour ties
- `scripts/presentation/person_actor.gd` — grove LOD + activity from needs
- `data/people.json`, `data/dialogue.json`, `data/residents.json`
- `tests/test_resident_life.gd`

### Interface
`ParishLife.tick(hours, ctx, chooser)` with `chooser` wired to `PetalDecide.choose` in the garden (offline = first ranked option). Ranked options put the strongest need first so the CPU `/decide` default is sensible. Work/home/rain routes stay with `_apply_shift`; only eat/social/leisure override walking.

### Player-facing
Directory and overhead labels name what they are doing. Clicking a resident writes a memory. Hungry residents walk to the stall; lonely ones take tea. A shared hour raises the neighbour tie and is remembered after save.

### Tests
- `tests/test_resident_life.gd` → `RESIDENT_LIFE_OK`
- `tests/test_systems.gd` → `SYSTEMS_OK`
- `tools/smoke.gd` → `PETAL_RULES_OK`
- garden `PETAL_SMOKE=1` → `PETAL_SMOKE_OK`
- grove `tests/smoke.gd` → pre-existing Variant inference warning on line 89 (PETAL-12); not this lane

Last commit: `b5d8e22` plus decide-steal guard.

### Requests
- PETAL-07: directory already shows the new lines; no UI rewrite needed.
- PETAL-09: Grove Park still unbuilt; leisure uses the tea porch.
- PETAL-08: eating does not auto-buy (avoids coin drift). Shop wants stay as they are.

### Blockers
None.

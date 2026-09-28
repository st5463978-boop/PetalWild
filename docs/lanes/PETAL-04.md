# PETAL-04 Resident / Sims-like life

Updated 2026-09-27. Addendum: executable repo and passing tests are source of truth. Visual QA complements them. PETAL-08 owns campaign state.

## Census

| Piece | Status |
| --- | --- |
| Identities (Nessa, Bram, Lumen) | COMPLETE |
| Jobs / scripted chores | PARTIAL — life sim does not replace watering, filing, stall |
| Day/night/rain routes | PARTIAL — `_apply_shift` still owns work/home/shelter |
| Needs, households, motives, ties, memories | COMPLETE via `ParishLife` |
| Daily activity pick | COMPLETE — ranked needs; `/decide` when live |
| Individual LOD | COMPLETE — L3 skip bob, L4 hide body, data still ticks |
| Grove Cara/Mia/Pod | DUPLICATE-LEGACY (`data/residents.json`, not the running garden) |

## Checkpoint

Branch `petal/04-residents`. Paths: `scripts/people/resident_life.gd`, `veg_person.gd`, `scripts/game/garden.gd`, `scripts/ui/hud.gd`, `scripts/presentation/person_actor.gd`, `data/people.json`, `data/dialogue.json`, `tests/test_resident_life.gd`.

Player-facing: directory names household, motive, hunger, company, ties, last memory. Overhead labels name the activity. A click writes a memory that save/load keeps. Hungry walk to the stall; lonely take tea. Town page counts households.

## Pass 2

Merged `petal/08-integration` (`3402530`) into this lane, then deepened the Sims rung.

1. **Readable directory.** People cards wrap blurb, motive, and memory. Hem-stone and lane-strip rumours stay on the Parish page, so Lumen, Bram, and Nessa fit in one People view.
2. **Grove Park leisure (PETAL-06).** Filing Grove Park remaps dusk leisure onto the lawn. Nobody new is spawned. Labels and memories name the park. Tea stays the social cup.
3. **Stall snack (PETAL-05).** Eating at the stall fills hunger and writes a crop memory. Lumen takes a peach slice from her own till. Nessa and Bram take stock if the crate has it and skip the hourly shop buy that hour. No extra `/decide` on the snack path.

`PETAL_RESIDENT_SHOT=1` writes `wave1_residents.png` (day directory), `residents_park.png` (dusk lawn), and `residents_directory.png` (park-day People page). Do not run full `PETAL_CAPTURE` (it overwrites other lanes' plates).

## Tests

- `RESIDENT_LIFE_OK` — hunger→eat, night→home, rain→shelter, greeting memory, dusk tea ties, stall snack, Grove Park leisure
- `SYSTEMS_OK`, `PETAL_RULES_OK`
- garden `PETAL_SMOKE` checks directory household/job and greeting memory round-trip
- `PETAL_RESIDENT_SHOT_OK` for pass-2 frames
- grove `tests/smoke.gd`: pre-existing Variant warning (PETAL-12)
- Qwen3-VL: not operational here; not used
- `/decide` stays Qwen3-1.7B DPO CPU, offline-first

## Requests

PETAL-09 Grove Park catalog row can stay `active: false`; the filed lawn is the live park. Jobs still do not replace watering, filing, or stall hours.

## Blockers

None.

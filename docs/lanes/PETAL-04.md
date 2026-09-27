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

## Tests

- `RESIDENT_LIFE_OK`, `SYSTEMS_OK`, `PETAL_RULES_OK`
- garden `PETAL_SMOKE` checks directory household/job and greeting memory round-trip
- `PETAL_CAPTURE=1` writes `docs/screenshots/wave1_residents.png`
- grove `tests/smoke.gd`: pre-existing Variant warning (PETAL-12)
- Qwen3-VL: not operational here; not used

## Requests

PETAL-09 Grove Park still unbuilt. PETAL-08 eating does not auto-buy.

## Blockers

None.

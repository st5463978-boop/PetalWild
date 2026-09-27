# Lane receipts

The repo is the memory. Chats are disposable.

Campaign lanes (this wave) live on `petal/NN-name`, created from `cursor/dpo-cpu-decide-9cb0` (`petal-campaign-baseline-20260927`). Never push to `main` or another lane's branch.

Older `PETAL_00`–`PETAL_15` numbers in `docs/AGENT_CONTRACTS.md` are a previous wave. Do not mix those ids with this campaign.

## Lanes

| Id | Branch | Role |
| --- | --- | --- |
| 01 | `petal/01-foundation` | Soil, growth, plants, garden boot |
| 02 | `petal/02-ecology` | Species, ecology rules, visits |
| 03 | `petal/03-jelly` | Jelly bodies, grab, L0–L1 |
| 04 | `petal/04-residents` | Veg people, dialogue, rounds |
| 05 | `petal/05-economy` | Stall, prices, coins, wants |
| 06 | `petal/06-town` | Venues, parish rooms, Grove Park |
| 07 | `petal/07-region` | District, road, land beyond the hedge |
| 08 | `petal/08-integration` | QA, merge, self-play, decide client |

## Receipt file

Keep `docs/lanes/<NN>.md` updated on every checkpoint:

```
# PETAL-NN <name>

- task:
- branch:
- commit:
- paths:
- interface:
- tests: (name, pass/fail)
- blockers:
- requests:
```

Short. No recursive identifiers. If the same failure class hits three times, write `docs/lanes/<NN>-BLOCKER.md` instead of looping.

## Merge

PETAL-08 pulls into `petal/08-integration`. Canonical live scene is `res://scenes/main.tscn` → `res://scenes/garden.tscn` (`scripts/game/garden.gd`). Kenney grove (`scripts/main.gd`, `scripts/sim/`, `scripts/presentation/grove_*.gd`) and `game/` (`.gdignore`) are duplicate-legacy. Do not wire them as the running game.

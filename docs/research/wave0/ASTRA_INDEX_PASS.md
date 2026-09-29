# Astra index, second pass

27 September 2026. The first recovery pass treated [awesome-gpt-6-astra](https://github.com/MartinDelophy/awesome-gpt-6-astra) as a pointer and followed one village repo. This pass opened the catalogue itself.

The list is 162 playable entries, updated on the page as 2026-09-26. Catalogue text is CC0-1.0. That grant is the list, not the games. Eighteen distinct source repositories are linked. The other entries are a play link, a creator post, or both. A playable page with no repository is not a candidate.

Hailo was not asked again. The earlier decide calls in this wave returned HTTP 502. These classes are from the licence files.

## What the list actually contains

Strategy and simulation is one section of about thirty entries. Most of that section has no source. The ones that matter to a garden, and what was done with them:

| Entry | Source | Class | Decision |
| --- | --- | --- | --- |
| Melon Lab (soft fruit) | `Ayi1337/gpt6-astra-one-shot-games` `4178b08` | RED | REJECT |
| CityMaker | `derek-wangpch/OpenCityMaker` `dc78e7f` | GREEN | STUDY |
| The Free Game | `LucasMarquesShiva/the-free-game` | YELLOW | STUDY, already carded |
| Dwellcraft | `Ryan-fm/Dwellcraft` | RED | REJECT, already carded |
| Jelly Baby | `scottstts/Jelly-Baby` | REVIEW | STUDY, already carded |
| Orbital Garden | file inside the catalogue, no grant of its own | REVIEW | do not copy |
| Last Beacon | `stackloomdev/last-beacon` | GREEN | not a garden system |
| Outerstead, Stillwater, Realm of Seratari, Mystery Town, Infinite Garden, Greenhouse, Chao Party | no repository on the entry | — | observed only |

## Melon Lab

The parent repository has no `LICENSE` file. GitHub reports no SPDX. Public source is not permission. Decision REJECT. Do not copy `melon-lab/src/public/physics.js`.

What the file is, so PETAL-03 does not hunt it again: a 2D ring of eighteen points, a distance constraint around the ring, a weak pull across the diameter, and a pressure term that tries to keep the enclosed area. Same-size fruits that overlap become one larger fruit. That is the same budget as Gloop, which is MIT and already STUDY. Melon Lab does not replace that card, and it does not replace the Jelly-Baby feel note. It has no grab and no throw.

## CityMaker

`LICENSE` is MIT, copyright 2026 Derek Wang. Commit `dc78e7fe87809470bfe13f95cee6c90b195cd2dd`.

It is a 4×4 2048 board. Twelve real cities, eleven silhouette tiers each, procedural Three.js models, a local save per city. It is not a settlement simulator, not residents, and not roads.

PETAL-06 can use the presentation idea: a town reads as a few silhouettes on a board, and a closer view is a choice, not a second game. Do not import the project. Do not copy the landmark atlas or the real city names into Petalwild.

## Orbital Garden

`works/orbital-garden/` is committed in the catalogue. `package.json` states no licence. The catalogue's own licence section says linked code keeps its own licence. Do not treat the CC0 badge as a grant on `index.html`.

The observed idea is presentation only: each particle keeps an identity while the shape eases from one form to another. That is not a plant sim and not a soft body. Leave the file where it is.

## Other linked repositories

Opened far enough to read the GitHub licence API or the `LICENSE` file. None of these solve grab, growth, residents, or the stall.

| Repository | SPDX / file | Decision |
| --- | --- | --- |
| `BEROCHLU/astrafloor` | MIT | Not a candidate. Zombie shooter. |
| `threapchills/MagicCarpetWizard` | no licence file | REJECT |
| `Hiraeth010/blackwater` | MIT | Not a candidate. Tactical shooter. |
| `yongqixue99-hue/fruit-ninja-dojo` | no licence file | REJECT |
| `Ryan-fm/clockout-unseen` | no licence file | REJECT |
| `MiaAI-Lab/GPT-6-Astra-100-HTML-Files` | no licence file | REJECT. Pixel Orchard is a memory match inside this dump. |
| `stackloomdev/silent-meridian` | MIT | Not a candidate. Point-and-click. |
| `Vheissu/hit-and-run-web` | MIT text, then a carve-out | REJECT. The MIT grant is the new code. It does not cover The Simpsons: Hit & Run assets. |
| `sgyno09-source/dual-realms` | no licence file | REJECT |
| `tayttm/race-jimothy` | no licence file | REJECT |
| `asmoyou/toy2game` | Toy2Game Noncommercial License 1.0 | REJECT. The README says the grant is source-available and not an OSI open-source licence. |

`user-attachments` links in the list are screenshots, not repositories.

## Playable pages with no source

These were named in the visual brief or sit in the simulation section. The HTML was not fetched again. The catalogue entry is the whole of the record. Do not reconstruct them from the live site.

- Outerstead: four survivors, food, and work priorities. No repository.
- Stillwater: an aquarium with feed and plants. No repository.
- Realm of Seratari: one creature, towns that grow off to the side. No repository.
- Mystery Town, Infinite Garden, Greenhouse Escape Room: no repository on the entry.
- Chao Party: an unofficial Sonic fan game. No repository, and the characters are not ours.
- Monopoly City, Sundrift, Cabsolutely, AGI of Empires: already noted as pages in `r2_notes.md`. Still no source worth a card, except CityMaker above.

## What changed for the build lanes

PETAL-03 does not gain a solver. The unlicensed fruit ring is rejected. The grab rewrite and the later spring-bone call stay the jelly cards.

PETAL-06 gains CityMaker as a readability STUDY. It does not gain a city importer.

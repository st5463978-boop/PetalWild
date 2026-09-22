# PetalWild open-asset hunt

Checked 2026-09-22 by PETAL-13. Pages and zip headers were fetched live. Nothing in this note was copied from a commercial game. Viva Piñata, Nintendo, and Cities: Skylines were not searched and not downloaded.

Art bar, from `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`: a soft, lush storybook garden. Rounded orchard trees and a willow, clipped hedges, flower rows, dark soil beds, a stone path, a small pastel shed or stall, warm morning light. A pack survives only if it can sit in that picture. A flat low-poly kit dumped in raw does not. A photogrammetry shrub dumped in raw does not.

Licence bar: CC0, MIT, BSD, or Apache preferred. CC-BY is recorded as yellow and is not on the shortlist. Unclear or custom licences are rejected. GPL and AGPL are rejected even when the upstream art is CC0.

## Shortlist (would survive art direction)

Ten packs. Sizes are the live download, not a guess. "Use" is the PetalWild slot, not a claim that the pack is already shaded for the game.

| # | Pack | Source | Creator | Licence | Use | Size | Style |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Stylized Nature MegaKit, Standard | https://quaternius.com/packs/stylizednaturemegakit.html and https://quaternius.itch.io/stylized-nature-megakit | Quaternius | CC0 | Trees, flowers, grass, rocks | 99 MB zip on itch; OpenGameArt lists the same standard set at 104.1 Mb | Closest mesh match. The live preview is a soft painted forest with rounded canopies, a dirt path, and simple rocks. Still stylized, so use the leaf cards and a warm grade. The free tier is a subset (OpenGameArt says 68 of 116 models). Source tier (paid, still stated CC0) adds Godot shaders. |
| 2 | Stylized Garden Asset Pack | https://assetquest.itch.io/stylized-garden-asset-pack | Asset Quest | CC0, stated on the page and inside the demo zip | Flowers, grass cards, pots, furniture, walls, pavilions | Full zip 82 MB. Free demo 4.7 MB (downloaded; see below) | The live setup render is a planted clump: sunflower, hydrangea-like blooms, a white bench, grass cards. More garden than forest, and softer than Kenney or KayKit. Import the demo before promoting the 82 MB pack to hero props. |
| 3 | Poly Haven garden HDRIs: Meadow, Forest Slope, Arboretum | https://polyhaven.com/a/meadow , https://polyhaven.com/a/forest_slope , https://polyhaven.com/a/arboretum | Sergej Majboroda; Andreas Mischok; Sergej Majboroda | CC0 (site-wide) | Sky and light only | 1K HDR about 1.7–1.8 MB each; 4K about 22–28 MB | These do not become meshes. Meadow is the low-contrast one (Meadow 2 is high-contrast and is not the pick). Forest Slope is low-contrast canopy light. Arboretum is warm, partly cloudy sunrise, which matches the target plates. |
| 4 | ambientCG ground trio at 1K JPG | https://ambientcg.com/view?id=Ground037 , https://ambientcg.com/view?id=Ground023 , https://ambientcg.com/view?id=PavingStones138 , https://ambientcg.com/view?id=Moss002 | ambientCG | CC0, https://ambientcg.com/license | Lawn, leaf-litter beds, mossy path, hedge bases | 1K-JPG zips: Ground037 10.1 MB, Ground023 10.0 MB, Moss002 9.9 MB, PavingStones138 4.7 MB. Confirmed by HEAD on 2026-09-22 | Photo scans. They survive only after the albedo is pulled into the painted greens and browns. Do not use 4K/8K detail, and do not leave them as realistic PBR next to the shed. |
| 5 | Poly Haven Brown Mud Leaves 01, 1K | https://polyhaven.com/a/brown_mud_leaves_01 | Rob Tuytel | CC0 | Dark mulch in the vegetable beds | 1K JPG maps are about 1.2 MB diffuse, 1.4 MB GL normal, under 1 MB each for AO, rough, and height | Same rule as the ambientCG trio: palette-crush it. It is a bed texture, not a hero surface. |
| 6 | Poly Haven Bark Willow, 1K | https://polyhaven.com/a/bark_willow | Dario Barresi, Dimitrios Savva | CC0 | Willow and orchard trunks | 1K JPG set is about 3.8 MB across diffuse, rough, GL normal, height, and AO | Use softened, at 1K, on smooth trunks. A sharp photo bark tile will fight the storybook trees. |
| 7 | UI Audio | https://kenney.nl/assets/ui-audio direct zip linked from that page | Kenney | CC0 on the page | Stall and tool UI | 0.39 MB zip | No visual style. Soft clicks can survive; skip anything that sounds like an arcade menu. |
| 8 | Interface Sounds | https://kenney.nl/assets/interface-sounds | Kenney | CC0 on the page; OpenGameArt mirror https://opengameart.org/content/interface-sounds | Confirm, cancel, select | 0.80 MB zip (834,536 bytes). OGA describes 100 OGG files | Same as UI Audio. Pick the dull confirms. |
| 9 | Impact Sounds | https://kenney.nl/assets/impact-sounds | Kenney | CC0 on the page. Page lists 130 files | Place, dig, and soft foley | 0.76 MB zip (800,850 bytes) | Survives if the sharp cartoon hits are left out. |
| 10 | Park ambiences | https://opengameart.org/content/park-ambiences | Thimras | CC0 on the OpenGameArt page | Birds, small water, wind bed | Three separate WAVs: birds 86.2 Mb, river 99.1 Mb, wind 74 Mb | Real park takes from Adelaide, which fit a garden bed better than synth jingles. They are not a zip with a licence file inside, so they were not downloaded. Audition and cut the rain-heavy start of the birds take. |

Import order that protects the look: light (3) first, then Quaternius trees and rocks (1), then AssetQuest flowers and props (2), then palette-crushed ground (4, 5, 6), then audio (7–10). Do not drop 1 and 2 in unshaded.

## Downloaded this pass

One pack, under the 30 MB cap, and only because `Readme/Licence_DEMO.txt` is inside the zip.

`third_party/incoming/assetquest-stylized-garden-demo/`

AssetQuest Stylized Garden free demo. 4,883,126 bytes. SHA-256 `a9fd020e798d1c13590d2153bf8003d4524e5fc55d5bebda4969128c1aba55f5`. Provenance and the full licence quote are in that folder's `PROVENANCE.md`.

Quoted licence line: "License: (Creative Commons Zero, CC0)" and "You can use this content for personal, educational, and commercial purposes." Credit to Asset Quest is optional. The demo is a slice (bench, table, planter, umbrella, several flowers, two grasses), not the 82 MB pack.

No other archive was kept. Kenney zips were sized with HEAD requests only.

## Reachable, but do not drop in raw

These are real CC0 downloads. They fail the storybook bar as hero art. Useful as blockout or as a reminder of what not to ship.

| Pack | Source | Creator | Licence | Use if any | Size | Why it fails raw |
| --- | --- | --- | --- | --- | --- | --- |
| Nature Kit | https://kenney.nl/assets/nature-kit | Kenney | CC0 (badge on the live sample, and on https://opengameart.org/content/nature-kit) | Blockout only | Kenney zip 10.1 MB (10,537,521 bytes). OGA lists Nature Kit (2.1).zip at 10.5 Mb, 330+ models | Flat triangles, camping props, cyan palette. A collage, not a garden. |
| Foliage Sprites | https://kenney.nl/assets/foliage-sprites | Kenney | CC0 | Not for the 3D grove | 2.32 MB | Flat 2D leaf sprites. |
| Tiny Farm | https://kenney.nl/assets/tiny-farm | Kenney | CC0 | None as hero art | 0.18 MB zip. Page says released 2026 | Same Kenney family. Too small and too diagrammatic for the target. Preview was not judged beyond the pack family. |
| Food Kit, Furniture Kit, Holiday Kit | https://kenney.nl/assets/food-kit , https://kenney.nl/assets/furniture-kit , https://kenney.nl/assets/holiday-kit | Kenney | CC0 | Prop blockout only | 4.39 MB, 4.89 MB, 4.27 MB | Low-poly kits. They will not read as the stall, the shed, or the harvest. |
| KayKit Forest Nature Pack, free tier | https://kaylousberg.itch.io/kaykit-forest and https://kaylousberg.com/game-assets/forest-nature-pack | Kay Lousberg | CC0. The page also asks that unmodified copies not be resold | Massing blockout only | Free 6.1 MB (100+ models). Extra 81 MB. Source 94 MB | One atlas and one author, so it is not a collage, but the live sheet is hard-facet blobs and stacked rocks. It does not survive a close view. |
| Niwl lowpoly plant pack | https://niwl-games.itch.io/plants | Niwl Games | CC0 on the page | Godot-ready blockout only | Page lists 15 MB, 11 MB, and 32 MB files. Which file is the free tier was not separated | Named and tagged as low-poly. |
| Tiny Treats house plants, free | https://tinytreats.itch.io/house-plants | Tiny Treats | CC0 on the page | Indoor pots only, if ever | Free 17 MB. Source 21 MB | Gradient-atlas houseplants, not the outdoor hedge and rows. |
| Ultimate Nature, Simple Nature, Ultimate Crops, Ultimate Food | https://quaternius.com/packs/ultimatenature.html , https://quaternius.com/packs/simplenature.html , https://quaternius.com/packs/ultimatecrops.html , https://quaternius.com/packs/ultimatefood.html | Quaternius | CC0 mentioned on each live page. Sizes are not printed on those pages | Crops can proxy growth stages in greybox | Not published on the pages checked | 2016–2020 flat kits. The MegaKit replaces them for anything the camera sees. |
| 3D Low-Poly Exterior Plants | https://godotengine.org/asset-library/asset/1604 | Malcolm Nixon (Shapespark kit converted to Godot) | CC0 on the official Asset Library page | None | Not sized this pass | Low-poly exterior plants, ready as scenes, wrong look. |
| Poly Haven photo plants | https://polyhaven.com/a/shrub_03 , https://polyhaven.com/a/grass_medium_01 , https://polyhaven.com/a/fern_02 , https://polyhaven.com/a/dandelion_01 | Rico Cilliers, Rob Tuytel | CC0 | Reference, or a normal-map study | Shrub 03 page bundle was listed around 16 MB. Grass Medium 01 is a 2M-triangle clump, about 62 MB on the asset page | Photogrammetry next to the pastel shed breaks the storybook read. |
| Music Jingles, RPG Audio | https://kenney.nl/assets/music-jingles , https://kenney.nl/assets/rpg-audio | Kenney | CC0 | Not the garden score | 1.18 MB and 0.92 MB | Short game cues, not birds and wind. |
| Birds and Wind | https://opengameart.org/content/birds-and-wind-ambient-birds-wind-and-synth | Spring Spring | CC0 | Audition only | 13.9 Mb OGG | Synth plus birds. It may fight a storybook score. Single file, no licence file inside, not downloaded. |

## Rejected

| Item | Why |
| --- | --- |
| Godot Asset Library "Quaternius' Simple Nature pack" by Lopano, asset id 1819 | Official library API (`filter=nature`, Godot 4.3) returned this as the only nature hit, and its cost field is GPLv3. Do not copy it. The Quaternius original is CC0; this port is not. |
| Pixabay audio and photos | Pixabay Content License is a custom licence, not CC0, MIT, BSD, or Apache. |
| Freesound pack "park & garden NL EU 2020" and "wind garden" by klankbeeld | The live sound page requires credit and forbids use in royalty-free stock. That is CC-BY plus an extra limit. Yellow, and not shortlisted. |
| Freesound `AMB_garden_summer_afternoon_birds and wind` by matucha | The snippet uses CC0-style wording, but this pass did not open a licence file for it. Left as unclear rather than shortlisted. |
| Itch "Free Nature Sounds" by Outta This World Audio | Custom royalty-free text, AI-assisted tag, and a ban on redistributing the files as a library. Not CC0. |
| store.godotengine.org listing of the MegaKit | A CC0 label was visible there, but that record was not in the official Asset Library API result above. Take the pack from Quaternius. |
| Any ripped commercial garden, including Viva Piñata, Nintendo, and Cities: Skylines | Out of scope. Not downloaded. |

## Direct Kenney zips confirmed reachable

HEAD 200 on 2026-09-22. These URLs were extracted from the asset pages, not invented.

- Nature Kit: https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip
- Impact Sounds: https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip
- Interface Sounds: https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip
- UI Audio: https://kenney.nl/media/pages/assets/ui-audio/490d233f68-1677590494/kenney_ui-audio.zip

Kenney zips usually carry their own CC0 text. That was not re-opened this pass, because the one kept download is the AssetQuest demo, whose licence file was read.

## Gaps

No public CC0 pack found this pass is already the painted hedge-and-shed look. The shortlist is the set that can be graded into it. Hedges, the willow silhouette, the pastel shed, and the vegetable rows still need to be built or heavily edited. The full AssetQuest pack and the Quaternius standard MegaKit are the next two downloads when a larger fetch is allowed.

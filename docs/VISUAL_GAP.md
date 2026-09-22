# Visual gap

Compared on 2026-09-22. The scene `tools/run.sh` launches is Hedge Hollow. Shots: `docs/screenshots/wave1_overview.png`, `wave1_jelly.png`, `wave1_lumen.png`. Targets: `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`.

The north backdrop trees are shorter than the hedge. Canopy walls (far north and the inner north hedge) are one spine at 0.45 of the old width, with leaves kept on the crest. That stem cut does not open the skyline: the far band (screen y 280–345) is still about 64–80% occluder against the hill color, same as the previous overview. Leaf cards still fill those columns, and the stall sits in front of the central notch. Bellhelp’s close-up is unchanged: a matte green cup with a small gold center on open lawn. StandardMaterial3D specular is disabled (the old `specular` float was ignored). Pure white on the overview dropped from 0.582% to 0.417% (5401 of 1,296,000 pixels).

## Three largest gaps

1. **Hedge skyline.** The lower body is still a leafy wall. The stem is narrower; the leaf coat still bridges the 2.5 m gaps. PETAL-05.

2. **Bellhelp.** The cup reads and the center no longer glows. The silhouette is still a simple cup rather than a layered blossom. PETAL-03.

3. **Highlights.** 0.417% of overview pixels are pure white. The largest clusters sit on the foreground path (around y 760) and in the stall band (around x 680, y 320). PETAL-06.

# Visual gap

Compared on 2026-09-22. The scene `tools/run.sh` launches is Hedge Hollow. Shots: `docs/screenshots/wave1_overview.png`, `wave1_jelly.png`, `wave1_lumen.png`. Targets: `docs/reference/petalwild_target_garden_01.png` and `petalwild_target_garden_02.png`.

The outer hedge rises and falls, with leaf cards along the walls. A lower hedge boxes four beds. Bellhelp is a green bell with a petal skirt. Lumen is a leek with a leaf crown, apron, spectacles, and satchel.

## Three largest gaps

1. **Hedge mass.** The outline is broken, and the wall under the cards is still one shader mesh. PETAL-05 and PETAL-06.

2. **Bellhelp.** The petals read. The core is still a glossy lathe with no inner seed. PETAL-03 and PETAL-06.

3. **Ground and light.** Lumen is still capsules. The lawn inside the rooms is one plane, and there are no sun shafts on llvmpipe. PETAL-04 and PETAL-06.

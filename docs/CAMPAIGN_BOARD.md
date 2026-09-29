# Campaign board

NOW / NEXT / LATER. The long-term town-and-civilisation target is not this week's work.

## NOW

Playable Hedge Hollow on `petal/09-art-rescue`, continued on `cursor/playable-jelly-body-9956`.

- Tend the four beds. Feed a jelly from a ripe plant or the pouch.
- Grab, nuzzle, throw. A fed idle jelly shows the approved cut-out. Hunger or a grab shows a shaded gel icon with two black eyes. The grab squash stays in camera space, so those eyes stay on the front. A neon mark floats above that icon: cog while a hungry jelly is walking to food, envelope when a visitor comes back, heart for a snack or a click, locked heart when two adults of one species are here. The eyes stay clear.
- Stall, jam, tea, journal. A carried jam crate sells at the Petal Stall for petal coins, the jam crate drops, dusk shuts that sale with the stall, and the save keeps the coins and the crate. Vale map on M. Town page on C. Selling the last carried tea empties the open South Lane kitchen cup. A crate left on the stall keeps that cup full. Carrying a pot, a resident finishing the crate, or a new pot refreshes that same open cup. Coins stay put unless it was a sale.
- Enter near the Hedge Tea House opens that room on the cottage camera path. The porch kettle and its steam are on the counter. Carrying while the room is open fills the South Lane cup and does not move coins. Esc closes the room and puts the kettle back on the porch. `tea_house.active` stays false.
- Enter near the potting shed opens that room on the same path. The jam pan and its steam sit on the bench. Cooking and carrying stay the mill calls and do not move coins. Esc closes the room and puts the pan back in front of the shed. `grove_park.active` stays false.
- Grove Park opens after the road rumour and Nessa's filing. Lumen and Bram walk through the hedge gate and stay on the grass. South Lane puts six cottages on that path when the rumour is filed. A near camera stands one tomato household at the first door. Enter steps into that kitchen. T drinks one kettle tea. G walks that household through the gate to the lawn, the lawn count includes them, their cottage window goes dark while they are out, and arriving there draws a hungry Bellhelp onto that grass with both eyes showing. G again walks them home. The place page names where they are, keeps the tea sip after reload, and Reed’s near-row matches. Esc steps back out. The hint shows Enter, T, and G. Clicking the household says the tea line. Catalog stays `active: false`.

## NEXT

- `PETAL_QA_SCRIPTS_OK`, `ICON_FACE_OK`, `JELLY_PLAY_OK`, and `PETAL_RESIDENT_SHOT_OK` are green on this tip (2026-09-29). The held plate and the landed plate show the gel with both eyes on the front. Carried tea already sells at the stall. Carried cane jam already sells too: `JAM_CRATE_SOLD_OK`.
- `KITCHEN_CUP_SOLD_OK` covers the open kitchen after the last stall sale. `KITCHEN_CUP_LIVE_OK` covers that same open cup after a carry, after Lumen finishes the crate, and after a new pot.
- Neon status marks are on this branch. `JELLY_ICON_OK` is the plate where the cog sits above both eyes. The demo scene and gif reel stay on `cursor/jelly-status-icons-ffcb`.
- `PETAL_TOWN_SHOT_OK` shows the door household, then the sealed kitchen with the window, Moss, and the tea cup, then the lawn again.
- `PETAL_TEA_HOUSE_SHOT_OK` opens the tea house, keeps the kettle in frame, carries without paying, and Esc closes the room (`tea_house_inside.png`).
- `PETAL_SHED_SHOT_OK` opens the potting shed, keeps the pan and its steam in frame, carries without paying, and Esc closes the room (`potting_shed_inside.png`).
- `kettle_brew.png` keeps the brewing kettle and its steam in frame. `jam_pan.png` still shows the copper pan in front of the shed wall. The research hut is still the outside shell. The same Enter / Esc room is the next interior. The other cottages stay closed.
- Point `main` at this garden when the suite stays green. Do not replay the east-chain.

## LATER

- City Park pond scene (`cursor/city-park-pond-c8ec`) as a destination, after the live garden still boots.
- Water plan (`docs` on `cursor/water-plan-937d`). No shader until the pond the player scoops needs it.
- Trust ranks above the filing that already exists. External actions stay inside the sim.
- Agent civilisation, distant bodies, and a second town grid.

## Do not rebuild

East-chain paces. Kenney parish boot. GPL jelly source. Lane branches 01–07 as whole merges. Generated placeholder art.

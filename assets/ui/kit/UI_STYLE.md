# PetalWild UI style guide + prompt sheet (v1, 28 Sep 2026)

Owner: art desk. Status: **v1 proposal – awaiting Scott's pick of direction.**
Companion: `ui_palette.png` (labelled swatch), `tools/build_ui_kit.py` (post-process pipeline), `tools/ui_manifest.json` (asset list, sizes, 9-slice margins).
Harmonises with `/workspace/petalwild-artdesk/VISUAL_TARGET.md` (target v1). The world is a warm toy diorama; the UI is the **ornate carved frame around the diorama** – a mantelpiece you look through.

## 1. Pillars
1. **Carved, layered relief.** Every frame is built like a mantel or cornice: 3–5 stepped mouldings (fillet → cove → bead → ogee), bead-and-reel and egg-and-dart runs, rosettes at corners. Depth comes from stacking, not from clutter.
2. **Precious garden materials.** Green marble panels, burnished gold and brass trim, warm carved walnut. Gold picks up the lantern colour; marble picks up the hedge greens.
3. **Psychedelic shimmer, cosy restraint.** An iridescent green→gold sheen and a soft inner glow on edges and selected states only. Centres stay calm and readable.

## 2. Camera and medium
Front-on orthographic (no perspective, no tilt), hand-painted / lightly rendered 2D with real material feel (not pixel art, not flat vector). Light from the **top-left**, warm (`#f2dea7`), matching the world's late-afternoon sun. Soft ambient occlusion in carved recesses; no hard black drop shadows baked into assets (Godot adds shadows via StyleBox/shader).

## 3. Palette (UI roles) – world hexes reused where they fit
| Role | Hex | From |
|---|---|---|
| Marble base (panel fill) | `#1f5a2c` | proposal, between hedge core `#0b5d12` and moss `#236b1b` |
| Marble light vein | `#6fcc38` → `#9fd82d` | leaf-tip highlight / clover light |
| Marble dark vein / deep recess | `#0b3d14` | proposal (darker than hedge core, above `#1f130b` floor) |
| Hedge green accent | `#2f9d2b` | hedge base |
| Lawn accent (hover tint) | `#75bd27` | lawn base |
| Gold highlight | `#f8c04b` | lantern glow |
| Gold mid (burnished) | `#e2af64` → `#ecb12a` | sign board / thatch |
| Gold shadow / brass | `#b57a07` | sunflower amber |
| Brass deep | `#6e4d32` | timber shadow |
| Carved walnut | `#936942` | stall timber |
| Walnut highlight | `#d5bc9a` | planed edge |
| Parchment (journal, text plates) | `#f5dbb4` | awning cream (brightest allowed) |
| Ink (text on parchment) | `#322116` | soil base |
| Text on marble | `#f5dbb4` with `#1f130b` 2 px outline | cream / soil gap |
| Iridescent sheen ramp | `#2f9d2b` → `#6fcc38` → `#f8c04b` → `#e28d17` | hedge → leaf tip → lantern → lantern amber |
| Selected glow | `#f8c04b` @ 60–80% additive | lantern glow |
| Danger / low water | `#c84b1d` | poppy orange-red |
Rules: no pure `#ffffff` / `#000000` (same as world). No blue/teal UI chrome (sky `#cee5fd` only for the weather badge sky).

## 4. Detail budget and readability
- **Frames only are ornate.** Panel/slot/button interiors are plain marble or parchment with ≤ 10% vein contrast so text and icons sit on calm ground.
- Border depth at 1x (1920×1080 base): panel 48 px, top bar 40 px tall trim, slot 12 px, button 16 px.
- **Phone check:** everything must read at 50% of 1x (phone 1266×585 capture). Icons read by silhouette alone at 32 px; ornament may blur into a gold band there – that is fine, it must not blur into the icon.
- Selected state must differ by **both** value and glow, not colour alone (colour-blind safe).
- Out of bounds: skulls, religious iconography, readable fake text/runes in ornaments, neon magenta/cyan, chrome/silver, thin spiky filigree that aliases at 1x.

## 5. Specs (Godot 4.8)
Design base 1920×1080 (**1x**); **2x** = 3840×2160 (4K PC). Masters are the raw generations (≈1024–1536 px) kept untouched in `masters/`.
Project: `display/window/stretch/mode = canvas_items`, aspect `expand`. Ship the **@2x** set; Godot downsamples for 1080p, browser (1600×900) and phone. Import: Filter **Linear**, **Mipmaps ON** (downscaled UI stays clean), Compress **Lossless** (VRAM compression smears gold edges), Fix Alpha Border ON. Keep @1x for the browser build if the download budget (≤ 60 MB) gets tight.

| Asset | File stem | @1x size | @2x size | 9-slice margins @1x (L,T,R,B) | Notes |
|---|---|---|---|---|---|
| Panel frame | `ui_panel_9slice` | 192×192 | 384×384 | 48,48,48,48 | StyleBoxTexture / NinePatchRect, centre = stretch |
| Top bar | `ui_topbar` | 1200×88 | 2400×176 | 120,0,120,0 (3-slice horizontal) | centre tiles/stretches |
| Hotbar slot | `ui_slot_{normal,hover,selected}` | 96×96 | 192×192 | 16,16,16,16 | icon sits in inner 64×64 |
| Primary button | `ui_button_primary` | 240×72 | 480×144 | 32,24,32,24 | gold-faced |
| Secondary button | `ui_button_secondary` | 240×72 | 480×144 | 32,24,32,24 | walnut/marble-faced |
| Petal currency | `ui_icon_petal` | 32×32 | 64×64 | – | + `@4x` 128 for shop |
| Tool icons ×10 | `ui_tool_{tiller,seed,raincan,fertilize,tend,scoop,home,hands,journal,stall}` | 64×64 | 128×128 | – | transparent, no frame (slot provides it) |
| Weather/day badge | `ui_badge_weather` | 128×128 | 256×256 | – | round medallion, sun/cloud swaps later |
| Journal page | `ui_journal_page` | 800×560 | 1600×1120 | 64,64,64,64 | parchment in carved frame |
| Cursor | `ui_cursor` | 32×32 | 64×64 | – | hotspot (2,2) @1x / (4,4) @2x; Godot max 256 |
| Logo plate | `ui_logo_plate` | 800×320 | 1600×640 | – | text is **re-set in Godot/PIL** if the generation mangles it |
Naming: lower case, `ui_<subject>[_<state>]@<scale>x.png`; 9-slice files carry `_9slice`; margins also written to `kit/ui_kit_margins.json`.

## 6. Prompt sheet (built-in image generator)
I write the prompts; the generator makes the images. Every prompt = STYLE BLOCK + subject line + NEGATIVES.

**STYLE BLOCK (use verbatim, 55 words):**
> Game UI asset for a cosy garden sim, front-on orthographic, hand-painted with real material feel. Ornate carved relief with layered cornice mouldings, coving, bead-and-reel and egg-and-dart trim. Polished green marble (#1f5a2c with #6fcc38 veins), burnished gold and brass (#f8c04b, #b57a07), subtle iridescent green-to-gold sheen, soft warm glow, top-left warm light. Readable, calm centre.

**NEGATIVES (append):**
> Isolated on a flat solid pure magenta (#FF00FF) background, no other background, no scenery, no text, no letters, no watermark, no signature, no baked drop shadow, no perspective or tilt, no cropping at the frame edge, no neon, no chrome silver, no skulls.
(The logo prompt drops "no text / no letters".)

### 6a. Exploration boards (3 images, 16:9)
1. **A – Green marble + gold filigree:** "Style exploration sheet on one canvas: a rectangular panel frame, a long top bar, three square inventory slots (normal, glowing hover, gold-lit selected), two buttons, a round medallion badge. Green marble fields framed by stepped burnished-gold cornice mouldings with fine gold filigree and bead trim."
2. **B – Carved walnut + brass:** same layout, "warm carved walnut frames with deep stepped mouldings, acanthus rosettes at the corners, brass beading and brass corner caps, green marble inlay panels in the centres."
3. **C – Psychedelic iridescent:** same layout, "green marble and gold, but the gold mouldings shimmer with an iridescent green-to-gold oil-slick sheen, softly glowing edges, faint luminous veins in the marble, dreamy but still cosy and readable."

### 6b. Kit subject lines (winning direction's material words replace the STYLE BLOCK materials if B or C wins)
| # | Stem | Subject line | Aspect |
|---|---|---|---|
| 1 | panel | "A single square ornamental panel frame filling the canvas, symmetrical on all four sides, identical corners with small rosettes, straight uniform moulding runs along each edge so it can be nine-sliced, plain dark green marble centre." | 1:1 |
| 2 | topbar | "A single long horizontal banner bar, 12:1 proportions, ornate end caps with rosettes on left and right, a straight uniform moulded middle section, plain green marble inner strip for text." | 16:9 |
| 3 | slots | "Three square inventory slots side by side, same frame each: left plain (normal), middle with a soft green-gold inner glow (hover), right with bright gold-lit rim and warm lantern glow (selected). Empty dark marble wells." | 16:9 |
| 4 | buttons | "Two wide rounded-rectangle buttons stacked vertically: top is gold-faced with a raised bevel (primary); bottom is carved walnut with brass edge (secondary). Blank faces, no text." | 16:9 |
| 5 | petal | "A single small game currency icon: a chunky five-petal flower coin in gold with a green marble centre, thick rounded petals, bold silhouette." | 1:1 |
| 6–15 | tools | One per image: "A single chunky game tool icon, bold silhouette, gold and brass with carved walnut handle, green enamel accents: **<tool>**." Tools: tiller = small garden hoe/tiller; seed = seed pouch with sprouting seed; raincan = watering can; fertilize = sack of fertiliser with sparkles; tend = pruning shears with leaf; scoop = trowel scoop; home = small cottage; hands = open gloved hand; journal = closed leather journal with gold clasp; stall = market stall with striped awning. | 1:1 |
| 16 | badge | "A single round medallion badge, carved gold rim with bead trim, inner disc showing a soft golden sun over green hills, blank lower scroll ribbon." | 1:1 |
| 17 | journal | "An open journal page in landscape: warm cream parchment (#f5dbb4) centre, framed by a carved walnut and gold border with corner rosettes, faint botanical watermark, no writing." | 16:9 |
| 18 | cursor | "A single ornate pointer arrow cursor pointing to the top-left, gold with green marble inlay, thick and chunky, tip at the very top-left." | 1:1 |
| 19 | logo | "A wide ornamental title plate: green marble cartouche with layered gold cornice frame and leafy flourishes, the word 'PetalWild' in large elegant gold serif letters in the centre." | 16:9 |

### 6c. Variation grid (change ONE variable per line if a batch misses)
1. Material weight: "gold mouldings" → "brass mouldings" (less glare).
2. Ornament density: "fine filigree" → "broad simple beading" (for phone readability).
3. Sheen strength: "subtle iridescent sheen" → "strong iridescent sheen".
4. Relief depth: "shallow relief" ↔ "deep layered relief".
5. Background obedience: add "the entire background is flat magenta #FF00FF" at the start if the key colour drifts.

## 7. Post-process (tools/build_ui_kit.py)
Raw → `raw/`; masters copied verbatim → `masters/`. Magenta key (distance from `#FF00FF` + despill) → trim → split sheets by connected components → fit to @2x → Lanczos @1x → 9-slice margins written to JSON → `contact_ui.png` → `mock_hud.png` over `garden_overview.png` → INVENTORY rows (licence: generated in-house).

## 8. Run sheet (generation → build)
Status 28 Sep 2026 ~01:40 BST: **no images generated yet**. The executor lane that wrote this sheet had no GenerateImage tool (only ComfyUI-MCP, with no ComfyUI installed and no GPU on the box, plus Higgsfield, which is zero-spend). The pipeline has been smoke-tested on procedural stand-ins in `_pipeline_test/` (not art).
Planned generation budget: **≤ 28** (3 boards + 19 kit images + up to 6 rerolls). Before each batch: `python3 /home/box/tools/image-quota/imgquota.py check N`; after: `record N "petalwild ui <what>"`.

1. Boards → save as `boards/board_A_marble_gold.png`, `boards/board_B_walnut_brass.png`, `boards/board_C_iridescent.png` (3 gens).
2. Pick a direction (see §6a); swap its material words into the STYLE BLOCK.
3. Kit raws → save into `raw/` with exactly these names (19 gens): `panel.png`, `topbar.png`, `slots.png` (3 slots in one row, left→right normal/hover/selected), `buttons.png` (primary above secondary), `petal.png`, `tool_tiller.png`, `tool_seed.png`, `tool_raincan.png`, `tool_fertilize.png`, `tool_tend.png`, `tool_scoop.png`, `tool_home.png`, `tool_hands.png`, `tool_journal.png`, `tool_stall.png`, `badge.png`, `journal.png`, `cursor.png`, `logo.png`.
4. Build: `python3 tools/build_ui_kit.py --root /workspace/art_library/ui --inventory /workspace/art_library/INVENTORY.md`
   → `kit/*@1x.png`, `kit/*@2x.png` (+ `ui_icon_petal@4x.png`), `kit/ui_kit_margins.json`, `masters/master_*.png`, `contact_ui.png`, `mock_hud.png`, INVENTORY rows.
5. Check `contact_ui.png` for magenta fringe and a wrong split count (the script prints `FAIL` if a sheet splits into the wrong number of pieces). If the logo lettering is mangled, re-set "PetalWild" in Cormorant Garamond Bold over the plate rather than rerolling more than twice.

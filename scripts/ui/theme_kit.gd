class_name ThemeKit
extends RefCounted

const INK := Color("1c2418")
const MOSS := Color("1f6b38")
const MOSS_DEEP := Color("174e2c")
const CREAM := Color("f7f1e6")
const TERRACOTTA := Color("c4653d")
const GOLD := Color("e2b15a")
const PARCHMENT := Color("f5dbb4")
const SOIL := Color("1f130b")

const KIT := "res://assets/ui/kit"
const _FALLBACK_MARGINS := {
	"ui_panel_9slice": [48, 48, 48, 48],
	"ui_topbar": [120, 0, 120, 0],
	"ui_slot_normal": [16, 16, 16, 16],
	"ui_slot_hover": [16, 16, 16, 16],
	"ui_slot_selected": [16, 16, 16, 16],
	"ui_button_primary": [32, 24, 32, 24],
	"ui_button_secondary": [32, 24, 32, 24],
	"ui_journal_page": [64, 64, 64, 64],
}

static var font_regular: Font
static var font_semibold: Font
static var booted := false
static var kit_margins := {}
static var slot_normal: StyleBox
static var slot_hover: StyleBox
static var slot_selected: StyleBox
static var panel_slice: StyleBox
static var journal_slice: StyleBox
static var topbar_slice: StyleBox

static func boot() -> void:
	if booted and font_regular != null:
		return
	booted = true
	if ResourceLoader.exists("res://assets/fonts/Inter-Regular.ttf"):
		font_regular = load("res://assets/fonts/Inter-Regular.ttf")
		font_semibold = load("res://assets/fonts/Inter-SemiBold.ttf")
	else:
		font_regular = ThemeDB.fallback_font
		font_semibold = ThemeDB.fallback_font
	_load_margins()
	panel_slice = slice("ui_panel_9slice")
	journal_slice = slice("ui_journal_page")
	topbar_slice = slice("ui_topbar")
	slot_normal = slice("ui_slot_normal", 12)
	slot_hover = slice("ui_slot_hover", 12)
	slot_selected = slice("ui_slot_selected", 12)

static func _load_margins() -> void:
	kit_margins = {}
	var path := KIT + "/ui_kit_margins.json"
	if not FileAccess.file_exists(path):
		return
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		kit_margins = parsed

static func size(base: int) -> int:
	return int(round(float(base) * (1.18 if Settings.large_text else 1.0)))

static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			return loaded
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)

static func kit_tex(stem: String, scale := "1x") -> Texture2D:
	return tex("%s/%s@%s.png" % [KIT, stem, scale])

static func margins_1x(stem: String) -> Array:
	var spec: Variant = kit_margins.get(stem, {})
	if spec is Dictionary:
		var row: Variant = (spec as Dictionary).get("margins_1x_LTRB", [])
		if row is Array and (row as Array).size() >= 4:
			return row
	return _FALLBACK_MARGINS.get(stem, [16, 16, 16, 16])

static func slice(stem: String, content := -1) -> StyleBoxTexture:
	boot()
	var box := StyleBoxTexture.new()
	box.texture = kit_tex(stem, "1x")
	var m := margins_1x(stem)
	box.texture_margin_left = float(m[0])
	box.texture_margin_top = float(m[1])
	box.texture_margin_right = float(m[2])
	box.texture_margin_bottom = float(m[3])
	var pad := content if content >= 0 else int(mini(int(m[0]), 28))
	box.content_margin_left = pad
	box.content_margin_top = pad
	box.content_margin_right = pad
	box.content_margin_bottom = pad
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.draw_center = true
	return box

static func panel(alpha := 0.94) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(CREAM, alpha)
	box.border_color = Color(0.42, 0.33, 0.22, 0.35)
	box.set_border_width_all(1)
	box.set_corner_radius_all(16)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.shadow_color = Color(0.12, 0.1, 0.06, 0.16)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 4)
	return box

static func button_box(filled: bool) -> StyleBox:
	boot()
	var stem := "ui_button_primary" if filled else "ui_button_secondary"
	var box := slice(stem, 12)
	return box

static func make_theme() -> Theme:
	boot()
	var theme := Theme.new()
	theme.default_font = font_regular
	theme.default_font_size = size(16)
	theme.set_font("font", "Button", font_semibold)
	theme.set_font_size("font_size", "Button", size(15))
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_outline_color", "Button", SOIL)
	theme.set_constant("outline_size", "Button", 1)
	theme.set_stylebox("normal", "Button", button_box(false))
	theme.set_stylebox("hover", "Button", button_box(true))
	theme.set_stylebox("pressed", "Button", button_box(true))
	theme.set_stylebox("focus", "Button", button_box(false))
	theme.set_stylebox("disabled", "Button", button_box(false))
	theme.set_stylebox("panel", "Panel", panel_slice if panel_slice else panel())
	theme.set_color("font_color", "Label", INK)
	theme.set_font("font", "Label", font_regular)
	theme.set_font_size("font_size", "Label", size(16))
	return theme

static func label(text: String, px: int, color: Color = INK) -> Label:
	boot()
	var node := Label.new()
	node.text = text
	node.set_meta("base_px", px)
	node.add_theme_font_override("font", font_regular)
	node.add_theme_font_size_override("font_size", size(px))
	node.add_theme_color_override("font_color", color)
	return node

static func outline_label(text: String, px: int, color: Color = PARCHMENT, outline_px: int = 3) -> Label:
	var node := label(text, px, color)
	node.add_theme_color_override("font_outline_color", SOIL)
	node.add_theme_constant_override("outline_size", outline_px)
	node.set_meta("outline_px", outline_px)
	return node

static func restyle(node: Node) -> void:
	if node is Control and (node as Control).theme != null:
		(node as Control).theme = make_theme()
	if node is Label and node.has_meta("base_px"):
		var px := int(node.get_meta("base_px"))
		(node as Label).add_theme_font_size_override("font_size", size(px))
		if node.has_meta("outline_px"):
			(node as Label).add_theme_constant_override("outline_size", int(node.get_meta("outline_px")))
	for child in node.get_children():
		restyle(child)

static func title(text: String, px: int) -> Label:
	var node := label(text, px, INK)
	node.add_theme_font_override("font", font_semibold)
	return node

static func apply_cursor() -> void:
	boot()
	var cursor := kit_tex("ui_cursor", "1x")
	if cursor == null:
		return
	var hot := Vector2(2, 2)
	var spec: Variant = kit_margins.get("ui_cursor", {})
	if spec is Dictionary:
		var row: Variant = (spec as Dictionary).get("hotspot_1x", [])
		if row is Array and (row as Array).size() >= 2:
			hot = Vector2(float(row[0]), float(row[1]))
	Input.set_custom_mouse_cursor(cursor, Input.CURSOR_ARROW, hot)

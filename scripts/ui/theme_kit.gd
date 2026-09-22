class_name ThemeKit
extends RefCounted

const INK := Color("1c2418")
const MOSS := Color("1f6b38")
const MOSS_DEEP := Color("174e2c")
const CREAM := Color("f7f1e6")
const TERRACOTTA := Color("c4653d")
const GOLD := Color("e2b15a")

static var font_regular: Font
static var font_semibold: Font
static var booted := false

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

static func size(base: int) -> int:
	return int(round(float(base) * (1.18 if Settings.large_text else 1.0)))

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

static func button_box(filled: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = MOSS if filled else Color(CREAM, 0.96)
	box.border_color = MOSS_DEEP if filled else Color(0.42, 0.33, 0.22, 0.28)
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

static func make_theme() -> Theme:
	boot()
	var theme := Theme.new()
	theme.default_font = font_regular
	theme.default_font_size = size(16)
	theme.set_font("font", "Button", font_semibold)
	theme.set_font_size("font_size", "Button", size(15))
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", CREAM)
	theme.set_color("font_pressed_color", "Button", CREAM)
	theme.set_stylebox("normal", "Button", button_box(false))
	theme.set_stylebox("hover", "Button", button_box(true))
	theme.set_stylebox("pressed", "Button", button_box(true))
	theme.set_stylebox("focus", "Button", button_box(false))
	theme.set_stylebox("panel", "Panel", panel())
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

static func restyle(node: Node) -> void:
	if node is Control and (node as Control).theme != null:
		(node as Control).theme = make_theme()
	if node is Label and node.has_meta("base_px"):
		var px := int(node.get_meta("base_px"))
		(node as Label).add_theme_font_size_override("font_size", size(px))
	for child in node.get_children():
		restyle(child)

static func title(text: String, px: int) -> Label:
	var node := label(text, px, INK)
	node.add_theme_font_override("font", font_semibold)
	return node

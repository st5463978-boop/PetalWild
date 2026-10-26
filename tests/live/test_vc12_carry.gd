extends SceneTree

## VC12: the seed tool shows the whole plant name, the map overlay survives save/load,
## and the title Licences page reads THIRD_PARTY_NOTICES.md.

const PA := preload("res://tests/support/petal_assert.gd")

var errors: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	OS.add_logger(ErrorSink.new(self))
	call_deferred("_boot")


func _boot() -> void:
	var t: PetalAssert = PA.new("vc12_carry")
	var packed: PackedScene = load("res://scenes/garden.tscn")
	var garden: Node = packed.instantiate()
	root.add_child(garden)
	for _i in 3:
		await process_frame
	_seed_labels(t, garden)
	_overlay_round_trip(t, garden)
	garden.queue_free()
	await process_frame
	await _licences(t)
	var bad := 0
	for row in errors:
		if row.find("Parse Error") != -1 or row.find("previously freed") != -1 or row.find("Invalid call") != -1 or row.find("Invalid access") != -1:
			bad += 1
			print("ERR ", row)
	t.expect(bad == 0, "no script errors during the VC12 checks")
	t.done()


func _seed_labels(t: PetalAssert, garden: Node) -> void:
	var hud: Node = garden.get("hud")
	var button: Button = hud.get("seed_button")
	var economy := root.get_node("Economy")
	var cases := [
		["meadowbell_seed", "Meadowbell", 6],
		["nightlantern_seed", "Nightlantern", 128],
		["mosspear_seed", "Mosspear", 1],
	]
	for row in cases:
		var id := str(row[0])
		var name := str(row[1])
		var count := int(row[2])
		economy.set("selected_seed", id)
		economy.call("add", id, count - int(economy.call("count", id)))
		garden.call("_update_status")
		var lines: PackedStringArray = button.text.split("\n")
		t.expect(lines.size() == 2, "%s uses two lines" % name)
		t.expect(lines[1] == name, "the seed tool shows the full name %s" % name)
		t.expect(lines[0].find("×%d" % count) != -1, "the seed tool shows ×%d" % count)
		t.expect(button.tooltip_text == "%s ×%d" % [name, count], "the seed tooltip keeps %s and the count" % name)
		t.expect(_line_fits(button, lines[1]), "%s fits inside the seed button" % name)
		t.expect(button.text.find(name.substr(0, name.length() - 1)) == button.text.find(name), "%s is not clipped to a shorter word" % name)
	economy.set("selected_seed", "missing_seed")
	garden.call("_update_status")
	t.expect(button.text == "2  Seed\nEmpty", "an unknown seed reads Empty")


func _line_fits(button: Button, line: String) -> bool:
	var font := button.get_theme_font("font")
	if font == null:
		return false
	var font_size := button.get_theme_font_size("font_size")
	var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pad := 28.0
	var style := button.get_theme_stylebox("normal")
	if style != null:
		pad = style.content_margin_left + style.content_margin_right + 6.0
	return button.custom_minimum_size.x + 0.5 >= width + pad


func _overlay_round_trip(t: PetalAssert, garden: Node) -> void:
	var view: Object = garden.get("overlays")
	view.call("set_channel", "moisture")
	var state: Dictionary = garden.call("to_state")
	t.expect(str(state.get("overlay", "")) == "moisture", "the save records the open map")
	view.call("set_channel", "")
	garden.call("apply_state", state)
	t.expect(str(view.call("channel_id")) == "moisture", "load restores the moisture map")
	var bare := state.duplicate(true)
	bare.erase("overlay")
	view.call("set_channel", "light")
	garden.call("apply_state", bare)
	t.expect(str(view.call("channel_id")) == "", "a save with no map row stays off")
	state["overlay"] = "nope"
	view.call("set_channel", "quality")
	garden.call("apply_state", state)
	t.expect(str(view.call("channel_id")) == "", "an unknown map does not stick")


func _licences(t: PetalAssert) -> void:
	var main: Node = load("res://scripts/app/main.gd").new()
	root.add_child(main)
	await process_frame
	var text := str(main.call("_licence_text"))
	t.expect(text.find("Kenney") != -1, "licences include the Kenney notice")
	t.expect(text.find("SIL Open Font License") != -1, "licences include the Inter font")
	t.expect(text.find("assets/art/vc_garden/") != -1, "licences name the original garden art")
	t.expect(text.find("Jelly Baby GPL source is not included.") == -1, "the licences page is not the missing-file fallback")
	main.call("_show_licences")
	await process_frame
	var shown := ""
	for child in main.find_children("*", "Label", true, false):
		var label := child as Label
		if label.text.find("Kenney") != -1:
			shown = label.text
			break
	t.expect(shown.find("Kenney") != -1, "the Licences page shows the notice")
	main.queue_free()
	await process_frame


class ErrorSink:
	extends Logger
	var host: SceneTree

	func _init(tree: SceneTree) -> void:
		host = tree

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
		host.errors.append("%s:%d %s %s" % [file, line, code, rationale])

	func _log_message(message: String, error: bool) -> void:
		if error:
			host.errors.append(message)

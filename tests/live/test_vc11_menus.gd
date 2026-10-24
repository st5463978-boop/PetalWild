extends SceneTree

## VC11 menus and mechanics: Esc chain and unpause, the controls card, time speed,
## a full save/load round trip, bed-group caps, the softlock seed, and the title screen.

const PA := preload("res://tests/support/petal_assert.gd")
const TEST_SLOT := 9

var errors: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	OS.add_logger(ErrorSink.new(self))
	call_deferred("_boot")


func _boot() -> void:
	var t: PetalAssert = PA.new("vc11_menus")
	var packed: PackedScene = load("res://scenes/garden.tscn")
	var garden: Node = packed.instantiate()
	root.add_child(garden)
	for _i in 3:
		await process_frame
	var hud: Node = garden.get("hud")
	await _esc_chain(t, garden, hud)
	_controls(t, garden, hud)
	_speed(t, garden)
	_round_trip(t, garden)
	_district_caps(t, garden)
	_softlock(t, garden, hud)
	await _journal_layout(t, garden, hud)
	t.expect(not bool(garden.call("autosave_allowed")), "headless runs never autosave over a player slot")
	t.expect(not bool(garden.call("autosave", "leave")), "autosave is a no-op when not allowed")
	garden.queue_free()
	await process_frame
	await _title(t)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save().call("path_for", TEST_SLOT)))
	var bad := 0
	for row in errors:
		if row.find("Parse Error") != -1 or row.find("previously freed") != -1 or row.find("Invalid call") != -1 or row.find("Invalid access") != -1:
			bad += 1
			print("ERR ", row)
	t.expect(bad == 0, "no script errors during the VC11 checks")
	t.done()


func _key(code: Key, unicode: int = 0) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.unicode = unicode
	down.pressed = true
	root.push_input(down)
	var up := down.duplicate()
	up.pressed = false
	root.push_input(up)


func _esc_chain(t: PetalAssert, garden: Node, hud: Node) -> void:
	var journal: Control = hud.get("journal")
	var shop: Control = hud.get("shop")
	var help: Control = hud.get("help_panel")
	var pause: Control = hud.get("pause_panel")
	hud.call("toggle_journal")
	t.expect(journal.visible, "J opens the journal")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(not journal.visible, "Esc closes the journal first")
	t.expect(not paused, "closing the journal does not pause")
	hud.call("toggle_shop")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(not shop.visible and not paused, "Esc closes the stall without pausing")
	_key(KEY_F1)
	await process_frame
	t.expect(help.visible, "F1 opens the controls card")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(not help.visible and not paused, "Esc closes the controls card")
	_key(KEY_SLASH, 63)
	await process_frame
	t.expect(help.visible, "? opens the controls card")
	hud.call("toggle_help")
	hud.call("show_nessa")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(not (hud.get("proposal") as Control).visible and not paused, "Esc closes a proposal")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(paused and pause.visible, "Esc with nothing open pauses")
	t.expect(not _clock().get("running"), "pausing stops the clock")
	_key(KEY_F1)
	await process_frame
	t.expect(help.visible and paused, "F1 opens the controls card over the pause menu")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(not help.visible and paused, "Esc closes the card and stays paused")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(not paused, "Esc while paused resumes")
	t.expect(not pause.visible, "resume hides the pause menu")
	t.expect(bool(_clock().get("running")), "resume restarts the clock")


func _controls(t: PetalAssert, garden: Node, hud: Node) -> void:
	var help_script: Script = load("res://scripts/ui/controls_help.gd")
	var keys: PackedStringArray = help_script.call("keys")
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "N", "Y", "T", "J", "B", "O", "F", "P", "Esc", "F5", "F9"]:
		t.expect(keys.has(key), "the controls card lists %s" % key)
	var buttons: Dictionary = hud.get("tool_buttons")
	var blank := 0
	for id in buttons.keys():
		if str((buttons[id] as Button).tooltip_text) == "":
			blank += 1
	t.expect(blank == 0, "every tool button has a tooltip")
	t.expect((hud.get("help_button") as Button).text.find("F1") != -1, "the top bar shows an F1 Controls button")
	var help_panel: Control = hud.get("help_panel")
	var help_layer := help_panel.get_parent() as CanvasLayer
	t.expect(help_layer != null and help_layer.layer > 11, "the help card sits above the overlay panel layer")
	var theme: Theme = help_panel.theme
	t.expect(theme.get_color("font_focus_color", "Button") == theme.get_color("font_color", "Button"), "a focused button keeps its readable ink label")


func _speed(t: PetalAssert, garden: Node) -> void:
	var clock := _clock()
	t.expect(is_equal_approx(float(clock.get("scale")), 6.0), "time starts at 1x")
	garden.call("cycle_speed")
	t.expect(is_equal_approx(float(clock.get("scale")), 12.0), "T steps time to 2x")
	garden.call("_update_status")
	t.expect(str((garden.get("hud").get("clock_label") as Label).text).find("2×") != -1, "the clock label shows the speed")
	garden.call("cycle_speed")
	garden.call("cycle_speed")
	t.expect(is_equal_approx(float(clock.get("scale")), 6.0), "T wraps back to 1x")


func _round_trip(t: PetalAssert, garden: Node) -> void:
	var save := _save()
	var districts: Object = garden.get("districts")
	districts.call("begin_next")
	for x in 3:
		districts.call("toggle_paint", Vector2i(x, 0))
	districts.call("set_policy", districts.get("active_id"), "market_day", true)
	garden.call("cycle_speed")
	_economy().set("coins", 77)
	var before: Dictionary = _norm(garden.call("to_state"))
	t.expect(bool(save.call("write_slot", TEST_SLOT, garden.call("to_state"))), "the test slot writes")
	_economy().set("coins", 1)
	_clock().set("scale", 24.0)
	districts.call("set_policy", districts.get("active_id"), "market_day", false)
	var loaded: Dictionary = save.call("read_slot", TEST_SLOT)
	t.expect(not loaded.is_empty(), "the test slot reads back")
	garden.call("apply_state", loaded)
	var after: Dictionary = _norm(garden.call("to_state"))
	for key in before.keys():
		var same := JSON.stringify(before[key]) == JSON.stringify(after.get(key))
		t.expect(same, "save/load keeps %s" % key)
		if not same:
			print("   before ", JSON.stringify(before[key]).left(300))
			print("   after  ", JSON.stringify(after.get(key)).left(300))
	t.expect(int(_economy().get("coins")) == 77, "coins survive save/load")
	t.expect(is_equal_approx(float(_clock().get("scale")), 12.0), "time speed survives save/load")
	t.expect((districts.call("policies_of", districts.get("active_id")) as PackedStringArray).has("market_day"), "bed-group policies survive save/load")
	_clock().set("scale", 6.0)


func _district_caps(t: PetalAssert, garden: Node) -> void:
	var districts: Object = garden.get("districts")
	var cap := int(districts.call("max_groups"))
	t.expect(cap > 0, "policies.json caps bed groups")
	for i in 30:
		districts.call("begin_next")
		districts.call("toggle_paint", Vector2i(i % 10, 4 + i / 10))
	var rows: Dictionary = districts.call("journal_row")
	var opened := 0
	for entry in garden.get("districts").get("_order"):
		opened += 1
	t.expect(opened <= cap, "thirty presses of N open at most %d groups (got %d)" % [cap, opened])
	var empty_msg := ""
	districts.set("active_id", "")
	var fresh: Object = load("res://scripts/city/districts.gd").new()
	fresh.call("setup", ServiceField.new(), CausalLog.new())
	fresh.call("begin_next")
	empty_msg = str(fresh.call("begin_next"))
	t.expect(empty_msg.find("no beds yet") != -1, "N on an empty group says to paint it first")
	t.expect((fresh.get("_order") as PackedStringArray).size() == 1, "N on an empty group opens nothing new")
	# The VC11 exploit: many one-bed market groups printed coins from nothing.
	var farm: Object = load("res://scripts/city/districts.gd").new()
	var field := ServiceField.new()
	field.setup(10, 8)
	farm.call("setup", field, CausalLog.new())
	for i in cap:
		farm.call("begin_next")
		farm.call("toggle_paint", Vector2i(i, 0))
		farm.call("set_policy", farm.get("active_id"), "market_day", true)
	_economy().set("coins", 10)
	for day in [2, 3, 4]:
		farm.call("charge_daily", day)
	t.expect(int(_economy().get("coins")) <= 10, "one-bed market groups no longer print coins (now %d)" % int(_economy().get("coins")))


func _softlock(t: PetalAssert, garden: Node, hud: Node) -> void:
	var economy := _economy()
	economy.set("coins", 0)
	economy.set("bag", {})
	for cell in garden.get("soil").call("all"):
		cell.set("plant_id", "")
		cell.set("growth", 0.0)
	_clock().set("minute", 9.0 * 60.0)
	t.expect(bool(garden.call("is_stuck")), "no coins, seeds, produce or plants counts as stuck")
	if (hud.get("shop") as Control).visible:
		hud.call("toggle_shop")
	hud.call("toggle_shop")
	t.expect(int(economy.call("count", "meadowbell_seed")) == 2, "Lumen hands over two spare seeds when the garden is stuck")
	t.expect(not bool(garden.call("is_stuck")), "the spare seed ends the softlock")
	economy.set("bag", {})
	hud.call("toggle_shop")
	hud.call("toggle_shop")
	t.expect(int(economy.call("count", "meadowbell_seed")) == 0, "the spare seed comes once a day")
	hud.call("toggle_shop")
	economy.set("coins", 36)


func _journal_layout(t: PetalAssert, garden: Node, hud: Node) -> void:
	garden.call("set_tool", "district")
	var districts: Object = garden.get("districts")
	var first := str((districts.get("_order") as PackedStringArray)[0])
	districts.call("paint_cell", first, Vector2i(9, 7))
	var active := str(districts.get("active_id"))
	t.expect(active != "" and int(districts.call("cell_count", active)) > 0, "a painted group is active for the strip")
	garden.call("show_directory", "place")
	for _i in 4:
		await process_frame
	var strip: Control = garden.get("badges").get("strip")
	var journal: Control = hud.get("journal")
	t.expect(strip.visible, "the policy strip shows with the District tool")
	t.expect(journal.get_global_rect().position.y >= strip.get_global_rect().end.y, "the journal sits below the policy strip")
	var scroll: ScrollContainer = hud.get("journal_scroll")
	var box: Control = hud.get("journal_box")
	t.expect(box.get_combined_minimum_size().x <= scroll.size.x + 1.0, "parish page text wraps instead of scrolling sideways")
	for page in ["people", "trust", "journal"]:
		garden.call("show_directory", page)
		await process_frame
		t.expect(box.get_combined_minimum_size().x <= scroll.size.x + 1.0, "%s page fits the journal width" % page)
	hud.call("close_top")
	garden.call("set_tool", "till")


func _title(t: PetalAssert) -> void:
	var save := _save()
	save.call("write_slot", TEST_SLOT, {"name": "Test Hollow", "clock": {"day": 2.0}, "economy": {"coins": 30.0}})
	var main: Node = load("res://scripts/app/main.gd").new()
	root.add_child(main)
	await process_frame
	var quit: Node = main.find_child("Quit", true, false)
	t.expect(quit != null, "the title screen has a Quit button off the web")
	t.expect(str(main.call("_int_text", 2.0)) == "2", "day and coins show as whole numbers")
	main.call("pick_new_slot", TEST_SLOT, "Fresh")
	t.expect(int(main.get("armed_slot")) == TEST_SLOT, "an occupied slot asks before it is replaced")
	t.expect(current_scene == null or current_scene.scene_file_path.find("garden") == -1, "the first click does not start a game")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(int(main.get("armed_slot")) == 0, "Esc cancels the armed replace")
	main.call("_show_settings")
	await process_frame
	var panel: Control = main.get("root").get_node("Panel")
	var box: Control = panel.get_node("Box")
	t.expect(box.get_combined_minimum_size().x <= panel.size.x - 30.0, "the settings page fits its panel")
	_key(KEY_ESCAPE)
	await process_frame
	t.expect(str(main.get("page")) == "new", "Esc goes back to the New garden page")
	main.call("_show_controls")
	await process_frame
	t.expect(main.find_child("ControlsCard", true, false) != null, "the title screen shows the controls card")
	main.queue_free()
	await process_frame


func _norm(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _save() -> Node:
	return root.get_node("SaveGame")


func _clock() -> Node:
	return root.get_node("Clock")


func _economy() -> Node:
	return root.get_node("Economy")


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

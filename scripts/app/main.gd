extends Node

var theme: Theme
var root: Control
var first_button: Button
var continue_button: Button
## Slot waiting for a second click before an occupied save is replaced; 0 is none.
var armed_slot := 0
var page := "new"

func _ready() -> void:
	ThemeKit.boot()
	theme = ThemeKit.make_theme()
	Clock.running = false
	_build()

func _build() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	add_child(root)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color.WHITE
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/title_backdrop.gdshader")
	backdrop.material = material
	root.add_child(backdrop)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 72
	column.offset_top = 80
	column.offset_right = 560
	column.offset_bottom = -48
	column.add_theme_constant_override("separation", 10)
	root.add_child(column)
	column.add_child(ThemeKit.title("PetalWild", 64))
	column.add_child(ThemeKit.label("Hedge Hollow keeps its own appointments.", 20, ThemeKit.CREAM))
	column.add_child(ThemeKit.label("A living garden. Small enough to hold.", 16, ThemeKit.CREAM))
	column.add_child(HSeparator.new())
	var new_game := Button.new()
	new_game.text = "New garden"
	new_game.pressed.connect(_show_new)
	column.add_child(new_game)
	first_button = new_game
	var continue_game := Button.new()
	continue_game.text = "Continue"
	continue_game.pressed.connect(_show_continue)
	continue_game.disabled = not _any_save()
	continue_game.tooltip_text = "No gardens saved yet." if continue_game.disabled else ""
	column.add_child(continue_game)
	continue_button = continue_game
	var settings := Button.new()
	settings.text = "Settings"
	settings.pressed.connect(_show_settings)
	column.add_child(settings)
	var licences := Button.new()
	licences.text = "Licences"
	licences.pressed.connect(_show_licences)
	var controls := Button.new()
	controls.text = "Controls"
	controls.pressed.connect(_show_controls)
	column.add_child(controls)
	column.add_child(licences)
	if OS.get_name() != "Web":
		var quit := Button.new()
		quit.name = "Quit"
		quit.text = "Quit"
		quit.pressed.connect(func(): get_tree().quit())
		column.add_child(quit)
	column.add_child(ThemeKit.label("Godot %s" % _engine_label(), 13, ThemeKit.CREAM))
	var panel := Panel.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -520
	panel.offset_right = -48
	panel.offset_top = 80
	panel.offset_bottom = -48
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_top = 16
	box.offset_right = -18
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_show_new()
	first_button.call_deferred("grab_focus")


## Esc steps back: cancel an armed overwrite, then return to the New garden page.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()


func go_back() -> void:
	if armed_slot != 0:
		armed_slot = 0
		_show_new()
	elif page != "new":
		_show_new()
	if first_button != null and first_button.is_inside_tree():
		first_button.grab_focus()


func _any_save() -> bool:
	for slot in [1, 2, 3]:
		if not SaveGame.meta(slot).is_empty():
			return true
	return false


func _int_text(value: Variant) -> String:
	return str(int(float(value))) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else str(value)

func _box() -> VBoxContainer:
	return root.get_node("Panel/Box")

func _clear_box() -> void:
	for child in _box().get_children():
		child.free()

func _show_new(keep_name: String = "") -> void:
	page = "new"
	_clear_box()
	_box().add_child(ThemeKit.title("New garden", 28))
	_box().add_child(_wrapped("Name the parish, then pick a slot. An occupied slot asks before it is replaced.", 15))
	var field := LineEdit.new()
	field.name = "GardenName"
	field.text = keep_name if keep_name != "" else "Hedge Hollow"
	field.placeholder_text = "Garden name"
	_box().add_child(field)
	for slot in [1, 2, 3]:
		var button := Button.new()
		var header := SaveGame.meta(slot)
		if header.is_empty():
			button.text = "Slot %d  ·  empty" % slot
		elif armed_slot == slot:
			button.text = "Replace %s (day %s)? Click again. Esc cancels." % [header.get("name", "Garden"), _int_text(header.get("day", 1))]
			button.add_theme_color_override("font_color", ThemeKit.TERRACOTTA)
		else:
			button.text = "Slot %d  ·  %s  ·  day %s  ·  replace" % [slot, header.get("name", "Garden"), _int_text(header.get("day", 1))]
		button.name = "Slot%d" % slot
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(func(): pick_new_slot(slot, field.text))
		_box().add_child(button)


## First click on an occupied slot arms it; the second click replaces it.
func pick_new_slot(slot: int, garden_name: String) -> void:
	if not SaveGame.meta(slot).is_empty() and armed_slot != slot:
		armed_slot = slot
		_show_new(garden_name)
		var again := _box().get_node_or_null("Slot%d" % slot)
		if again is Button:
			(again as Button).grab_focus()
		return
	armed_slot = 0
	_start_new(slot, garden_name)

func _show_continue() -> void:
	page = "continue"
	armed_slot = 0
	_clear_box()
	_box().add_child(ThemeKit.title("Continue", 28))
	var any := false
	for slot in [1, 2, 3]:
		var header := SaveGame.meta(slot)
		if header.is_empty():
			continue
		any = true
		var button := Button.new()
		button.text = "Slot %d  ·  %s  ·  day %s  ·  %s petal" % [slot, header.get("name", "Garden"), _int_text(header.get("day", 1)), _int_text(header.get("coins", 0))]
		button.pressed.connect(func(): _continue_slot(slot))
		_box().add_child(button)
	if not any:
		_box().add_child(ThemeKit.label("No gardens saved on this machine yet.", 15))

func _show_settings() -> void:
	page = "settings"
	armed_slot = 0
	_clear_box()
	_box().add_child(ThemeKit.title("Settings", 28))
	_box().add_child(ThemeKit.label("Volume", 15))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.01
	slider.value = Settings.master
	slider.value_changed.connect(func(v):
		Settings.master = float(v)
		Settings.apply_audio()
		Settings.save_settings()
	)
	_box().add_child(slider)
	var large := CheckButton.new()
	large.text = "Large text"
	large.button_pressed = Settings.large_text
	large.toggled.connect(func(on):
		Settings.large_text = on
		Settings.save_settings()
		theme = ThemeKit.make_theme()
		root.theme = theme
	)
	_box().add_child(large)
	var motion := CheckButton.new()
	motion.text = "Reduce motion"
	motion.button_pressed = Settings.reduce_motion
	motion.toggled.connect(func(on):
		Settings.reduce_motion = on
		Settings.save_settings()
	)
	_box().add_child(motion)
	var calm := CheckButton.new()
	calm.text = "Calm weather"
	calm.button_pressed = Settings.photosensitivity
	calm.toggled.connect(func(on):
		Settings.photosensitivity = on
		Settings.save_settings()
	)
	_box().add_child(calm)
	_box().add_child(_wrapped("JEV game core URL. Explicit only. Blank is offline. Paid calls show the cost and wait.", 14))
	var core_url := LineEdit.new()
	core_url.placeholder_text = "http://127.0.0.1:8771"
	core_url.text = Settings.jev_game_core_url
	core_url.text_changed.connect(func(v):
		var core := JevGameCore.new()
		if core.set_configured_url(str(v)):
			Settings.jev_game_core_url = core.configured_url
		else:
			Settings.jev_game_core_url = ""
			core_url.text = ""
		Settings.save_settings()
	)
	_box().add_child(core_url)
	_box().add_child(_wrapped("All keys are on the Controls page. F1 shows them in the garden.", 14))


func _show_controls() -> void:
	page = "controls"
	armed_slot = 0
	_clear_box()
	_box().add_child(ThemeKit.title("Controls", 28))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box().add_child(scroll)
	var card := ControlsHelp.build_card(14)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)


func _wrapped(text: String, px: int) -> Label:
	var label := ThemeKit.label(text, px)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	return label

func _show_licences() -> void:
	page = "licences"
	armed_slot = 0
	_clear_box()
	_box().add_child(ThemeKit.title("Licences", 28))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box().add_child(scroll)
	var label := ThemeKit.label(_licence_text(), 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)

func _start_new(slot: int, garden_name: String) -> void:
	var name := garden_name.strip_edges()
	if name == "":
		name = "Hedge Hollow"
	SaveGame.active_slot = slot
	SaveGame.garden_name = name
	SaveGame.pending_state = null
	Economy.reset_new()
	Clock.reset_new()
	Trust.reset_new()
	get_tree().change_scene_to_file("res://scenes/garden.tscn")

func _continue_slot(slot: int) -> void:
	var state := SaveGame.read_slot(slot)
	if state.is_empty():
		return
	SaveGame.active_slot = slot
	SaveGame.garden_name = str(state.get("name", "Hedge Hollow"))
	SaveGame.pending_state = state
	get_tree().change_scene_to_file("res://scenes/garden.tscn")

func _licence_text() -> String:
	var path := "res://THIRD_PARTY_NOTICES.md"
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return "PetalWild original work. Godot engine is MIT. Inter is SIL OFL. Jelly Baby GPL source is not included."

func _engine_label() -> String:
	return "4.8.dev6"

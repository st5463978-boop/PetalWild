extends CanvasLayer

var title_layer: Control
var play_layer: Control
var journal: PanelContainer
var shop: PanelContainer
var pause_layer: PanelContainer
var debug_layer: PanelContainer
var toast: Label
var day_label: Label
var petal_label: Label
var plot_label: Label
var phase_label: Label
var journal_text: RichTextLabel
var shop_box: VBoxContainer
var seed_row: HBoxContainer
var tool_buttons: Dictionary = {}
var tab := "grove"
var photo := false
var toast_time := 0.0
var font: Font


func _ready() -> void:
	var font_file := FontFile.new()
	if font_file.load_dynamic_font("res://third_party/fonts/Nunito.ttf") == OK:
		font = font_file
	layer = 10
	_build_title()
	_build_play()
	_build_journal()
	_build_shop()
	_build_pause()
	_build_debug()
	if not Session.notice.is_connected(_on_notice):
		Session.notice.connect(_on_notice)
	_apply_scale()
	enter_title()


func _process(delta: float) -> void:
	toast_time -= delta
	toast.visible = toast_time > 0.0
	if not play_layer.visible:
		return
	day_label.text = "Day %d  %s" % [Session.day, Session.phase_name()]
	phase_label.text = "%s   %.1f×" % [Session.weather.capitalize(), Session.speed]
	petal_label.text = "%d petals" % Session.petals
	_mark_tools()
	if debug_layer.visible:
		_fill_debug()
	if journal.visible:
		_fill_journal()


func enter_title() -> void:
	title_layer.visible = true
	play_layer.visible = false
	journal.visible = false
	shop.visible = false
	pause_layer.visible = false


func enter_play() -> void:
	title_layer.visible = false
	play_layer.visible = true
	pause_layer.visible = false


func over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and not (hovered is ColorRect)


func toggle_journal() -> void:
	journal.visible = not journal.visible
	if journal.visible:
		shop.visible = false
		_fill_journal()


func toggle_shop() -> void:
	if not Session.playing:
		return
	shop.visible = not shop.visible
	if shop.visible:
		journal.visible = false
		_fill_shop()


func toggle_pause() -> void:
	if title_layer.visible:
		return
	pause_layer.visible = not pause_layer.visible
	Session.paused = pause_layer.visible or photo
	if pause_layer.visible:
		_fill_pause_note()


func toggle_debug() -> void:
	debug_layer.visible = not debug_layer.visible


func toggle_photo() -> void:
	photo = not photo
	play_layer.visible = not photo and Session.playing
	journal.visible = false
	shop.visible = false
	Session.paused = photo or pause_layer.visible


func set_plot(text: String) -> void:
	if plot_label:
		plot_label.text = text


func _on_notice(text: String) -> void:
	toast.text = text
	toast_time = 3.8


func _build_title() -> void:
	title_layer = Control.new()
	title_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(title_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.09, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_layer.add_child(dim)
	var card := PanelContainer.new()
	card.theme = _theme()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -240
	card.offset_top = -280
	card.offset_right = 240
	card.offset_bottom = 280
	title_layer.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var title := Label.new()
	title.text = "PetalWild"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "A living garden at the hedge of Havenbrook."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	box.add_child(_button("New garden", _new_game))
	for slot in [1, 2, 3]:
		var slot_button := _button("Continue slot %d" % slot, _continue.bind(slot))
		slot_button.disabled = not Session.has_slot(slot)
		box.add_child(slot_button)
	box.add_child(_button("Credits and licences", _show_credits))


func _build_play() -> void:
	play_layer = Control.new()
	play_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(play_layer)
	var top := PanelContainer.new()
	top.theme = _theme()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_top = 12
	top.offset_right = -16
	top.offset_bottom = 78
	play_layer.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	day_label = Label.new()
	day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(day_label)
	phase_label = Label.new()
	row.add_child(phase_label)
	petal_label = Label.new()
	row.add_child(petal_label)
	row.add_child(_button("1×", func(): Session.speed = 1.0))
	row.add_child(_button("1.5×", func(): Session.speed = 1.5))
	row.add_child(_button("3×", func(): Session.speed = 3.0))
	plot_label = Label.new()
	plot_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	plot_label.position = Vector2(16, 86)
	plot_label.add_theme_color_override("font_color", Color(0.97, 0.95, 0.88))
	plot_label.add_theme_font_size_override("font_size", 16)
	play_layer.add_child(plot_label)
	var tools := HBoxContainer.new()
	tools.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tools.offset_left = 16
	tools.offset_top = -72
	tools.offset_right = -16
	tools.offset_bottom = -16
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	tools.theme = _theme()
	play_layer.add_child(tools)
	var names := [
		["till", "1 Tiller"],
		["seed", "2 Seed Pouch"],
		["water", "3 Raincan"],
		["fert", "4 Fertilise"],
		["tend", "5 Tend"],
		["scoop", "6 Pond Scoop"],
		["home", "7 Home Kit"],
	]
	for entry in names:
		var button := _button(entry[1], _select_tool.bind(entry[0]))
		tool_buttons[entry[0]] = button
		tools.add_child(button)
	seed_row = HBoxContainer.new()
	seed_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	seed_row.offset_left = 16
	seed_row.offset_top = -124
	seed_row.offset_right = -16
	seed_row.offset_bottom = -78
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.theme = _theme()
	play_layer.add_child(seed_row)
	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position = Vector2(280, 780)
	toast.custom_minimum_size = Vector2(880, 32)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	toast.add_theme_font_size_override("font_size", 20)
	play_layer.add_child(toast)
	var hint := Label.new()
	hint.text = "WASD pan   drag right to orbit   wheel zoom   J journal   B stall   F focus   P photo   Esc pause   F3 debug"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -96
	hint.offset_bottom = -74
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86, 0.85))
	play_layer.add_child(hint)


func _build_journal() -> void:
	journal = PanelContainer.new()
	journal.theme = _theme()
	journal.visible = false
	journal.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	journal.offset_left = 16
	journal.offset_top = 96
	journal.offset_right = 460
	journal.offset_bottom = -140
	add_child(journal)
	var box := VBoxContainer.new()
	journal.add_child(box)
	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	for entry in [["grove", "Grove"], ["species", "Species"], ["people", "People"], ["town", "Town"], ["trust", "Trust"]]:
		tabs.add_child(_button(entry[1], _set_tab.bind(entry[0])))
	journal_text = RichTextLabel.new()
	journal_text.bbcode_enabled = true
	journal_text.fit_content = false
	journal_text.scroll_active = true
	journal_text.custom_minimum_size = Vector2(400, 420)
	journal_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(journal_text)


func _build_shop() -> void:
	shop = PanelContainer.new()
	shop.theme = _theme()
	shop.visible = false
	shop.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	shop.offset_left = -420
	shop.offset_top = 96
	shop.offset_right = -16
	shop.offset_bottom = -140
	add_child(shop)
	var box := VBoxContainer.new()
	shop.add_child(box)
	var title := Label.new()
	title.text = "Petal Stall"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	shop_box = VBoxContainer.new()
	box.add_child(shop_box)


func _build_pause() -> void:
	pause_layer = PanelContainer.new()
	pause_layer.theme = _theme()
	pause_layer.visible = false
	pause_layer.set_anchors_preset(Control.PRESET_CENTER)
	pause_layer.offset_left = -220
	pause_layer.offset_top = -230
	pause_layer.offset_right = 220
	pause_layer.offset_bottom = 230
	add_child(pause_layer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pause_layer.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	box.add_child(_button("Resume", toggle_pause))
	box.add_child(_button("Save slot 1", func(): Session.save_slot(1)))
	box.add_child(_button("Save slot 2", func(): Session.save_slot(2)))
	box.add_child(_button("Save slot 3", func(): Session.save_slot(3)))
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = Session.master_volume
	volume.value_changed.connect(func(value: float):
		Session.master_volume = value
		Session.save_settings()
	)
	box.add_child(volume)
	var motion := CheckButton.new()
	motion.text = "Reduce camera motion"
	motion.button_pressed = Session.reduce_motion
	motion.toggled.connect(func(on: bool):
		Session.reduce_motion = on
		Session.save_settings()
	)
	box.add_child(motion)
	box.add_child(_button("Larger text", func():
		Session.ui_scale = 1.25 if Session.ui_scale < 1.2 else 1.0
		Session.save_settings()
		_apply_scale()
	))
	box.add_child(_button("Title", func():
		Session.paused = true
		enter_title()
	))


func _build_debug() -> void:
	debug_layer = PanelContainer.new()
	debug_layer.theme = _theme()
	debug_layer.visible = false
	debug_layer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_layer.offset_left = -360
	debug_layer.offset_top = 96
	debug_layer.offset_right = -16
	debug_layer.offset_bottom = 520
	add_child(debug_layer)
	var box := VBoxContainer.new()
	debug_layer.add_child(box)
	box.add_child(_button("Grow planted crops", func(): Session.grow_all()))
	box.add_child(_button("Rain", func(): Session.force_weather("rain")))
	box.add_child(_button("Clear", func(): Session.force_weather("clear")))
	box.add_child(_button("Night", func(): Session.force_hour(22.0)))
	box.add_child(_button("Dusk", func(): Session.force_hour(17.6)))
	box.add_child(_button("+50 petals", func(): Session.petals += 50))
	box.add_child(_button("Call Sunburst", _debug_visitor.bind("sunburst")))
	box.add_child(_button("Trust 4 foundry", func(): Session.trust.set_trust("media_foundry", 4)))
	box.add_child(_button("Hear foundry plan", func(): Session.trust.draft_foundry_plan(Session.petals)))


func _fill_journal() -> void:
	var lines: PackedStringArray = []
	match tab:
		"grove":
			lines.append("[b]Grove journal[/b]")
			lines.append("Quality %.0f    moisture %.0f%%    fertility %.0f%%" % [
				Session.quality(), Session.garden.average_moisture() * 100.0, Session.garden.average_fertility() * 100.0
			])
			lines.append("Season %s" % Session.season)
			for entry in Session.log_lines:
				lines.append("• " + str(entry))
		"species":
			var ctx: Dictionary = Session._ecology_context()
			for spec in Session.content.species:
				var rec: Dictionary = Session.ecology.records[str(spec.id)]
				lines.append("[b]%s[/b]  %s" % [spec.name, str(rec.state).to_lower().replace("_", " ")])
				lines.append(str(spec.get("journal", "")))
				for line in Session.ecology.progress_lines(spec, ctx):
					lines.append(line)
				lines.append("")
		"people":
			for spec in Session.content.residents:
				var person: Dictionary = Session.people[str(spec.id)]
				var state := "in the garden" if person.unlocked else "not yet"
				lines.append("[b]%s[/b]  %s" % [spec.name, state])
				lines.append("%s · %s" % [spec.job, spec.personality])
				if person.unlocked:
					lines.append("energy %.0f  social %.0f  purpose %.0f  mood %s" % [
						float(person.energy) * 100.0, float(person.social) * 100.0, float(person.purpose) * 100.0, person.mood
					])
				lines.append("")
			for key in Session.relationships.keys():
				lines.append("%s  %.2f" % [key, float(Session.relationships[key])])
		"town":
			var stats: Dictionary = Session.town.stats
			lines.append("[b]Havenbrook[/b]  aggregate simulation")
			lines.append(str(Session.content.districts[0].blurb) if Session.content.districts.size() else "")
			lines.append("Population %d" % int(stats.get("population", 0)))
			lines.append("Employment %.0f%%" % (float(stats.get("employment", 0.0)) * 100.0))
			lines.append("Happiness %.0f%%" % (float(stats.get("happiness", 0.0)) * 100.0))
			lines.append("Tourism %.2f" % float(stats.get("tourism", 0.0)))
			lines.append("Land value %.0f%%" % (float(stats.get("land_value", 0.0)) * 100.0))
			lines.append("Open venues: " + ", ".join(stats.get("open_venues", [])))
			lines.append("Nearby Veg People run at full schedules. The rest of Havenbrook is statistical.")
		"trust":
			lines.append("[b]Outside authority[/b]")
			lines.append("Observe, reason, propose, then wait. Nothing is sent without a yes, and trust 4 still cannot reach an external tool.")
			for id in Session.trust.agents.keys():
				var agent: Dictionary = Session.trust.agents[id]
				lines.append("%s  trust %d  %s" % [agent.name, int(agent.trust), agent.role])
			for proposal in Session.trust.proposals:
				lines.append("")
				lines.append(str(proposal.text))
				lines.append("Status: %s" % proposal.status)
			if not Session.trust.proposals.is_empty():
				lines.append("")
			for entry in Session.trust.audit:
				lines.append("%s · %s" % [entry.kind, entry.note])
	journal_text.text = "\n".join(lines)
	if tab == "trust" and not Session.trust.proposals.is_empty():
		pass


func _fill_shop() -> void:
	for child in shop_box.get_children():
		child.queue_free()
	var open := Session.unlock_ok({"type": "resident_unlocked", "id": "quin_hearth"})
	if not open:
		var closed := Label.new()
		closed.text = "The stall is built. Quin arrives after a Sunburst visits."
		closed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		shop_box.add_child(closed)
	for item in Session.content.items:
		var unlocked := Session.unlock_ok(item.get("unlock", {"type": "always"}))
		var label := "%s  %d petals" % [item.name, int(item.price)]
		if not unlocked:
			label += "  (not yet)"
		var button := _button(label, _buy.bind(str(item.id)))
		button.disabled = not unlocked or not open
		shop_box.add_child(button)
	shop_box.add_child(Label.new())
	for plant_id in Session.content.plants.keys():
		var count := int(Session.inventory.get("produce_%s" % plant_id, 0))
		if count <= 0:
			continue
		var plant: Dictionary = Session.content.plants[plant_id]
		shop_box.add_child(_button("Sell %s ×%d  (+%d)" % [plant.name, count, int(plant.sell)], _sell.bind(str(plant_id))))
	var pouch := Label.new()
	pouch.text = "Pouch  sunpetal %d   corn %d   fert %d   homes %d" % [
		int(Session.inventory.get("seed_sunpetal", 0)),
		int(Session.inventory.get("seed_petal_corn", 0)),
		int(Session.inventory.get("fert_pack", 0)),
		int(Session.inventory.get("home_kit", 0)),
	]
	pouch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_box.add_child(pouch)


func _fill_debug() -> void:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var present := 0
	for id in Session.ecology.records.keys():
		if bool(Session.ecology.records[id].present):
			present += 1
	if debug_layer.get_child_count() == 0:
		return
	var box: VBoxContainer = debug_layer.get_child(0)
	var info := box.get_node_or_null("Profile")
	if info == null:
		info = Label.new()
		info.name = "Profile"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(info)
	info.text = "FPS %.0f\nprocess %.2f ms\ndraw calls %.0f\nprimitives %.0f\nstatic mem %.1f MB\npresent jellies %d\nquality %.0f\nsim layers hero→aggregate" % [
		fps, process_ms, draws, prims, mem, present, Session.quality()
	]


func _fill_pause_note() -> void:
	pass


func _mark_tools() -> void:
	for id in tool_buttons.keys():
		var button: Button = tool_buttons[id]
		button.modulate = Color(1.25, 1.12, 0.72) if Session.tool == id else Color.WHITE
	seed_row.visible = Session.tool == "seed"
	if Session.tool != "seed":
		return
	if seed_row.get_child_count() == 0:
		for plant_id in ["sunpetal", "petal_corn", "dewberry", "moonvine"]:
			seed_row.add_child(_button(Session.content.plant_name(plant_id), _select_seed.bind(plant_id)))
	for child in seed_row.get_children():
		if child is Button:
			var selected: bool = str(child.text).begins_with(Session.content.plant_name(Session.selected_seed))
			child.modulate = Color(1.25, 1.12, 0.72) if selected else Color.WHITE


func _select_tool(id: String) -> void:
	Session.tool = id


func _select_seed(plant_id: String) -> void:
	Session.selected_seed = plant_id


func _buy(item_id: String) -> void:
	Session.buy(item_id)
	_fill_shop()


func _sell(plant_id: String) -> void:
	Session.sell_produce(plant_id)
	_fill_shop()


func _new_game() -> void:
	Session.new_game()
	Session.begin_playing()
	enter_play()


func _continue(slot: int) -> void:
	if Session.load_slot(slot):
		enter_play()


func _set_tab(next: String) -> void:
	tab = next
	_fill_journal()


func _show_credits() -> void:
	toast.text = "Original PetalWild work. Godot MIT. Nunito OFL. No GPL code copied."
	toast_time = 5.0
	toast.visible = true


func _debug_visitor(id: String) -> void:
	if not Session.ecology.records.has(id):
		return
	var rec: Dictionary = Session.ecology.records[id]
	rec.state = "VISITOR"
	rec.present = true
	rec.mood = "curious"
	Session._say("Debug called %s." % id)


func _apply_scale() -> void:
	var window := get_window()
	if window:
		window.content_scale_factor = Session.ui_scale


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	if font:
		button.add_theme_font_override("font", font)
	return button


func _theme() -> Theme:
	var theme := Theme.new()
	if font:
		theme.default_font = font
	theme.default_font_size = 18
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.32, 0.2)
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = Color(0.28, 0.46, 0.26)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.96, 0.93, 0.86, 0.94)
	panel.border_color = Color(0.33, 0.42, 0.24)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(14)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	theme.set_stylebox("disabled", "Button", normal)
	theme.set_color("font_color", "Button", Color(0.97, 0.95, 0.88))
	theme.set_color("font_disabled_color", "Button", Color(0.75, 0.75, 0.7))
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_color("font_color", "Label", Color(0.15, 0.18, 0.12))
	theme.set_color("default_color", "RichTextLabel", Color(0.15, 0.18, 0.12))
	return theme

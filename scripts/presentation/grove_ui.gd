extends Control

var game
var title: Control
var journal: PanelContainer
var shop: PanelContainer
var pause_menu: PanelContainer
var city: PanelContainer
var map_panel: PanelContainer
var debug_panel: PanelContainer
var credits: PanelContainer
var settings: PanelContainer
var speech: PanelContainer
var toasts: VBoxContainer
var clock_label: Label
var coin_label: Label
var plot_label: Label
var hint_label: Label
var speech_label: Label
var speech_row: HBoxContainer
var tool_buttons: Array = []
var seed_label: Label
var home_label: Label
var journal_box: VBoxContainer
var shop_box: VBoxContainer
var city_label: Label
var map_grid: GridContainer
var photo_label: Label
var photo_hidden: Array = []
var slot_box: VBoxContainer
var volume: HSlider
var motion: CheckButton
var scale_slider: HSlider
var full_toggle: CheckButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	_hud()
	_build_title()
	_build_journal()
	_build_shop()
	_build_pause()
	_build_city()
	_build_map()
	_build_debug()
	_build_credits()
	_build_settings()
	_build_speech()
	photo_label = Label.new()
	photo_label.text = "Photo  ·  P to return"
	photo_label.visible = false
	photo_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	photo_label.position = Vector2(520, 660)
	add_child(photo_label)


func show_title() -> void:
	_hide_play_panels()
	title.visible = true
	_fill_slots()


func hide_title() -> void:
	title.visible = false


func refresh(state: Dictionary, hover: Vector2i) -> void:
	if state.is_empty():
		return
	clock_label.text = PetalClock.clock_label(state)
	coin_label.text = "%d petals" % int(state.get("coins", 0))
	var phase := PetalRules.phase_for(int(state.get("minute", 0)))
	var weather := String(state.get("weather", "clear"))
	if hover.x >= 0:
		var plot: Dictionary = WorldState.plot_at(state, hover.x, hover.y)
		var plant := String(plot.get("plant", ""))
		var growth := int(float(plot.get("growth", 0.0)) * 100.0)
		plot_label.text = "%s  moisture %d%%  fertility %d%%  %s" % [
			String(plot.get("g", "")),
			int(float(plot.get("m", 0.0)) * 100.0),
			int(float(plot.get("f", 0.0)) * 100.0),
			("%s %d%%" % [plant, growth]) if plant != "" else "empty",
		]
	else:
		plot_label.text = "%s · %s" % [phase, weather]
	var seeds: Array = PetalSim.available_seeds(state, PetalContent.catalogs())
	var selected := String(state.get("selected_seed", ""))
	if seeds.is_empty():
		seed_label.text = "Pouch empty"
	else:
		var def: Dictionary = PetalContent.items.get(selected, {})
		seed_label.text = "Seed  %s × %d" % [def.get("name", selected), int(state["inventory"].get(selected, 0))]
	var homes := ["Stall", "Path", "Lamp", "Bench", "Lantern"]
	home_label.text = "Home kit  %s" % homes[game.tool_sub % homes.size()]
	for i in tool_buttons.size():
		tool_buttons[i].modulate = Color("F2C14E") if i == game.tool else Color.WHITE
	if city.visible:
		_fill_city(state)


func toast(text: String, kind: String = "ok") -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(360, 0)
	label.modulate = Color("F2C14E") if kind == "error" else Color("F7F1E4")
	toasts.add_child(label)
	var timer := get_tree().create_timer(4.2)
	timer.timeout.connect(label.queue_free)
	while toasts.get_child_count() > 4:
		toasts.get_child(0).queue_free()


func say(speaker: String, text: String, offer_shop: bool) -> void:
	speech.visible = true
	speech_label.text = "%s: %s" % [speaker, text]
	for child in speech_row.get_children():
		child.queue_free()
	if offer_shop:
		speech_row.add_child(_button("Open stall", func(): game.open_shop()))
	speech_row.add_child(_button("Close", func(): speech.visible = false))


func show_shop() -> void:
	shop.visible = true
	_fill_shop()


func photo(on: bool) -> void:
	if on:
		photo_hidden.clear()
		for child in get_children():
			if child == photo_label or not child.visible:
				continue
			photo_hidden.append(child)
			child.visible = false
		photo_label.visible = true
		return
	photo_label.visible = false
	for child in photo_hidden:
		if is_instance_valid(child):
			child.visible = true
	photo_hidden.clear()


func _hud() -> void:
	var top := PanelContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.offset_bottom = 64
	add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	var word := Label.new()
	word.text = "PetalWild"
	row.add_child(word)
	clock_label = Label.new()
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(clock_label)
	coin_label = Label.new()
	row.add_child(coin_label)
	plot_label = Label.new()
	plot_label.position = Vector2(20, 70)
	add_child(plot_label)
	var dock := PanelContainer.new()
	dock.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dock.offset_left = -420
	dock.offset_right = 420
	dock.offset_top = -92
	dock.offset_bottom = -16
	add_child(dock)
	var dock_box := VBoxContainer.new()
	dock.add_child(dock_box)
	var tools := HBoxContainer.new()
	dock_box.add_child(tools)
	var names := ["1 Till", "2 Seed", "3 Water", "4 Feed", "5 Tend", "6 Pond", "7 Home"]
	for i in names.size():
		var index := i
		var button := _button(names[i], func(): game.set_tool(index))
		tools.add_child(button)
		tool_buttons.append(button)
	var sub := HBoxContainer.new()
	dock_box.add_child(sub)
	seed_label = Label.new()
	seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_child(seed_label)
	home_label = Label.new()
	sub.add_child(home_label)
	sub.add_child(_button("R cycle", func(): game.cycle_context()))
	sub.add_child(_button("J Journal", func(): _toggle(journal)))
	sub.add_child(_button("M Map", func(): _toggle(map_panel)))
	sub.add_child(_button("C Town", func(): _toggle(city)))
	toasts = VBoxContainer.new()
	toasts.position = Vector2(18, 110)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)
	hint_label = Label.new()
	hint_label.text = "Right-drag looks  ·  scroll zooms  ·  WASD moves  ·  click the ground  ·  drag a jelly"
	hint_label.position = Vector2(18, 660)
	add_child(hint_label)


func _build_title() -> void:
	title = _full_panel()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_child(box)
	var title_label := Label.new()
	title_label.text = "PetalWild"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 54)
	box.add_child(title_label)
	var sub := Label.new()
	sub.text = "A living garden, small enough to hold."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	slot_box = VBoxContainer.new()
	box.add_child(slot_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(_button("Settings", func(): settings.visible = true))
	row.add_child(_button("Credits", func(): credits.visible = true))
	row.add_child(_button("Parish", func(): game.open_parish()))
	add_child(title)


func _fill_slots() -> void:
	for child in slot_box.get_children():
		child.queue_free()
	for i in 3:
		var info: Dictionary = PetalSave.summarise(i + 1)
		var label := "Empty bed" if info.get("empty", true) else "Day %d · %d petals" % [int(info.get("day", 1)), int(info.get("coins", 0))]
		var slot := i + 1
		var row := HBoxContainer.new()
		row.add_child(_button("Grove %d  %s" % [slot, label], func(): game.continue_slot(slot)))
		if not info.get("empty", true):
			row.add_child(_button("New", func(): game.new_slot(slot)))
		slot_box.add_child(row)


func _build_journal() -> void:
	journal = _side_panel(false)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 560)
	journal.add_child(scroll)
	journal_box = VBoxContainer.new()
	journal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(journal_box)
	add_child(journal)


func _fill_journal(state: Dictionary) -> void:
	for child in journal_box.get_children():
		child.queue_free()
	journal_box.add_child(_heading("Garden journal"))
	var ctx := PetalContext.build(state, PetalContent.catalogs())
	journal_box.add_child(_body("Quality %d%%. The wild pond beyond the west hedge is not a garden pond." % int(float(ctx["quality"]) * 100.0)))
	journal_box.add_child(_heading("Grokbot jellies"))
	for id in PetalContent.species.keys():
		var def: Dictionary = PetalContent.species[id]
		var rec: Dictionary = state["species"][id]
		var known := PetalRules.state_index(String(rec.get("state", "unknown"))) >= PetalRules.state_index("sighted")
		if not known:
			journal_box.add_child(_body("Unrecorded. %s" % def.get("hint", "")))
			continue
		var unmet := PetalRules.first_unmet(def.get("visit", []), ctx)
		var settle := PetalRules.first_unmet(def.get("settle", []), ctx)
		var line := "%s · %s" % [def["name"], String(rec.get("state", "")).replace("_", " ")]
		if String(rec.get("state", "")) in ["unknown", "sighted", "curious"]:
			line += "\nVisit: %s" % ("ready" if unmet == "" else unmet)
		else:
			line += "\nSettle: %s" % ("staying" if settle == "" else settle)
		if bool(rec.get("variant", false)):
			line += "\nA paler variant."
		journal_box.add_child(_body(line))
	journal_box.add_child(_heading("Veg people"))
	for id in PetalContent.residents.keys():
		var def: Dictionary = PetalContent.residents[id]
		var person: Dictionary = state["people"][id]
		if not bool(person.get("present", false)):
			var unmet := PetalRules.first_unmet(def.get("arrives", []), ctx)
			journal_box.add_child(_body("%s has not arrived. %s" % [def["name"], unmet]))
			continue
		var needs: Dictionary = person.get("needs", {})
		journal_box.add_child(_body("%s · %s · %s\nTrust %d · energy %d hunger %d social %d purpose %d\n%s" % [
			def["name"], def.get("role", ""), person.get("mood", ""),
			int(person.get("trust", 0)),
			int(float(needs.get("energy", 0)) * 100.0),
			int(float(needs.get("hunger", 0)) * 100.0),
			int(float(needs.get("social", 0)) * 100.0),
			int(float(needs.get("purpose", 0)) * 100.0),
			def.get("personality", ""),
		]))
		var person_id := String(id)
		journal_box.add_child(_button("Trust +", func(): game.bump_trust(person_id, 1)))
		if person_id == "oshi":
			journal_box.add_child(_button("Hear Oshi's plan", func(): game.ask_proposal(false)))
			journal_box.add_child(_button("Approve plan", func(): game.ask_proposal(true)))
		for memory in person.get("memories", []):
			journal_box.add_child(_body("· %s" % memory))


func _build_shop() -> void:
	shop = _center_panel()
	var box := VBoxContainer.new()
	shop.add_child(box)
	box.add_child(_heading("Petal Stall"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 360)
	box.add_child(scroll)
	shop_box = VBoxContainer.new()
	scroll.add_child(shop_box)
	box.add_child(_button("Close stall", func(): shop.visible = false))
	add_child(shop)


func _fill_shop() -> void:
	for child in shop_box.get_children():
		child.queue_free()
	var state: Dictionary = game.state()
	shop_box.add_child(_body("Cara keeps the counter. %d petals in your pocket." % int(state.get("coins", 0))))
	for id in PetalContent.items.keys():
		var def: Dictionary = PetalContent.items[id]
		var have := int(state["inventory"].get(id, 0))
		var row := HBoxContainer.new()
		row.add_child(_body("%s × %d" % [def.get("name", id), have]))
		if int(def.get("buy", 0)) > 0:
			var item_id := String(id)
			row.add_child(_button("Buy %d" % int(def["buy"]), func(): game.buy(item_id)))
		if int(def.get("sell", 0)) > 0 and have > 0:
			var sell_id := String(id)
			row.add_child(_button("Sell %d" % int(def["sell"]), func(): game.sell(sell_id)))
		shop_box.add_child(row)


func _build_pause() -> void:
	pause_menu = _center_panel()
	var box := VBoxContainer.new()
	pause_menu.add_child(box)
	box.add_child(_heading("Paused"))
	box.add_child(_button("Resume", func(): pause_menu.visible = false))
	box.add_child(_button("Save grove", func(): game.save_current()))
	box.add_child(_button("Settings", func(): settings.visible = true))
	box.add_child(_button("Credits and licences", func(): credits.visible = true))
	box.add_child(_button("Title", func(): game.to_title()))
	box.add_child(_button("Quit", func(): get_tree().quit()))
	add_child(pause_menu)


func _build_city() -> void:
	city = _side_panel(true)
	city_label = Label.new()
	city_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	city_label.custom_minimum_size = Vector2(360, 400)
	city.add_child(city_label)
	add_child(city)


func _fill_city(state: Dictionary) -> void:
	var people_n := 0
	var residents := 0
	for id in state["people"].keys():
		if bool(state["people"][id].get("present", false)):
			people_n += 1
	for id in state["species"].keys():
		if PetalRules.state_index(String(state["species"][id].get("state", "unknown"))) >= PetalRules.state_index("resident"):
			residents += 1
	var lines := "Garden Grove\nPhase A · one cultivated terrace\n\nVeg people present %d\nResident jellies %d\nStall %s\nSales %d\nPetal coins %d\nThefts %d\n\n" % [
		people_n, residents, "open" if state.get("stall_open", false) else "latched",
		int(state.get("sales", 0)), int(state.get("coins", 0)), int(state.get("theft", 0)),
	]
	lines += "Places\n"
	for id in PetalContent.venues.keys():
		var venue: Dictionary = PetalContent.venues[id]
		var built := "open" if id == "petal_stall" and state.get("stall_open", false) else ("standing" if venue.get("active", false) else "not built")
		lines += "%s · %s · %s\n" % [venue.get("name", id), venue.get("phase", ""), built]
	lines += "\nOnly the stall is a working venue. The other rooms are named so the town has a direction. Nobody is simulated inside them."
	city_label.text = lines


func _build_map() -> void:
	map_panel = _center_panel()
	var box := VBoxContainer.new()
	map_panel.add_child(box)
	box.add_child(_heading("Terrace"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 360)
	box.add_child(scroll)
	map_grid = GridContainer.new()
	map_grid.columns = 16
	scroll.add_child(map_grid)
	box.add_child(_button("Close", func(): map_panel.visible = false))
	add_child(map_panel)


func _fill_map(state: Dictionary) -> void:
	for child in map_grid.get_children():
		child.queue_free()
	var width := int(state["width"])
	var height := int(state["height"])
	map_grid.columns = width
	for y in height:
		for x in width:
			var plot: Dictionary = state["plots"][y * width + x]
			var swatch := ColorRect.new()
			swatch.custom_minimum_size = Vector2(18, 18)
			match String(plot.get("g", "")):
				"soil":
					swatch.color = Color("6B442C")
				"path":
					swatch.color = Color("C2B39A")
				"pond":
					swatch.color = Color("1E6A66")
				_:
					swatch.color = Color("7FA85A")
			if String(plot.get("plant", "")) != "":
				swatch.color = swatch.color.lerp(Color("F2C14E"), 0.45)
			var cx := x
			var cy := y
			swatch.gui_input.connect(func(event):
				if event is InputEventMouseButton and event.pressed:
					game.focus_plot(cx, cy)
			)
			map_grid.add_child(swatch)


func _build_debug() -> void:
	debug_panel = _side_panel(true)
	var box := VBoxContainer.new()
	debug_panel.add_child(box)
	box.add_child(_heading("Grove tools"))
	box.add_child(_button("Noon", func(): game.set_clock(12 * 60)))
	box.add_child(_button("Dusk", func(): game.set_clock(17 * 60 + 30)))
	box.add_child(_button("Night", func(): game.set_clock(22 * 60)))
	box.add_child(_button("Rain", func(): game.set_weather("rain")))
	box.add_child(_button("Golden hour", func(): game.set_weather("golden")))
	box.add_child(_button("Clear", func(): game.set_weather("clear")))
	box.add_child(_button("+40 petals", func(): game.add_coins(40)))
	box.add_child(_button("Grow all", func(): game.grow_all()))
	box.add_child(_button("Soak soil", func(): game.soak()))
	box.add_child(_button("Sunburst visits", func(): game.force_species("sunburst", "visitor")))
	box.add_child(_button("Sunburst resident", func(): game.force_species("sunburst", "resident")))
	box.add_child(_fps())
	box.add_child(_button("Close", func(): debug_panel.visible = false))
	add_child(debug_panel)


func _fps() -> Label:
	var label := Label.new()
	label.name = "Fps"
	return label


func _process(_delta: float) -> void:
	var label := debug_panel.find_child("Fps", true, false) if debug_panel != null else null
	if label is Label and debug_panel.visible:
		label.text = "FPS %d   draw calls %d   primitives %d   jellies %d" % [
			int(Engine.get_frames_per_second()),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			game.jelly_count() if game != null else 0,
		]


func _build_credits() -> void:
	credits = _center_panel()
	var box := VBoxContainer.new()
	credits.add_child(box)
	box.add_child(_heading("Credits and licences"))
	box.add_child(_body("PetalWild's own code is MIT. Godot Engine 4.8-dev6 is MIT. Kenney Nature Kit and Interface Sounds are CC0. Poly Haven textures in use are CC0. Nunito is not bundled. Procedural wind and music are original.\n\nJelly Baby was used as a feel reference. Its GPL code is not in this project.\n\nNo Viva Piñata, Cities: Skylines, or Nintendo assets.\n\nInspirations are genre ideas: ecology, household life, venues, and a town that might someday hold agents. The characters, species, and garden are original."))
	box.add_child(_button("Close", func(): credits.visible = false))
	add_child(credits)


func _build_settings() -> void:
	settings = _center_panel()
	var box := VBoxContainer.new()
	settings.add_child(box)
	box.add_child(_heading("Settings"))
	box.add_child(_body("Volume"))
	volume = HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.01
	volume.value = 0.8
	volume.custom_minimum_size = Vector2(280, 24)
	volume.value_changed.connect(func(v): PetalAudio.set_volume(float(v)))
	box.add_child(volume)
	motion = CheckButton.new()
	motion.text = "Reduce motion"
	motion.toggled.connect(func(on): PetalWorld.reduce_motion = on)
	box.add_child(motion)
	full_toggle = CheckButton.new()
	full_toggle.text = "Fullscreen"
	full_toggle.toggled.connect(func(on):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	)
	box.add_child(full_toggle)
	box.add_child(_body("Interface scale"))
	scale_slider = HSlider.new()
	scale_slider.min_value = 0.85
	scale_slider.max_value = 1.45
	scale_slider.step = 0.05
	scale_slider.value = 1.0
	scale_slider.value_changed.connect(func(v): theme.default_font_size = int(18 * float(v)))
	box.add_child(scale_slider)
	box.add_child(_button("Close", func(): settings.visible = false))
	add_child(settings)


func _build_speech() -> void:
	speech = PanelContainer.new()
	speech.visible = false
	speech.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	speech.offset_left = -340
	speech.offset_right = 340
	speech.offset_top = -210
	speech.offset_bottom = -110
	var box := VBoxContainer.new()
	speech.add_child(box)
	speech_label = Label.new()
	speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(speech_label)
	speech_row = HBoxContainer.new()
	box.add_child(speech_row)
	add_child(speech)


func toggle_pause() -> void:
	if title.visible:
		return
	pause_menu.visible = not pause_menu.visible


func toggle_debug() -> void:
	debug_panel.visible = not debug_panel.visible


func _toggle(panel: Control) -> void:
	panel.visible = not panel.visible
	if panel == journal and panel.visible:
		_fill_journal(game.state())
	if panel == map_panel and panel.visible:
		_fill_map(game.state())
	if panel == city and panel.visible:
		_fill_city(game.state())


func _hide_play_panels() -> void:
	for panel in [journal, shop, pause_menu, city, map_panel, debug_panel, speech]:
		panel.visible = false


func _full_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = 40
	panel.offset_bottom = -40
	return panel


func _center_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -240
	panel.offset_bottom = 240
	return panel


func _side_panel(left: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	if left:
		panel.offset_left = 16
		panel.offset_right = -860
	else:
		panel.offset_left = 860
		panel.offset_right = -16
	panel.offset_top = 78
	panel.offset_bottom = -110
	return panel


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 26)
	return label


func _body(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(320, 0)
	return label


func _button(text: String, cb: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(cb)
	return button


func _make_theme() -> Theme:
	var made := Theme.new()
	var ink := Color("1C2A22")
	var paper := Color("F3E6C8")
	var leaf := Color("2F6B45")
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(paper, 0.94)
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(14)
	panel.set_border_width_all(2)
	panel.border_color = leaf
	made.set_stylebox("panel", "PanelContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = leaf
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color("3E8A58")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("214833")
	made.set_stylebox("normal", "Button", normal)
	made.set_stylebox("hover", "Button", hover)
	made.set_stylebox("pressed", "Button", pressed)
	made.set_stylebox("focus", "Button", hover)
	made.set_color("font_color", "Button", paper)
	made.set_color("font_hover_color", "Button", paper)
	made.set_color("font_color", "Label", ink)
	made.set_color("font_color", "CheckButton", ink)
	made.default_font_size = 18
	return made

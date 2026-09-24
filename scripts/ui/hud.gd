class_name Hud
extends CanvasLayer

var host: Node
var tool_buttons := {}
var seed_menu: Panel
var journal: Panel
var shop: Panel
var pause_panel: Panel
var proposal: Panel
var clock_label: Label
var coin_label: Label
var weather_label: Label
var hover_label: Label
var toast_label: Label
var hint_label: Label
var photo_label: Label
var journal_box: VBoxContainer
var shop_box: VBoxContainer
var people_box: VBoxContainer
var trust_box: VBoxContainer
var place_box: VBoxContainer
var pages := {}
var seed_button: Button
var _toast_time := 0.0

func build(owner: Node) -> void:
	host = owner
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var theme := ThemeKit.make_theme()
	_top(theme)
	_tools(theme)
	_journal(theme)
	_shop(theme)
	_pause(theme)
	_proposal(theme)
	toast_label = ThemeKit.label("", ThemeKit.size(16), ThemeKit.CREAM)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_top = 86
	toast_label.offset_left = -280
	toast_label.offset_right = 280
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", ThemeKit.INK)
	add_child(toast_label)
	hint_label = ThemeKit.label("1 till   2 seed   3 water   4 feed   5 tend   H hands   J journal   B stall", 14, ThemeKit.CREAM)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_bottom = -100
	hint_label.offset_left = -420
	hint_label.offset_right = 420
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_label)
	photo_label = ThemeKit.title("Photo  ·  Esc", 18)
	photo_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	photo_label.offset_top = 24
	photo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	photo_label.visible = false
	add_child(photo_label)

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			toast_label.text = ""

func apply_text_scale() -> void:
	ThemeKit.restyle(self)

func set_status(clock_text: String, weather: String, coins: int, hover: String, seed_name: String) -> void:
	if clock_label:
		clock_label.text = clock_text
		weather_label.text = weather.capitalize()
		coin_label.text = "%d petal" % coins
		hover_label.text = hover
	if seed_button:
		seed_button.text = "2  Seed\n%s" % seed_name

func toast(text: String) -> void:
	toast_label.text = text
	_toast_time = 3.4
	hint_label.visible = false

func set_tool(tool_name: String) -> void:
	for key in tool_buttons.keys():
		var button: Button = tool_buttons[key]
		var on: bool = str(key) == tool_name
		button.add_theme_stylebox_override("normal", ThemeKit.button_box(on))
		button.add_theme_color_override("font_color", ThemeKit.CREAM if on else ThemeKit.INK)

func show_journal(rows: Array, events: Array, residents: int, bites: Array = []) -> void:
	_clear(journal_box)
	journal_box.add_child(ThemeKit.title("Grow journal", 22))
	journal_box.add_child(ThemeKit.label("%d residents in the parish" % residents, 14, ThemeKit.MOSS_DEEP))
	var ordered := rows.duplicate()
	ordered.sort_custom(func(a, b): return _status_rank(str(a["status"])) > _status_rank(str(b["status"])))
	for row in ordered:
		journal_box.add_child(_species_card(row))
	if not events.is_empty():
		journal_box.add_child(ThemeKit.title("Today", 16))
		for line in events.slice(0, 6):
			journal_box.add_child(ThemeKit.label("· " + str(line), 14))
	if not bites.is_empty():
		journal_box.add_child(ThemeKit.title("Who ate", 16))
		for line in bites:
			journal_box.add_child(ThemeKit.label("· " + str(line), 14))

func show_people(rows: Array) -> void:
	_clear(journal_box)
	journal_box.add_child(ThemeKit.title("Parish directory", 22))
	for row in rows:
		journal_box.add_child(_person_card(row))

func show_trust(lines: Array, audit: Array) -> void:
	_clear(journal_box)
	journal_box.add_child(ThemeKit.title("Trust", 22))
	journal_box.add_child(ThemeKit.label("External tools stay closed. Approvals here move parish coins or the parish book only.", 14))
	for line in lines:
		journal_box.add_child(ThemeKit.label(str(line), 15))
	journal_box.add_child(ThemeKit.title("Audit", 16))
	if audit.is_empty():
		journal_box.add_child(ThemeKit.label("No approved actions yet.", 14))
	for entry in audit.slice(0, 8):
		journal_box.add_child(ThemeKit.label("%s · %s · %s" % [entry.get("person", ""), entry.get("action", ""), entry.get("result", "")], 13))

func show_place(stats: Dictionary) -> void:
	_clear(journal_box)
	journal_box.add_child(ThemeKit.title(str(stats.get("name", "Hedge Hollow")), 22))
	journal_box.add_child(ThemeKit.label("Phase %s · one parish. The lane beyond the hedge counts ripe beds." % str(stats.get("phase", "A")), 14))
	journal_box.add_child(ThemeKit.label("Veg people  %s" % str(stats.get("veg_people", 0)), 16))
	journal_box.add_child(ThemeKit.label("Creature residents  %s" % str(stats.get("creature_residents", 0)), 16))
	journal_box.add_child(ThemeKit.label("Employed at the stall  %s" % str(stats.get("employed", 0)), 16))
	journal_box.add_child(ThemeKit.label("Garden care  %d%%" % int(float(stats.get("garden_quality", 0.0)) * 100.0), 16))
	journal_box.add_child(ThemeKit.label("Petal coins  %s" % str(stats.get("coins", 0)), 16))
	journal_box.add_child(ThemeKit.label("Bees over the beds  %s" % str(stats.get("bees", 0)), 16))
	journal_box.add_child(ThemeKit.label("Birds  %s · %s" % [str(stats.get("birds", 0)), str(stats.get("bird_state", "crossing"))], 16))
	journal_box.add_child(ThemeKit.label("Petal Stall demand  %s" % str(stats.get("stall_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Potting Shed demand  %s" % str(stats.get("shed_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Hedge Tea House demand  %s" % str(stats.get("tea_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Research Hut demand  %s" % str(stats.get("hut_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Media Foundry demand  %s" % str(stats.get("foundry_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Town Hall demand  %s" % str(stats.get("hall_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Lane beyond the hedge  %s" % str(stats.get("lane_passers", 0)), 16))
	journal_box.add_child(ThemeKit.label(str(stats.get("road_line", "The road beyond the hedge is not yet a rumour.")), 14))
	var cane_line := str(stats.get("cane_line", ""))
	if cane_line != "":
		journal_box.add_child(ThemeKit.label(cane_line, 14))
	var bell_line := str(stats.get("bell_line", ""))
	if bell_line != "":
		journal_box.add_child(ThemeKit.label(bell_line, 14))
	var peach_line := str(stats.get("peach_line", ""))
	if peach_line != "":
		journal_box.add_child(ThemeKit.label(peach_line, 14))
	var reed_line := str(stats.get("reed_line", ""))
	if reed_line != "":
		journal_box.add_child(ThemeKit.label(reed_line, 14))
	var grow_line := str(stats.get("grow_line", ""))
	if grow_line != "":
		journal_box.add_child(ThemeKit.label(grow_line, 14))
	var sweet_line := str(stats.get("sweet_line", ""))
	if sweet_line != "":
		journal_box.add_child(ThemeKit.label(sweet_line, 14))
	var ripe_line := str(stats.get("ripe_line", ""))
	if ripe_line != "":
		journal_box.add_child(ThemeKit.label(ripe_line, 14))
	journal_box.add_child(ThemeKit.label("Demand for the rooms that are not built is not simulated.", 14))
	journal_box.add_child(ThemeKit.title("Town Hall board", 16))
	var notices: Array = stats.get("notices", [])
	if notices.is_empty():
		journal_box.add_child(ThemeKit.label("The board is bare. Approved proposals are posted here. The town beyond the hedge is not.", 14))
	for notice in notices:
		journal_box.add_child(ThemeKit.label(str(notice), 14))
	journal_box.add_child(ThemeKit.title("Venues", 16))
	for line in stats.get("venues", []):
		journal_box.add_child(ThemeKit.label(str(line), 14))
	var tiers = stats.get("tiers", {})
	journal_box.add_child(ThemeKit.label("Sim tiers  hero %s · near %s · district %s · offscreen %s" % [tiers.get("0", 0), tiers.get("1", 0), tiers.get("2", 0), tiers.get("3", 0)], 14))

func show_shop(stock: Array, produce: Array, proposal_ready: bool, stall_open: bool = true) -> void:
	_clear(shop_box)
	shop_box.add_child(ThemeKit.title("Petal Stall", 22))
	if stall_open:
		shop_box.add_child(ThemeKit.label("Lumen Peel will not move coins unless you ask.", 14))
	else:
		shop_box.add_child(ThemeKit.label("The stall is shut until morning.", 14))
	for item in stock:
		var button := Button.new()
		var lock := str(item.get("lock_note", ""))
		if bool(item.get("locked", false)):
			button.text = "%s  ·  wrapped" % item.get("name", "")
			button.disabled = true
		else:
			button.text = "%s  ·  %d petal" % [item.get("name", ""), int(item.get("price", 0))]
			button.disabled = not stall_open
			if stall_open:
				button.pressed.connect(func(): host.buy(str(item.get("id", ""))))
		shop_box.add_child(button)
		if lock != "" and bool(item.get("locked", false)):
			shop_box.add_child(ThemeKit.label(lock, 12, ThemeKit.TERRACOTTA))
	shop_box.add_child(ThemeKit.title("Sell", 16))
	var any := false
	for item in produce:
		any = true
		var button := Button.new()
		button.text = "Sell %s  ·  %d  (%d)" % [item.get("name", ""), int(item.get("price", 0)), int(item.get("count", 0))]
		button.disabled = not stall_open
		var plant_id := str(item.get("id", ""))
		if stall_open:
			button.pressed.connect(func(): host.sell(plant_id))
		shop_box.add_child(button)
	if not any:
		shop_box.add_child(ThemeKit.label("The pouch has no produce yet.", 14))
	if proposal_ready:
		var hear := Button.new()
		hear.text = "Hear Lumen's tray proposal"
		hear.pressed.connect(func(): _show_lumen())
		shop_box.add_child(hear)

func toggle_journal() -> void:
	journal.visible = not journal.visible
	if journal.visible:
		shop.visible = false
		host.refresh_panels()

func toggle_shop() -> void:
	shop.visible = not shop.visible
	if shop.visible:
		journal.visible = false
		host.refresh_panels()

func show_page(page: String) -> void:
	for key in pages.keys():
		pages[key].visible = key == page

func set_photo(on: bool) -> void:
	for child in get_children():
		if child == photo_label:
			continue
		child.visible = not on
	photo_label.visible = on
	if not on:
		journal.visible = false
		shop.visible = false
		pause_panel.visible = false
		proposal.visible = false

func show_pause(on: bool) -> void:
	pause_panel.visible = on

func _top(theme: Theme) -> void:
	var bar := Panel.new()
	bar.theme = theme
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = 12
	bar.offset_bottom = 78
	add_child(bar)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	bar.add_child(row)
	clock_label = ThemeKit.title("Day 1  ·  Golden", 20)
	weather_label = ThemeKit.label("Golden", 16, ThemeKit.MOSS_DEEP)
	coin_label = ThemeKit.title("36 petal", 20)
	hover_label = ThemeKit.label("Hedge Hollow", 14)
	row.add_child(clock_label)
	row.add_child(weather_label)
	row.add_child(coin_label)
	row.add_child(hover_label)

func _tools(theme: Theme) -> void:
	var bar := Panel.new()
	bar.theme = theme
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	bar.offset_top = -108
	bar.offset_bottom = -12
	add_child(bar)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	var specs := [
		["till", "1  Tiller"],
		["seed", "2  Seed"],
		["water", "3  Raincan"],
		["feed", "4  Fertilize"],
		["tend", "5  Tend"],
		["scoop", "6  Scoop"],
		["home", "7  Home"],
		["hands", "H  Hands"],
	]
	for spec in specs:
		var button := Button.new()
		button.text = spec[1]
		button.custom_minimum_size = Vector2(112, 72)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var id := str(spec[0])
		button.pressed.connect(func(): host.set_tool(id))
		row.add_child(button)
		tool_buttons[id] = button
		if id == "seed":
			seed_button = button
	var journal_button := Button.new()
	journal_button.text = "J  Journal"
	journal_button.custom_minimum_size = Vector2(112, 72)
	journal_button.pressed.connect(toggle_journal)
	row.add_child(journal_button)
	var stall_button := Button.new()
	stall_button.text = "B  Stall"
	stall_button.custom_minimum_size = Vector2(100, 72)
	stall_button.pressed.connect(toggle_shop)
	row.add_child(stall_button)

func _journal(theme: Theme) -> void:
	journal = Panel.new()
	journal.theme = theme
	journal.visible = false
	journal.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	journal.offset_left = 16
	journal.offset_top = 90
	journal.offset_bottom = -120
	journal.offset_right = 460
	add_child(journal)
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(12, 10)
	tabs.size = Vector2(420, 36)
	journal.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 52)
	scroll.size = Vector2(428, 520)
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_top = 52
	scroll.offset_right = -8
	scroll.offset_bottom = -8
	journal.add_child(scroll)
	journal_box = VBoxContainer.new()
	journal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_box.custom_minimum_size = Vector2(400, 0)
	scroll.add_child(journal_box)
	people_box = VBoxContainer.new()
	trust_box = VBoxContainer.new()
	place_box = VBoxContainer.new()
	pages = {"journal": journal_box, "people": people_box, "trust": trust_box, "place": place_box}
	# Pages share the scroll by reparenting. Simpler: one box and we swap content via show methods.
	# People, trust, and place are filled into journal_box by the host when the tab changes.
	for spec in [["journal", "Garden"], ["people", "People"], ["trust", "Trust"], ["place", "Parish"]]:
		var button := Button.new()
		var page := str(spec[0])
		button.text = spec[1]
		button.pressed.connect(func(): host.show_directory(page))
		tabs.add_child(button)

func _shop(theme: Theme) -> void:
	shop = Panel.new()
	shop.theme = theme
	shop.visible = false
	shop.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	shop.anchor_left = 1.0
	shop.anchor_right = 1.0
	shop.offset_left = -420
	shop.offset_right = -16
	shop.offset_top = 90
	shop.offset_bottom = -120
	add_child(shop)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_top = 8
	scroll.offset_right = -8
	scroll.offset_bottom = -8
	shop.add_child(scroll)
	shop_box = VBoxContainer.new()
	shop_box.custom_minimum_size = Vector2(360, 0)
	scroll.add_child(shop_box)

func _pause(theme: Theme) -> void:
	pause_panel = Panel.new()
	pause_panel.theme = theme
	pause_panel.visible = false
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.offset_left = -220
	pause_panel.offset_right = 220
	pause_panel.offset_top = -230
	pause_panel.offset_bottom = 230
	add_child(pause_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 16
	box.offset_right = -16
	box.offset_bottom = -16
	pause_panel.add_child(box)
	box.add_child(ThemeKit.title("Paused", 28))
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func(): host.resume())
	box.add_child(resume)
	var save := Button.new()
	save.text = "Save garden"
	save.pressed.connect(func(): host.quick_save())
	box.add_child(save)
	var load := Button.new()
	load.text = "Load garden"
	load.pressed.connect(func(): host.quick_load())
	box.add_child(load)
	box.add_child(ThemeKit.label("Volume", 14))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = Settings.master
	slider.value_changed.connect(func(v): host.set_master(float(v)))
	box.add_child(slider)
	var large := CheckButton.new()
	large.text = "Large text"
	large.button_pressed = Settings.large_text
	large.toggled.connect(func(on): host.set_large_text(on))
	box.add_child(large)
	var motion := CheckButton.new()
	motion.text = "Reduce motion"
	motion.button_pressed = Settings.reduce_motion
	motion.toggled.connect(func(on): host.set_reduce_motion(on))
	box.add_child(motion)
	var flash := CheckButton.new()
	flash.text = "Calm weather"
	flash.button_pressed = Settings.photosensitivity
	flash.toggled.connect(func(on): host.set_calm(on))
	box.add_child(flash)
	var quit := Button.new()
	quit.text = "Leave to title"
	quit.pressed.connect(func(): host.quit_to_title())
	box.add_child(quit)

func _proposal(theme: Theme) -> void:
	proposal = Panel.new()
	proposal.theme = theme
	proposal.visible = false
	proposal.set_anchors_preset(Control.PRESET_CENTER)
	proposal.offset_left = -260
	proposal.offset_right = 260
	proposal.offset_top = -180
	proposal.offset_bottom = 180
	add_child(proposal)

func _show_lumen() -> void:
	_fill_proposal(
		"Lumen Peel",
		"I can set aside a peach tray from tomorrow's sowing.\n\nIt would take 8 petal coins from the stall tin.\n\nNo coins leave Hedge Hollow. I will not do it unless you say so.",
		"Set the tray aside",
		func(): host.accept_lumen()
	)

func show_draft() -> void:
	_fill_proposal(
		"Nessa Pod",
		"I can keep three short episodes about the garden in the parish book.\n\nNo coins. Nothing is sent. You would be approving a draft that stays here.",
		"Keep the draft",
		func(): host.accept_draft()
	)

func show_road() -> void:
	_fill_proposal(
		"Nessa Pod",
		"The road beyond the hedge is only a rumour.\n\nI can write that in the parish book.\n\nNo coins. Nothing is sent. I will not write it unless you say so.",
		"File the rumour",
		func(): host.accept_road()
	)

func show_nessa() -> void:
	_fill_proposal(
		"Nessa Pod",
		"I can write the pollinator notes into the parish book.\n\nNo letters leave the garden. No network. No coins.\n\nShall I file them?",
		"File the notes",
		func(): host.accept_nessa()
	)

func _fill_proposal(title: String, body: String, accept_label: String, accept: Callable) -> void:
	for child in proposal.get_children():
		child.free()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 12
	box.offset_right = -16
	box.offset_bottom = -12
	proposal.add_child(box)
	box.add_child(ThemeKit.title(title, 22))
	var copy := ThemeKit.label(body, 15)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(copy)
	var yes := Button.new()
	yes.text = accept_label
	yes.pressed.connect(func():
		proposal.visible = false
		accept.call()
	)
	box.add_child(yes)
	var no := Button.new()
	no.text = "Not now"
	no.pressed.connect(func(): proposal.visible = false)
	box.add_child(no)
	proposal.visible = true

func _species_card(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ThemeKit.panel(0.72))
	var box := VBoxContainer.new()
	card.add_child(box)
	box.add_child(ThemeKit.title("%s  ·  %s" % [row.get("name", ""), row.get("status", "")], 16))
	box.add_child(ThemeKit.label(str(row.get("blurb", "")), 13))
	for line in row.get("met", []):
		box.add_child(ThemeKit.label("✓  " + str(line), 13, ThemeKit.MOSS))
	for line in row.get("unmet", []):
		box.add_child(ThemeKit.label("·  " + str(line), 13, ThemeKit.TERRACOTTA))
	var romance := str(row.get("romance", ""))
	if romance != "":
		var ready: bool = row.get("romance_met", false)
		var residents := int(row.get("residents", 0))
		var text := "Romance  ·  %s" % romance if ready else "Romance conditions unmet  ·  %s" % romance
		if str(row.get("status", "")) == "breeding" or str(row.get("status", "")) == "bonded":
			text = romance
		box.add_child(ThemeKit.label("%s   (%d residents)" % [text, residents], 13))
	return card

func _person_card(row: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ThemeKit.panel(0.72))
	var box := VBoxContainer.new()
	card.add_child(box)
	box.add_child(ThemeKit.title(str(row.get("name", "")), 16))
	box.add_child(ThemeKit.label("%s  ·  %s" % [row.get("role", ""), row.get("state", "")], 13, ThemeKit.MOSS_DEEP))
	box.add_child(ThemeKit.label("%s  ·  %s" % [row.get("home", ""), row.get("job", "")], 13))
	box.add_child(ThemeKit.label(str(row.get("blurb", "")), 13))
	if bool(row.get("present", false)):
		box.add_child(ThemeKit.label("Mood %s   care %.0f   belonging %.0f   purpose %.0f" % [row.get("mood", ""), float(row.get("energy", 0)) * 100, float(row.get("belonging", 0)) * 100, float(row.get("purpose", 0)) * 100], 13))
		box.add_child(ThemeKit.label("With you  %.0f" % (float(row.get("relation", 0)) * 100), 13))
	else:
		for line in row.get("unmet", []):
			box.add_child(ThemeKit.label("·  " + str(line), 13, ThemeKit.TERRACOTTA))
	if bool(row.get("can_file", false)):
		var button := Button.new()
		button.text = "Hear Nessa's notes proposal"
		button.pressed.connect(show_nessa)
		box.add_child(button)
	var kept := str(row.get("road_line", ""))
	if kept != "":
		box.add_child(ThemeKit.label(kept, 13))
	if bool(row.get("can_road", false)):
		var road := Button.new()
		road.text = "Hear the road rumour"
		road.pressed.connect(show_road)
		box.add_child(road)
	if bool(row.get("can_draft", false)):
		var draft := Button.new()
		draft.text = "Hear the parish draft"
		draft.pressed.connect(show_draft)
		box.add_child(draft)
	return card

func _clear(box: VBoxContainer) -> void:
	if box == null:
		return
	for child in box.get_children():
		child.free()

func _status_rank(status: String) -> int:
	match status:
		"ready to visit":
			return 5
		"visitor", "repeat", "settler":
			return 4
		"resident", "bonded", "breeding":
			return 3
		"curious":
			return 2
		_:
			return 1

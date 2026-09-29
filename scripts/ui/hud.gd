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
var toast_panel: PanelContainer
var hint_label: Label
var photo_label: Label
var inspect_panel: Panel
var inspect_box: VBoxContainer
var journal_box: VBoxContainer
var shop_box: VBoxContainer
var seed_button: Button
var _toast_time := 0.0

func build(owner: Node) -> void:
	host = owner
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	var theme := ThemeKit.make_theme()
	ThemeKit.apply_cursor()
	_top(theme)
	_tools(theme)
	_journal(theme)
	_shop(theme)
	_pause(theme)
	_proposal(theme)
	toast_panel = PanelContainer.new()
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.offset_left = -260
	toast_panel.offset_right = 260
	toast_panel.offset_top = 64
	toast_panel.offset_bottom = 100
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.07, 0.06, 0.05, 0.84)
	plate.set_corner_radius_all(10)
	plate.content_margin_left = 18
	plate.content_margin_right = 18
	plate.content_margin_top = 6
	plate.content_margin_bottom = 6
	toast_panel.add_theme_stylebox_override("panel", plate)
	toast_label = ThemeKit.outline_label("", 16)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(toast_label)
	toast_panel.visible = false
	add_child(toast_panel)
	hint_label = ThemeKit.outline_label("kettle / crate   click a face   Space   F8 play   C town   M vale", 13)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_bottom = -96
	hint_label.offset_top = -118
	hint_label.offset_left = -420
	hint_label.offset_right = 420
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)
	photo_label = ThemeKit.outline_label("Photo  ·  Esc", 18)
	photo_label.add_theme_font_override("font", ThemeKit.font_semibold)
	photo_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	photo_label.offset_top = 24
	photo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	photo_label.visible = false
	add_child(photo_label)
	_inspect_card(theme)

func _inspect_card(theme: Theme) -> void:
	inspect_panel = Panel.new()
	inspect_panel.theme = theme
	inspect_panel.visible = false
	inspect_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	inspect_panel.offset_left = 16
	inspect_panel.offset_top = 88
	inspect_panel.offset_right = 340
	inspect_panel.offset_bottom = 420
	add_child(inspect_panel)
	_gild(inspect_panel)
	inspect_box = VBoxContainer.new()
	inspect_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	inspect_box.offset_left = 48
	inspect_box.offset_top = 44
	inspect_box.offset_right = -48
	inspect_box.offset_bottom = -44
	inspect_box.add_theme_constant_override("separation", 4)
	inspect_panel.add_child(inspect_box)

func show_inspect(row: Dictionary) -> void:
	if inspect_panel == null:
		return
	inspect_panel.visible = true
	_clear(inspect_box)
	inspect_box.add_child(ThemeKit.title(str(row.get("name", "")), 18))
	inspect_box.add_child(ThemeKit.label("Mood  ·  %s" % str(row.get("mood", "")), 14))
	inspect_box.add_child(ThemeKit.label("Bond  ·  %d%%" % int(float(row.get("bond", 0.0)) * 100.0), 14))
	var hunger_line := str(row.get("hunger_line", ""))
	if hunger_line != "":
		inspect_box.add_child(ThemeKit.label(hunger_line, 14))
	elif float(row.get("hunger", 1.0)) < 0.28:
		inspect_box.add_child(ThemeKit.label("Hungry  ·  wants %s" % str(row.get("food", "food")), 13, ThemeKit.TERRACOTTA))
	var place := str(row.get("place", ""))
	if place != "":
		inspect_box.add_child(ThemeKit.label(place, 13, ThemeKit.MOSS_DEEP))
	inspect_box.add_child(ThemeKit.label(str(row.get("life", "")).capitalize(), 13, ThemeKit.MOSS_DEEP))
	inspect_box.add_child(ThemeKit.label(str(row.get("hint", "The face looks back. Esc lets go.")), 12))
	if bool(row.get("can_feed", false)):
		var feed := Button.new()
		feed.text = "Feed from the pouch"
		feed.pressed.connect(func(): host.feed_inspected())
		inspect_box.add_child(feed)

func hide_inspect() -> void:
	if inspect_panel:
		inspect_panel.visible = false

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			toast_label.text = ""
			if toast_panel:
				toast_panel.visible = false

func apply_text_scale() -> void:
	ThemeKit.restyle(self)

func set_status(clock_text: String, weather: String, coins: int, hover: String, seed_name: String) -> void:
	if clock_label:
		clock_label.text = clock_text
		weather_label.text = weather.capitalize()
		coin_label.text = str(coins)
		hover_label.text = hover
	if seed_button:
		seed_button.tooltip_text = seed_name

func toast(text: String) -> void:
	toast_label.text = text
	_toast_time = 3.4
	if toast_panel:
		toast_panel.visible = text != ""
	hint_label.visible = false

func set_tool(tool_name: String) -> void:
	for key in tool_buttons.keys():
		var button: Button = tool_buttons[key]
		var on: bool = str(key) == tool_name
		_skin_slot(button, on)

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
	var lane_where := str(stats.get("lane_where", ""))
	if lane_where != "":
		journal_box.add_child(ThemeKit.label(lane_where, 16))
	var lane_memory := str(stats.get("lane_memory", ""))
	if lane_memory != "":
		journal_box.add_child(ThemeKit.label(lane_memory, 15))
	journal_box.add_child(ThemeKit.label("Phase %s · one parish. The lane beyond the hedge counts ripe beds." % str(stats.get("phase", "A")), 14))
	for line in stats.get("town_lines", []):
		journal_box.add_child(ThemeKit.label(str(line), 14))
	journal_box.add_child(ThemeKit.label("Veg people  %s" % str(stats.get("veg_people", 0)), 16))
	journal_box.add_child(ThemeKit.label("Households  %s" % str(stats.get("households", 0)), 16))
	journal_box.add_child(ThemeKit.label("Creature residents  %s" % str(stats.get("creature_residents", 0)), 16))
	journal_box.add_child(ThemeKit.label("Employed at the stall  %s" % str(stats.get("employed", 0)), 16))
	journal_box.add_child(ThemeKit.label("Garden care  %d%%" % int(float(stats.get("garden_quality", 0.0)) * 100.0), 16))
	var ecology_line := str(stats.get("ecology_line", ""))
	if ecology_line != "":
		journal_box.add_child(ThemeKit.label(ecology_line, 14))
	var habitat_line := str(stats.get("habitat_line", ""))
	if habitat_line != "":
		journal_box.add_child(ThemeKit.label(habitat_line, 14))
	var courtship_line := str(stats.get("courtship_line", ""))
	if courtship_line != "":
		journal_box.add_child(ThemeKit.label(courtship_line, 14))
	var forage_line := str(stats.get("forage_line", ""))
	if forage_line != "":
		journal_box.add_child(ThemeKit.label(forage_line, 14, ThemeKit.TERRACOTTA))
	journal_box.add_child(ThemeKit.label("Petal coins  %s" % str(stats.get("coins", 0)), 16))
	journal_box.add_child(ThemeKit.label("Bees over the beds  %s" % str(stats.get("bees", 0)), 16))
	journal_box.add_child(ThemeKit.label("Birds  %s · %s" % [str(stats.get("birds", 0)), str(stats.get("bird_state", "crossing"))], 16))
	journal_box.add_child(ThemeKit.label("Petal Stall demand  %s" % str(stats.get("stall_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Potting Shed demand  %s" % str(stats.get("shed_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Hedge Tea House demand  %s" % str(stats.get("tea_demand", 0)), 16))
	var kettle_line := str(stats.get("kettle_line", ""))
	if kettle_line != "":
		journal_box.add_child(ThemeKit.label(kettle_line, 16))
	var lane_tea := str(stats.get("lane_tea_line", ""))
	if lane_tea != "":
		journal_box.add_child(ThemeKit.label(lane_tea, 14))
	var town_tea := int(stats.get("town_tea", 0))
	if town_tea > 0:
		journal_box.add_child(ThemeKit.label("Lane cups at the porch  %s" % str(town_tea), 16))
	journal_box.add_child(ThemeKit.label("Research Hut demand  %s" % str(stats.get("hut_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Media Foundry demand  %s" % str(stats.get("foundry_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Town Hall demand  %s" % str(stats.get("hall_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Grove Park demand  %s" % str(stats.get("park_demand", 0)), 16))
	journal_box.add_child(ThemeKit.label("Lane houses  %s" % str(stats.get("lane_houses", 0)), 16))
	journal_box.add_child(ThemeKit.label("Lane beyond the hedge  %s" % str(stats.get("lane_passers", 0)), 16))
	journal_box.add_child(ThemeKit.label(str(stats.get("road_line", "The road beyond the hedge is not yet a rumour.")), 14))
	for key in ["far_bell_line", "bell_sale_line", "join_line", "south_line", "lane_south_line", "end_line", "lane_busy_line", "east_line", "east_past_line", "east_far_line", "east_near_line", "east_closer_bell_line", "west_gate_bell_line", "south_step_line", "west_turn_line", "end_step_line", "outer_east_line", "further_east_line", "span_east_line", "reach_east_line", "field_east_line", "brink_east_line", "margin_east_line", "hem_east_line", "hem_stone_line", "hem_stone_bell_line", "hem_stone_on_bell_line", "hem_stone_far_bell_line", "hem_stone_out_bell_line", "outer_stone_strip_line", "outer_strip_bell_stone_line", "meadow_strip_bell_line", "meadow_stone_strip_line", "farther_strip_bell_line", "last_bell_stone_line", "last_strip_bell_line", "end_strip_stone_line", "far_bell_stone_line", "far_stone_strip_line", "gate_sale_line", "parish_sale_line"]:
		var road_bit := str(stats.get(key, ""))
		if road_bit != "":
			journal_box.add_child(ThemeKit.label(road_bit, 14))
	var cross_line := str(stats.get("cross_line", ""))
	if cross_line != "":
		journal_box.add_child(ThemeKit.label(cross_line, 14))
	var want_line := str(stats.get("want_line", ""))
	if want_line != "":
		journal_box.add_child(ThemeKit.label(want_line, 14))
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
	var pear_line := str(stats.get("pear_line", ""))
	if pear_line != "":
		journal_box.add_child(ThemeKit.label(pear_line, 14))
	var lantern_line := str(stats.get("lantern_line", ""))
	if lantern_line != "":
		journal_box.add_child(ThemeKit.label(lantern_line, 14))
	var seed_line := str(stats.get("seed_line", ""))
	if seed_line != "":
		journal_box.add_child(ThemeKit.label(seed_line, 14))
	var leaf_line := str(stats.get("leaf_line", ""))
	if leaf_line != "":
		journal_box.add_child(ThemeKit.label(leaf_line, 14))
	var grow_line := str(stats.get("grow_line", ""))
	if grow_line != "":
		journal_box.add_child(ThemeKit.label(grow_line, 14))
	var sweet_line := str(stats.get("sweet_line", ""))
	if sweet_line != "":
		journal_box.add_child(ThemeKit.label(sweet_line, 14))
	var ripe_line := str(stats.get("ripe_line", ""))
	if ripe_line != "":
		journal_box.add_child(ThemeKit.label(ripe_line, 14))
	var wade_line := str(stats.get("wade_line", ""))
	if wade_line != "":
		journal_box.add_child(ThemeKit.label(wade_line, 14))
	var dusk_line := str(stats.get("dusk_line", ""))
	if dusk_line != "":
		journal_box.add_child(ThemeKit.label(dusk_line, 14))
	journal_box.add_child(ThemeKit.label("Demand for rooms that are not built stays in the town counts, not as bodies.", 14))
	var vale_line := str(stats.get("vale_line", ""))
	if vale_line != "":
		journal_box.add_child(ThemeKit.title("Petal Vale", 16))
		journal_box.add_child(ThemeKit.label(vale_line, 14))
		for line in stats.get("vale_rows", []):
			journal_box.add_child(ThemeKit.label(str(line), 14))
	journal_box.add_child(ThemeKit.title("Town Hall board", 16))
	var notices: Array = stats.get("notices", [])
	if notices.is_empty():
		journal_box.add_child(ThemeKit.label("The board is bare. Approved proposals are posted here. The vale keeps its own page.", 14))
	for notice in notices:
		journal_box.add_child(ThemeKit.label(str(notice), 14))
	journal_box.add_child(ThemeKit.title("Venues", 16))
	for line in stats.get("venues", []):
		journal_box.add_child(ThemeKit.label(str(line), 14))
	var tiers = stats.get("tiers", {})
	journal_box.add_child(ThemeKit.label("Sim tiers  hero %s · near %s · district %s · offscreen %s · town %s" % [tiers.get("0", 0), tiers.get("1", 0), tiers.get("2", 0), tiers.get("3", 0), tiers.get("4", 0)], 14))

func show_vale(report: Dictionary) -> void:
	_clear(journal_box)
	journal_box.add_child(ThemeKit.title(str(report.get("title", "Petal Vale")), 22))
	journal_box.add_child(_wrap("Parishes beyond the hedge. Carts, walkers, and seed. Not a war map.", 14, ThemeKit.MOSS_DEEP))
	var world_line := str(report.get("world_line", ""))
	if world_line != "":
		journal_box.add_child(_wrap(world_line, 14))
	journal_box.add_child(_vale_map(report))
	var ask_rows_raw = report.get("ask_rows", [])
	var ask_rows: Array = ask_rows_raw if typeof(ask_rows_raw) == TYPE_ARRAY else []
	var asked := {}
	if not ask_rows.is_empty():
		journal_box.add_child(ThemeKit.title("Parish asks", 16))
		journal_box.add_child(_wrap("They asked first. Send what they named.", 13, ThemeKit.TERRACOTTA))
		for spec in ask_rows:
			var ask: Dictionary = spec
			var to_id := str(ask.get("to", ""))
			var crop := str(ask.get("crop", ""))
			if to_id != "":
				asked[to_id] = true
			journal_box.add_child(_wrap(str(ask.get("text", ask.get("label", ""))), 14, ThemeKit.TERRACOTTA))
			if to_id == "" or crop == "":
				continue
			var button := Button.new()
			button.text = str(ask.get("label", "Send"))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(func(): host.send_vale_cart(to_id, crop))
			journal_box.add_child(button)
	for row in report.get("settlements", []):
		var hamlet: Dictionary = row
		var lod := int(hamlet.get("lod", 4))
		var lod_name := "region"
		if lod <= 2:
			lod_name = "district"
		elif lod == 3:
			lod_name = "settlement"
		var choice := str(hamlet.get("choice", ""))
		var conf := float(hamlet.get("confidence", 0.0))
		journal_box.add_child(ThemeKit.title("%s · %s" % [str(hamlet.get("name", "")), str(hamlet.get("stance", ""))], 16))
		journal_box.add_child(_wrap("grows %s · needs %s · %s · %d hands" % [str(hamlet.get("specialty", "")), str(hamlet.get("need", "")), lod_name, int(hamlet.get("hands", 0))], 14))
		if choice != "":
			journal_box.add_child(_wrap("%s (%.2f)" % [choice, conf], 13, ThemeKit.MOSS_DEEP))
		journal_box.add_child(_wrap(str(hamlet.get("stock_line", "")), 13))
	var carts_raw = report.get("carts", [])
	var carts: Array = carts_raw if typeof(carts_raw) == TYPE_ARRAY else []
	if not carts.is_empty():
		journal_box.add_child(ThemeKit.title("Carts on the lane", 16))
		for line in carts:
			journal_box.add_child(_wrap("· " + str(line), 14))
	var walks_raw = report.get("migrants", [])
	var walks: Array = walks_raw if typeof(walks_raw) == TYPE_ARRAY else []
	if not walks.is_empty():
		journal_box.add_child(ThemeKit.title("Walkers", 16))
		for line in walks:
			journal_box.add_child(_wrap("· " + str(line), 14))
	if bool(report.get("can_welcome", false)):
		var welcome := Button.new()
		welcome.text = "Welcome the walker at the hedge"
		welcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		welcome.pressed.connect(func(): host.welcome_vale())
		journal_box.add_child(welcome)
	journal_box.add_child(ThemeKit.title("Send a cart", 16))
	for spec in report.get("sends", []):
		var send: Dictionary = spec
		var to_id := str(send.get("to", ""))
		if asked.has(to_id):
			continue
		var button := Button.new()
		button.text = str(send.get("label", "Send"))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var crop := str(send.get("crop", ""))
		button.pressed.connect(func(): host.send_vale_cart(to_id, crop))
		journal_box.add_child(button)
	journal_box.add_child(ThemeKit.title("Share seed", 16))
	for spec in report.get("sends", []):
		var send: Dictionary = spec
		var button := Button.new()
		button.text = "Share %s seed with %s" % [str(send.get("crop", "")), str(send.get("name", send.get("to", "")))]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var to_id := str(send.get("to", ""))
		var crop := str(send.get("crop", ""))
		button.pressed.connect(func(): host.share_vale_seed(to_id, crop))
		journal_box.add_child(button)
	var log_raw = report.get("log", [])
	var log: Array = log_raw if typeof(log_raw) == TYPE_ARRAY else []
	if not log.is_empty():
		journal_box.add_child(ThemeKit.title("Vale book", 16))
		for line in log:
			journal_box.add_child(_wrap("· " + str(line), 14))

func _vale_map(report: Dictionary) -> Control:
	var board := Control.new()
	board.custom_minimum_size = Vector2(380, 196)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var asked := {}
	for spec in report.get("ask_rows", []):
		var ask: Dictionary = spec
		asked[str(ask.get("to", ""))] = true
	var inbound := {}
	for spec in report.get("cart_rows", []):
		var cart: Dictionary = spec
		inbound[str(cart.get("to", ""))] = true
	var origin := Vector2(190, 92)
	var size := 48.0
	for row in report.get("settlements", []):
		var hamlet: Dictionary = row
		var q := float(int(hamlet.get("q", 0)))
		var r := float(int(hamlet.get("r", 0)))
		var at := origin + Vector2(size * 1.5 * q, size * sqrt(3.0) * (r + q * 0.5))
		var lod := int(hamlet.get("lod", 4))
		var fill := Color("#6a5a48")
		if bool(hamlet.get("player", false)):
			fill = Color("#c4895a")
		elif lod <= 2:
			fill = Color("#6d9a4a")
		elif lod == 3:
			fill = Color("#8a7a4a")
		if asked.has(str(hamlet.get("id", ""))):
			fill = ThemeKit.TERRACOTTA
		var cell := ColorRect.new()
		cell.color = fill
		cell.position = at - Vector2(30, 14)
		cell.size = Vector2(60, 28)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(cell)
		var id := str(hamlet.get("id", ""))
		var short := id
		match id:
			"hollow":
				short = "Hollow"
			"reedbank":
				short = "Reed"
			"mossford":
				short = "Moss"
			"lea":
				short = "Lea"
			"thatch":
				short = "Thatch"
		if inbound.has(id):
			short = "· " + short
		var caption := ThemeKit.label(short, 11, ThemeKit.CREAM)
		caption.position = at - Vector2(28, 10)
		caption.size = Vector2(56, 20)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.add_child(caption)
	return board

func show_shop(stock: Array, produce: Array, proposal_ready: bool, stall_open: bool = true, mill: Dictionary = {}) -> void:
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
	shop_box.add_child(ThemeKit.title("Kettle", 16))
	shop_box.add_child(ThemeKit.label(str(mill.get("line", "The kettle is quiet.")), 14))
	var left := int(mill.get("left", 0))
	if left > 0:
		shop_box.add_child(ThemeKit.label("Left  ·  %d min" % left, 13))
	var brew := Button.new()
	brew.text = "Stock the kettle  ·  peach + meadowbell"
	brew.disabled = not bool(mill.get("can_stock", false))
	brew.pressed.connect(func(): host.stock_kettle())
	shop_box.add_child(brew)
	var carry := Button.new()
	carry.text = "Carry tea to the crate"
	carry.disabled = not bool(mill.get("can_carry", false))
	carry.pressed.connect(func(): host.carry_tea())
	shop_box.add_child(carry)
	var tea := Button.new()
	tea.text = "Sell hedge tea  ·  %d  (%d)" % [int(mill.get("price", 22)), int(mill.get("crate", 0))]
	tea.disabled = not stall_open or int(mill.get("crate", 0)) <= 0
	if stall_open:
		tea.pressed.connect(func(): host.sell_tea())
	shop_box.add_child(tea)
	shop_box.add_child(ThemeKit.title("Pan", 16))
	var jam := Button.new()
	jam.text = "Stock the pan  ·  bramble"
	jam.disabled = not bool(mill.get("can_jam", false))
	jam.pressed.connect(func(): host.stock_jam())
	shop_box.add_child(jam)
	var jam_carry := Button.new()
	jam_carry.text = "Carry jam to the crate"
	jam_carry.disabled = not bool(mill.get("can_carry_jam", false))
	jam_carry.pressed.connect(func(): host.carry_jam())
	shop_box.add_child(jam_carry)
	var jam_sell := Button.new()
	jam_sell.text = "Sell cane jam  ·  %d  (%d)" % [int(mill.get("jam_price", 16)), int(mill.get("jam_crate", 0))]
	jam_sell.disabled = not stall_open or int(mill.get("jam_crate", 0)) <= 0
	if stall_open:
		jam_sell.pressed.connect(func(): host.sell_jam())
	shop_box.add_child(jam_sell)
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
		if inspect_panel:
			inspect_panel.visible = false
		if toast_panel:
			toast_panel.visible = toast_label != null and toast_label.text != ""

func show_pause(on: bool) -> void:
	pause_panel.visible = on

func _top(theme: Theme) -> void:
	var bar := Panel.new()
	bar.theme = theme
	bar.add_theme_stylebox_override("panel", ThemeKit.topbar_slice)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 48
	bar.offset_right = -48
	bar.offset_top = 6
	bar.offset_bottom = 62
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 84
	row.offset_right = -18
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	clock_label = ThemeKit.outline_label("Day 1  ·  Morning", 18)
	clock_label.add_theme_font_override("font", ThemeKit.font_semibold)
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weather_label = ThemeKit.outline_label("Clear", 16, ThemeKit.GOLD)
	weather_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var petal := TextureRect.new()
	petal.texture = ThemeKit.kit_tex("ui_icon_petal", "2x")
	petal.custom_minimum_size = Vector2(28, 28)
	petal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	petal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	petal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_label = ThemeKit.outline_label("36", 18)
	coin_label.add_theme_font_override("font", ThemeKit.font_semibold)
	coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hover_label = ThemeKit.outline_label("Hedge Hollow", 14)
	hover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hover_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(clock_label)
	row.add_child(weather_label)
	row.add_child(petal)
	row.add_child(coin_label)
	row.add_child(hover_label)
	var badge := TextureRect.new()
	badge.texture = ThemeKit.kit_tex("ui_badge_weather", "2x")
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge.offset_left = 14
	badge.offset_top = 0
	badge.offset_right = 86
	badge.offset_bottom = 72
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)

func _tools(_theme: Theme) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.offset_left = -400
	row.offset_right = 400
	row.offset_top = -90
	row.offset_bottom = -8
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(row)
	var specs := [
		["till", "1", "ui_tool_tiller"],
		["seed", "2", "ui_tool_seed"],
		["water", "3", "ui_tool_raincan"],
		["feed", "4", "ui_tool_fertilize"],
		["tend", "5", "ui_tool_tend"],
		["scoop", "6", "ui_tool_scoop"],
		["home", "7", "ui_tool_home"],
		["hands", "H", "ui_tool_hands"],
	]
	for spec in specs:
		var id := str(spec[0])
		var button := _slot_button(str(spec[2]), str(spec[1]), func(): host.set_tool(id))
		row.add_child(button)
		tool_buttons[id] = button
		if id == "seed":
			seed_button = button
	row.add_child(_slot_button("ui_tool_journal", "J", toggle_journal))
	row.add_child(_slot_button("ui_tool_stall", "B", toggle_shop))

func _slot_button(icon_stem: String, key: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = ""
	button.custom_minimum_size = Vector2(72, 72)
	button.icon = ThemeKit.kit_tex(icon_stem, "2x")
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.pressed.connect(on_press)
	button.clip_contents = false
	_skin_slot(button, false)
	var key_label := ThemeKit.outline_label(key, 16, ThemeKit.PARCHMENT, 5)
	key_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key_label.offset_left = 10
	key_label.offset_top = 6
	key_label.offset_right = 52
	key_label.offset_bottom = 40
	key_label.z_index = 8
	key_label.clip_text = false
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(key_label)
	return button

func _skin_slot(button: Button, on: bool) -> void:
	if button == null:
		return
	var box: StyleBox = ThemeKit.slot_selected if on else ThemeKit.slot_normal
	var hover: StyleBox = ThemeKit.slot_selected if on else ThemeKit.slot_hover
	if box == null or hover == null:
		return
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", ThemeKit.slot_selected)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", ThemeKit.slot_normal)

func _journal(theme: Theme) -> void:
	journal = Panel.new()
	journal.theme = theme
	journal.add_theme_stylebox_override("panel", ThemeKit.journal_slice)
	journal.visible = false
	journal.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	journal.offset_left = 12
	journal.offset_top = 80
	journal.offset_bottom = -110
	journal.offset_right = 520
	add_child(journal)
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(64, 64)
	tabs.size = Vector2(390, 36)
	journal.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(56, 108)
	scroll.size = Vector2(400, 520)
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 56
	scroll.offset_top = 108
	scroll.offset_right = -56
	scroll.offset_bottom = -56
	journal.add_child(scroll)
	journal_box = VBoxContainer.new()
	journal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_box.custom_minimum_size = Vector2(380, 0)
	scroll.add_child(journal_box)
	for spec in [["journal", "Garden"], ["people", "People"], ["trust", "Trust"], ["place", "Parish"], ["vale", "Vale"]]:
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
	shop.offset_left = -500
	shop.offset_right = -12
	shop.offset_top = 80
	shop.offset_bottom = -110
	add_child(shop)
	_gild(shop)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 48
	scroll.offset_top = 44
	scroll.offset_right = -48
	scroll.offset_bottom = -44
	shop.add_child(scroll)
	shop_box = VBoxContainer.new()
	shop_box.custom_minimum_size = Vector2(360, 0)
	scroll.add_child(shop_box)

func _pause(theme: Theme) -> void:
	pause_panel = Panel.new()
	pause_panel.theme = theme
	pause_panel.visible = false
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.offset_left = -240
	pause_panel.offset_right = 240
	pause_panel.offset_top = -250
	pause_panel.offset_bottom = 250
	add_child(pause_panel)
	_gild(pause_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 48
	box.offset_top = 44
	box.offset_right = -48
	box.offset_bottom = -44
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
	proposal.offset_left = -280
	proposal.offset_right = 280
	proposal.offset_top = -200
	proposal.offset_bottom = 200
	add_child(proposal)

func _gild(host_panel: Panel, well := 40) -> void:
	var inner := Panel.new()
	inner.add_theme_stylebox_override("panel", ThemeKit.panel(0.94))
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = well
	inner.offset_top = well
	inner.offset_right = -well
	inner.offset_bottom = -well
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host_panel.add_child(inner)

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

func show_park() -> void:
	_fill_proposal(
		"Nessa Pod",
		"Grove Park can be a public lawn beyond the hedge.\n\nI can write that in the parish book. The lawn will hold visitors as a count. Nobody is spawned.\n\nNo coins. Nothing is sent. I will not write it unless you say so.",
		"File Grove Park",
		func(): host.accept_park()
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
	_gild(proposal)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 48
	box.offset_top = 44
	box.offset_right = -48
	box.offset_bottom = -44
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
	var need := str(row.get("need", ""))
	if need != "":
		box.add_child(ThemeKit.label(need, 13, ThemeKit.TERRACOTTA))
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
	if bool(row.get("present", false)):
		var blurb := str(row.get("blurb", ""))
		if blurb != "":
			box.add_child(_wrap(blurb, 13))
		box.add_child(ThemeKit.label("Mood %s   care %.0f   belonging %.0f   purpose %.0f" % [row.get("mood", ""), float(row.get("energy", 0)) * 100, float(row.get("belonging", 0)) * 100, float(row.get("purpose", 0)) * 100], 13))
		box.add_child(ThemeKit.label("Hunger %.0f   company %.0f" % [float(row.get("hunger", 0)) * 100, float(row.get("social", 0)) * 100], 13))
		box.add_child(ThemeKit.label("With you  %.0f" % (float(row.get("relation", 0)) * 100), 13))
		var house := str(row.get("household", ""))
		if house != "":
			box.add_child(ThemeKit.label("Household  %s" % house, 13))
		var motive := str(row.get("motive", ""))
		if motive != "":
			box.add_child(_wrap(motive, 13))
		var ties := str(row.get("ties", ""))
		if ties != "":
			box.add_child(ThemeKit.label("With neighbours  %s" % ties, 13))
		var memory := str(row.get("memory", ""))
		if memory != "":
			box.add_child(_wrap(memory, 13))
		var want_line := str(row.get("want_line", ""))
		if want_line != "":
			box.add_child(ThemeKit.label(want_line, 13))
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
		box.add_child(_wrap(kept, 13))
	var park_kept := str(row.get("park_line", ""))
	if park_kept != "":
		box.add_child(ThemeKit.label(park_kept, 13))
	for key in ["join_line", "parish_bell_line", "parish_sale_line", "hem_card_line", "hem_stone_card_line", "hem_stone_bell_card_line", "hem_stone_on_bell_card_line", "hem_stone_far_bell_card_line", "hem_stone_out_bell_card_line", "meadow_stone_strip_card_line"]:
		var card_bit := str(row.get(key, ""))
		if card_bit != "":
			box.add_child(ThemeKit.label(card_bit, 13))
	if bool(row.get("can_road", false)):
		var road := Button.new()
		road.text = "Hear the road rumour"
		road.pressed.connect(show_road)
		box.add_child(road)
	if bool(row.get("can_park", false)):
		var park := Button.new()
		park.text = "Hear Grove Park"
		park.pressed.connect(show_park)
		box.add_child(park)
	if bool(row.get("can_draft", false)):
		var draft := Button.new()
		draft.text = "Hear the parish draft"
		draft.pressed.connect(show_draft)
		box.add_child(draft)
	return card

func _wrap(text: String, px: int, color: Color = ThemeKit.INK) -> Label:
	var node := ThemeKit.label(text, px, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size = Vector2(380, 0)
	return node

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

extends Node3D

var soil := SoilField.new()
var road := RoadDressing.new()
var ecology: Ecology
var camera: GardenCamera
var hud: Hud
var debug_overlay: DebugOverlay
var atmosphere: Atmosphere
var audio: GardenAudio
var bees: GardenBees
var birds: GardenBirds
var people := {}
var patches := {}
var bed_blooms: Array[MultiMeshInstance3D] = []
var bed_inside: Array[MultiMeshInstance3D] = []
var bed_turf: MultiMeshInstance3D
var bed_blades: MultiMeshInstance3D
var bed_frame: MultiMeshInstance3D
var soil_lid: BoxMesh
var bed_lid: BoxMesh
var plant_views := {}
var structures := {"home_kit": 0}
var home_points: Array = []
var shift := ""
var bram_bed := Vector2i(-1, -1)
var bram_feeding := false
var nessa_watch: Jelly = null
var nessa_filing := false
var nessa_drafting := false
var nessa_bees := false
var nessa_farewell := false
var farewell_names: Array[String] = []
var scooped: Array[Vector3] = []
var scoop_root: Node3D
var home_root: Node3D
var highlight: MeshInstance3D
var tool := "till"
var held: Jelly
var events: Array = []
var directory_page := "journal"
var panel_timer := 0.0
var gossip_done := false
var gossip_timer := 2.5
var photo := false
var focus: Jelly
var last_land := 0
var visual_timer := 0.0
var loam_hours := 0.0
var bell_day := -1
var lane_afternoon_days: Array[int] = []
var bird_day := -1
var bee_day := -1
var bee_note_day := -1
var bee_flower := Vector3.ZERO
var crate_yields := {}
var last_shop_hour := -1.0
var bus := GardenBus.new()

func _ready() -> void:
	ThemeKit.boot()
	_build()
	if SaveGame.pending_state != null:
		apply_state(SaveGame.pending_state)
		SaveGame.pending_state = null
	else:
		_opening_plants()
	_sync_plants()
	_refresh_soil_colors()
	if OS.get_environment("PETAL_SMOKE") == "1":
		_run_smoke()
		return
	if OS.get_environment("PETAL_CAPTURE") == "1":
		await _run_capture()
		return
	Clock.running = true
	if Settings.reduce_motion:
		camera.intro = 1.0
		camera.user_moved = true

func _build() -> void:
	var creatures := Node3D.new()
	creatures.name = "Creatures"
	add_child(creatures)
	ecology = Ecology.new()
	add_child(ecology)
	ecology.boot(creatures)
	ecology.attractor_provider = Callable(self, "_attractor_for")
	ecology.soil_effect_cb = Callable(self, "_apply_soil_effect")
	ecology.event_happened.connect(_on_ecology)

	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.build(self)
	atmosphere.photosensitivity = Settings.photosensitivity

	GardenDressing.new().build(self)
	GardenProps.new().build(self)
	road.build(self)

	scoop_root = Node3D.new()
	scoop_root.name = "Scoops"
	add_child(scoop_root)
	home_root = Node3D.new()
	home_root.name = "Homes"
	add_child(home_root)
	_build_patches()

	camera = GardenCamera.new()
	add_child(camera)
	audio = GardenAudio.new()
	add_child(audio)
	bees = GardenBees.new()
	add_child(bees)
	bees.build()
	birds = GardenBirds.new()
	add_child(birds)
	birds.build()
	_spawn_people()

	hud = Hud.new()
	add_child(hud)
	hud.build(self)
	hud.set_tool(tool)
	debug_overlay = DebugOverlay.new()
	add_child(debug_overlay)
	debug_overlay.build(self)

func _process(delta: float) -> void:
	if photo:
		atmosphere.apply(Clock.hour(), Clock.weather, camera)
		return
	var minutes := delta * Clock.scale if Clock.running else 0.0
	if minutes > 0.0:
		_dew(minutes / 60.0)
		_prime_reed(minutes / 60.0)
		var lost := soil.tick(minutes, Clock.weather)
		if lost.size() > 0:
			toast("A bed dried out.")
		if soil.seeded != "":
			toast("%s took the next bed." % str(ContentDB.plant(soil.seeded).get("name", "A plant")))
		_hold_loam(minutes / 60.0)
		_hold_cane(minutes / 60.0)
		_hold_fruit(minutes / 60.0)
		_hold_bells(minutes / 60.0)
		_browse(minutes / 60.0)
		_bee_growth(minutes / 60.0)
	var world := world_snapshot()
	if minutes > 0.0:
		_ring_bells(world)
		_note_bees()
		_dawn_birds()
	if Clock.running:
		_note_lane_afternoon()
	ecology.tick(delta, world)
	_wire_jellies()
	_update_creatures(delta)
	_check_nessa(world)
	_apply_shift(false)
	_drift_people(delta, world)
	camera.nudge(delta)
	if bees:
		bees.tick(delta, Settings.reduce_motion, Clock.weather, bee_flower, bee_day == Clock.day, _second_bell())
	if birds:
		birds.tick(delta, Settings.reduce_motion, Clock.hour(), Clock.weather)
	visual_timer += delta
	if visual_timer > 0.2:
		visual_timer = 0.0
		_sync_plants()
		_refresh_soil_colors()
	_update_highlight()
	atmosphere.apply(Clock.hour(), Clock.weather, camera)
	_lamps()
	audio.set_weather(Clock.weather)
	_tick_shop()
	_update_status()
	panel_timer += delta
	if panel_timer > 0.45 and (hud.journal.visible or hud.shop.visible):
		panel_timer = 0.0
		refresh_panels()
	if debug_overlay.visible:
		debug_overlay.set_text(_debug_text())
	if not gossip_done:
		gossip_timer -= delta
		if gossip_timer <= 0.0:
			gossip_done = true
			_person("bram").say("The stall is loud. The beds were quieter.")
	SimLod.recount(ecology.actors)
	SimLod.note_population(_present_people(), ecology.resident_total(), float(world.get("garden_quality", 0.0)), Economy.coins)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				set_tool("till")
			KEY_2:
				set_tool("seed")
			KEY_3:
				set_tool("water")
			KEY_4:
				set_tool("feed")
			KEY_5:
				set_tool("tend")
			KEY_6:
				set_tool("scoop")
			KEY_7:
				set_tool("home")
			KEY_H, KEY_0:
				set_tool("hands")
			KEY_J:
				hud.toggle_journal()
			KEY_B:
				hud.toggle_shop()
			KEY_F:
				_focus_next()
			KEY_P:
				_toggle_photo()
			KEY_ESCAPE:
				_esc()
			KEY_F3:
				debug_overlay.toggle()
			KEY_F5:
				quick_save()
			KEY_F9:
				quick_load()
			KEY_BRACKETLEFT:
				_cycle_seed(-1)
			KEY_BRACKETRIGHT:
				_cycle_seed(1)
			KEY_SPACE:
				_toggle_time()
		return
	if photo:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_primary_down()
		else:
			_primary_up()

func set_tool(next: String) -> void:
	tool = next
	hud.set_tool(next)
	if next == "seed":
		_cycle_seed(0)

func select_seed(seed_id: String) -> void:
	Economy.selected_seed = seed_id

func show_directory(page: String) -> void:
	directory_page = page
	hud.journal.visible = true
	refresh_panels()

func refresh_panels() -> void:
	var world := world_snapshot()
	if directory_page == "people":
		hud.show_people(_people_rows(world))
	elif directory_page == "trust":
		hud.show_trust(_trust_lines(), Trust.audit)
	elif directory_page == "place":
		hud.show_place(_place_stats(world))
	else:
		hud.show_journal(_journal_rows(world), events, ecology.resident_total(), _bite_lines())
	if hud.shop.visible:
		hud.show_shop(_stock(world), _produce(), Trust.lumen_proposal_day != Clock.day, _stall_open())

func _stall_open() -> bool:
	var h := Clock.hour()
	return h >= 5.0 and h < 19.5

func _lane_passers() -> int:
	# ponytail: ripe beds are the only reason to walk the lane; a crowd if the town keeps its own clock.
	if not _stall_open():
		return 0
	if Clock.weather != "clear" and Clock.weather != "golden":
		return 0
	var ripe := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "" and plot.growth >= 1.0:
			ripe += 1
	return ripe

func _sell_price(plant_id: String) -> int:
	var price := int(ContentDB.plant(plant_id).get("sell_price", 1))
	price = PlantGenetics.price(price, _next_yield(plant_id))
	if _lane_passers() > 0:
		price += 1
	return price

func _next_yield(plant_id: String) -> float:
	var held = crate_yields.get(plant_id, [])
	if typeof(held) == TYPE_ARRAY and held.size() > 0:
		return float(held[0])
	return 1.0

func _store_yield(plant_id: String, crop_yield: float) -> void:
	if not crate_yields.has(plant_id):
		crate_yields[plant_id] = []
	crate_yields[plant_id].append(crop_yield)

func _take_yield(plant_id: String) -> float:
	var held = crate_yields.get(plant_id, [])
	if typeof(held) != TYPE_ARRAY or held.is_empty():
		return 1.0
	return float(held.pop_front())

func _tick_shop() -> void:
	if not _stall_open():
		return
	var hour := floorf(Clock.hour())
	if hour == last_shop_hour:
		return
	last_shop_hour = hour
	for id in ["nessa", "bram"]:
		var person := _person(id)
		VillageShop.wish(person)
		var deal := VillageShop.trade(person)
		if str(deal.get("choice", "")) != "buy":
			continue
		var crop := str(deal.get("id", ""))
		person.want = ""
		toast("%s bought %s for %d petal." % [person.display_name, ContentDB.plant(crop).get("name", crop), int(deal.get("price", 0))])
		person.say("I'll take that.")
		refresh_panels()

func _note_lane_afternoon() -> void:
	# ponytail: three distinct afternoons; a clock if a partial afternoon should count.
	if lane_afternoon_days.size() >= 3:
		return
	var hour := Clock.hour()
	if hour < 12.0 or hour >= 17.0:
		return
	if _lane_passers() <= 0:
		return
	if lane_afternoon_days.has(Clock.day):
		return
	lane_afternoon_days.append(Clock.day)

func _road_rumoured() -> bool:
	return lane_afternoon_days.size() >= 3

func _road_line() -> String:
	# ponytail: one sentence; a count if the page should list the afternoons.
	if Trust.has_action("parish_road_rumour"):
		return "The book keeps the rumour of the road beyond the hedge."
	if _road_rumoured():
		return "The road beyond the hedge is a rumour."
	return "The road beyond the hedge is not yet a rumour."

func _road_card_line() -> String:
	# ponytail: one card line after the filing; the page sentence stays the longer one.
	if Trust.has_action("parish_road_rumour"):
		return "The road is only a rumour."
	return ""

func _far_bell_line() -> String:
	return road.line("parish_road_bell")


func _bell_sale_line() -> String:
	# ponytail: one page line the day a sale names the far-lawn bells.
	if _far_bell_line() == "" or Trust.bell_named_day != Clock.day:
		return ""
	return "A sale named the far-lawn bells."

func _join_line() -> String:
	return road.line("parish_road_join")


func _south_line() -> String:
	return road.line("parish_road_south_stone")


func _lane_south_line() -> String:
	# ponytail: one page line; passers stay a count, no body walks the south stone.
	if not Trust.has_action("parish_road_rumour") or _lane_passers() < 1:
		return ""
	return "The lane has reached the south stone."

func _end_line() -> String:
	return road.line("parish_road_end_stone")


func _east_line() -> String:
	return road.line("parish_road_east")


func _east_past_line() -> String:
	return road.line("parish_road_east_past")


func _east_far_line() -> String:
	return road.line("parish_road_east_far_stone")


func _east_near_line() -> String:
	return road.line("parish_road_east_near")


func _east_closer_bell_line() -> String:
	return road.line("parish_road_east_closer_bell")


func _west_gate_bell_line() -> String:
	return road.line("parish_road_east_hedge_west_bell")


func _south_step_line() -> String:
	return road.line("parish_road_east_hedge_west_south")


func _west_turn_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_west")


func _end_step_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_north")


func _outer_east_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_rim")


func _further_east_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_farther")


func _span_east_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_span")


func _reach_east_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_reach_bell")


func _field_east_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_field")


func _brink_east_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_brink")


func _margin_east_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_margin")


func _hem_east_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem")


func _hem_stone_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone")


func _hem_stone_bell_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_bell")


func _hem_stone_on_bell_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_on_bell")


func _hem_stone_far_bell_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_far_bell")


func _hem_stone_out_bell_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_bell")


func _outer_stone_strip_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_strip")


func _outer_strip_bell_stone_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone")


func _meadow_strip_bell_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell")


func _meadow_stone_strip_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")


func _farther_strip_bell_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell")


func _last_bell_stone_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone")


func _last_strip_bell_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell")


func _end_strip_stone_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")


func _far_bell_stone_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone")


func _far_stone_strip_line() -> String:
	return road.line("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")


func _hem_card_line() -> String:
	# ponytail: Nessa's card repeats the page line while that strip is showing.
	if _hem_east_line() == "":
		return ""
	return "The way steps past the margin strip."

func _hem_stone_card_line() -> String:
	# ponytail: Nessa's card repeats the page line while that stone is showing.
	if _hem_stone_line() == "":
		return ""
	return "The way steps past the hem strip."

func _hem_stone_bell_card_line() -> String:
	# ponytail: Nessa's card repeats the page line while that bell is showing.
	if _hem_stone_bell_line() == "":
		return ""
	return "The way steps east of the hem stone."

func _hem_stone_on_bell_card_line() -> String:
	# ponytail: Nessa's card repeats the page line while the farther bell is showing.
	if _hem_stone_on_bell_line() == "":
		return ""
	return "The way steps east of the hem-stone bell."

func _hem_stone_far_bell_card_line() -> String:
	# ponytail: Nessa's card repeats the page line while the bell past that one is showing.
	if _hem_stone_far_bell_line() == "":
		return ""
	return "The way steps past the hem-stone bell."

func _hem_stone_out_bell_card_line() -> String:
	# ponytail: Nessa's card repeats the page line while the bell east of the far bell is showing.
	if _hem_stone_out_bell_line() == "":
		return ""
	return "The way steps east of the far bell."

func _meadow_stone_strip_card_line() -> String:
	# ponytail: Nessa's card repeats the page line while the meadow-strip stone's strip is showing.
	if _meadow_stone_strip_line() == "":
		return ""
	return "The way steps east of the meadow-strip stone."

func _gate_sale_line() -> String:
	# ponytail: one page line the day a sale names the bell toward the gate.
	if _west_gate_bell_line() == "" or Trust.gate_bell_named_day != Clock.day:
		return ""
	return "A sale named the bell toward the gate."

func _parish_sale_line() -> String:
	# ponytail: one page line the day a sale names the parish-end bell.
	if _east_closer_bell_line() == "" or Trust.parish_bell_named_day != Clock.day:
		return ""
	return "A sale named the parish-end bell."

func _lane_busy_line() -> String:
	# ponytail: one page line at three passers; no body walks past the bench.
	if not Trust.has_action("parish_road_rumour") or _lane_passers() < 3:
		return ""
	return "The lane is busy past the bench."

func _want_line() -> String:
	for id in ["nessa", "bram", "lumen"]:
		var person := _person(id)
		if person == null or not person.present or person.want == "":
			continue
		return "%s is looking for %s." % [person.display_name, ContentDB.plant(person.want).get("name", person.want)]
	return ""

func _cross_line() -> String:
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "":
			continue
		if absf(plot.hue - 0.5) > 0.05 or absf(plot.stature - 1.0) > 0.05 or absf(plot.crop_yield - 1.0) > 0.05:
			return "A seedling took after both parents."
	return ""

func _cane_line() -> String:
	# ponytail: one page line while both opening canes are short; it goes when either ripens.
	var near := soil.get_cell(4, 2)
	var far := soil.get_cell(5, 2)
	if near.plant_id != "bramble" or far.plant_id != "bramble":
		return ""
	if near.growth >= 1.0 or far.growth >= 1.0:
		return ""
	return "Two young brambles stand short of ripe."

func _leaf_line() -> String:
	# ponytail: one page line while both opening canes are short of ripe.
	var near := soil.get_cell(4, 2)
	var far := soil.get_cell(5, 2)
	if near.plant_id != "bramble" or far.plant_id != "bramble":
		return ""
	if near.growth >= 1.0 or far.growth >= 1.0:
		return ""
	return "The berries have leaves."

func _bell_line() -> String:
	# ponytail: one page line while all three opening bells are short; it goes when any ripens.
	var cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]
	for cell in cells:
		var plot := soil.get_cell(cell.x, cell.y)
		if plot.plant_id != "meadowbell" or plot.growth >= 1.0:
			return ""
	return "Three meadowbells are showing."

func _peach_line() -> String:
	# ponytail: one page line for the opening peach; it goes when that fruit ripens.
	var plot := soil.get_cell(3, 2)
	if plot.plant_id != "peach" or plot.growth >= 1.0:
		return ""
	return "A peach is showing."

func _reed_line() -> String:
	# ponytail: one page line for the opening reed; it goes when that reed ripens.
	var plot := soil.get_cell(7, 5)
	if plot.plant_id != "reed" or plot.growth >= 1.0:
		return ""
	return "A reed is showing."

func _pear_line() -> String:
	# ponytail: one page line for the opening pear; it goes when that pear ripens.
	var plot := soil.get_cell(4, 1)
	if plot.plant_id != "mosspear" or plot.growth >= 1.0:
		return ""
	return "A mosspear is showing."

func _lantern_line() -> String:
	# ponytail: one page line for the opening lantern; it goes when that bulb ripens.
	var plot := soil.get_cell(6, 4)
	if plot.plant_id != "nightlantern" or plot.growth >= 1.0 or plot.chem != "nightloam":
		return ""
	return "A nightlantern is showing."

func _seed_line() -> String:
	# ponytail: one page line while the opening bed holds night-loam.
	var plot := soil.get_cell(6, 4)
	if plot.chem != "nightloam" or not _seed_open("nightlantern_seed"):
		return ""
	return "The nightlantern seed is open."

func _grow_line() -> String:
	# ponytail: one dawn line on day 2; it lasts until the next morning.
	var day := Clock.day
	var hour := Clock.hour()
	var showing := (day == 2 and hour >= 5.0) or (day == 3 and hour < 5.0)
	if not showing:
		return ""
	return "The peach, the brambles, and the reed take up growing."

func _sweet_line() -> String:
	# ponytail: one page line before the first sighting; it goes once Bellhelp is sighted.
	var ripe := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "meadowbell" and plot.growth >= 1.0:
			ripe += 1
	if ripe < 3:
		return ""
	if ecology.rules.rank_of(str(ecology.states.get("bellhelp", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return ""
	return "The meadow is sweet enough."

func _ripe_cane_line() -> String:
	# ponytail: one page line before the first sighting; it goes once Berrypatch is sighted.
	var ripe := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "bramble" and plot.growth >= 1.0:
			ripe += 1
	if ripe < 2:
		return ""
	if ecology.rules.rank_of(str(ecology.states.get("berrypatch", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return ""
	return "The canes are ripe enough."

func _wade_line() -> String:
	# ponytail: one page line before the first sighting; it goes once Bulrush is sighted.
	if GardenLayout.BASE_POND_CELLS + scooped.size() < 26:
		return ""
	var ripe := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "reed" and plot.growth >= 1.0:
			ripe += 1
	if ripe < 3:
		return ""
	if ecology.rules.rank_of(str(ecology.states.get("bulrush", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return ""
	return "The reeds are ready to wade."

func _dusk_line() -> String:
	# ponytail: one page line before the first sighting; it goes once Pegapear is sighted.
	var weather := Clock.weather
	if weather != "mist" and weather != "rain":
		return ""
	var hour := Clock.hour()
	if hour < 16.0 or hour > 22.0:
		return ""
	if ecology.rules.rank_of(str(ecology.states.get("pegapear", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return ""
	var mature: Dictionary = world_snapshot().get("mature", {})
	if int(mature.get("peach", 0)) < 1 or int(mature.get("nightlantern", 0)) < 1:
		return ""
	return "The dusk is wet enough."

func _rumour_blurb(id: String) -> String:
	# ponytail: one rumour while that page line is up; other species stay unseen.
	if id == "bellhelp" and _sweet_line() != "":
		return "The meadow is sweet enough."
	if id == "berrypatch" and _ripe_cane_line() != "":
		return "The canes are ripe enough."
	if id == "berrypatch" and _leaf_line() != "":
		return "The berries have leaves."
	if id == "bulrush" and _wade_line() != "":
		return "The reeds are ready to wade."
	if id == "pegapear" and _dusk_line() != "":
		return "The dusk is wet enough."
	return "Not sighted yet."

func _rumour_count(sentence: String) -> int:
	var count := 0
	for row in _journal_rows(world_snapshot()):
		var entry: Dictionary = row
		if str(entry.get("name", "")) != "A rumour":
			continue
		var blurb := str(entry.get("blurb", ""))
		if blurb.find("Bellhelp") != -1 or blurb.find("Berrypatch") != -1 or blurb.find("Bulrush") != -1 or blurb.find("Pegapear") != -1:
			return -1
		if blurb == sentence:
			count += 1
		elif blurb == "Not sighted yet.":
			continue
		elif blurb == _sweet_line() or blurb == _ripe_cane_line() or blurb == _wade_line() or blurb == _dusk_line() or blurb == _leaf_line() or blurb == _cross_line() or blurb == "The lane is busy past the bench." or blurb == "The lane has reached the south stone." or blurb == "The way ends past the bench." or blurb == "The way south ends at a stone." or blurb == "Three bells stand on the far lawn." or blurb == "A sale named the far-lawn bells." or blurb == "A sale named the parish-end bell." or blurb == "The way continues east past the bell." or blurb == "A bell stands at the parish end." or blurb == "A bell stands beside the way toward the gate." or blurb == "A sale named the bell toward the gate." or blurb == "The way turns west of the far-south bell." or blurb == "The way steps toward the end stone." or blurb == "The way steps further east of the outer bell." or blurb == "The way steps past the east-end bell." or blurb == "The way steps past the margin strip." or blurb == "The way steps past the hem strip." or blurb == "The way steps east of the hem stone." or blurb == "The way steps east of the hem-stone bell." or blurb == "The way steps past the hem-stone bell." or blurb == "The way steps east of the far bell." or blurb == "The way steps east of the meadow-strip stone." or blurb == "The way steps past the last bell stone." or blurb == "The way steps east of the last-strip's stone." or blurb == "The way steps east of the far bell stone.":
			continue
		else:
			return -1
	return count

func _sweet_rumour_count() -> int:
	return _rumour_count("The meadow is sweet enough.")

func _cane_rumour_count() -> int:
	return _rumour_count("The canes are ripe enough.")

func _leaf_rumour_count() -> int:
	return _rumour_count("The berries have leaves.")

func _wade_rumour_count() -> int:
	return _rumour_count("The reeds are ready to wade.")

func _dusk_rumour_count() -> int:
	return _rumour_count("The dusk is wet enough.")

func _busy_rumour_count() -> int:
	return _rumour_count("The lane is busy past the bench.")

func _reached_rumour_count() -> int:
	return _rumour_count("The lane has reached the south stone.")

func _end_rumour_count() -> int:
	return _rumour_count("The way ends past the bench.")

func _south_rumour_count() -> int:
	return _rumour_count("The way south ends at a stone.")

func _bell_rumour_count() -> int:
	return _rumour_count("Three bells stand on the far lawn.")

func _sale_rumour_count() -> int:
	return _rumour_count("A sale named the far-lawn bells.")

func _parish_sale_rumour_count() -> int:
	return _rumour_count("A sale named the parish-end bell.")

func _east_past_rumour_count() -> int:
	return _rumour_count("The way continues east past the bell.")

func _east_closer_bell_rumour_count() -> int:
	return _rumour_count("A bell stands at the parish end.")

func _west_gate_bell_rumour_count() -> int:
	return _rumour_count("A bell stands beside the way toward the gate.")

func _gate_sale_rumour_count() -> int:
	return _rumour_count("A sale named the bell toward the gate.")

func _west_turn_rumour_count() -> int:
	return _rumour_count("The way turns west of the far-south bell.")

func _end_step_rumour_count() -> int:
	return _rumour_count("The way steps toward the end stone.")

func _further_east_rumour_count() -> int:
	return _rumour_count("The way steps further east of the outer bell.")

func _span_east_rumour_count() -> int:
	return _rumour_count("The way steps past the east-end bell.")

func _hem_east_rumour_count() -> int:
	return _rumour_count("The way steps past the margin strip.")

func _hem_stone_rumour_count() -> int:
	return _rumour_count("The way steps past the hem strip.")

func _hem_stone_bell_rumour_count() -> int:
	return _rumour_count("The way steps east of the hem stone.")

func _hem_stone_on_bell_rumour_count() -> int:
	return _rumour_count("The way steps east of the hem-stone bell.")

func _hem_stone_far_bell_rumour_count() -> int:
	return _rumour_count("The way steps past the hem-stone bell.")

func _hem_stone_out_bell_rumour_count() -> int:
	return _rumour_count("The way steps east of the far bell.")

func _meadow_stone_strip_rumour_count() -> int:
	return _rumour_count("The way steps east of the meadow-strip stone.")

func _last_bell_stone_rumour_count() -> int:
	return _rumour_count("The way steps past the last bell stone.")

func _end_strip_stone_rumour_count() -> int:
	return _rumour_count("The way steps east of the last-strip's stone.")

func _far_stone_strip_rumour_count() -> int:
	return _rumour_count("The way steps east of the far bell stone.")

func _stall_shut() -> void:
	toast("The stall is shut until morning.")
	var lumen := _person("lumen")
	if lumen != null:
		lumen.say("The stall is shut until morning.")

func buy(item_id: String) -> void:
	var item := ContentDB.item(item_id)
	if item.is_empty():
		return
	if not _stall_open():
		_stall_shut()
		return
	if not _shop_unlocked(item):
		toast(str(item.get("lock_reason", "Not yet.")))
		return
	if not Economy.spend(int(item.get("price", 0))):
		toast("The stall tin is short.")
		_person("lumen").say("That is more than the tin holds.")
		return
	Economy.add(item_id, 1)
	audio.play_kind("coin")
	toast("Bought %s." % item.get("name", "it"))
	_person("lumen").say("In the pouch.")
	refresh_panels()

func _buyer_for(plant_id: String) -> VegPerson:
	for id in ["nessa", "bram", "lumen"]:
		var person := _person(id)
		if person != null and person.present and person.want == plant_id:
			return person
	return null

func sell(plant_id: String) -> void:
	if not _stall_open():
		_stall_shut()
		return
	if Economy.count(plant_id) <= 0:
		return
	var buyer := _buyer_for(plant_id)
	var extra := 1 if buyer != null else 0
	if buyer:
		buyer.want = ""
	var price := _sell_price(plant_id) + extra
	_take_yield(plant_id)
	Economy.take(plant_id, 1)
	Economy.earn(price)
	audio.play_kind("coin")
	if extra > 0:
		toast("Sold %s for %d petal. %s was looking for that." % [ContentDB.plant(plant_id).get("name", plant_id), price, buyer.display_name])
	else:
		toast("Sold %s for %d petal." % [ContentDB.plant(plant_id).get("name", plant_id), price])
	if _bell_rumour_count() == 1:
		toast("Three bells stand on the far lawn.")
		Trust.bell_named_day = Clock.day
	if _east_closer_bell_rumour_count() == 1:
		toast("A bell stands at the parish end.")
		Trust.parish_bell_named_day = Clock.day
	if _west_gate_bell_rumour_count() == 1:
		toast("A bell stands beside the way toward the gate.")
		Trust.gate_bell_named_day = Clock.day
	if _lane_passers() > 0:
		Trust.file_lane_sale("lumen")
	refresh_panels()

func accept_lumen() -> void:
	if Trust.lumen_proposal_day == Clock.day:
		toast("The tray was already set aside today.")
		return
	if not Trust.approve_spend("lumen", "peach_tray", "Parish coins only. Nothing left Hedge Hollow.", 8):
		toast("Not enough coins for the tray.")
		return
	Economy.add("peach_seed", 2)
	toast("Lumen set aside a peach tray. Eight coins left the tin.")
	_person("lumen").say("The tray is wrapped. The tin is lighter.")
	refresh_panels()

func accept_road() -> void:
	if not _road_rumoured():
		toast("The road is not a rumour yet. Nothing was filed.")
		return
	if Trust.has_action("parish_road_rumour"):
		toast("The rumour is already in the book.")
		return
	var nessa := _person("nessa")
	if nessa == null or not nessa.present:
		toast("Nessa is not here. Nothing was filed.")
		return
	Trust.file_road_rumour("nessa")
	toast("Nessa filed the road rumour. Nothing left the parish.")
	nessa.say("The road is only a rumour. The book keeps it.")
	road.sync(Trust.has_action("parish_road_rumour"))
	refresh_panels()

# Road pieces live in data/road_pieces.json. Counts stay named for smoke.
func _road_path_count() -> int:
	return road.count("parish_road_path")

func _road_inside_count() -> int:
	return road.count("parish_road_inside")

func _road_join_count() -> int:
	return road.count("parish_road_join")

func _road_far_stone_count() -> int:
	return road.count("parish_road_far_stone")

func _road_far_path_count() -> int:
	return road.count("parish_road_far_path")

func _road_south_stone_count() -> int:
	return road.count("parish_road_south_stone")

func _road_south_bench_count() -> int:
	return road.count("parish_road_south_bench")

func _road_past_bench_count() -> int:
	return road.count("parish_road_past_bench")

func _road_end_stone_count() -> int:
	return road.count("parish_road_end_stone")

func _road_lawn_count() -> int:
	return road.count("parish_road_lawn")

func _road_end_bell_count() -> int:
	return road.count("parish_road_end_bell")

func _road_east_count() -> int:
	return road.count("parish_road_east")

func _road_east_bell_count() -> int:
	return road.count("parish_road_east_bell")

func _road_east_past_count() -> int:
	return road.count("parish_road_east_past")

func _road_east_far_count() -> int:
	return road.count("parish_road_east_far")

func _road_east_far_stone_count() -> int:
	return road.count("parish_road_east_far_stone")

func _road_east_far_bench_count() -> int:
	return road.count("parish_road_east_far_bench")

func _road_east_return_count() -> int:
	return road.count("parish_road_east_return")

func _road_east_near_count() -> int:
	return road.count("parish_road_east_near")

func _road_east_closer_count() -> int:
	return road.count("parish_road_east_closer")

func _road_east_closer_bell_count() -> int:
	return road.count("parish_road_east_closer_bell")

func _road_east_hedge_count() -> int:
	return road.count("parish_road_east_hedge")

func _road_east_hedge_bell_count() -> int:
	return road.count("parish_road_east_hedge_bell")

func _road_east_hedge_past_count() -> int:
	return road.count("parish_road_east_hedge_past")

func _road_east_hedge_onward_count() -> int:
	return road.count("parish_road_east_hedge_onward")

func _road_east_hedge_stone_count() -> int:
	return road.count("parish_road_east_hedge_stone")

func _road_east_hedge_face_bell_count() -> int:
	return road.count("parish_road_east_hedge_face_bell")

func _road_east_hedge_west_count() -> int:
	return road.count("parish_road_east_hedge_west")

func _road_east_hedge_west_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_stone")

func _road_east_hedge_west_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_bell")

func _road_east_hedge_west_south_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_south_bell")

func _road_east_hedge_west_south_count() -> int:
	return road.count("parish_road_east_hedge_west_south")

func _road_east_hedge_west_further_count() -> int:
	return road.count("parish_road_east_hedge_west_further")

func _road_east_hedge_west_further_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_further_bell")

func _road_east_hedge_west_pace_count() -> int:
	return road.count("parish_road_east_hedge_west_pace")

func _road_east_hedge_west_pace_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_bell")

func _road_east_hedge_west_pace_south_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_south")

func _road_east_hedge_west_pace_south_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_south_bell")

func _road_east_hedge_west_pace_far_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_far")

func _road_east_hedge_west_pace_far_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_far_bell")

func _road_east_hedge_west_pace_west_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_west")

func _road_east_hedge_west_pace_on_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_on")

func _road_east_hedge_west_pace_near_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_near")

func _road_east_hedge_west_pace_north_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_north")

func _road_east_hedge_west_pace_east_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east")

func _road_east_hedge_west_pace_east_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_bell")

func _road_east_hedge_west_pace_east_on_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_on")

func _road_east_hedge_west_pace_east_on_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_on_bell")

func _road_east_hedge_west_pace_east_out_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_out")

func _road_east_hedge_west_pace_east_out_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_out_bell")

func _road_east_hedge_west_pace_east_beyond_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_beyond")

func _road_east_hedge_west_pace_east_beyond_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_beyond_bell")

func _road_east_hedge_west_pace_east_yonder_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_yonder")

func _road_east_hedge_west_pace_east_yonder_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_yonder_bell")

func _road_east_hedge_west_pace_east_outer_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_outer")

func _road_east_hedge_west_pace_east_outer_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_outer_bell")

func _road_east_hedge_west_pace_east_rim_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_rim")

func _road_east_hedge_west_pace_east_farther_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_farther")

func _road_east_hedge_west_pace_east_along_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_along_bell")

func _road_east_hedge_west_pace_east_forth_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_forth")

func _road_east_hedge_west_pace_east_forth_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_forth_bell")

func _road_east_hedge_west_pace_east_span_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_span")

func _road_east_hedge_west_pace_east_mark_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_mark_bell")

func _road_east_hedge_west_pace_east_reach_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_reach")

func _road_east_hedge_west_pace_east_reach_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_reach_bell")

func _road_east_hedge_west_pace_east_field_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_field")

func _road_east_hedge_west_pace_east_lea_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_lea")

func _road_east_hedge_west_pace_east_lea_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_lea_bell")

func _road_east_hedge_west_pace_east_verge_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_verge")

func _road_east_hedge_west_pace_east_verge_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_verge_bell")

func _road_east_hedge_west_pace_east_brink_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_brink")

func _road_east_hedge_west_pace_east_edge_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_edge")

func _road_east_hedge_west_pace_east_edge_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_edge_bell")

func _road_east_hedge_west_pace_east_margin_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_margin")

func _road_east_hedge_west_pace_east_hem_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem")

func _road_east_hedge_west_pace_east_hem_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone")

func _road_east_hedge_west_pace_east_hem_stone_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_bell")

func _road_east_hedge_west_pace_east_hem_stone_on_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_on_bell")

func _road_east_hedge_west_pace_east_hem_stone_far_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_far_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone")

func _road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_count() -> int:
	return road.count("parish_road_east_hedge_west_pace_east_hem_stone_out_on_bell_stone_east_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip_bell_stone_strip")

func _road_bell_count() -> int:
	return road.count("parish_road_bell")

func _road_bench_count() -> int:
	return road.count("parish_road_bench")

func _road_stone_count() -> int:
	return road.count("parish_road_stone")

func _file_nessa() -> void:
	Trust.file_notes("nessa", "Pollinator notes filed in the parish book. No external action.")
	toast("Nessa filed the notes. Nothing left the garden.")
	if _person("nessa").present:
		_person("nessa").say("Filed. The book stays on the shelf.")
	refresh_panels()

func accept_draft() -> void:
	var nessa := _person("nessa")
	if Trust.level("nessa") < 1:
		toast("The notes come first. Nothing was drafted.")
		return
	if Trust.has_action("parish_draft"):
		toast("The draft is already in the book.")
		return
	if not nessa.present:
		Trust.file_draft("nessa")
		toast("The draft stayed in the book. Nothing was sent.")
		refresh_panels()
		return
	nessa_drafting = true
	nessa_filing = false
	nessa_farewell = false
	nessa_watch = null
	nessa.chore = GardenLayout.FOUNDRY + Vector3(0, 0, -0.95)
	nessa.has_chore = true
	nessa.say("I will leave the draft at the foundry.")
	refresh_panels()

func _keep_draft() -> void:
	Trust.file_draft("nessa")
	toast("The draft stayed in the book. Nothing was sent.")
	if _person("nessa").present:
		_person("nessa").say("Three episodes, on the shelf. I did not send them.")
	refresh_panels()

func accept_nessa() -> void:
	var nessa := _person("nessa")
	if not nessa.present:
		_file_nessa()
		return
	# ponytail: the walk is not in the save; the filed audit is. Bram's bed is the same.
	nessa_filing = true
	nessa_farewell = false
	nessa_watch = null
	nessa.chore = GardenLayout.HUT + Vector3(0, 0, -1.05)
	nessa.has_chore = true
	nessa.say("I will file these at the hut.")
	refresh_panels()

func quick_save() -> void:
	if SaveGame.write_slot(SaveGame.active_slot, to_state()):
		bus.note("save", "Saved slot %d." % SaveGame.active_slot)
		toast("Saved slot %d." % SaveGame.active_slot)
		audio.play_kind("ui", -12)
	else:
		toast("The save did not take.")

func quick_load() -> void:
	var data := SaveGame.read_slot(SaveGame.active_slot)
	if data.is_empty():
		toast("Slot %d is empty." % SaveGame.active_slot)
		return
	apply_state(data)
	bus.note("load", "Garden restored.")
	toast("Garden restored.")

func resume() -> void:
	get_tree().paused = false
	hud.show_pause(false)
	if not photo:
		Clock.running = true

func quit_to_title() -> void:
	get_tree().paused = false
	Clock.running = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func set_master(value: float) -> void:
	Settings.master = value
	Settings.apply_audio()
	Settings.save_settings()

func set_large_text(on: bool) -> void:
	Settings.large_text = on
	Settings.save_settings()
	hud.apply_text_scale()
	if hud.journal.visible or hud.shop.visible:
		refresh_panels()
	toast("Large text is on." if on else "Large text is off.")

func set_reduce_motion(on: bool) -> void:
	Settings.reduce_motion = on
	Settings.save_settings()

func set_calm(on: bool) -> void:
	Settings.photosensitivity = on
	atmosphere.photosensitivity = on
	Settings.save_settings()

func debug_grow() -> void:
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "":
			plot.growth = 1.0
			plot.moisture = 0.9
	_sync_plants()
	toast("Everything ripe.")

func debug_spawn(id: String) -> void:
	var jelly := ecology.force_spawn(id)
	jelly.global_position = GardenLayout.cell_center(2, 2)
	toast("Spawned %s." % id)

func debug_coins(amount: int) -> void:
	Economy.earn(amount)

func debug_hour(step: float) -> void:
	Clock.set_hour(Clock.hour() + step)

func debug_weather(next: String) -> void:
	Clock.weather = next
	Clock.weather_changed.emit(next)

func debug_resident() -> void:
	var jelly := ecology.first("bellhelp")
	if jelly == null:
		jelly = ecology.force_spawn("bellhelp")
	jelly.life = "resident"
	jelly.site_time = 40.0
	ecology._raise("bellhelp", "resident")
	toast("Bellhelp is a resident.")

func toast(text: String) -> void:
	events.push_front(text)
	if events.size() > 24:
		events.resize(24)
	bus.note("toast", text)
	if hud:
		hud.toast(text)

func _toggle_time() -> void:
	if photo or get_tree().paused:
		return
	Clock.running = not Clock.running
	bus.note("time", "rest" if not Clock.running else "move")
	toast("Time rests." if not Clock.running else "Time moves.")

func _ring_bells(world: Dictionary) -> void:
	# ponytail: one quiet chime a day, and that chime carries one meadowbell seed.
	var hour := Clock.hour()
	if hour >= 21.0 or hour < 5.0 or Clock.weather == "rain":
		return
	var mature: Dictionary = world.get("mature", {})
	if int(mature.get("meadowbell", 0)) < 3:
		return
	var ringer := false
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "bellhelp" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("visitor"):
			continue
		ringer = true
		break
	if not ringer or bell_day == Clock.day:
		return
	bell_day = Clock.day
	audio.play_kind("ring", -22.0)
	var sown := soil.seed_from("meadowbell")
	if sown != "":
		bee_flower = soil.sown_at
	else:
		bee_flower = _average_plant("meadowbell")
	bee_day = Clock.day
	if sown != "":
		toast("Bellhelp rings, very quietly. %s took the next bed." % str(ContentDB.plant(sown).get("name", "A plant")))
		return
	toast("Bellhelp rings, very quietly.")

func _note_bees() -> void:
	# ponytail: one book line a day; the other ripe bell gets the second line.
	if bee_note_day == Clock.day or bee_day != Clock.day or Clock.weather == "rain":
		return
	bee_note_day = Clock.day
	Trust.file_bee_note("nessa")
	toast("Nessa wrote the bees on that bed into the parish book.")
	var other := _second_bell()
	if other != Vector3.ZERO:
		var other_name := str(ContentDB.plant("meadowbell").get("name", "Meadowbell"))
		Trust.file_bee_note("nessa", "Two bees on the other %s. Nothing was spent." % other_name)
		toast("Nessa wrote the two bees on the other %s into the parish book." % other_name)
	_walk_to_bees()

func _walk_to_bees() -> void:
	# ponytail: one walk to that bed; a queue if she is already filing or saying goodbye.
	var nessa := _person("nessa")
	if nessa == null or not nessa.present or nessa.has_chore or nessa_filing or nessa_drafting or nessa_farewell:
		return
	nessa_bees = true
	nessa_watch = null
	nessa.chore = bee_flower
	nessa.has_chore = true
	nessa.say("I will walk to the bees.")

func _finish_bee_walk() -> void:
	if not nessa_bees:
		return
	var nessa := _person("nessa")
	if nessa == null or nessa.global_position.distance_to(nessa.chore) >= 0.55:
		return
	nessa_bees = false
	nessa.has_chore = false
	nessa.say("The bees are on that bed. The line is in the book.")

func _dawn_birds() -> void:
	# ponytail: two lines before seven; a third if the morning keeps more birds.
	var h := Clock.hour()
	if h < 5.0 or h >= 7.0 or Clock.weather == "rain" or bird_day == Clock.day:
		return
	bird_day = Clock.day
	if audio:
		audio.play_kind("chirp", -20.0)
	toast("The birds leave the hedge.")
	toast("They sing once more before seven.")

func world_snapshot() -> Dictionary:
	var mature := {}
	var chem := {}
	var moisture := 0.0
	var fertility_all := 0.0
	var fertility_worked := 0.0
	var worked := 0
	var count := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		count += 1
		moisture += plot.moisture
		fertility_all += plot.fertility
		if plot.tilled:
			fertility_worked += plot.fertility
			worked += 1
		chem[plot.chem] = int(chem.get(plot.chem, 0)) + 1
		if plot.plant_id != "" and plot.growth >= 1.0:
			mature[plot.plant_id] = int(mature.get(plot.plant_id, 0)) + 1
	var mature_total := 0
	for value in mature.values():
		mature_total += int(value)
	var quality := clampf(float(mature_total) / 10.0, 0.0, 1.0) * 0.75
	quality += clampf(moisture / maxf(float(count), 1.0), 0.0, 1.0) * 0.25
	# ponytail: fertility is the tilled beds; untouched grass stays out until a plot keeps its own score.
	var fertility := fertility_all / maxf(float(count), 1.0)
	if worked > 0:
		fertility = fertility_worked / float(worked)
	return {
		"mature": mature,
		"pond_cells": GardenLayout.BASE_POND_CELLS + scooped.size(),
		"moisture": moisture / maxf(float(count), 1.0),
		"fertility": fertility,
		"chem": chem,
		"weather": Clock.weather,
		"hour": Clock.hour(),
		"species_state": ecology.states.duplicate(),
		"resident_count": ecology.resident_counts(),
		"structures": structures.duplicate(),
		"garden_quality": quality,
	}

func to_state() -> Dictionary:
	var cast: Array = []
	for id in ContentDB.people_order:
		cast.append(_person(id).to_state())
	var homes: Array = []
	for point in home_points:
		homes.append([point.x, point.y, point.z])
	var ponds: Array = []
	for point in scooped:
		ponds.append([point.x, point.y, point.z])
	return {
		"name": SaveGame.garden_name,
		"clock": Clock.to_state(),
		"economy": Economy.to_state(),
		"trust": Trust.to_state(),
		"soil": soil.to_state(),
		"seed_rain": soil.seed_rain,
		"ecology": ecology.to_state(),
		"structures": structures.duplicate(),
		"homes": homes,
		"scooped": ponds,
		"people": cast,
		"events": events.slice(0, 20),
		"gossip_done": gossip_done,
		"bram_bed": [bram_bed.x, bram_bed.y],
		"bram_feeding": bram_feeding,
		"nessa_filing": nessa_filing,
		"nessa_drafting": nessa_drafting,
		"nessa_bees": nessa_bees,
		"nessa_farewell": nessa_farewell,
		"farewell_names": farewell_names.duplicate(),
		"nessa_watch": _watch_record(),
		"loam_hours": loam_hours,
		"bell_day": bell_day,
		"bird_day": bird_day,
		"bee_day": bee_day,
		"bee_note_day": bee_note_day,
		"lane_afternoon_days": lane_afternoon_days.duplicate(),
		"bee_flower": [bee_flower.x, bee_flower.y, bee_flower.z],
		"crate_yields": crate_yields.duplicate(true),
	}

func apply_state(data: Dictionary) -> void:
	Clock.apply_state(data.get("clock", {}))
	Economy.apply_state(data.get("economy", {}))
	Trust.apply_state(data.get("trust", {}))
	soil.apply_state(data.get("soil", []))
	soil.seed_rain = float(data.get("seed_rain", 0.0))
	ecology.apply_state(data.get("ecology", {}))
	var saved_structures = data.get("structures", {})
	if typeof(saved_structures) == TYPE_DICTIONARY:
		structures = saved_structures.duplicate()
	home_points.clear()
	for child in home_root.get_children():
		child.free()
	for entry in data.get("homes", []):
		var point := Vector3(float(entry[0]), float(entry[1]), float(entry[2]))
		home_points.append(point)
		_place_home(point, false)
	scooped.clear()
	for child in scoop_root.get_children():
		child.free()
	for entry in data.get("scooped", []):
		var point := Vector3(float(entry[0]), float(entry[1]), float(entry[2]))
		scooped.append(point)
		_add_scoop_mesh(point)
	_grow_pond()
	for entry in data.get("people", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var person := _person(str(entry.get("id", "")))
		if person:
			person.apply_state(entry)
	events = data.get("events", []).duplicate()
	gossip_done = bool(data.get("gossip_done", true))
	bram_bed = Vector2i(-1, -1)
	var bed = data.get("bram_bed", [])
	if typeof(bed) == TYPE_ARRAY and bed.size() == 2:
		bram_bed = Vector2i(int(bed[0]), int(bed[1]))
	bram_feeding = bool(data.get("bram_feeding", false))
	nessa_filing = bool(data.get("nessa_filing", false))
	nessa_drafting = bool(data.get("nessa_drafting", false))
	nessa_bees = bool(data.get("nessa_bees", false))
	nessa_farewell = bool(data.get("nessa_farewell", false))
	farewell_names.clear()
	for entry in data.get("farewell_names", []):
		farewell_names.append(str(entry))
	_bind_watch(data.get("nessa_watch", {}))
	loam_hours = float(data.get("loam_hours", 0.0))
	bell_day = int(data.get("bell_day", -1))
	bird_day = int(data.get("bird_day", -1))
	bee_day = int(data.get("bee_day", -1))
	bee_note_day = int(data.get("bee_note_day", -1))
	lane_afternoon_days.clear()
	for saved_day in data.get("lane_afternoon_days", []):
		lane_afternoon_days.append(int(saved_day))
	var flower = data.get("bee_flower", [])
	if typeof(flower) == TYPE_ARRAY and flower.size() == 3:
		bee_flower = Vector3(float(flower[0]), float(flower[1]), float(flower[2]))
	crate_yields = {}
	var saved_yields = data.get("crate_yields", {})
	if typeof(saved_yields) == TYPE_DICTIONARY:
		for key in saved_yields.keys():
			var row = saved_yields[key]
			var copied: Array = []
			if typeof(row) == TYPE_ARRAY:
				for value in row:
					copied.append(float(value))
			crate_yields[str(key)] = copied
	_clear_inspect()
	_clear_plants()
	_sync_plants()
	_refresh_soil_colors()
	road.sync(Trust.has_action("parish_road_rumour"))

func _watch_record() -> Dictionary:
	# ponytail: one arrival, one farewell, one hut, one foundry; a queue if Nessa keeps more than one errand.
	if nessa_watch == null or not is_instance_valid(nessa_watch):
		return {}
	return {
		"species": nessa_watch.species_id,
		"position": [nessa_watch.global_position.x, nessa_watch.global_position.y, nessa_watch.global_position.z],
	}

func _bind_watch(saved) -> void:
	nessa_watch = null
	if typeof(saved) != TYPE_DICTIONARY:
		return
	var pos = saved.get("position", [])
	if typeof(pos) != TYPE_ARRAY or pos.size() != 3:
		return
	var want := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var species := str(saved.get("species", ""))
	var best: Jelly = null
	var nearest := 0.75
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != species:
			continue
		var dist := jelly.global_position.distance_to(want)
		if dist < nearest:
			nearest = dist
			best = jelly
	nessa_watch = best

func _run_smoke() -> void:
	var opening_peach := soil.get_cell(3, 2)
	var opening_cane := soil.get_cell(4, 2)
	var opening_far := soil.get_cell(5, 2)
	var opening_pear := soil.get_cell(4, 1)
	var opening_lamp := soil.get_cell(6, 4)
	if opening_peach.plant_id != "peach" or opening_cane.plant_id != "bramble" or opening_cane.growth < 0.7 or opening_cane.growth >= 1.0 or opening_far.plant_id != "bramble" or opening_far.growth < 0.7 or opening_far.growth >= 1.0 or opening_pear.plant_id != "mosspear" or opening_pear.growth < 0.7 or opening_pear.growth >= 1.0 or opening_pear.fertility < 0.58 or _plot_line(opening_pear).find("Pear showing.") == -1 or _pear_line() != "A mosspear is showing." or opening_lamp.plant_id != "nightlantern" or opening_lamp.growth < 0.7 or opening_lamp.growth >= 1.0 or opening_lamp.chem != "nightloam" or _plot_line(opening_lamp).find("Light showing.") == -1 or _lantern_line() != "A nightlantern is showing." or _seed_line() != "The nightlantern seed is open." or _lane_passers() != 0 or ecology.first("berrypatch") != null or _cane_line() != "Two young brambles stand short of ripe." or _leaf_line() != "The berries have leaves." or _leaf_rumour_count() != 1 or _plot_line(opening_cane).find("Berries showing.") == -1 or _plot_line(opening_far).find("Berries showing.") == -1:
		push_error("smoke: the opening bramble ripened the lane")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the berry leaves did not save")
		get_tree().quit(1)
		return
	opening_cane.growth = 1.0
	opening_far.plant_id = ""
	if _leaf_line() != "" or _leaf_rumour_count() != 0:
		push_error("smoke: a cleared cane kept the berry rumour")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	opening_peach = soil.get_cell(3, 2)
	opening_cane = soil.get_cell(4, 2)
	opening_far = soil.get_cell(5, 2)
	opening_pear = soil.get_cell(4, 1)
	opening_lamp = soil.get_cell(6, 4)
	if opening_cane.plant_id != "bramble" or opening_far.plant_id != "bramble" or opening_cane.growth >= 1.0 or opening_far.growth >= 1.0 or _leaf_line() != "The berries have leaves." or _leaf_rumour_count() != 1:
		push_error("smoke: a reload dropped the berry leaves")
		get_tree().quit(1)
		return
	var day_clock := Clock.day
	var day_hour := Clock.hour()
	var grow_saved: Array = []
	for cell in soil.all():
		var grow_bed: SoilCell = cell
		grow_saved.append(grow_bed.to_dict())
	Clock.day = 1
	soil.tick(60.0, "golden")
	if opening_pear.growth < 1.0 or opening_lamp.growth < 1.0 or opening_peach.growth != 0.72 or _pear_line() != "" or _lantern_line() != "":
		push_error("smoke: day 1 held the mosspear or the nightlantern")
		get_tree().quit(1)
		return
	var grown_view := PlantView.new()
	add_child(grown_view)
	grown_view.show_plant("nightlantern", opening_lamp.growth, opening_lamp.moisture, opening_lamp.fertility)
	var grown_leaves := 0
	var grown_radius := 0.0
	for grown_node in grown_view.get_children():
		var grown_mesh := grown_node as MeshInstance3D
		if grown_mesh == null:
			continue
		var grown_albedo: Color = (grown_mesh.material_override as StandardMaterial3D).albedo_color
		if grown_mesh.mesh is BoxMesh and grown_albedo.is_equal_approx(Color("#243628")):
			grown_leaves += 1
		if grown_mesh.mesh is SphereMesh and grown_albedo.is_equal_approx(Color("#ffd27a")):
			grown_radius = (grown_mesh.mesh as SphereMesh).radius
	if grown_leaves != 2 or absf(grown_radius - 0.09) > 0.001:
		push_error("smoke: a day-1 hour changed the nightlantern leaves")
		get_tree().quit(1)
		return
	grown_view.queue_free()
	var hour_reed := soil.get_cell(7, 5)
	var hour_view := PlantView.new()
	add_child(hour_view)
	hour_view.show_plant("reed", hour_reed.growth, hour_reed.moisture, hour_reed.fertility)
	var hour_brown := 0
	var hour_straw := 0
	for hour_node in hour_view.get_children():
		var hour_mesh := hour_node as MeshInstance3D
		if hour_mesh == null or not (hour_mesh.mesh is SphereMesh):
			continue
		var hour_albedo: Color = (hour_mesh.material_override as StandardMaterial3D).albedo_color
		if hour_albedo.is_equal_approx(Color("#6a4a28")):
			hour_brown += 1
		if hour_albedo.is_equal_approx(Color("#9a7040")):
			hour_straw += 1
	if hour_reed.plant_id != "reed" or absf(hour_reed.growth - 0.70) > 0.001 or hour_brown != 3 or hour_straw != 0:
		push_error("smoke: a day-1 hour changed the reed heads")
		get_tree().quit(1)
		return
	hour_view.queue_free()
	var fruit_view := PlantView.new()
	add_child(fruit_view)
	fruit_view.show_plant("peach", opening_peach.growth, opening_peach.moisture, opening_peach.fertility)
	var fruit_count := 0
	var fruit_spheres := 0
	var stem_count := 0
	for fruit_node in fruit_view.get_children():
		var fruit_mesh := fruit_node as MeshInstance3D
		if fruit_mesh == null:
			continue
		var fruit_albedo: Color = (fruit_mesh.material_override as StandardMaterial3D).albedo_color
		if fruit_mesh.mesh is SphereMesh:
			fruit_spheres += 1
			if fruit_albedo.is_equal_approx(Color("#8a4e22")):
				fruit_count += 1
		if fruit_mesh.mesh is CylinderMesh and fruit_albedo.is_equal_approx(Color("#6b4a32")):
			stem_count += 1
	if absf(opening_peach.growth - 0.72) > 0.001 or fruit_count != 1 or fruit_spheres != 1 or stem_count != 1:
		push_error("smoke: a day-1 hour changed the peach fruit")
		get_tree().quit(1)
		return
	fruit_view.queue_free()
	var hour_bells_ripe := true
	for hour_at in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]:
		var hour_bell: SoilCell = soil.get_cell(hour_at.x, hour_at.y)
		if hour_bell.plant_id != "meadowbell" or hour_bell.growth < 1.0:
			hour_bells_ripe = false
	if not hour_bells_ripe or _bell_line() != "":
		push_error("smoke: a day-1 hour left the meadowbells showing")
		get_tree().quit(1)
		return
	var grow_i := 0
	for cell in soil.all():
		var grown_bed: SoilCell = cell
		grown_bed.apply_dict(grow_saved[grow_i])
		grow_i += 1
	Clock.day = day_clock
	Clock.set_hour(day_hour)
	opening_pear.growth = 1.0
	if _pear_line() != "" or _lane_passers() < 1:
		push_error("smoke: a ripe mosspear kept the young pear page")
		get_tree().quit(1)
		return
	opening_pear.growth = 0.72
	if _pear_line() != "A mosspear is showing." or _lane_passers() != 0:
		push_error("smoke: the young pear page stayed down")
		get_tree().quit(1)
		return
	opening_lamp.growth = 1.0
	if _lantern_line() != "" or _lane_passers() < 1:
		push_error("smoke: a ripe nightlantern kept the young lantern page")
		get_tree().quit(1)
		return
	opening_lamp.growth = 0.72
	if _lantern_line() != "A nightlantern is showing." or _lane_passers() != 0:
		push_error("smoke: the young lantern page stayed down")
		get_tree().quit(1)
		return
	opening_cane.growth = 1.0
	if _cane_line() != "" or _leaf_line() != "" or _leaf_rumour_count() != 0 or _ripe_cane_line() != "" or _lane_passers() < 1 or _plot_line(opening_cane).find("Berries showing.") != -1:
		push_error("smoke: a ripe opening cane kept the young line")
		get_tree().quit(1)
		return
	opening_far.growth = 1.0
	if _ripe_cane_line() != "The canes are ripe enough." or _ripe_cane_line().find("Berrypatch") != -1 or _cane_rumour_count() != 1:
		push_error("smoke: two ripe canes stayed quiet")
		get_tree().quit(1)
		return
	ecology.states["berrypatch"] = "sighted"
	var berry_blurb := ""
	for row in _journal_rows(world_snapshot()):
		var berry_row: Dictionary = row
		if str(berry_row.get("name", "")) == "Berrypatch":
			berry_blurb = str(berry_row.get("blurb", ""))
	if _ripe_cane_line() != "" or _cane_rumour_count() != 0 or berry_blurb != str(ContentDB.species_def("berrypatch").get("blurb", "")):
		push_error("smoke: a sighting kept the ripe cane line")
		get_tree().quit(1)
		return
	ecology.states["berrypatch"] = "rumoured"
	if _cane_rumour_count() != 1:
		push_error("smoke: the cane rumour stayed named")
		get_tree().quit(1)
		return
	if _plot_line(opening_cane).find("Rich enough.") != -1:
		push_error("smoke: poor soil called the canes rich")
		get_tree().quit(1)
		return
	_force_plant(6, 2, "bramble", 1.0)
	_force_plant(6, 3, "bramble", 0.78)
	if _plot_line(opening_cane).find("Rich enough.") != -1 or _plot_line(soil.get_cell(6, 3)).find("Berries showing.") == -1:
		push_error("smoke: three canes in poor soil looked rich")
		get_tree().quit(1)
		return
	var saved_feed: Array = []
	for cell in soil.all():
		var fed: SoilCell = cell
		if fed.tilled:
			saved_feed.append([fed, fed.fertility])
			fed.fertility = 0.7
	var young_cane := soil.get_cell(6, 3)
	if _plot_line(opening_cane).find("Rich enough.") == -1 or _plot_line(opening_far).find("Rich enough.") == -1 or _plot_line(soil.get_cell(6, 2)).find("Rich enough.") == -1 or _plot_line(young_cane).find("Rich enough.") != -1 or _plot_line(young_cane).find("Berries showing.") == -1 or _plot_line(opening_cane).find("Grapling") != -1:
		push_error("smoke: rich canes stayed quiet")
		get_tree().quit(1)
		return
	opening_far.growth = 0.74
	if _plot_line(opening_cane).find("Rich enough.") != -1:
		push_error("smoke: two ripe canes looked rich")
		get_tree().quit(1)
		return
	opening_far.growth = 1.0
	ecology.states["grapling"] = "sighted"
	if _plot_line(opening_cane).find("Rich enough.") != -1:
		push_error("smoke: a sighting kept the rich cane line")
		get_tree().quit(1)
		return
	ecology.states["grapling"] = "rumoured"
	for row in saved_feed:
		var restored: SoilCell = row[0]
		restored.fertility = row[1]
	for extra in [Vector2i(6, 2), Vector2i(6, 3)]:
		var spare := soil.get_cell(extra.x, extra.y)
		spare.plant_id = ""
		spare.growth = 0.0
		spare.tilled = false
	if _plot_line(opening_cane).find("Rich enough.") != -1:
		push_error("smoke: the rich line stayed after the soil was restored")
		get_tree().quit(1)
		return
	opening_far.growth = 0.74
	opening_cane.growth = 0.32
	if _plot_line(opening_cane).find("Berries showing.") != -1:
		push_error("smoke: a short cane claimed the berries were showing")
		get_tree().quit(1)
		return
	opening_cane.growth = 0.78
	var opening_reed := soil.get_cell(7, 5)
	if opening_peach.growth < 0.7 or opening_peach.growth >= 1.0 or opening_reed.plant_id != "reed" or opening_reed.growth < 0.65 or opening_reed.growth >= 1.0 or _plot_line(opening_peach).find("Fruit showing.") == -1 or _plot_line(opening_reed).find("Heads showing.") == -1 or _lane_passers() != 0 or _peach_line() != "A peach is showing." or _reed_line() != "A reed is showing.":
		push_error("smoke: the opening peach or reed ripened the lane")
		get_tree().quit(1)
		return
	var reed_view := PlantView.new()
	add_child(reed_view)
	reed_view.show_plant("reed", opening_reed.growth, opening_reed.moisture, opening_reed.fertility)
	var reed_brown := 0
	var reed_straw := 0
	for reed_node in reed_view.get_children():
		var reed_mesh := reed_node as MeshInstance3D
		if reed_mesh == null or not (reed_mesh.mesh is SphereMesh):
			continue
		var reed_albedo: Color = (reed_mesh.material_override as StandardMaterial3D).albedo_color
		if reed_albedo.is_equal_approx(Color("#6a4a28")):
			reed_brown += 1
		if reed_albedo.is_equal_approx(Color("#9a7040")):
			reed_straw += 1
	if absf(opening_reed.growth - 0.70) > 0.001 or reed_brown != 3 or reed_straw != 0:
		push_error("smoke: the opening reed head was straw")
		get_tree().quit(1)
		return
	reed_view.queue_free()
	opening_peach.growth = 1.0
	opening_reed.growth = 0.22
	if _plot_line(opening_peach).find("Fruit showing.") != -1 or _plot_line(opening_reed).find("Heads showing.") != -1 or _lane_passers() < 1 or _peach_line() != "" or _reed_line() != "A reed is showing.":
		push_error("smoke: a ripe peach kept the young fruit line")
		get_tree().quit(1)
		return
	opening_reed.growth = 1.0
	if _reed_line() != "" or _wade_line() != "":
		push_error("smoke: a ripe reed kept the young reed line")
		get_tree().quit(1)
		return
	var scoop_n := scooped.size()
	while GardenLayout.BASE_POND_CELLS + scooped.size() < 26:
		scooped.append(Vector3(0, 0, float(scooped.size())))
	_force_plant(6, 5, "reed", 1.0)
	_force_plant(8, 5, "reed", 1.0)
	if _wade_line() != "The reeds are ready to wade." or _wade_line().find("Bulrush") != -1 or _wade_rumour_count() != 1:
		push_error("smoke: three ripe reeds stayed quiet")
		get_tree().quit(1)
		return
	ecology.states["bulrush"] = "sighted"
	var rush_blurb := ""
	for row in _journal_rows(world_snapshot()):
		var rush_row: Dictionary = row
		if str(rush_row.get("name", "")) == "Bulrush":
			rush_blurb = str(rush_row.get("blurb", ""))
	if _wade_line() != "" or _wade_rumour_count() != 0 or rush_blurb != str(ContentDB.species_def("bulrush").get("blurb", "")):
		push_error("smoke: a sighting kept the wade line")
		get_tree().quit(1)
		return
	ecology.states["bulrush"] = "rumoured"
	soil.get_cell(8, 5).growth = 0.4
	if _wade_line() != "":
		push_error("smoke: two ripe reeds called the stand ready")
		get_tree().quit(1)
		return
	soil.get_cell(8, 5).growth = 1.0
	while scooped.size() > scoop_n:
		scooped.pop_back()
	if _wade_line() != "":
		push_error("smoke: a narrow pond called the reeds ready")
		get_tree().quit(1)
		return
	while scooped.size() < scoop_n + 4:
		scooped.append(Vector3(0, 0, float(scooped.size())))
	for extra in [Vector2i(6, 5), Vector2i(8, 5)]:
		var spare := soil.get_cell(extra.x, extra.y)
		spare.plant_id = ""
		spare.growth = 0.0
		spare.tilled = false
	while scooped.size() > scoop_n:
		scooped.pop_back()
	opening_peach.growth = 0.72
	opening_reed.growth = 0.70
	if _dusk_line() != "":
		push_error("smoke: a dry afternoon called the dusk wet")
		get_tree().quit(1)
		return
	var dusk_hour := Clock.hour()
	var dusk_weather := Clock.weather
	opening_peach.growth = 1.0
	_force_plant(1, 3, "nightlantern", 1.0)
	Clock.weather = "mist"
	Clock.set_hour(18.0)
	if _dusk_line() != "The dusk is wet enough." or _dusk_line().find("Pegapear") != -1 or _dusk_rumour_count() != 1:
		push_error("smoke: a wet dusk stayed quiet")
		get_tree().quit(1)
		return
	Clock.weather = "golden"
	if _dusk_line() != "":
		push_error("smoke: a dry dusk stayed wet")
		get_tree().quit(1)
		return
	Clock.weather = "rain"
	Clock.set_hour(14.0)
	if _dusk_line() != "":
		push_error("smoke: an afternoon rain called the dusk wet")
		get_tree().quit(1)
		return
	Clock.set_hour(18.0)
	soil.get_cell(1, 3).growth = 0.4
	if _dusk_line() != "":
		push_error("smoke: a young lantern called the dusk wet")
		get_tree().quit(1)
		return
	soil.get_cell(1, 3).growth = 1.0
	ecology.states["pegapear"] = "sighted"
	var pear_blurb := ""
	for row in _journal_rows(world_snapshot()):
		var pear_row: Dictionary = row
		if str(pear_row.get("name", "")) == "Pegapear":
			pear_blurb = str(pear_row.get("blurb", ""))
	if _dusk_line() != "" or _dusk_rumour_count() != 0 or pear_blurb != str(ContentDB.species_def("pegapear").get("blurb", "")):
		push_error("smoke: a sighting kept the dusk line")
		get_tree().quit(1)
		return
	ecology.states["pegapear"] = "rumoured"
	var dusk_bed := soil.get_cell(1, 3)
	dusk_bed.plant_id = ""
	dusk_bed.growth = 0.0
	dusk_bed.tilled = false
	opening_peach.growth = 0.72
	Clock.weather = dusk_weather
	Clock.set_hour(dusk_hour)
	if _dusk_line() != "":
		push_error("smoke: the dusk line stayed after the weather turned")
		get_tree().quit(1)
		return
	_force_plant(2, 3, "mosspear", 1.0)
	_force_plant(2, 4, "mosspear", 1.0)
	_force_plant(2, 5, "mosspear", 0.5)
	if _plot_line(soil.get_cell(2, 3)).find("Pear-sweet.") != -1:
		push_error("smoke: bare soil called the pears sweet")
		get_tree().quit(1)
		return
	var moss_chem: Array = []
	var night_n := 0
	for cell in soil.all():
		if night_n >= 4:
			break
		var chem_bed: SoilCell = cell
		moss_chem.append([chem_bed, chem_bed.chem])
		chem_bed.chem = "nightloam"
		night_n += 1
	if _plot_line(soil.get_cell(2, 3)).find("Pear-sweet.") != -1:
		push_error("smoke: thin feed called the pears sweet")
		get_tree().quit(1)
		return
	var moss_feed: Array = []
	for cell in soil.all():
		var fed_bed: SoilCell = cell
		if fed_bed.tilled:
			moss_feed.append([fed_bed, fed_bed.fertility])
			fed_bed.fertility = 0.7
	var sweet_pear := soil.get_cell(2, 3)
	var second_pear := soil.get_cell(2, 4)
	var short_pear := soil.get_cell(2, 5)
	if _plot_line(sweet_pear).find("Pear-sweet.") == -1 or _plot_line(second_pear).find("Pear-sweet.") == -1 or _plot_line(short_pear).find("Pear-sweet.") != -1 or _plot_line(sweet_pear).find("Gushorn") != -1:
		push_error("smoke: fed pears stayed quiet")
		get_tree().quit(1)
		return
	second_pear.growth = 0.5
	if _plot_line(sweet_pear).find("Pear-sweet.") != -1 or _plot_line(second_pear).find("Pear-sweet.") != -1:
		push_error("smoke: one mosspear called the bed sweet")
		get_tree().quit(1)
		return
	second_pear.growth = 1.0
	moss_chem[0][0].chem = "base"
	var held_lamp_chem := opening_lamp.chem
	opening_lamp.chem = "base"
	if _plot_line(sweet_pear).find("Pear-sweet.") != -1:
		push_error("smoke: thin night-loam called the pears sweet")
		get_tree().quit(1)
		return
	opening_lamp.chem = held_lamp_chem
	moss_chem[0][0].chem = "nightloam"
	ecology.states["gushorn"] = "sighted"
	if _plot_line(sweet_pear).find("Pear-sweet.") != -1:
		push_error("smoke: a sighting kept the pear-sweet line")
		get_tree().quit(1)
		return
	ecology.states["gushorn"] = "rumoured"
	for chem_row in moss_chem:
		var chem_plot: SoilCell = chem_row[0]
		chem_plot.chem = chem_row[1]
	for feed_row in moss_feed:
		var feed_plot: SoilCell = feed_row[0]
		feed_plot.fertility = feed_row[1]
	for extra in [Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5)]:
		var spare_pear := soil.get_cell(extra.x, extra.y)
		spare_pear.plant_id = ""
		spare_pear.growth = 0.0
		spare_pear.tilled = false
		spare_pear.chem = "base"
	if _plot_line(soil.get_cell(2, 3)).find("Pear-sweet.") != -1:
		push_error("smoke: the pear-sweet line stayed after the beds were cleared")
		get_tree().quit(1)
		return
	var follow_bell := soil.get_cell(1, 1)
	var follow_young := soil.get_cell(2, 1)
	var follow_growth := follow_bell.growth
	follow_bell.growth = 1.0
	if _plot_line(follow_bell).find("A follower is close.") != -1:
		push_error("smoke: a rumour called a follower close")
		get_tree().quit(1)
		return
	ecology.states["bellhelp"] = "sighted"
	if _plot_line(follow_bell).find("A follower is close.") != -1:
		push_error("smoke: a sighting called a follower close")
		get_tree().quit(1)
		return
	ecology.states["bellhelp"] = "visitor"
	if _plot_line(follow_bell).find("A follower is close.") == -1 or _plot_line(follow_young).find("A follower is close.") != -1 or _plot_line(follow_young).find("Bells showing.") == -1 or _plot_line(follow_bell).find("Dusknip") != -1 or _plot_line(follow_bell).find("Bellhelp") != -1:
		push_error("smoke: a visited bell stayed quiet")
		get_tree().quit(1)
		return
	ecology.states["dusknip"] = "sighted"
	if _plot_line(follow_bell).find("A follower is close.") != -1:
		push_error("smoke: a sighting kept the follower line")
		get_tree().quit(1)
		return
	ecology.states["dusknip"] = "rumoured"
	ecology.states["bellhelp"] = "rumoured"
	follow_bell.growth = follow_growth
	if _plot_line(follow_bell).find("A follower is close.") != -1:
		push_error("smoke: the follower line stayed on a young bell")
		get_tree().quit(1)
		return
	var bank_reed := soil.get_cell(7, 5)
	var bank_growth := bank_reed.growth
	bank_reed.growth = 1.0
	if _plot_line(bank_reed).find("The bank is wet enough.") != -1:
		push_error("smoke: a dry bed called the bank wet")
		get_tree().quit(1)
		return
	ecology.states["bulrush"] = "visitor"
	if _plot_line(bank_reed).find("The bank is wet enough.") != -1:
		push_error("smoke: a dry visit called the bank wet")
		get_tree().quit(1)
		return
	var bank_water: Array = []
	for cell in soil.all():
		var wet_bed: SoilCell = cell
		bank_water.append([wet_bed, wet_bed.moisture])
		wet_bed.moisture = 0.62
	bank_reed.growth = 0.70
	if _plot_line(bank_reed).find("The bank is wet enough.") != -1 or _plot_line(bank_reed).find("Heads showing.") == -1:
		push_error("smoke: a young reed claimed the bank")
		get_tree().quit(1)
		return
	bank_reed.growth = 1.0
	if _plot_line(bank_reed).find("The bank is wet enough.") == -1 or _plot_line(bank_reed).find("Reedic") != -1 or _plot_line(bank_reed).find("Bulrush") != -1:
		push_error("smoke: a wet visit stayed quiet")
		get_tree().quit(1)
		return
	ecology.states["reedic"] = "sighted"
	if _plot_line(bank_reed).find("The bank is wet enough.") != -1:
		push_error("smoke: a sighting kept the bank line")
		get_tree().quit(1)
		return
	ecology.states["reedic"] = "rumoured"
	ecology.states["bulrush"] = "rumoured"
	for water_row in bank_water:
		var water_plot: SoilCell = water_row[0]
		water_plot.moisture = water_row[1]
	bank_reed.growth = bank_growth
	if _plot_line(bank_reed).find("The bank is wet enough.") != -1:
		push_error("smoke: the bank line stayed after the beds dried")
		get_tree().quit(1)
		return
	var parish_bell := soil.get_cell(1, 1)
	var parish_young := soil.get_cell(2, 1)
	var parish_third := soil.get_cell(1, 2)
	var parish_growths: Array[float] = [parish_bell.growth, parish_young.growth, parish_third.growth]
	parish_bell.growth = 1.0
	ecology.states["bellhelp"] = "resident"
	if _plot_line(parish_bell).find("The parish is looked after.") != -1:
		push_error("smoke: a thin garden looked after")
		get_tree().quit(1)
		return
	var parish_water: Array = []
	for cell in soil.all():
		var soaked: SoilCell = cell
		parish_water.append([soaked, soaked.moisture])
		soaked.moisture = 1.0
	parish_young.growth = 1.0
	parish_third.growth = 1.0
	_force_plant(0, 0, "meadowbell", 1.0)
	parish_young.growth = 0.72
	if _plot_line(parish_bell).find("The parish is looked after.") == -1 or _plot_line(parish_third).find("The parish is looked after.") == -1 or _plot_line(parish_young).find("The parish is looked after.") != -1 or _plot_line(parish_young).find("Bells showing.") == -1 or _plot_line(parish_bell).find("Cirlark") != -1 or _plot_line(parish_bell).find("Bellhelp") != -1:
		push_error("smoke: a looked-after parish stayed quiet")
		get_tree().quit(1)
		return
	ecology.states["cirlark"] = "sighted"
	if _plot_line(parish_bell).find("The parish is looked after.") != -1:
		push_error("smoke: a sighting kept the parish line")
		get_tree().quit(1)
		return
	ecology.states["cirlark"] = "rumoured"
	ecology.states["bellhelp"] = "rumoured"
	for soak_row in parish_water:
		var soak_plot: SoilCell = soak_row[0]
		soak_plot.moisture = soak_row[1]
	parish_bell.growth = parish_growths[0]
	parish_young.growth = parish_growths[1]
	parish_third.growth = parish_growths[2]
	var parish_extra := soil.get_cell(0, 0)
	parish_extra.plant_id = ""
	parish_extra.growth = 0.0
	parish_extra.tilled = false
	if _plot_line(parish_bell).find("The parish is looked after.") != -1:
		push_error("smoke: the parish line stayed on a thin garden")
		get_tree().quit(1)
		return
	var opening_bells: Array[SoilCell] = [soil.get_cell(1, 1), soil.get_cell(2, 1), soil.get_cell(1, 2)]
	var bells_ready := true
	for bell in opening_bells:
		if bell.plant_id != "meadowbell" or bell.growth < 0.7 or bell.growth >= 1.0 or _plot_line(bell).find("Bells showing.") == -1:
			bells_ready = false
	if not bells_ready or ecology.first("bellhelp") != null or _lane_passers() != 0 or _bell_line() != "Three meadowbells are showing." or _bell_line().find("Bellhelp") != -1:
		push_error("smoke: the opening bells brought Bellhelp")
		get_tree().quit(1)
		return
	opening_bells[0].growth = 0.4
	if _plot_line(opening_bells[0]).find("Bells showing.") != -1 or _bell_line() != "Three meadowbells are showing.":
		push_error("smoke: a short bell claimed the bells were showing")
		get_tree().quit(1)
		return
	opening_bells[0].growth = 1.0
	if _plot_line(opening_bells[0]).find("Bells showing.") != -1 or _lane_passers() < 1 or _bell_line() != "":
		push_error("smoke: a ripe bell kept the young bell line")
		get_tree().quit(1)
		return
	opening_bells[0].growth = 0.76
	var held_peach := opening_peach.growth
	var held_cane := opening_cane.growth
	var held_far := opening_far.growth
	var held_reed := opening_reed.growth
	var held_bell := opening_bells[0].growth
	soil.tick(120.0, "golden")
	if opening_peach.growth != held_peach or opening_cane.growth != held_cane or opening_far.growth != held_far or opening_reed.growth != held_reed or opening_bells[0].growth <= held_bell:
		push_error("smoke: day 1 grew a held opening crop")
		get_tree().quit(1)
		return
	Clock.day = 2
	soil.tick(30.0, "golden")
	if opening_peach.growth <= held_peach or opening_bells[0].growth < 1.0:
		push_error("smoke: day 2 left the peach held")
		get_tree().quit(1)
		return
	Clock.day = 1
	opening_peach.growth = held_peach
	opening_cane.growth = held_cane
	opening_far.growth = held_far
	opening_reed.growth = held_reed
	opening_bells[0].growth = held_bell
	opening_bells[0].fertility = 0.38
	opening_bells[1].growth = 0.72
	opening_bells[1].fertility = 0.38
	opening_bells[2].growth = 0.70
	opening_bells[2].fertility = 0.38
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the day-1 hold did not save")
		get_tree().quit(1)
		return
	opening_peach.grow_from_day = 1
	opening_cane.grow_from_day = 1
	opening_far.grow_from_day = 1
	opening_reed.grow_from_day = 1
	apply_state(SaveGame.read_slot(1))
	opening_peach = soil.get_cell(3, 2)
	opening_cane = soil.get_cell(4, 2)
	opening_far = soil.get_cell(5, 2)
	opening_reed = soil.get_cell(7, 5)
	var reloaded_bell := soil.get_cell(1, 1)
	if opening_peach.grow_from_day != 2 or opening_cane.grow_from_day != 2 or opening_far.grow_from_day != 2 or opening_reed.grow_from_day != 2 or reloaded_bell.grow_from_day != 1:
		push_error("smoke: a reload dropped the day-1 hold")
		get_tree().quit(1)
		return
	var reloaded_peach := opening_peach.growth
	var reloaded_bell_growth := reloaded_bell.growth
	soil.tick(60.0, "golden")
	if opening_peach.growth != reloaded_peach or opening_cane.growth != held_cane or opening_reed.growth != held_reed or reloaded_bell.growth <= reloaded_bell_growth:
		push_error("smoke: a reloaded day 1 grew a held crop")
		get_tree().quit(1)
		return
	reloaded_bell.growth = 0.76
	reloaded_bell.fertility = 0.38
	if _grow_line() != "":
		push_error("smoke: day 1 announced the held crops")
		get_tree().quit(1)
		return
	Clock.day = 2
	Clock.set_hour(4.0)
	if _grow_line() != "":
		push_error("smoke: the night before dawn announced the held crops")
		get_tree().quit(1)
		return
	Clock.set_hour(5.0)
	if _grow_line() != "The peach, the brambles, and the reed take up growing." or _grow_line().find("Bellhelp") != -1:
		push_error("smoke: dawn on day 2 stayed quiet")
		get_tree().quit(1)
		return
	Clock.day = 3
	Clock.set_hour(4.5)
	if _grow_line() == "":
		push_error("smoke: the line left before the next morning")
		get_tree().quit(1)
		return
	Clock.set_hour(5.0)
	if _grow_line() != "":
		push_error("smoke: the next morning kept the growing line")
		get_tree().quit(1)
		return
	Clock.day = 1
	Clock.set_hour(15.2)
	if _sweet_line() != "" or _sweet_rumour_count() != 0:
		push_error("smoke: young bells called the meadow sweet")
		get_tree().quit(1)
		return
	var sweet_growth: Array[float] = [opening_bells[0].growth, opening_bells[1].growth, opening_bells[2].growth]
	for bell in opening_bells:
		bell.growth = 1.0
	if _sweet_line() != "The meadow is sweet enough." or _sweet_line().find("Bellhelp") != -1 or _sweet_rumour_count() != 1:
		push_error("smoke: three ripe bells stayed quiet")
		get_tree().quit(1)
		return
	ecology.states["bellhelp"] = "sighted"
	var sighted_blurb := ""
	for row in _journal_rows(world_snapshot()):
		var entry: Dictionary = row
		if str(entry.get("name", "")) == "Bellhelp":
			sighted_blurb = str(entry.get("blurb", ""))
	if _sweet_line() != "" or _sweet_rumour_count() != 0 or sighted_blurb != str(ContentDB.species_def("bellhelp").get("blurb", "")):
		push_error("smoke: a sighting kept the sweet line")
		get_tree().quit(1)
		return
	ecology.states["bellhelp"] = "rumoured"
	if _sweet_rumour_count() != 1:
		push_error("smoke: the rumour stayed named")
		get_tree().quit(1)
		return
	for i in opening_bells.size():
		opening_bells[i].growth = sweet_growth[i]
	if _sweet_rumour_count() != 0:
		push_error("smoke: young bells kept the sweet rumour")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		plot.plant_id = ""
		plot.growth = 0.0
		plot.tilled = false
		plot.grow_from_day = 1
	for i in 3:
		_force_plant(i, 1, "meadowbell", 1.0)
	_refresh_soil_colors()
	var meadow_n := _bed_flower_count()
	var seam: MeshInstance3D = patches["0,0"]
	var crop: MeshInstance3D = patches["0,1"]
	if seam.mesh != bed_lid or crop.mesh != bed_lid:
		push_error("smoke: empty bed stayed a separate lid")
		get_tree().quit(1)
		return
	soil.get_cell(0, 0).tilled = true
	_refresh_soil_colors()
	var meadow_after := _bed_flower_count()
	if seam.mesh != soil_lid:
		push_error("smoke: tilled bed kept the meadow lid")
		get_tree().quit(1)
		return
	soil.get_cell(0, 0).tilled = false
	_refresh_soil_colors()
	if meadow_n < 40 or meadow_after != meadow_n - 21:
		push_error("smoke: empty beds kept their meadow")
		get_tree().quit(1)
		return
	soil.get_cell(0, 1).plant_id = ""
	soil.get_cell(0, 1).growth = 0.0
	soil.get_cell(0, 1).tilled = false
	_refresh_soil_colors()
	var opened := _bed_flower_count()
	if opened != meadow_n + 13:
		push_error("smoke: a planted bed kept a bare rim")
		get_tree().quit(1)
		return
	_force_plant(0, 1, "meadowbell", 1.0)
	_refresh_soil_colors()
	var bridges := 0
	for bridge_node in get_children():
		if str(bridge_node.name).begins_with("BedBridge"):
			bridges += 1
	if bridges != 2:
		push_error("smoke: the plots stayed apart")
		get_tree().quit(1)
		return
	var bridge_n := 0
	var bridge_bands: Array[Rect2] = [
		Rect2(-7.25, -2.62, 4.25, 2.4),
		Rect2(-1.72, -2.62, 4.07, 2.4),
	]
	for bloom_i in bed_blooms.size():
		var bridge_multi := bed_blooms[bloom_i].multimesh
		for bridge_i in bridge_multi.instance_count:
			var bridge_at := bridge_multi.get_instance_transform(bridge_i).origin
			var on_strip := false
			for bridge_band in bridge_bands:
				if bridge_band.has_point(Vector2(bridge_at.x, bridge_at.z)):
					on_strip = true
					break
			if not on_strip:
				continue
			if GardenLayout.on_path(bridge_at.x, bridge_at.z) or GardenLayout.on_track(bridge_at.x, bridge_at.z):
				push_error("smoke: a bridge bloom sat on the worn center")
				get_tree().quit(1)
				return
			bridge_n += 1
	if bridge_n < 180:
		push_error("smoke: the bridge strips stayed thin")
		get_tree().quit(1)
		return
	var lawn_node := get_node_or_null("LawnBlooms") as MultiMeshInstance3D
	if lawn_node == null or lawn_node.multimesh == null or lawn_node.multimesh.instance_count < 1400:
		push_error("smoke: the parish lawn stayed a thin scatter")
		get_tree().quit(1)
		return
	var lawn_multi := lawn_node.multimesh
	var hedge_n := 0
	var apron_n := 0
	var front_n := 0
	for lawn_i in lawn_multi.instance_count:
		var lawn_at := lawn_multi.get_instance_transform(lawn_i).origin
		if lawn_at.x < -12.2:
			push_error("smoke: a lawn bloom sat in the west hedge")
			get_tree().quit(1)
			return
		if lawn_at.x < -11.25 and lawn_at.x > -12.2:
			hedge_n += 1
		if lawn_at.x > 2.9 and lawn_at.x < 6.9 and lawn_at.z > 2.85 and lawn_at.z < 5.65:
			apron_n += 1
		if lawn_at.z < -9.55:
			push_error("smoke: a lawn bloom sat in the south hedge")
			get_tree().quit(1)
			return
		if lawn_at.x > -7.8 and lawn_at.x < 3.3 and lawn_at.z < -7.4 and lawn_at.z > -9.45:
			front_n += 1
		if GardenLayout.on_path(lawn_at.x, lawn_at.z) or GardenLayout.in_plots(lawn_at.x, lawn_at.z, 0.0):
			push_error("smoke: a lawn bloom sat on a bed or the worn walk")
			get_tree().quit(1)
			return
		if GardenLayout.pond_distance(lawn_at.x, lawn_at.z) < GardenLayout.POND_RADIUS or lawn_at.y > 0.45:
			push_error("smoke: a lawn bloom climbed the hill or the pond")
			get_tree().quit(1)
			return
		if Vector2(lawn_at.x - GardenLayout.TEA.x, lawn_at.z - GardenLayout.TEA.z).length() < 1.15 or Vector2(lawn_at.x - GardenLayout.HUT.x, lawn_at.z - GardenLayout.HUT.z).length() < 1.15 or Vector2(lawn_at.x - GardenLayout.FOUNDRY.x, lawn_at.z - GardenLayout.FOUNDRY.z).length() < 1.15 or Vector2(lawn_at.x - GardenLayout.HALL.x, lawn_at.z - GardenLayout.HALL.z).length() < 1.15:
			push_error("smoke: a lawn bloom sat in a room")
			get_tree().quit(1)
			return
	if hedge_n < 60:
		push_error("smoke: the lawn inside the west hedge stayed thin (%d)" % hedge_n)
		get_tree().quit(1)
		return
	if apron_n < 55:
		push_error("smoke: the east apron stayed thin (%d)" % apron_n)
		get_tree().quit(1)
		return
	if front_n < 50:
		push_error("smoke: the south lawn stayed thin (%d)" % front_n)
		get_tree().quit(1)
		return
	ecology.tick(0.2, world_snapshot())
	if ecology.first("bellhelp") == null:
		push_error("smoke: bellhelp did not arrive")
		get_tree().quit(1)
		return
	var before := Economy.coins
	buy("fertilizer")
	if Economy.coins >= before:
		push_error("smoke: stall did not charge")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: save failed")
		get_tree().quit(1)
		return
	var loaded := SaveGame.read_slot(1)
	if loaded.is_empty() or int(loaded.get("economy", {}).get("coins", -1)) != Economy.coins:
		push_error("smoke: reload mismatch")
		get_tree().quit(1)
		return
	var open_hour := Clock.hour()
	var shut_tin := Economy.coins
	var shut_pouch := Economy.count("fertilizer")
	Economy.add("meadowbell", 1)
	var shut_bells := Economy.count("meadowbell")
	Clock.set_hour(22.0)
	buy("fertilizer")
	sell("meadowbell")
	if Economy.coins != shut_tin or Economy.count("fertilizer") != shut_pouch or Economy.count("meadowbell") != shut_bells or events.is_empty() or str(events[0]).find("shut") == -1:
		push_error("smoke: the stall took coins at night")
		get_tree().quit(1)
		return
	Clock.set_hour(4.5)
	buy("fertilizer")
	if Economy.coins != shut_tin or Economy.count("fertilizer") != shut_pouch:
		push_error("smoke: the stall took coins before morning")
		get_tree().quit(1)
		return
	Clock.set_hour(5.0)
	buy("fertilizer")
	if Economy.coins >= shut_tin or Economy.count("fertilizer") != shut_pouch + 1:
		push_error("smoke: the stall stayed shut at morning")
		get_tree().quit(1)
		return
	Economy.earn(shut_tin - Economy.coins)
	Economy.take("fertilizer", 1)
	Economy.take("meadowbell", 1)
	if Economy.coins != shut_tin or Economy.count("fertilizer") != shut_pouch or Economy.count("meadowbell") != shut_bells - 1:
		push_error("smoke: the morning sale was not put back")
		get_tree().quit(1)
		return
	Clock.set_hour(open_hour)
	var small := hud.clock_label.get_theme_font_size("font_size")
	set_large_text(true)
	var big := hud.clock_label.get_theme_font_size("font_size")
	set_large_text(false)
	if big <= small:
		push_error("smoke: large text did not grow the hud")
		get_tree().quit(1)
		return
	var venue_lines: Array = _place_stats(world_snapshot()).get("venues", [])
	var saw_open := false
	var saw_closed := false
	for line in venue_lines:
		if str(line).find("open") != -1:
			saw_open = true
		if str(line).find("not built") != -1:
			saw_closed = true
	if not saw_open or not saw_closed:
		push_error("smoke: parish venues missing")
		get_tree().quit(1)
		return
	bees.tick(1.0, false, "clear")
	if bees.bodies[0].position.distance_to(bees.homes[0]) < 0.05:
		push_error("smoke: bees did not leave the flower")
		get_tree().quit(1)
		return
	bees.tick(0.0, true, "rain")
	if bees.bodies[0].position.distance_to(bees.homes[0]) > 0.02:
		push_error("smoke: bees did not shelter from the rain")
		get_tree().quit(1)
		return
	var kept_hour := Clock.hour()
	birds.tick(1.0, false, 15.3, "golden")
	if birds.bodies[0].position.distance_to(birds.perches[0]) < 0.4:
		push_error("smoke: birds did not cross the garden")
		get_tree().quit(1)
		return
	birds.tick(0.0, true, 2.0, "clear")
	if birds.bodies[0].position.distance_to(birds.perches[0]) > 0.05:
		push_error("smoke: birds flew through the night")
		get_tree().quit(1)
		return
	birds.tick(1.0, false, 5.0, "clear")
	if birds.bodies[0].position.distance_to(birds.perches[0]) < 0.4:
		push_error("smoke: birds stayed on the perch at morning")
		get_tree().quit(1)
		return
	birds.tick(0.0, true, 13.0, "rain")
	if birds.bodies[0].position.distance_to(birds.perches[0]) > 0.05:
		push_error("smoke: birds flew in the rain")
		get_tree().quit(1)
		return
	bees.bodies[0].position = bees.homes[0] + Vector3(2.0, 0.0, 0.0)
	bees.tick(0.0, true, "mist")
	if bees.bodies[0].position.distance_to(bees.homes[0]) < 1.0:
		push_error("smoke: the mist sent the bees home")
		get_tree().quit(1)
		return
	birds.bodies[0].position = birds.perches[0] + Vector3(3.0, 1.0, 0.0)
	birds.tick(0.0, true, 17.2, "mist")
	if birds.bodies[0].position.distance_to(birds.perches[0]) < 1.0:
		push_error("smoke: the mist sat the birds")
		get_tree().quit(1)
		return
	Clock.set_hour(4.5)
	_apply_shift(false)
	if not shift.begins_with("night") or _person("bram").waypoints.is_empty() or _person("bram").waypoints[0].distance_to(GardenLayout.SHED) > 2.0:
		push_error("smoke: the parish was out before dawn")
		get_tree().quit(1)
		return
	Clock.set_hour(5.0)
	_apply_shift(false)
	if shift.begins_with("night") or _person("bram").waypoints.is_empty() or _person("bram").waypoints[0].distance_to(GardenLayout.SHED) < 2.0:
		push_error("smoke: the parish stayed in at morning")
		get_tree().quit(1)
		return
	var dew_plot := soil.get_cell(3, 3)
	var dew_meadow := soil.get_cell(3, 4)
	var dew_moist := dew_plot.moisture
	var dew_till := dew_plot.tilled
	var dew_plant := dew_plot.plant_id
	var dew_growth := dew_plot.growth
	var meadow_moist := dew_meadow.moisture
	var meadow_till := dew_meadow.tilled
	var meadow_plant := dew_meadow.plant_id
	var dew_seed := soil.seeded
	var dew_rain := soil.seed_rain
	var dew_tin := Economy.coins
	var dew_trust := Trust.level("nessa")
	dew_plot.tilled = true
	dew_plot.plant_id = ""
	dew_plot.moisture = 0.2
	dew_meadow.tilled = false
	dew_meadow.plant_id = ""
	dew_meadow.moisture = 0.2
	Clock.set_hour(6.0)
	_dew(1.0)
	if dew_plot.moisture < 0.6 or dew_meadow.moisture > 0.21 or soil.seeded != dew_seed or absf(soil.seed_rain - dew_rain) > 0.001 or Economy.coins != dew_tin or Trust.level("nessa") != dew_trust:
		push_error("smoke: the morning dew missed the open bed")
		get_tree().quit(1)
		return
	dew_plot.moisture = 0.2
	Clock.weather = "rain"
	_dew(1.0)
	if dew_plot.moisture > 0.21:
		push_error("smoke: dew stacked on the rain")
		get_tree().quit(1)
		return
	Clock.set_hour(4.5)
	dew_plot.moisture = 0.2
	_dew(1.0)
	Clock.set_hour(7.0)
	_dew(1.0)
	Clock.set_hour(15.3)
	_dew(1.0)
	Clock.set_hour(22.0)
	_dew(1.0)
	if dew_plot.moisture > 0.21:
		push_error("smoke: dew fell outside the morning")
		get_tree().quit(1)
		return
	dew_plot.moisture = dew_moist
	dew_plot.tilled = dew_till
	dew_plot.plant_id = dew_plant
	dew_plot.growth = dew_growth
	dew_meadow.moisture = meadow_moist
	dew_meadow.tilled = meadow_till
	dew_meadow.plant_id = meadow_plant
	soil.seeded = dew_seed
	soil.seed_rain = dew_rain
	Clock.set_hour(kept_hour)
	var hold_rows: Array = []
	for cell in soil.all():
		var hold_cell: SoilCell = cell
		hold_rows.append([hold_cell, hold_cell.moisture, hold_cell.growth, hold_cell.fertility, hold_cell.wilt, hold_cell.plant_id, hold_cell.taken])
	var hold_seed := soil.seeded
	var hold_rain := soil.seed_rain
	var hold_tin := Economy.coins
	var hold_trust := Trust.level("nessa")
	var hold_bed := soil.get_cell(4, 6)
	hold_bed.plant_id = ""
	hold_bed.moisture = 0.55
	soil.seed_rain = 0.3
	soil.tick(60.0, "mist")
	if absf(hold_bed.moisture - 0.55) > 0.001 or soil.seeded != "" or absf(soil.seed_rain) > 0.001:
		push_error("smoke: the mist watered the bed")
		get_tree().quit(1)
		return
	hold_bed.moisture = 0.55
	soil.tick(60.0, "clear")
	if hold_bed.moisture > 0.4:
		push_error("smoke: a clear hour kept the mist")
		get_tree().quit(1)
		return
	hold_bed.plant_id = "meadowbell"
	hold_bed.growth = 0.5
	hold_bed.moisture = 0.1
	hold_bed.fertility = 0.5
	hold_bed.wilt = 1.0
	hold_bed.taken = false
	soil.tick(60.0, "mist")
	if absf(hold_bed.wilt - 1.0) > 0.001 or absf(hold_bed.growth - 0.5) > 0.001 or absf(hold_bed.moisture - 0.1) > 0.001 or hold_bed.plant_id != "meadowbell":
		push_error("smoke: the mist dried a thirsty bed")
		get_tree().quit(1)
		return
	soil.tick(60.0, "clear")
	if hold_bed.wilt < 1.5 or hold_bed.moisture > 0.1:
		push_error("smoke: a clear hour spared the thirsty bed")
		get_tree().quit(1)
		return
	if Economy.coins != hold_tin or Trust.level("nessa") != hold_trust:
		push_error("smoke: the mist moved the parish")
		get_tree().quit(1)
		return
	for row in hold_rows:
		var kept: SoilCell = row[0]
		kept.moisture = row[1]
		kept.growth = row[2]
		kept.fertility = row[3]
		kept.wilt = row[4]
		kept.plant_id = row[5]
		kept.taken = row[6]
	soil.seeded = hold_seed
	soil.seed_rain = hold_rain
	var feed_rows: Array = []
	for cell in soil.all():
		var feed_cell: SoilCell = cell
		feed_rows.append([feed_cell, feed_cell.moisture, feed_cell.growth, feed_cell.fertility, feed_cell.wilt, feed_cell.plant_id, feed_cell.taken, feed_cell.tilled, feed_cell.chem])
	var feed_seed := soil.seeded
	var feed_rain := soil.seed_rain
	var feed_tin := Economy.coins
	var feed_trust := Trust.level("nessa")
	var fallow := soil.get_cell(6, 1)
	fallow.tilled = true
	fallow.plant_id = ""
	fallow.fertility = 0.12
	soil.tick(60.0, "clear")
	if fallow.fertility < 0.15 or fallow.fertility > 0.2:
		push_error("smoke: a clear hour left the empty bed hungry")
		get_tree().quit(1)
		return
	fallow.fertility = 0.4
	soil.tick(60.0, "clear")
	if absf(fallow.fertility - 0.42) > 0.001:
		push_error("smoke: the empty bed grew rich on its own")
		get_tree().quit(1)
		return
	fallow.fertility = 0.55
	soil.tick(60.0, "clear")
	if absf(fallow.fertility - 0.55) > 0.001:
		push_error("smoke: a clear hour spent the feed already in the bed")
		get_tree().quit(1)
		return
	fallow.fertility = 0.12
	soil.tick(60.0, "golden")
	if absf(fallow.fertility - 0.12) > 0.001:
		push_error("smoke: the golden afternoon fed the empty bed")
		get_tree().quit(1)
		return
	fallow.fertility = 0.12
	soil.tick(60.0, "mist")
	if absf(fallow.fertility - 0.12) > 0.001:
		push_error("smoke: the mist fed the empty bed")
		get_tree().quit(1)
		return
	fallow.fertility = 0.12
	soil.tick(60.0, "rain")
	if fallow.fertility > 0.121:
		push_error("smoke: the rain fed the empty bed")
		get_tree().quit(1)
		return
	fallow.plant_id = ""
	fallow.tilled = true
	fallow.moisture = 0.5
	soil.tick(60.0, "golden")
	if absf(fallow.moisture - 0.5) > 0.001:
		push_error("smoke: the golden afternoon dried the empty bed")
		get_tree().quit(1)
		return
	fallow.plant_id = "meadowbell"
	fallow.growth = 0.4
	fallow.moisture = 0.8
	fallow.fertility = 0.4
	fallow.wilt = 0.0
	soil.tick(60.0, "golden")
	if absf(fallow.moisture - 0.8) > 0.001:
		push_error("smoke: the golden afternoon dried a living bed")
		get_tree().quit(1)
		return
	fallow.plant_id = ""
	fallow.growth = 0.0
	fallow.moisture = 0.5
	soil.tick(60.0, "clear")
	if fallow.moisture > 0.32 or fallow.moisture < 0.24:
		push_error("smoke: a clear hour left the empty bed wet")
		get_tree().quit(1)
		return
	fallow.moisture = 0.44
	soil.tick(60.0, "mist")
	if absf(fallow.moisture - 0.44) > 0.001:
		push_error("smoke: the mist changed the water it was holding")
		get_tree().quit(1)
		return
	var grass := soil.get_cell(6, 3)
	grass.tilled = false
	grass.plant_id = ""
	grass.fertility = 0.12
	soil.tick(60.0, "clear")
	if absf(grass.fertility - 0.12) > 0.001:
		push_error("smoke: untilled grass regained feed")
		get_tree().quit(1)
		return
	var living := soil.get_cell(6, 2)
	living.tilled = true
	living.plant_id = "meadowbell"
	living.growth = 0.4
	living.moisture = 0.8
	living.fertility = 0.5
	living.wilt = 0.0
	living.taken = false
	soil.tick(60.0, "clear")
	if living.fertility > 0.48 or living.fertility < 0.45 or living.plant_id != "meadowbell":
		push_error("smoke: a living crop stopped tiring the soil")
		get_tree().quit(1)
		return
	if Economy.coins != feed_tin or Trust.level("nessa") != feed_trust:
		push_error("smoke: the fallow hour moved the parish")
		get_tree().quit(1)
		return
	for row in feed_rows:
		var fed: SoilCell = row[0]
		fed.moisture = row[1]
		fed.growth = row[2]
		fed.fertility = row[3]
		fed.wilt = row[4]
		fed.plant_id = row[5]
		fed.taken = row[6]
		fed.tilled = row[7]
		fed.chem = row[8]
	soil.seeded = feed_seed
	soil.seed_rain = feed_rain
	var dawn_notes: Array = events.duplicate()
	var dawn_top := ""
	if not dawn_notes.is_empty():
		dawn_top = str(dawn_notes[0])
	var dawn_clock := Clock.day
	var dawn_mark := bird_day
	var dawn_tin := Economy.coins
	var dawn_trust := Trust.level("nessa")
	Clock.set_hour(4.5)
	_dawn_birds()
	if bird_day != dawn_mark or events.size() != dawn_notes.size() or (not events.is_empty() and str(events[0]) != dawn_top):
		push_error("smoke: the birds sang before morning")
		get_tree().quit(1)
		return
	Clock.set_hour(5.0)
	Clock.weather = "rain"
	_dawn_birds()
	if bird_day != dawn_mark or events.size() != dawn_notes.size() or (not events.is_empty() and str(events[0]) != dawn_top):
		push_error("smoke: the birds sang in the rain")
		get_tree().quit(1)
		return
	Clock.set_hour(7.0)
	_dawn_birds()
	Clock.set_hour(22.0)
	_dawn_birds()
	if bird_day != dawn_mark or events.size() != dawn_notes.size() or (not events.is_empty() and str(events[0]) != dawn_top):
		push_error("smoke: the birds sang after the morning")
		get_tree().quit(1)
		return
	Clock.set_hour(5.0)
	_dawn_birds()
	if bird_day != Clock.day or events.size() < dawn_notes.size() + 2 or str(events[1]).find("leave the hedge") == -1 or str(events[0]).find("once more before seven") == -1 or Economy.coins != dawn_tin or Trust.level("nessa") != dawn_trust:
		push_error("smoke: the birds stayed quiet at morning")
		get_tree().quit(1)
		return
	var dawn_size := events.size()
	var dawn_tail := str(events[dawn_size - 1])
	_dawn_birds()
	if events.size() != dawn_size or str(events[dawn_size - 1]) != dawn_tail or bird_day != Clock.day:
		push_error("smoke: the birds sang twice in one morning")
		get_tree().quit(1)
		return
	Clock.day = dawn_clock + 1
	Clock.set_hour(5.0)
	_dawn_birds()
	if bird_day != Clock.day or events.size() < 2 or str(events[1]).find("leave the hedge") == -1 or str(events[0]).find("once more before seven") == -1:
		push_error("smoke: the next morning stayed quiet")
		get_tree().quit(1)
		return
	var dawn_pack := to_state()
	if int(dawn_pack.get("bird_day", -2)) != Clock.day:
		push_error("smoke: the morning song did not save")
		get_tree().quit(1)
		return
	events = dawn_notes.duplicate()
	bird_day = dawn_mark
	Clock.day = dawn_clock
	Clock.set_hour(kept_hour)
	if Economy.coins != dawn_tin or Trust.level("nessa") != dawn_trust:
		push_error("smoke: the morning song moved the parish")
		get_tree().quit(1)
		return
	var bell := ecology.first("bellhelp")
	var guest_life := bell.life
	var bell_was := bell.global_position
	var awning := GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
	bell.life = "visitor"
	bell.leaving = false
	bell.held = false
	bell.young = false
	bell.global_position = Vector3(10.5, 0.0, -8.5)
	Clock.set_hour(22.0)
	var night_guest := bell.global_position.distance_to(awning)
	_update_creatures(0.016)
	bell.tier = 2
	bell._process(2.0)
	if not bell.use_berth or bell.global_position.distance_to(awning) > night_guest - 0.8:
		push_error("smoke: a visitor stayed out at night")
		get_tree().quit(1)
		return
	bell.leaving = true
	bell.goal = Vector3(-1.0, 0.0, -1.0)
	_update_creatures(0.016)
	if bell.use_berth or bell.goal.distance_to(awning) < 0.3:
		push_error("smoke: a departure sheltered at night")
		get_tree().quit(1)
		return
	bell.leaving = false
	bell.goal = awning
	bell.global_position = Vector3(10.5, 0.0, -8.5)
	Clock.set_hour(15.3)
	_update_creatures(0.016)
	if bell.use_berth or bell.goal.distance_to(awning) < 0.3:
		push_error("smoke: the morning left a visitor under the awning")
		get_tree().quit(1)
		return
	bell.life = guest_life
	bell.use_berth = false
	bell.global_position = bell_was
	Clock.set_hour(kept_hour)
	var bell_home := bell.global_position
	bell.global_position = camera.global_position + camera.global_transform.basis.z * 4.0
	_update_creatures(0.016)
	bell._process(0.016)
	if bell.tier < 3 or bell.visible:
		push_error("smoke: offscreen jelly stayed visible")
		get_tree().quit(1)
		return
	bell.global_position = bell_home
	_update_creatures(0.016)
	bell._process(0.016)
	if bell.tier >= 3 or not bell.visible:
		push_error("smoke: onscreen jelly was hidden")
		get_tree().quit(1)
		return
	var demand := int(_place_stats(world_snapshot()).get("stall_demand", -1))
	if demand != _present_people() + ecology.resident_total() + _lane_passers() or demand < 1:
		push_error("smoke: stall demand mismatch")
		get_tree().quit(1)
		return
	var life_was := bell.life
	var kit := Vector3(9.0, 0.0, 5.0)
	home_points.append(kit)
	bell.life = "resident"
	bell.global_position = camera.global_position + camera.global_transform.basis.z * 6.0
	bell.global_position.y = 0.0
	var far := bell.global_position.distance_to(kit)
	_update_creatures(1.0)
	bell._process(2.0)
	var nearer := bell.global_position.distance_to(kit)
	if not bell.use_berth or nearer > far - 0.8:
		push_error("smoke: resident did not walk home")
		get_tree().quit(1)
		return
	home_points.pop_back()
	bell.life = life_was
	bell.use_berth = false
	bell.global_position = bell_home
	Clock.set_hour(21.0)
	var night_kit := Vector3(8.0, 0.0, 4.0)
	home_points.append(night_kit)
	bell.life = "resident"
	bell.global_position = Vector3(-4.0, 0.0, -2.0)
	var night_far := bell.global_position.distance_to(night_kit)
	_update_creatures(0.016)
	bell.tier = 1
	bell._process(2.0)
	if not bell.wants_sleep or not bell.use_berth or bell.global_position.distance_to(night_kit) > night_far - 0.8:
		push_error("smoke: the resident stayed out at night")
		get_tree().quit(1)
		return
	home_points.pop_back()
	bell.life = life_was
	bell.use_berth = false
	bell.wants_sleep = false
	bell.global_position = bell_home
	var bram := _person("bram")
	Clock.set_hour(15.3)
	_apply_shift(false)
	if bram.waypoints[0].distance_to(GardenLayout.SHED) < 2.0:
		push_error("smoke: day job was the shed")
		get_tree().quit(1)
		return
	Clock.set_hour(21.0)
	_apply_shift(false)
	if bram.waypoints[0].distance_to(GardenLayout.SHED) > 2.0:
		push_error("smoke: night route missed the shed")
		get_tree().quit(1)
		return
	if _person("nessa").waypoints.is_empty() or _person("nessa").waypoints[0].distance_to(GardenLayout.HUT + Vector3(0, 0, -1.05)) < 0.3:
		push_error("smoke: the hut took her before the notes")
		get_tree().quit(1)
		return
	var walk := bram.global_position.distance_to(bram.waypoints[0])
	bram._process(3.0)
	if bram.global_position.distance_to(bram.waypoints[0]) > walk - 0.8:
		push_error("smoke: bram did not walk home")
		get_tree().quit(1)
		return
	var shower_day := Clock.day
	Clock.day = 1
	Clock.set_hour(20.4)
	if Clock.weather != "rain":
		push_error("smoke: an odd night stayed dry")
		get_tree().quit(1)
		return
	Clock.set_hour(13.0)
	if Clock.weather == "rain":
		push_error("smoke: an odd afternoon rained")
		get_tree().quit(1)
		return
	Clock.day = 2
	Clock.set_hour(20.4)
	if Clock.weather != "mist":
		push_error("smoke: an even night rained")
		get_tree().quit(1)
		return
	Clock.set_hour(10.9)
	if Clock.weather != "clear":
		push_error("smoke: the even morning rained")
		get_tree().quit(1)
		return
	Clock.set_hour(11.0)
	if Clock.weather != "rain":
		push_error("smoke: the even morning edge stayed dry")
		get_tree().quit(1)
		return
	Clock.set_hour(13.0)
	if Clock.weather != "rain":
		push_error("smoke: the even afternoon stayed dry")
		get_tree().quit(1)
		return
	Clock.set_hour(15.0)
	if Clock.weather != "rain":
		push_error("smoke: the late even afternoon stayed dry")
		get_tree().quit(1)
		return
	Clock.set_hour(16.5)
	if Clock.weather != "mist":
		push_error("smoke: dusk joined the shower")
		get_tree().quit(1)
		return
	Clock.day = 1
	Clock.set_hour(11.0)
	if Clock.weather != "golden":
		push_error("smoke: the odd morning edge rained")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	if Clock.weather != "golden":
		push_error("smoke: the capture afternoon rained")
		get_tree().quit(1)
		return
	Clock.day = 2
	Clock.set_hour(15.0)
	_apply_shift(false)
	var shower_porch := GardenLayout.TEA + Vector3(0, 0, -1.15)
	var rain_hut := GardenLayout.HUT + Vector3(0, 0, -1.05)
	var rain_desk := GardenLayout.FOUNDRY + Vector3(0, 0, -0.95)
	if shift != "rain" or _person("nessa").waypoints.size() != 3 or _person("nessa").waypoints[0].distance_to(shower_porch) > 0.3 or _person("nessa").waypoints[1].distance_to(rain_hut) > 0.3 or _person("nessa").waypoints[2].distance_to(rain_desk) > 0.3 or bram.waypoints.size() != 2 or bram.waypoints[0].distance_to(GardenLayout.SHED) > 2.0 or bram.waypoints[1].distance_to(GardenLayout.STALL) > 2.0 or _person("lumen").waypoints.size() != 2:
		push_error("smoke: the rain bell missed the tea house")
		get_tree().quit(1)
		return
	Clock.set_hour(17.2)
	if Clock.weather != "mist":
		push_error("smoke: the mist hour stayed a shower")
		get_tree().quit(1)
		return
	_apply_shift(false)
	if shift != "rain" or _person("nessa").waypoints.size() != 3 or _person("nessa").waypoints[0].distance_to(shower_porch) > 0.3 or _person("bram").waypoints.size() != 2 or _person("lumen").waypoints.size() != 2:
		push_error("smoke: the mist left the parish on the day round")
		get_tree().quit(1)
		return
	var mist_coins := Economy.coins
	var mist_trust := Trust.level("nessa")
	Clock.day = 1
	Clock.set_hour(15.3)
	_apply_shift(false)
	if Clock.weather != "golden" or shift == "rain" or _person("bram").waypoints.is_empty() or _person("bram").waypoints[0].distance_to(GardenLayout.SHED) < 2.0 or Economy.coins != mist_coins or Trust.level("nessa") != mist_trust:
		push_error("smoke: the golden afternoon took the rain shelter")
		get_tree().quit(1)
		return
	Clock.day = 2
	Clock.set_hour(15.0)
	_apply_shift(false)
	var nessa_was := _person("nessa").present
	var rain_coins := Economy.coins
	var rain_trust := Trust.level("nessa")
	_person("nessa").present = true
	_person("nessa").has_chore = false
	_person("nessa").index = 1
	_person("nessa").pause = 0.0
	_person("nessa").global_position = shower_porch
	var rain_far := _person("nessa").global_position.distance_to(rain_hut)
	_person("nessa")._process(3.0)
	if _person("nessa").global_position.distance_to(rain_hut) > rain_far - 0.8 or nessa_filing or nessa_drafting or Trust.level("nessa") != rain_trust or Economy.coins != rain_coins:
		push_error("smoke: nessa stayed on the tea porch")
		get_tree().quit(1)
		return
	_person("nessa").present = nessa_was
	bell.life = "resident"
	bell.wants_sleep = false
	bell.global_position = Vector3(-4.0, 0.0, -2.0)
	_update_creatures(0.016)
	if bell.use_berth:
		push_error("smoke: the shower invented a home")
		get_tree().quit(1)
		return
	var rain_day := Clock.day
	Clock.set_hour(22.0)
	bell.life = "resident"
	bell.leaving = false
	bell.held = false
	bell.young = false
	bell.global_position = Vector3(10.5, 0.0, -8.5)
	var bedless := bell.global_position.distance_to(awning)
	_update_creatures(0.016)
	bell.tier = 2
	bell._process(2.0)
	if not bell.wants_sleep or not bell.use_berth or bell.global_position.distance_to(awning) > bedless - 0.8:
		push_error("smoke: a resident with no kit stayed out at night")
		get_tree().quit(1)
		return
	Clock.day = 1
	Clock.set_hour(15.3)
	bell.goal = awning
	bell.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	if bell.use_berth or bell.wants_sleep or bell.goal.distance_to(awning) < 0.3:
		push_error("smoke: the morning left a resident under the awning")
		get_tree().quit(1)
		return
	Clock.day = rain_day
	Clock.set_hour(15.0)
	bell.life = "resident"
	bell.leaving = false
	bell.use_berth = false
	bell.wants_sleep = false
	bell.global_position = Vector3(-4.0, 0.0, -2.0)
	var wet_kit := Vector3(8.0, 0.0, 4.0)
	home_points.append(wet_kit)
	var wet_far := bell.global_position.distance_to(wet_kit)
	_update_creatures(0.016)
	bell.tier = 1
	bell._process(2.0)
	if bell.wants_sleep or not bell.use_berth or bell.global_position.distance_to(wet_kit) > wet_far - 0.8:
		push_error("smoke: a resident stayed out in the shower")
		get_tree().quit(1)
		return
	home_points.pop_back()
	bell.life = life_was
	bell.use_berth = false
	bell.wants_sleep = false
	bell.global_position = bell_home
	bell.life = "visitor"
	bell.leaving = false
	bell.global_position = Vector3(-1.0, 0.0, -2.0)
	var awning_far := bell.global_position.distance_to(awning)
	_update_creatures(0.016)
	bell.tier = 1
	bell._process(2.0)
	if bell.wants_sleep or not bell.use_berth or bell.global_position.distance_to(awning) > awning_far - 0.8:
		push_error("smoke: a visitor stayed out in the shower")
		get_tree().quit(1)
		return
	bell.global_position = Vector3(6.0, 0.0, -6.0)
	_update_creatures(0.016)
	bell.tier = 3
	var hidden_far := bell.global_position.distance_to(awning)
	bell._process(2.0)
	if bell.visible or bell.global_position.distance_to(awning) > hidden_far - 0.8:
		push_error("smoke: a hidden visitor stayed out in the shower")
		get_tree().quit(1)
		return
	bell.leaving = true
	bell.goal = GardenLayout.GATE
	bell.attract = GardenLayout.GATE
	_update_creatures(0.016)
	if bell.use_berth or bell.goal.distance_to(GardenLayout.GATE) > 0.2:
		push_error("smoke: the shower pulled a departure off the gate")
		get_tree().quit(1)
		return
	Clock.day = 1
	Clock.set_hour(13.0)
	bell.leaving = false
	_update_creatures(0.016)
	if Clock.weather == "rain" or bell.use_berth:
		push_error("smoke: a dry afternoon used the awning")
		get_tree().quit(1)
		return
	Clock.day = 2
	Clock.set_hour(13.0)
	bell.life = life_was
	bell.leaving = false
	bell.use_berth = false
	bell.wants_sleep = false
	bell.global_position = bell_home
	bell.attract = _attractor_for(ContentDB.species_def("bellhelp"))
	_update_creatures(0.016)
	bell._process(0.016)
	var soaked := {}
	for cell in soil.all():
		var plot: SoilCell = cell
		soaked["%d,%d" % [plot.ix, plot.iz]] = [plot.moisture, plot.growth, plot.wilt, plot.plant_id]
	var rain_bed := soil.get_cell(0, 0)
	rain_bed.moisture = 0.12
	soil.tick(60.0, Clock.weather)
	if rain_bed.moisture < 0.9:
		push_error("smoke: the afternoon shower missed the bed")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: Array = soaked["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(kept[0])
		plot.growth = float(kept[1])
		plot.wilt = float(kept[2])
		plot.plant_id = str(kept[3])
	var seed_snap := {}
	for cell in soil.all():
		var plot: SoilCell = cell
		seed_snap["%d,%d" % [plot.ix, plot.iz]] = [plot.moisture, plot.growth, plot.wilt, plot.plant_id, plot.tilled, plot.fertility, plot.chem]
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.growth >= 1.0:
			plot.growth = 0.4
	var seed_parent := soil.get_cell(0, 0)
	var seed_child := soil.get_cell(1, 0)
	seed_parent.tilled = true
	seed_parent.plant_id = "meadowbell"
	seed_parent.growth = 1.0
	seed_parent.fertility = maxf(seed_parent.fertility, 0.4)
	seed_parent.moisture = 0.8
	seed_parent.chem = "base"
	seed_child.tilled = true
	seed_child.plant_id = ""
	seed_child.growth = 0.0
	seed_child.wilt = 0.0
	seed_child.fertility = maxf(seed_child.fertility, 0.4)
	seed_child.chem = "base"
	var seed_block := soil.get_cell(0, 1)
	seed_block.plant_id = "reed"
	seed_block.growth = 0.2
	seed_block.tilled = true
	soil.seed_rain = 0.0
	soil.tick(60.0, "rain")
	if soil.seeded != "meadowbell" or seed_child.plant_id != "meadowbell" or seed_child.growth > 0.3:
		push_error("smoke: the rain did not carry the seed")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the seedling did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	seed_child = soil.get_cell(1, 0)
	if seed_child.plant_id != "meadowbell" or absf(soil.seed_rain) > 0.05:
		push_error("smoke: the seedling did not reload")
		get_tree().quit(1)
		return
	var seed_other := soil.get_cell(0, 1)
	seed_other.tilled = true
	seed_other.plant_id = ""
	seed_other.growth = 0.0
	seed_other.fertility = 0.4
	seed_other.chem = "base"
	soil.tick(60.0, "clear")
	if seed_other.plant_id != "" or soil.seeded != "":
		push_error("smoke: a dry hour carried seed")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: Array = seed_snap["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(kept[0])
		plot.growth = float(kept[1])
		plot.wilt = float(kept[2])
		plot.plant_id = str(kept[3])
		plot.tilled = bool(kept[4])
		plot.fertility = float(kept[5])
		plot.chem = str(kept[6])
	soil.seed_rain = 0.0
	var pear_coins := Economy.coins
	var pear_trust := Trust.level("nessa")
	for cell in soil.all():
		var ripe: SoilCell = cell
		if ripe.growth >= 1.0:
			ripe.growth = 0.5
	var pear_parent := soil.get_cell(6, 2)
	var pear_child := soil.get_cell(7, 2)
	pear_parent.tilled = true
	pear_parent.plant_id = "mosspear"
	pear_parent.growth = 1.0
	pear_parent.fertility = 0.7
	pear_parent.moisture = 0.9
	pear_parent.wilt = 0.0
	pear_parent.chem = "base"
	pear_child.tilled = true
	pear_child.plant_id = ""
	pear_child.growth = 0.0
	pear_child.wilt = 0.0
	pear_child.fertility = 0.41
	pear_child.moisture = 0.8
	pear_child.chem = "base"
	var pear_blocks: Array[Vector2i] = [Vector2i(5, 2), Vector2i(6, 1), Vector2i(6, 3)]
	for off in pear_blocks:
		var block := soil.get_cell(off.x, off.y)
		block.tilled = true
		block.plant_id = "reed"
		block.growth = 0.2
	soil.tick(30.0, "rain")
	if pear_child.plant_id != "" or soil.seeded != "":
		push_error("smoke: a thin bed took the mosspear")
		get_tree().quit(1)
		return
	pear_child.fertility = 0.42
	soil.tick(30.0, "rain")
	if soil.seeded != "mosspear" or pear_child.plant_id != "mosspear" or pear_child.growth < 0.1 or pear_child.growth > 0.3:
		push_error("smoke: the rain did not set the mosspear seedling")
		get_tree().quit(1)
		return
	var pear_growth := pear_child.growth
	soil.tick(60.0, "rain")
	if pear_child.plant_id != "mosspear" or absf(pear_child.growth - pear_growth) > 0.001:
		push_error("smoke: the seedling ripened on fallow feed")
		get_tree().quit(1)
		return
	pear_child.fertility = 0.7
	pear_child.moisture = 0.9
	soil.tick(60.0, "clear")
	if pear_child.plant_id != "mosspear" or pear_child.growth <= pear_growth + 0.2 or Economy.coins != pear_coins or Trust.level("nessa") != pear_trust:
		push_error("smoke: a fed mosspear seedling stayed short")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: Array = seed_snap["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(kept[0])
		plot.growth = float(kept[1])
		plot.wilt = float(kept[2])
		plot.plant_id = str(kept[3])
		plot.tilled = bool(kept[4])
		plot.fertility = float(kept[5])
		plot.chem = str(kept[6])
	soil.seed_rain = 0.0
	var dry_pear := soil.get_cell(6, 2)
	var ripe_pear := soil.get_cell(7, 2)
	var dry_bell := soil.get_cell(8, 2)
	var fed_pear := soil.get_cell(6, 3)
	dry_pear.tilled = true
	dry_pear.plant_id = "mosspear"
	dry_pear.growth = 0.3
	dry_pear.fertility = 0.42
	dry_pear.moisture = 0.08
	dry_pear.wilt = 5.2
	dry_pear.chem = "base"
	ripe_pear.tilled = true
	ripe_pear.plant_id = "mosspear"
	ripe_pear.growth = 1.0
	ripe_pear.fertility = 0.7
	ripe_pear.moisture = 0.08
	ripe_pear.wilt = 5.2
	ripe_pear.chem = "base"
	dry_bell.tilled = true
	dry_bell.plant_id = "meadowbell"
	dry_bell.growth = 0.6
	dry_bell.fertility = 0.5
	dry_bell.moisture = 0.08
	dry_bell.wilt = 5.2
	dry_bell.chem = "base"
	fed_pear.tilled = true
	fed_pear.plant_id = "mosspear"
	fed_pear.growth = 0.4
	fed_pear.fertility = 0.7
	fed_pear.moisture = 0.08
	fed_pear.wilt = 5.2
	fed_pear.chem = "base"
	var dry_growth := dry_pear.growth
	soil.tick(60.0, "clear")
	if dry_pear.plant_id != "mosspear" or dry_pear.growth >= dry_growth or dry_pear.wilt < 6.0 or ripe_pear.plant_id != "" or dry_bell.plant_id != "" or fed_pear.plant_id != "" or Economy.coins != pear_coins or Trust.level("nessa") != pear_trust:
		push_error("smoke: a dry hour cleared the waiting mosspear")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: Array = seed_snap["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(kept[0])
		plot.growth = float(kept[1])
		plot.wilt = float(kept[2])
		plot.plant_id = str(kept[3])
		plot.tilled = bool(kept[4])
		plot.fertility = float(kept[5])
		plot.chem = str(kept[6])
	soil.seed_rain = 0.0
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the shower did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if Clock.day != 2 or Clock.weather != "rain" or absf(Clock.hour() - 13.0) > 0.05:
		push_error("smoke: the shower did not reload")
		get_tree().quit(1)
		return
	shift = ""
	_apply_shift(false)
	if shift != "rain" or _person("nessa").waypoints.size() != 3 or _person("nessa").waypoints[0].distance_to(shower_porch) > 0.3 or bram.waypoints.size() != 2:
		push_error("smoke: the rain round did not reload")
		get_tree().quit(1)
		return
	Clock.day = shower_day
	Clock.set_hour(21.0)
	_apply_shift(false)
	var dry := soil.get_cell(2, 2)
	dry.tilled = true
	dry.moisture = 0.08
	var wet := soil.get_cell(3, 2)
	wet.tilled = true
	wet.moisture = 0.9
	_ask_bram()
	if not bram.has_chore or bram.chore.distance_to(GardenLayout.cell_center(2, 2)) > 0.2:
		push_error("smoke: bram ignored the dry bed")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: bram's bed did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if not bram.has_chore or bram_bed != Vector2i(2, 2) or bram.chore.distance_to(GardenLayout.cell_center(2, 2)) > 0.2:
		push_error("smoke: bram's bed did not reload")
		get_tree().quit(1)
		return
	var damp := dry.moisture
	bram.global_position = bram.chore
	_drift_people(0.1, world_snapshot())
	if dry.moisture < damp + 0.2:
		push_error("smoke: bram did not water the bed")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	bram.has_chore = false
	var thirsty := soil.get_cell(4, 2)
	thirsty.tilled = true
	thirsty.moisture = 0.05
	_drift_people(0.1, world_snapshot())
	if not bram.has_chore or bram_bed != Vector2i(4, 2):
		push_error("smoke: bram waited to be asked")
		get_tree().quit(1)
		return
	bram.has_chore = false
	bram_bed = Vector2i(-1, -1)
	thirsty.moisture = 0.74
	var held_water := {}
	for cell in soil.all():
		var plot: SoilCell = cell
		held_water["%d,%d" % [plot.ix, plot.iz]] = plot.moisture
		if plot.tilled:
			plot.moisture = 0.8
	thirsty.plant_id = "reed"
	thirsty.moisture = 0.45
	_drift_people(0.1, world_snapshot())
	if not bram.has_chore or bram_bed != Vector2i(4, 2):
		push_error("smoke: bram missed a wilting reed")
		get_tree().quit(1)
		return
	bram.has_chore = false
	bram_bed = Vector2i(-1, -1)
	thirsty.plant_id = ""
	thirsty.growth = 0.0
	for cell in soil.all():
		var plot: SoilCell = cell
		plot.moisture = float(held_water["%d,%d" % [plot.ix, plot.iz]])
	var fed_snap := {}
	for cell in soil.all():
		var plot: SoilCell = cell
		fed_snap["%d,%d" % [plot.ix, plot.iz]] = [plot.moisture, plot.fertility, plot.plant_id, plot.tilled, plot.growth]
		if plot.tilled:
			plot.moisture = 0.9
	var hungry_bed := soil.get_cell(1, 1)
	hungry_bed.plant_id = "meadowbell"
	hungry_bed.tilled = true
	hungry_bed.growth = 0.5
	hungry_bed.fertility = 0.05
	hungry_bed.moisture = 0.9
	bram.has_chore = false
	bram_feeding = false
	bram_bed = Vector2i(-1, -1)
	_drift_people(0.1, world_snapshot())
	if not bram_feeding or bram_bed != Vector2i(1, 1):
		push_error("smoke: bram missed a tired bed")
		get_tree().quit(1)
		return
	hungry_bed.moisture = 0.05
	bram.has_chore = false
	bram_feeding = false
	bram_bed = Vector2i(-1, -1)
	_drift_people(0.1, world_snapshot())
	if bram_feeding or bram_bed != Vector2i(1, 1):
		push_error("smoke: a tired bed jumped the dry one")
		get_tree().quit(1)
		return
	hungry_bed.moisture = 0.9
	bram.has_chore = false
	bram_feeding = false
	bram_bed = Vector2i(-1, -1)
	_drift_people(0.1, world_snapshot())
	if not bram_feeding or bram_bed != Vector2i(1, 1):
		push_error("smoke: bram did not return to the tired bed")
		get_tree().quit(1)
		return
	var feed_coins := Economy.coins
	var feed_pouch := Economy.count("fertilizer")
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the tired bed did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if not bram_feeding or bram_bed != Vector2i(1, 1):
		push_error("smoke: the tired bed did not reload")
		get_tree().quit(1)
		return
	bram.global_position = bram.chore
	var fed_before := soil.get_cell(1, 1).fertility
	_drift_people(0.1, world_snapshot())
	if soil.get_cell(1, 1).fertility < fed_before + 0.3 or bram_feeding or Economy.coins != feed_coins or Economy.count("fertilizer") != feed_pouch:
		push_error("smoke: bram did not feed the bed")
		get_tree().quit(1)
		return
	soil.get_cell(1, 1).fertility = 0.05
	bram.has_chore = false
	bram_feeding = false
	bram_bed = Vector2i(-1, -1)
	Clock.set_hour(21.0)
	_drift_people(0.1, world_snapshot())
	if bram.has_chore:
		push_error("smoke: bram fed a bed at night")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	for cell in soil.all():
		var plot: SoilCell = cell
		var fed_kept: Array = fed_snap["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(fed_kept[0])
		plot.fertility = float(fed_kept[1])
		plot.plant_id = str(fed_kept[2])
		plot.tilled = bool(fed_kept[3])
		plot.growth = float(fed_kept[4])
	bram.has_chore = false
	bram_feeding = false
	bram_bed = Vector2i(-1, -1)
	Clock.set_hour(21.0)
	var place := _place_stats(world_snapshot())
	if int(place.get("shed_demand", -1)) != 1:
		push_error("smoke: shed demand mismatch")
		get_tree().quit(1)
		return
	var saw_shed := false
	for line in place.get("venues", []):
		if str(line).find("Potting Shed") != -1 and str(line).find("open") != -1:
			saw_shed = true
	if not saw_shed:
		push_error("smoke: potting shed was not open")
		get_tree().quit(1)
		return
	var nessa := _person("nessa")
	nessa.present = true
	var bell_note := ecology.first("bellhelp")
	_on_ecology("%s has come to look." % bell_note.display_name)
	if not nessa.has_chore or nessa.chore.distance_to(bell_note.global_position) > 0.2:
		push_error("smoke: nessa did not watch the arrival")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: nessa's walk did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if not nessa.has_chore or nessa_watch == null or nessa.chore.distance_to(nessa_watch.global_position) > 0.2:
		push_error("smoke: nessa's walk did not reload")
		get_tree().quit(1)
		return
	nessa.global_position = nessa.chore
	_drift_people(0.1, world_snapshot())
	if events.is_empty() or str(events[0]).find("parish book") == -1:
		push_error("smoke: nessa did not write the book")
		get_tree().quit(1)
		return
	var saw_rumour := false
	var saw_bell := false
	for row in _journal_rows(world_snapshot()):
		var entry: Dictionary = row
		if str(entry.get("name", "")) == "A rumour":
			saw_rumour = true
			var rumour_blurb := str(entry.get("blurb", ""))
			if rumour_blurb.find("Bellhelp") != -1 or rumour_blurb.find("Berrypatch") != -1 or rumour_blurb.find("Bulrush") != -1 or rumour_blurb.find("Pegapear") != -1 or (rumour_blurb != "Not sighted yet." and rumour_blurb != _sweet_line() and rumour_blurb != _ripe_cane_line() and rumour_blurb != _wade_line() and rumour_blurb != _dusk_line() and rumour_blurb != _leaf_line()):
				push_error("smoke: rumour blurb leaked")
				get_tree().quit(1)
				return
			for line in entry.get("unmet", []):
				if str(line).find("Bellhelp") != -1 and ecology.rules.rank_of(str(ecology.states.get("bellhelp", "rumoured"))) < ecology.rules.rank_of("sighted"):
					push_error("smoke: hidden name in a rumour")
					get_tree().quit(1)
					return
		if str(entry.get("name", "")) == "Bellhelp":
			saw_bell = true
	if not saw_rumour or not saw_bell:
		push_error("smoke: journal names were wrong")
		get_tree().quit(1)
		return
	var gone := ecology.first("bellhelp")
	ecology.states["bellhelp"] = "visitor"
	gone.queue_free()
	ecology.actors.erase(gone)
	ecology.cooldowns["bellhelp"] = 0.0
	ecology.tick(0.2, world_snapshot())
	var again := ecology.first("bellhelp")
	if again == null or again.life != "repeat" or str(ecology.states.get("bellhelp", "")) != "repeat":
		push_error("smoke: a return was not a repeat visit")
		get_tree().quit(1)
		return
	if ecology.status_line("bellhelp", world_snapshot()) != "back again":
		push_error("smoke: journal did not say they were back")
		get_tree().quit(1)
		return
	var pond := get_node("Pond") as MeshInstance3D
	var span := pond.get_aabb().size.x
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var at := GardenLayout.POND_CENTER + Vector3(cos(angle), 0.0, sin(angle)) * (GardenLayout.POND_RADIUS + 0.5)
		_scoop(at)
	if scooped.size() < 4 or pond.get_aabb().size.x < span + 0.3:
		push_error("smoke: the pond did not widen")
		get_tree().quit(1)
		return
	var lifted := false
	for vert in pond.mesh.get_faces():
		var point: Vector3 = vert
		if GardenLayout.pond_distance(point.x, point.z) <= GardenLayout.POND_RADIUS + 0.05:
			continue
		var ground := GardenLayout.height_at(point.x, point.z)
		if point.y >= ground + 0.02 and point.y <= ground + 0.06:
			lifted = true
			break
	if not lifted:
		push_error("smoke: the new shore stayed under the bank")
		get_tree().quit(1)
		return
	for i in 3:
		_force_plant(8, 5 + i, "reed", 1.0)
	ecology.cooldowns["bulrush"] = 0.0
	ecology.tick(0.2, world_snapshot())
	if int(world_snapshot().get("pond_cells", 0)) < 26 or ecology.first("bulrush") == null:
		push_error("smoke: bulrush did not wade in")
		get_tree().quit(1)
		return
	var rush := ecology.first("bulrush")
	rush.life = "curious"
	rush.site_time = 7.0
	ecology.tick(0.2, world_snapshot())
	if ecology.rules.rank_of(str(ecology.states.get("bulrush", ""))) < ecology.rules.rank_of("visitor"):
		push_error("smoke: bulrush did not become a visitor")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		plot.moisture = maxf(plot.moisture, 0.62)
	ecology.cooldowns["reedic"] = 0.0
	ecology.tick(0.2, world_snapshot())
	if ecology.first("reedic") == null:
		push_error("smoke: reedic did not follow bulrush")
		get_tree().quit(1)
		return
	var reed := ecology.first("reedic")
	Clock.set_hour(15.3)
	rush.global_position = Vector3(5.0, 0.0, -2.2)
	rush.leaving = false
	rush.held = false
	reed.global_position = Vector3(5.0, 0.0, 1.4)
	reed.leaving = false
	reed.held = false
	var reed_far := reed.global_position.distance_to(rush.global_position)
	_update_creatures(0.016)
	reed.tier = 2
	reed._process(2.0)
	if reed.global_position.distance_to(rush.global_position) > reed_far - 0.8:
		push_error("smoke: reedic stayed off the bulrush")
		get_tree().quit(1)
		return
	reed.global_position = Vector3(5.0, 0.0, 1.4)
	var reed_hidden := reed.global_position.distance_to(rush.global_position)
	_update_creatures(0.016)
	reed.tier = 3
	reed._process(2.0)
	if reed.visible or reed.global_position.distance_to(rush.global_position) > reed_hidden - 0.8:
		push_error("smoke: a hidden reedic stayed off the bulrush")
		get_tree().quit(1)
		return
	rush.leaving = true
	reed.goal = Vector3(-1.0, 0.0, -1.0)
	_update_creatures(0.016)
	if reed.goal.distance_to(rush.global_position) < 0.2:
		push_error("smoke: reedic followed a departure")
		get_tree().quit(1)
		return
	rush.leaving = false
	rush.life = "settler"
	rush.site_time = 33.0
	ecology.tick(0.2, world_snapshot())
	if rush.life != "resident" or str(ecology.states.get("bulrush", "")) != "resident":
		push_error("smoke: bulrush did not settle")
		get_tree().quit(1)
		return
	ecology.tick(0.2, world_snapshot())
	var rush_mate: Jelly = null
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "bulrush" and body != rush:
			rush_mate = body
			break
	if rush_mate == null:
		push_error("smoke: bulrush has no company")
		get_tree().quit(1)
		return
	rush_mate.life = "settler"
	rush_mate.site_time = 33.0
	ecology.tick(0.2, world_snapshot())
	ecology.tick(0.2, world_snapshot())
	if str(ecology.states.get("bulrush", "")) != "breeding":
		push_error("smoke: bulrush did not breed")
		get_tree().quit(1)
		return
	var saw_pond := false
	for row in _journal_rows(world_snapshot()):
		if str(row.get("name", "")) == "Bulrush" and str(row.get("status", "")) == "breeding" and str(row.get("romance", "")).find("pair") != -1 and str(row.get("romance", "")).find("young") != -1:
			saw_pond = true
	if not saw_pond:
		push_error("smoke: journal hid the pond pair")
		get_tree().quit(1)
		return
	var young_rush: Jelly = null
	var rush_bodies := 0
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id != "bulrush":
			continue
		rush_bodies += 1
		if body.young:
			young_rush = body
	if young_rush == null or rush_bodies != 3 or events.is_empty() or str(events[0]).find("A young Bulrush") == -1:
		push_error("smoke: bulrush left no young")
		get_tree().quit(1)
		return
	var bank := _attractor_for(ContentDB.species_def("bulrush"))
	rush.global_position = bank
	rush.bite_wait = 2.0
	rush_mate.global_position = bank + Vector3(0.0, 0.0, 3.2)
	rush_mate.bite_wait = 2.0
	var wade := rush_mate.global_position.distance_to(rush.global_position)
	_update_creatures(0.016)
	rush_mate.tier = 2
	rush_mate._process(2.0)
	if rush_mate.global_position.distance_to(rush.global_position) > wade - 0.8:
		push_error("smoke: the pond pair stayed apart")
		get_tree().quit(1)
		return
	rush.bond = 0.55
	var pond_tin := Economy.coins
	ecology.tick(0.2, world_snapshot())
	if rush.life != "bonded" or str(ecology.states.get("bulrush", "")) != "breeding" or Economy.coins != pond_tin or Trust.level("nessa") != 0:
		push_error("smoke: the pond pair left the water")
		get_tree().quit(1)
		return
	saw_pond = false
	for row in _journal_rows(world_snapshot()):
		if str(row.get("name", "")) == "Bulrush" and str(row.get("romance", "")).find("trusts your hands") != -1:
			saw_pond = true
	if not saw_pond:
		push_error("smoke: journal hid the pond bond")
		get_tree().quit(1)
		return
	rush.global_position = Vector3(-4.0, 0.0, -2.0)
	rush.bite_wait = 2.0
	var water_far := rush.global_position.distance_to(bank)
	_update_creatures(0.016)
	var shore := _shore_point(0.0)
	if rush.use_berth or rush.goal.distance_to(shore) > 0.2 or GardenLayout.pond_distance(shore.x, shore.z) < GardenLayout.POND_RADIUS:
		push_error("smoke: a bonded bulrush left the bank")
	young_rush.global_position = GardenLayout.POND_CENTER
	young_rush.leaving = false
	young_rush.held = false
	young_rush.wants_sleep = false
	young_rush.use_berth = false
	_update_creatures(0.016)
	if GardenLayout.pond_distance(young_rush.goal.x, young_rush.goal.z) < GardenLayout.POND_RADIUS + 0.4:
		push_error("smoke: the young bulrush cut across the pond")
		get_tree().quit(1)
		return
	var far_bank := _shore_point(PI)
	young_rush.global_position = far_bank
	_update_creatures(0.016)
	var young_goal := young_rush.goal
	if GardenLayout.pond_distance(young_goal.x, young_goal.z) < GardenLayout.POND_RADIUS + 0.4 or young_goal.distance_to(shore) < 0.4:
		push_error("smoke: the young bulrush cut across the pond")
		get_tree().quit(1)
		return
		get_tree().quit(1)
		return
	rush._coast(2.0)
	if rush.global_position.distance_to(bank) > water_far - 0.5:
		push_error("smoke: a bonded bulrush stayed on the lawn")
		get_tree().quit(1)
		return
	var wade_tin := Economy.coins
	var wade_trust := Trust.level("nessa")
	var wade_spot := bank + Vector3(0.8, 0.0, 0.0)
	rush.global_position = wade_spot
	rush.goal = bank
	rush.use_berth = false
	rush.wants_sleep = false
	rush.leaving = false
	rush.held = false
	rush._coast(0.05)
	var wade_line := _bowl_line(rush.global_position)
	if absf(rush.global_position.y - wade_line) > 0.04:
		push_error("smoke: bulrush stood on the pond")
		get_tree().quit(1)
		return
	rush.global_position = Vector3(-4.0, 0.0, -2.0)
	rush.goal = bank
	rush._coast(0.05)
	if absf(rush.global_position.y) > 0.02:
		push_error("smoke: bulrush waded the lawn")
		get_tree().quit(1)
		return
	rush.global_position = bank
	rush.berth = bank
	rush.use_berth = true
	rush._coast(0.05)
	if absf(rush.global_position.y) > 0.02:
		push_error("smoke: a home put bulrush under the water")
		get_tree().quit(1)
		return
	rush.use_berth = false
	var disc_at := reed.global_position
	reed.global_position = bank + Vector3(0.6, 0.0, 0.2)
	reed.goal = bank
	reed.use_berth = false
	reed.wants_sleep = false
	reed.leaving = false
	reed.held = false
	reed._coast(0.05)
	var disc_line := _bowl_line(reed.global_position)
	if absf(reed.global_position.y - disc_line) > 0.04 or Economy.coins != wade_tin or Trust.level("nessa") != wade_trust:
		push_error("smoke: reedic stood on the pond")
		get_tree().quit(1)
		return
	reed.global_position = disc_at
	var young_at := young_rush.global_position
	young_rush.global_position = bank + Vector3(0.4, 0.0, -0.3)
	young_rush.goal = bank
	young_rush.use_berth = false
	young_rush.wants_sleep = false
	young_rush.leaving = false
	young_rush.held = false
	young_rush._coast(0.05)
	var young_line := _bowl_line(young_rush.global_position)
	if absf(young_rush.global_position.y - young_line) > 0.04:
		push_error("smoke: the young bulrush stood on the pond")
		get_tree().quit(1)
		return
	young_rush.global_position = young_at
	rush.global_position = Vector3(-4.0, 0.0, -2.0)
	var pond_kit := Vector3(-6.0, 0.0, 4.0)
	home_points.append(pond_kit)
	Clock.set_hour(21.0)
	rush.global_position = Vector3(-4.0, 0.0, -2.0)
	_update_creatures(0.016)
	if not rush.wants_sleep or not rush.use_berth or rush.goal.distance_to(pond_kit) > 0.2:
		push_error("smoke: the pond pair skipped the kit")
		get_tree().quit(1)
		return
	home_points.pop_back()
	Clock.set_hour(15.3)
	rush.wants_sleep = false
	rush.use_berth = false
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the pond pair did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	rush = null
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "bulrush" and body.life == "bonded":
			rush = body
			break
	if rush == null or rush.bond < 0.55 or str(ecology.states.get("bulrush", "")) != "breeding" or int(ecology.resident_counts().get("bulrush", 0)) < 2:
		push_error("smoke: the pond pair did not reload")
		get_tree().quit(1)
		return
	rush.global_position = Vector3(-4.0, 0.0, -2.0)
	rush.bite_wait = 2.0
	_update_creatures(0.016)
	if rush.goal.distance_to(_shore_point(0.0)) > 0.2:
		push_error("smoke: the pond bond did not reload")
		get_tree().quit(1)
		return
	Clock.set_hour(21.0)
	_force_plant(4, 2, "bramble", 1.0)
	_force_plant(5, 2, "bramble", 1.0)
	ecology.cooldowns["berrypatch"] = 0.0
	ecology.tick(0.2, world_snapshot())
	if ecology.first("berrypatch") == null:
		push_error("smoke: berrypatch did not come to the canes")
		get_tree().quit(1)
		return
	_force_plant(4, 3, "bramble", 1.0)
	_feed_beds()
	ecology.cooldowns["grapling"] = 0.0
	ecology.tick(0.2, world_snapshot())
	if float(world_snapshot()["fertility"]) < 0.55 or ecology.first("grapling") == null:
		push_error("smoke: grapling did not follow the fed beds")
		get_tree().quit(1)
		return
	var keeper := ecology.first("bellhelp")
	keeper.life = "repeat"
	keeper.site_time = 9.0
	ecology.tick(0.2, world_snapshot())
	keeper.site_time = 33.0
	ecology.tick(0.2, world_snapshot())
	if str(ecology.states.get("bellhelp", "")) != "resident":
		push_error("smoke: bellhelp did not settle")
		get_tree().quit(1)
		return
	ecology.tick(0.2, world_snapshot())
	var partner: Jelly = null
	for actor in ecology.actors:
		var body: Jelly = actor
		if body != keeper and body.species_id == "bellhelp":
			partner = body
	if partner == null:
		push_error("smoke: bellhelp has no company")
		get_tree().quit(1)
		return
	partner.site_time = 33.0
	# ponytail: one rank per tick, and romance reads the opening snapshot, so breeding lands on the fourth tick.
	ecology.tick(0.2, world_snapshot())
	ecology.tick(0.2, world_snapshot())
	ecology.tick(0.2, world_snapshot())
	ecology.tick(0.2, world_snapshot())
	if str(ecology.states.get("bellhelp", "")) != "breeding" or ecology.status_line("bellhelp", world_snapshot()) != "breeding":
		push_error("smoke: bellhelp did not breed")
		get_tree().quit(1)
		return
	var saw_pair := false
	for row in _journal_rows(world_snapshot()):
		if str(row.get("name", "")) == "Bellhelp" and str(row.get("status", "")) == "breeding" and str(row.get("romance", "")).find("pair") != -1 and str(row.get("romance", "")).find("young") != -1:
			saw_pair = true
	if not saw_pair:
		push_error("smoke: journal hid the pair")
		get_tree().quit(1)
		return
	var young_bell: Jelly = null
	var bell_bodies := 0
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id != "bellhelp":
			continue
		bell_bodies += 1
		if body.young:
			young_bell = body
	var young_tin := Economy.coins
	var young_trust := Trust.level("nessa")
	if young_bell == null or bell_bodies != 3 or events.is_empty() or str(events[0]).find("A young Bellhelp") == -1 or young_bell.life != "curious":
		push_error("smoke: bellhelp left no young")
		get_tree().quit(1)
		return
	young_bell.global_position = Vector3(10.5, 0.0, -8.5)
	young_bell.leaving = false
	young_bell.held = false
	young_bell.reduce_motion = true
	young_bell.tier = 0
	young_bell._process(0.016)
	if young_bell.scale.x > 0.7:
		push_error("smoke: the young bellhelp is full size")
		get_tree().quit(1)
		return
	young_bell.reduce_motion = false
	var young_far := young_bell.global_position.distance_to(keeper.global_position)
	_update_creatures(0.016)
	young_bell.tier = 2
	young_bell._process(2.0)
	if young_bell.global_position.distance_to(keeper.global_position) > young_far - 0.8:
		push_error("smoke: the young bellhelp stayed off the pair")
		get_tree().quit(1)
		return
	young_bell.tier = 0
	young_bell.reduce_motion = true
	young_bell._process(0.016)
	young_bell.reduce_motion = false
	if young_bell.scale.x < 0.6 or young_bell.scale.x > 0.75:
		push_error("smoke: the young bellhelp did not grow in place")
		get_tree().quit(1)
		return
	var bell_growth := {}
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "meadowbell":
			continue
		bell_growth["%d,%d" % [plot.ix, plot.iz]] = plot.growth
		plot.growth = 0.2
	var cool: Dictionary = ecology.cooldowns.duplicate()
	for id in ContentDB.species_order:
		ecology.cooldowns[id] = 5.0
	var farewell_was := nessa_farewell
	ecology.tick(0.2, world_snapshot())
	ecology.cooldowns = cool
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: String = "%d,%d" % [plot.ix, plot.iz]
		if bell_growth.has(kept):
			plot.growth = float(bell_growth[kept])
	if young_bell.leaving or nessa_farewell != farewell_was or events.is_empty() or str(events[0]).find("slips") != -1 or Economy.coins != young_tin or Trust.level("nessa") != young_trust:
		push_error("smoke: the young bellhelp left the pair")
		get_tree().quit(1)
		return
	if int(ecology.resident_counts().get("bellhelp", 0)) < 2:
		push_error("smoke: bellhelp pair is short")
		get_tree().quit(1)
		return
	keeper.global_position = Vector3(-3.2, 0.0, -1.6)
	partner.global_position = Vector3(-3.2, 0.0, 1.6)
	var apart := partner.global_position.distance_to(keeper.global_position)
	_update_creatures(0.016)
	partner.tier = 2
	partner._process(2.0)
	if partner.global_position.distance_to(keeper.global_position) > apart - 0.8:
		push_error("smoke: the pair stayed apart")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: breeding save failed")
		get_tree().quit(1)
		return
	var bred := SaveGame.read_slot(1)
	apply_state(bred)
	if str(ecology.states.get("bellhelp", "")) != "breeding" or ecology.status_line("bellhelp", world_snapshot()) != "breeding":
		push_error("smoke: breeding did not reload")
		get_tree().quit(1)
		return
	if int(ecology.resident_counts().get("bellhelp", 0)) < 2:
		push_error("smoke: the pair did not reload")
		get_tree().quit(1)
		return
	young_bell = null
	bell_bodies = 0
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id != "bellhelp":
			continue
		bell_bodies += 1
		if body.young:
			young_bell = body
	if young_bell == null or bell_bodies != 3 or not bool(ecology.young_spawned.get("bellhelp", false)):
		push_error("smoke: the young bellhelp did not reload")
		get_tree().quit(1)
		return
	var lead := ecology.first("bellhelp")
	var mate: Jelly = null
	for actor in ecology.actors:
		var mate_body: Jelly = actor
		if mate_body != lead and mate_body.species_id == "bellhelp" and ecology.rules.rank_of(mate_body.life) >= ecology.rules.rank_of("resident"):
			mate = mate_body
	if mate == null:
		push_error("smoke: the reloaded partner is missing")
		get_tree().quit(1)
		return
	lead.global_position = Vector3(-3.2, 0.0, -1.6)
	mate.global_position = Vector3(-3.2, 0.0, 1.6)
	var gap := mate.global_position.distance_to(lead.global_position)
	_update_creatures(0.016)
	mate.tier = 2
	mate._process(2.0)
	if mate.global_position.distance_to(lead.global_position) > gap - 0.8:
		push_error("smoke: the reloaded pair stayed apart")
		get_tree().quit(1)
		return
	var behind: Vector3 = camera.global_position + camera.global_transform.basis.z * 8.0
	behind.y = 0.0
	lead.global_position = behind + Vector3(-5.0, 0.0, 0.0)
	mate.global_position = behind + Vector3(5.0, 0.0, 0.0)
	var lead_kit := lead.global_position + Vector3(0.0, 0.0, 0.4)
	var mate_kit := mate.global_position + Vector3(0.0, 0.0, 0.4)
	home_points.append(lead_kit)
	home_points.append(mate_kit)
	var split := mate.global_position.distance_to(lead.global_position)
	_update_creatures(0.016)
	if not lead.use_berth or not mate.use_berth or lead.berth.distance_to(mate.berth) > 0.05:
		push_error("smoke: the pair did not share a home")
		get_tree().quit(1)
		return
	if lead.berth.distance_to(lead_kit) > 0.05:
		push_error("smoke: the shared home left the first resident")
		get_tree().quit(1)
		return
	mate._process(2.0)
	if mate.global_position.distance_to(lead.global_position) > split - 0.8:
		push_error("smoke: the pair did not walk home together")
		get_tree().quit(1)
		return
	home_points.pop_back()
	home_points.pop_back()
	lead.use_berth = false
	mate.use_berth = false
	lead.global_position = Vector3(-3.2, 0.0, -1.6)
	mate.global_position = Vector3(-3.2, 0.0, 1.6)
	young_bell.site_time = 8.0
	ecology._promote(young_bell, ContentDB.species_def("bellhelp"))
	young_bell.reduce_motion = true
	young_bell.tier = 0
	young_bell._process(0.016)
	var grown_bodies := 0
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "bellhelp":
			grown_bodies += 1
	if young_bell.young or young_bell.life != "visitor" or young_bell.scale.x < 0.9 or grown_bodies != 3 or Economy.coins != young_tin or Trust.level("nessa") != young_trust:
		push_error("smoke: the young bellhelp did not grow")
		get_tree().quit(1)
		return
	ecology.cooldowns["cirlark"] = 0.0
	ecology.tick(0.2, world_snapshot())
	if ecology.first("cirlark") == null:
		push_error("smoke: cirlark did not come for the resident")
		get_tree().quit(1)
		return
	if not _seed_open("nightlantern_seed"):
		push_error("smoke: the opening night-loam left the lantern seed shut")
		get_tree().quit(1)
		return
	var shop_lamp := soil.get_cell(6, 4)
	var shop_chem := shop_lamp.chem
	shop_lamp.chem = "base"
	if _seed_open("nightlantern_seed") or _seed_line() != "":
		push_error("smoke: nightlantern was for sale before night-loam")
		get_tree().quit(1)
		return
	shop_lamp.chem = shop_chem
	if _seed_line() != "The nightlantern seed is open.":
		push_error("smoke: the opening loam hid the seed line")
		get_tree().quit(1)
		return
	var nip := ecology.first("dusknip")
	if nip == null:
		push_error("smoke: dusknip did not follow bellhelp")
		get_tree().quit(1)
		return
	nip.life = "curious"
	nip.site_time = 7.0
	ecology.tick(0.2, world_snapshot())
	nip.site_time = 19.0
	ecology.tick(0.2, world_snapshot())
	nip.site_time = 33.0
	ecology.tick(0.2, world_snapshot())
	if int(world_snapshot().get("chem", {}).get("nightloam", 0)) < 4 or not _seed_open("nightlantern_seed"):
		push_error("smoke: night-loam did not unwrap the nightlantern")
		get_tree().quit(1)
		return
	_force_plant(0, 3, "peach", 1.0)
	_force_plant(1, 3, "nightlantern", 1.0)
	ecology.cooldowns["pegapear"] = 0.0
	ecology.tick(0.2, world_snapshot())
	if ecology.first("pegapear") == null:
		push_error("smoke: pegapear did not come at dusk")
		get_tree().quit(1)
		return
	_force_plant(6, 2, "mosspear", 1.0)
	_force_plant(6, 3, "mosspear", 1.0)
	_feed_beds()
	ecology.cooldowns["gushorn"] = 0.0
	ecology.tick(0.2, world_snapshot())
	if int(world_snapshot().get("chem", {}).get("nightloam", 0)) < 4 or ecology.first("gushorn") == null:
		push_error("smoke: gushorn did not come for the night-loam")
		get_tree().quit(1)
		return
	nessa.present = false
	place = _place_stats(world_snapshot())
	if int(place.get("tea_demand", -1)) != 0:
		push_error("smoke: tea demand before nessa")
		get_tree().quit(1)
		return
	nessa.present = true
	place = _place_stats(world_snapshot())
	if int(place.get("tea_demand", -1)) != 1:
		push_error("smoke: tea demand mismatch")
		get_tree().quit(1)
		return
	var saw_tea := false
	for line in place.get("venues", []):
		if str(line).find("Hedge Tea House") != -1 and str(line).find("open") != -1:
			saw_tea = true
		if str(line).find("Hedge Tea House") != -1 and str(line).find("not built") != -1:
			saw_tea = false
	if not saw_tea:
		push_error("smoke: tea house was not open")
		get_tree().quit(1)
		return
	nessa.has_chore = false
	Clock.set_hour(15.3)
	_apply_shift(false)
	var porch := GardenLayout.TEA + Vector3(0, 0, -1.15)
	if nessa.waypoints.is_empty() or nessa.waypoints[0].distance_to(porch) > 0.3:
		push_error("smoke: nessa's day round missed the tea house")
		get_tree().quit(1)
		return
	nessa.global_position = porch + Vector3(0, 0, -2.4)
	var tea_far := nessa.global_position.distance_to(porch)
	nessa._process(6.0)
	if nessa.global_position.distance_to(porch) > tea_far - 0.8:
		push_error("smoke: nessa did not walk to the tea house")
		get_tree().quit(1)
		return
	if int(place.get("hut_demand", -1)) != 0 or Trust.level("nessa") != 0:
		push_error("smoke: hut demand before the notes")
		get_tree().quit(1)
		return
	accept_nessa()
	var shelf := GardenLayout.HUT + Vector3(0, 0, -1.05)
	if not nessa_filing or not nessa.has_chore or nessa.chore.distance_to(shelf) > 0.3:
		push_error("smoke: nessa did not head for the hut")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the hut walk did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if not nessa_filing or not nessa.has_chore or nessa.chore.distance_to(shelf) > 0.3:
		push_error("smoke: the hut walk did not reload")
		get_tree().quit(1)
		return
	nessa.global_position = nessa.chore
	_drift_people(0.1, world_snapshot())
	var filed: Dictionary = Trust.audit[Trust.audit.size() - 1] if not Trust.audit.is_empty() else {}
	if Trust.level("nessa") != 1 or nessa_filing or str(filed.get("action", "")) != "file_parish_notes" or bool(filed.get("external", false)):
		push_error("smoke: the hut notes left the parish")
		get_tree().quit(1)
		return
	place = _place_stats(world_snapshot())
	if int(place.get("hut_demand", -1)) != 1:
		push_error("smoke: hut demand mismatch")
		get_tree().quit(1)
		return
	var saw_hut := false
	for line in place.get("venues", []):
		if str(line).find("Research Hut") != -1 and str(line).find("open") != -1:
			saw_hut = true
		if str(line).find("Research Hut") != -1 and str(line).find("not built") != -1:
			saw_hut = false
	if not saw_hut:
		push_error("smoke: research hut was not open")
		get_tree().quit(1)
		return
	var saw_nessa_home := false
	for row in _people_rows(world_snapshot()):
		if str(row.get("name", "")).find("Nessa") != -1 and str(row.get("home", "")) == "The research hut":
			saw_nessa_home = true
	if not saw_nessa_home:
		push_error("smoke: the directory left nessa unsettled")
		get_tree().quit(1)
		return
	var hut_tin := Economy.coins
	Clock.set_hour(21.0)
	_apply_shift(false)
	if not shift.begins_with("night") or nessa.waypoints.size() != 1 or nessa.waypoints[0].distance_to(shelf) > 0.3:
		push_error("smoke: nessa's night home missed the hut")
		get_tree().quit(1)
		return
	nessa.has_chore = false
	nessa.global_position = GardenLayout.GATE
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: nessa's night home did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	shift = ""
	_apply_shift(false)
	if Trust.level("nessa") != 1 or Economy.coins != hut_tin or nessa.waypoints.size() != 1 or nessa.waypoints[0].distance_to(shelf) > 0.3:
		push_error("smoke: nessa's night home did not reload")
		get_tree().quit(1)
		return
	var hut_far := nessa.global_position.distance_to(shelf)
	nessa.pause = 0.0
	nessa._process(3.0)
	if nessa.global_position.distance_to(shelf) > hut_far - 0.8:
		push_error("smoke: nessa did not walk home to the hut")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	_apply_shift(false)
	if int(place.get("foundry_demand", -1)) != 0 or int(place.get("hall_demand", -1)) != 0:
		push_error("smoke: foundry demand before the draft")
		get_tree().quit(1)
		return
	Trust.levels["nessa"] = 0
	accept_draft()
	if nessa_drafting or Trust.has_action("parish_draft"):
		push_error("smoke: a draft was kept before the notes")
		get_tree().quit(1)
		return
	Trust.levels["nessa"] = 1
	var tin := Economy.coins
	accept_draft()
	var desk := GardenLayout.FOUNDRY + Vector3(0, 0, -0.95)
	if not nessa_drafting or nessa.chore.distance_to(desk) > 0.3:
		push_error("smoke: nessa did not head for the foundry")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the foundry walk did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if not nessa_drafting or Economy.coins != tin or nessa.chore.distance_to(desk) > 0.3:
		push_error("smoke: the foundry walk did not reload")
		get_tree().quit(1)
		return
	nessa.global_position = nessa.chore
	_drift_people(0.1, world_snapshot())
	var draft: Dictionary = Trust.audit[Trust.audit.size() - 1] if not Trust.audit.is_empty() else {}
	if nessa_drafting or Economy.coins != tin or Trust.level("nessa") != 1:
		push_error("smoke: the draft changed the tin or the trust")
		get_tree().quit(1)
		return
	if str(draft.get("action", "")) != "parish_draft" or bool(draft.get("external", true)) or int(draft.get("cost", -1)) != 0:
		push_error("smoke: the draft left the parish")
		get_tree().quit(1)
		return
	place = _place_stats(world_snapshot())
	if int(place.get("foundry_demand", -1)) != 1:
		push_error("smoke: foundry demand mismatch")
		get_tree().quit(1)
		return
	var saw_foundry := false
	for line in place.get("venues", []):
		if str(line).find("Media Foundry") != -1 and str(line).find("open") != -1:
			saw_foundry = true
		if str(line).find("Media Foundry") != -1 and str(line).find("not built") != -1:
			saw_foundry = false
	if not saw_foundry:
		push_error("smoke: media foundry was not open")
		get_tree().quit(1)
		return
	if int(place.get("hall_demand", -1)) != 1:
		push_error("smoke: the hall did not post the draft")
		get_tree().quit(1)
		return
	var saw_hall := false
	var saw_notice := false
	for line in place.get("venues", []):
		if str(line).find("Town Hall") != -1 and str(line).find("open") != -1:
			saw_hall = true
		if str(line).find("Town Hall") != -1 and str(line).find("not built") != -1:
			saw_hall = false
	for notice in place.get("notices", []):
		if str(notice).find("Nothing was sent") != -1:
			saw_notice = true
	if not saw_hall or not saw_notice:
		push_error("smoke: town hall board was bare")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	var hand := ecology.first("bellhelp")
	if hand == null or hand.life != "resident":
		push_error("smoke: no resident to bond")
		get_tree().quit(1)
		return
	hand.bond = 0.55
	ecology.tick(0.2, world_snapshot())
	if hand.life != "bonded" or str(ecology.states.get("bellhelp", "")) != "breeding":
		push_error("smoke: the pet did not bond")
		get_tree().quit(1)
		return
	var saw_hands := false
	for row in _journal_rows(world_snapshot()):
		if str(row.get("status", "")) == "breeding" and str(row.get("romance", "")).find("pair") != -1 and str(row.get("romance", "")).find("trusts your hands") != -1:
			saw_hands = true
	if not saw_hands:
		push_error("smoke: journal hid the bond")
		get_tree().quit(1)
		return
	var stand := camera.target
	stand.y = 0.0
	hand.global_position = stand + Vector3(3.2, 0.0, 0.0)
	var hand_far := hand.global_position.distance_to(stand)
	_update_creatures(0.016)
	if hand.use_berth:
		push_error("smoke: the bond sent them home")
		get_tree().quit(1)
		return
	hand.tier = 2
	hand._process(2.0)
	if hand.global_position.distance_to(stand) > hand_far - 0.8:
		push_error("smoke: the bonded resident stayed away")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the bond did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	hand = ecology.first("bellhelp")
	if hand == null or hand.life != "bonded" or hand.bond < 0.55 or str(ecology.states.get("bellhelp", "")) != "breeding":
		push_error("smoke: the bond did not reload")
		get_tree().quit(1)
		return
	_force_plant(1, 1, "meadowbell", 1.0)
	var bite_plot := soil.get_cell(1, 1)
	hand.global_position = GardenLayout.cell_center(1, 1)
	hand.bite_wait = 0.0
	var ripe := int(world_snapshot()["mature"].get("meadowbell", 0))
	var who_tin := Economy.coins
	var who_trust := Trust.level("nessa")
	_browse(0.1)
	if bite_plot.growth > 0.6 or hand.bite_wait < 3.0 or int(world_snapshot()["mature"].get("meadowbell", 0)) >= ripe:
		push_error("smoke: the resident did not bite")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the bite did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	hand = ecology.first("bellhelp")
	bite_plot = soil.get_cell(1, 1)
	var who_lines: Array = _bite_lines()
	var who_line := ""
	if not who_lines.is_empty():
		who_line = str(who_lines[0])
	if hand == null or bite_plot.growth > 0.6 or hand.bite_wait < 3.0 or bite_plot.eaten_by != hand.display_name or who_line != "Bellhelp ate the Meadowbell." or Trust.level("nessa") != who_trust or Economy.coins != who_tin:
		push_error("smoke: the bite did not reload")
		get_tree().quit(1)
		return
	soil.tick(50.0, "mist")
	if bite_plot.eaten_by != "" or bite_plot.taken or bite_plot.growth < 1.0:
		push_error("smoke: a ripe bed kept who ate it")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	hand = ecology.first("bellhelp")
	bite_plot = soil.get_cell(1, 1)
	if hand == null or bite_plot.eaten_by != hand.display_name:
		push_error("smoke: the journal forgot who ate")
		get_tree().quit(1)
		return
	var stay_other := soil.get_cell(3, 2)
	var stay_id := stay_other.plant_id
	var stay_growth := stay_other.growth
	var stay_till := stay_other.tilled
	var stay_moist := stay_other.moisture
	var stay_feed := stay_other.fertility
	var stay_taken := stay_other.taken
	var stay_who := stay_other.eaten_by
	var stay_wilt := stay_other.wilt
	_force_plant(3, 2, "meadowbell", 1.0)
	var stay_at := GardenLayout.cell_center(1, 1)
	hand.bite_wait = 0.0
	hand.global_position = GardenLayout.cell_center(3, 2)
	_browse(0.1)
	if soil.get_cell(3, 2).growth < 0.95 or bite_plot.growth > 0.6 or bite_plot.eaten_by != hand.display_name or Trust.level("nessa") != who_trust or Economy.coins != who_tin:
		push_error("smoke: a short meal did not hold them")
		get_tree().quit(1)
		return
	hand.global_position = camera.target
	hand.global_position.y = 0.0
	_update_creatures(0.016)
	if hand.goal.distance_to(stay_at) > 0.2 or hand.goal.distance_to(GardenLayout.cell_center(3, 2)) < 0.3:
		push_error("smoke: the resident left the fruit they ate")
		get_tree().quit(1)
		return
	stay_other.plant_id = stay_id
	stay_other.growth = stay_growth
	stay_other.tilled = stay_till
	stay_other.moisture = stay_moist
	stay_other.fertility = stay_feed
	stay_other.taken = stay_taken
	stay_other.eaten_by = stay_who
	stay_other.wilt = stay_wilt
	hand.bite_wait = 4.0
	for cell in soil.all():
		var bed: SoilCell = cell
		if bed.plant_id == "meadowbell":
			bed.growth = 0.4
	_force_plant(1, 1, "meadowbell", 1.0)
	var fruit := GardenLayout.cell_center(1, 1)
	hand.global_position = camera.target
	hand.global_position.y = 0.0
	hand.bite_wait = 0.0
	var fruit_far := hand.global_position.distance_to(fruit)
	if not camera.is_position_in_frustum(hand.global_position) or fruit_far < 2.0:
		push_error("smoke: the ripe plant was already underfoot")
		get_tree().quit(1)
		return
	_update_creatures(0.016)
	if hand.goal.distance_to(fruit) > 0.2:
		push_error("smoke: a hungry resident did not face the fruit")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the hungry walk did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	hand = ecology.first("bellhelp")
	if hand == null or hand.bite_wait > 0.05 or soil.get_cell(1, 1).growth < 1.0:
		push_error("smoke: the hungry walk did not reload")
		get_tree().quit(1)
		return
	hand.global_position = camera.target
	hand.global_position.y = 0.0
	fruit_far = hand.global_position.distance_to(fruit)
	_update_creatures(0.016)
	hand._coast(2.0)
	if hand.global_position.distance_to(fruit) > fruit_far - 0.5 or soil.get_cell(1, 1).growth < 1.0:
		push_error("smoke: a hungry resident stayed off the fruit")
		get_tree().quit(1)
		return
	hand.global_position = fruit
	_browse(0.1)
	if soil.get_cell(1, 1).growth > 0.6 or hand.bite_wait < 3.0:
		push_error("smoke: a resident who reached the fruit did not bite")
		get_tree().quit(1)
		return
	_place_home(Vector3(8.0, 0.0, 4.0))
	var shelter := home_root.get_child(home_root.get_child_count() - 1)
	var bright := false
	for child in shelter.get_children():
		var part := child as MeshInstance3D
		if part == null:
			continue
		var paint := part.material_override as StandardMaterial3D
		var albedo := paint.albedo_color
		if albedo.r > 0.85 or albedo.g > 0.85 or albedo.b > 0.85 or paint.specular_mode != BaseMaterial3D.SPECULAR_DISABLED:
			bright = true
	if shelter.name != "HomeKit" or bright:
		push_error("smoke: the home kit is a bright box")
		get_tree().quit(1)
		return
	shelter.free()
	for cell in soil.all():
		var bed: SoilCell = cell
		if bed.plant_id == "meadowbell":
			bed.growth = 0.4
	_force_plant(4, 3, "meadowbell", 1.0)
	var off_plot := soil.get_cell(4, 3)
	hand.global_position = camera.global_position + camera.global_transform.basis.z * 8.0
	hand.global_position.y = 0.0
	hand.bite_wait = 0.0
	if camera.is_position_in_frustum(hand.global_position) or hand.global_position.distance_to(GardenLayout.cell_center(4, 3)) < 1.6:
		push_error("smoke: the hidden resident was still by the plant")
		get_tree().quit(1)
		return
	_browse(0.1)
	if off_plot.growth < 0.95 or soil.get_cell(1, 1).eaten_by != hand.display_name or hand.bite_wait > 0.05:
		push_error("smoke: a short meal let them bite off screen")
		get_tree().quit(1)
		return
	soil.get_cell(1, 1).eaten_by = ""
	soil.get_cell(1, 1).taken = false
	_browse(0.1)
	if off_plot.growth > 0.6 or hand.bite_wait < 3.0:
		push_error("smoke: a hidden resident left the ripe plant")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the hidden bite did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	hand = ecology.first("bellhelp")
	off_plot = soil.get_cell(4, 3)
	if hand == null or off_plot.growth > 0.6 or hand.bite_wait < 3.0:
		push_error("smoke: the hidden bite did not reload")
		get_tree().quit(1)
		return
	_force_plant(2, 2, "meadowbell", 1.0)
	var dry_bed := soil.get_cell(2, 2)
	dry_bed.moisture = 0.05
	_sync_plants()
	var dry_view: PlantView = plant_views["2,2"]
	if dry_view.scale.y > dry_view.scale.x * 0.8:
		push_error("smoke: a dry plant stood up")
		get_tree().quit(1)
		return
	dry_bed.moisture = 0.8
	_sync_plants()
	if absf(dry_view.scale.y - dry_view.scale.x) > 0.05:
		push_error("smoke: a watered plant stayed limp")
		get_tree().quit(1)
		return
	dry_bed.fertility = 0.05
	_sync_plants()
	if dry_view.scale.y > dry_view.scale.x * 0.9 or absf(dry_view.rotation.z) > 0.05:
		push_error("smoke: a tired plant looked watered or dry")
		get_tree().quit(1)
		return
	dry_bed.fertility = 0.38
	_sync_plants()
	if absf(dry_view.scale.y - dry_view.scale.x) > 0.05:
		push_error("smoke: a fed plant stayed short")
		get_tree().quit(1)
		return
	dry_bed.moisture = 0.05
	soil.tick(60.0, "clear")
	if dry_bed.growth > 0.9:
		push_error("smoke: a dry crop kept its height")
		get_tree().quit(1)
		return
	dry_bed.moisture = 1.0
	soil.tick(60.0, "clear")
	if dry_bed.growth < 0.95:
		push_error("smoke: a watered crop stayed short")
		get_tree().quit(1)
		return
	if dry_bed.wilt > 0.01:
		push_error("smoke: a watered bed was dying")
		get_tree().quit(1)
		return
	dry_bed.moisture = 0.1
	dry_bed.wilt = 3.2
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the drought did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	dry_bed = soil.get_cell(2, 2)
	if dry_bed.plant_id != "meadowbell" or absf(dry_bed.wilt - 3.2) > 0.05:
		push_error("smoke: the drought did not reload")
		get_tree().quit(1)
		return
	dry_bed.moisture = 0.05
	dry_bed.wilt = 5.2
	soil.tick(60.0, "clear")
	if dry_bed.plant_id != "":
		push_error("smoke: a long drought left the crop")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "bramble":
			plot.growth = 0.2
	var guest := ecology.force_spawn("berrypatch")
	guest.life = "visitor"
	guest.global_position = Vector3(-4.0, 0.0, -2.0)
	ecology.tick(0.1, world_snapshot())
	if not guest.leaving:
		push_error("smoke: a visitor stayed after the canes failed")
		get_tree().quit(1)
		return
	if not nessa_farewell or not nessa.has_chore or nessa.chore.distance_to(GardenLayout.GATE) > 0.2 or Trust.level("nessa") != 1 or Economy.coins != tin:
		push_error("smoke: nessa did not note the departure")
		get_tree().quit(1)
		return
	var gate_far := guest.global_position.distance_to(GardenLayout.GATE)
	guest._full(1.5)
	if guest.global_position.distance_to(GardenLayout.GATE) > gate_far - 0.5:
		push_error("smoke: a visitor did not walk to the gate")
		get_tree().quit(1)
		return
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "berrypatch":
			body.leaving = true
			body.goal = GardenLayout.GATE
	ecology.states["berrypatch"] = "visitor"
	if ecology.status_line("berrypatch", world_snapshot()) != "heading for the hedge":
		push_error("smoke: the journal kept a visitor who was leaving")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the departure did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	var departed: Jelly = null
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "berrypatch" and body.leaving:
			departed = body
			break
	if departed == null or departed.goal.distance_to(GardenLayout.GATE) > 0.2:
		push_error("smoke: the departure did not reload")
		get_tree().quit(1)
		return
	if not nessa_farewell or not nessa.has_chore or nessa.chore.distance_to(GardenLayout.GATE) > 0.2 or Trust.level("nessa") != 1 or Economy.coins != tin:
		push_error("smoke: nessa's departure note did not reload")
		get_tree().quit(1)
		return
	departed.global_position = Vector3(-4.0, 0.0, -2.0)
	gate_far = departed.global_position.distance_to(GardenLayout.GATE)
	departed._coast(1.5)
	if departed.global_position.distance_to(GardenLayout.GATE) > gate_far - 0.5:
		push_error("smoke: a hidden visitor did not walk to the gate")
		get_tree().quit(1)
		return
	nessa.global_position = GardenLayout.GATE
	_drift_people(0.1, world_snapshot())
	if nessa_farewell or nessa.has_chore or Trust.level("nessa") != 1 or Economy.coins != tin:
		push_error("smoke: the departure note left the parish")
		get_tree().quit(1)
		return
	if events.is_empty() or str(events[0]).find("departure") == -1:
		push_error("smoke: nessa did not write the departure")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "bramble":
			plot.growth = 1.0
	departed.global_position = Vector3(-4.0, 0.0, -2.0)
	departed.leaving = true
	departed.site_time = 3.0
	nessa_farewell = true
	nessa.has_chore = true
	nessa.chore = GardenLayout.GATE
	ecology.tick(0.1, world_snapshot())
	var turned := false
	for line in events:
		if str(line).find("turns back") != -1:
			turned = true
	if departed.leaving or not turned or nessa_farewell or nessa.has_chore or Trust.level("nessa") != 1 or Economy.coins != tin:
		push_error("smoke: a visitor did not turn back")
		get_tree().quit(1)
		return
	if ecology.status_line("berrypatch", world_snapshot()) == "heading for the hedge":
		push_error("smoke: the journal kept a visitor who turned back")
		get_tree().quit(1)
		return
	_update_creatures(0.016)
	if departed.use_berth or departed.goal.distance_to(GardenLayout.GATE) < 0.2:
		push_error("smoke: a visitor who turned back kept walking out")
		get_tree().quit(1)
		return
	departed.global_position = Vector3(-4.0, 0.0, -2.0)
	var back_at := departed.goal
	var cane_far := departed.global_position.distance_to(back_at)
	departed._coast(1.0)
	if departed.global_position.distance_to(back_at) > cane_far - 0.5:
		push_error("smoke: a visitor who turned back kept walking out")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the turn back did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	departed = null
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "berrypatch" and not body.leaving:
			departed = body
			break
	if departed == null or nessa_farewell or _person("nessa").has_chore or Trust.level("nessa") != 1 or Economy.coins != tin:
		push_error("smoke: the turn back did not reload")
		get_tree().quit(1)
		return
	departed.global_position = GardenLayout.GATE
	departed.leaving = true
	ecology.tick(0.1, world_snapshot())
	if is_instance_valid(departed) and not departed.is_queued_for_deletion():
		push_error("smoke: the gate let a visitor turn back")
		get_tree().quit(1)
		return
	_force_plant(0, 3, "peach", 1.0)
	_force_plant(1, 3, "nightlantern", 1.0)
	var pear := ecology.first("pegapear")
	if pear == null:
		pear = ecology.force_spawn("pegapear")
	pear.life = "visitor"
	pear.leaving = false
	pear.held = false
	pear.bite_wait = 2.0
	pear.reduce_motion = false
	Clock.set_hour(18.0)
	var lantern := _average_plant("nightlantern")
	var peach_at := _average_plant("peach")
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	var lantern_far := pear.global_position.distance_to(lantern)
	_update_creatures(0.016)
	if pear.use_berth or pear.goal.distance_to(lantern) > 0.2 or pear.goal.distance_to(peach_at) < 0.3:
		push_error("smoke: pegapear missed the nightlantern")
		get_tree().quit(1)
		return
	pear.tier = 2
	pear._process(2.0)
	if pear.global_position.distance_to(lantern) > lantern_far - 0.8 or soil.get_cell(0, 3).growth < 0.95:
		push_error("smoke: pegapear stayed off the nightlantern")
		get_tree().quit(1)
		return
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	hidden_far = pear.global_position.distance_to(lantern)
	_update_creatures(0.016)
	pear.tier = 3
	pear._process(2.0)
	if pear.visible or pear.global_position.distance_to(lantern) > hidden_far - 0.8:
		push_error("smoke: a hidden pegapear stayed off the nightlantern")
		get_tree().quit(1)
		return
	Clock.set_hour(20.0)
	pear.life = "visitor"
	pear.leaving = false
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	_update_creatures(0.016)
	awning = GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
	if not pear.use_berth or pear.goal.distance_to(awning) > 0.2:
		push_error("smoke: rain let pegapear leave the awning")
		get_tree().quit(1)
		return
	Clock.set_hour(18.0)
	pear.leaving = true
	pear.goal = GardenLayout.GATE
	pear.attract = GardenLayout.GATE
	_update_creatures(0.016)
	if pear.goal.distance_to(GardenLayout.GATE) > 0.2:
		push_error("smoke: a leaving pegapear walked to the lantern")
		get_tree().quit(1)
		return
	pear.leaving = false
	pear.life = "resident"
	Clock.set_hour(10.0)
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	pear.bite_wait = 2.0
	var peach_far := pear.global_position.distance_to(peach_at)
	_update_creatures(0.016)
	if pear.use_berth or pear.wants_sleep or pear.goal.distance_to(peach_at) > 0.2 or pear.goal.distance_to(lantern) < 0.3:
		push_error("smoke: morning left pegapear at the lantern")
		get_tree().quit(1)
		return
	pear.tier = 2
	pear._process(2.0)
	if pear.global_position.distance_to(peach_at) > peach_far - 0.8 or soil.get_cell(0, 3).growth < 0.95:
		push_error("smoke: pegapear did not return to the peach")
		get_tree().quit(1)
		return
	var dusk_tin := Economy.coins
	var dusk_trust := Trust.level("nessa")
	Clock.set_hour(18.0)
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the dusk walk did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	pear = ecology.first("pegapear")
	lantern = _average_plant("nightlantern")
	if pear == null or pear.life != "resident" or pear.leaving or Clock.hour() < 16.0:
		push_error("smoke: the dusk walk did not reload")
		get_tree().quit(1)
		return
	_update_creatures(0.016)
	if pear.goal.distance_to(lantern) > 0.2 or Trust.level("nessa") != dusk_trust or Economy.coins != dusk_tin:
		push_error("smoke: the dusk walk left the hour")
		get_tree().quit(1)
		return
	_force_plant(0, 3, "peach", 1.0)
	_force_plant(1, 3, "nightlantern", 1.0)
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id != "pegapear":
			body.bite_wait = 4.0
	pear.life = "visitor"
	pear.leaving = false
	pear.held = false
	pear.bite_wait = 0.0
	pear.tier = 2
	Clock.set_hour(18.0)
	pear.global_position = GardenLayout.cell_center(1, 3)
	_browse(0.1)
	if soil.get_cell(0, 3).growth < 0.95 or soil.get_cell(1, 3).growth < 0.95 or pear.bite_wait > 0.05 or Trust.level("nessa") != dusk_trust or Economy.coins != dusk_tin:
		push_error("smoke: a visitor ate at dusk")
		get_tree().quit(1)
		return
	pear.life = "resident"
	pear.bite_wait = 0.0
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	_update_creatures(0.016)
	if pear.use_berth or pear.goal.distance_to(lantern) > 0.2 or pear.goal.distance_to(peach_at) < 0.3 or soil.get_cell(0, 3).growth < 0.95 or soil.get_cell(1, 3).growth < 0.95:
		push_error("smoke: a hungry dusk walk left the lantern")
		get_tree().quit(1)
		return
	pear.global_position = GardenLayout.cell_center(1, 3)
	_browse(0.1)
	if soil.get_cell(1, 3).growth > 0.6 or soil.get_cell(0, 3).growth < 0.95 or pear.bite_wait < 3.0 or not soil.get_cell(1, 3).taken or soil.get_cell(1, 3).eaten_by != pear.display_name or events.is_empty() or str(events[0]).find("bite") == -1 or Trust.level("nessa") != dusk_trust or Economy.coins != dusk_tin:
		push_error("smoke: dusk left the lantern whole")
		get_tree().quit(1)
		return
	if soil.get_cell(1, 3).chem == "nightloam":
		if _plot_line(soil.get_cell(1, 3)).find("Growing back.") == -1:
			push_error("smoke: the bitten lantern hid the recovery")
			get_tree().quit(1)
			return
	elif _plot_line(soil.get_cell(1, 3)).find("Needs night-loam.") == -1 or _plot_line(soil.get_cell(1, 3)).find("Growing back.") != -1:
		push_error("smoke: the bitten lantern hid the loam")
		get_tree().quit(1)
		return
	var meal_back := {}
	for cell in soil.all():
		var plot: SoilCell = cell
		meal_back["%d,%d" % [plot.ix, plot.iz]] = [plot.moisture, plot.growth, plot.wilt, plot.plant_id, plot.fertility, plot.chem, plot.tilled]
	var kept_seeded := soil.seeded
	var kept_rain := soil.seed_rain
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "nightlantern" and not (plot.ix == 1 and plot.iz == 3):
			plot.plant_id = ""
	var meal_bed := soil.get_cell(1, 3)
	var meal_at := GardenLayout.cell_center(1, 3)
	pear.life = "visitor"
	pear.leaving = false
	pear.bite_wait = 2.0
	pear.tier = 2
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	Clock.set_hour(18.0)
	_update_creatures(0.016)
	if pear.use_berth or pear.goal.distance_to(meal_at) > 0.2:
		push_error("smoke: a visitor left the bitten lantern")
		get_tree().quit(1)
		return
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	_update_creatures(0.016)
	pear.tier = 3
	hidden_far = pear.global_position.distance_to(meal_at)
	pear._process(2.0)
	if pear.visible or pear.global_position.distance_to(meal_at) > hidden_far - 0.8 or Trust.level("nessa") != dusk_trust or Economy.coins != dusk_tin:
		push_error("smoke: a hidden pegapear left the bitten lantern")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: Array = meal_back["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(kept[0])
		plot.growth = float(kept[1])
		plot.wilt = float(kept[2])
		plot.plant_id = str(kept[3])
		plot.fertility = float(kept[4])
		plot.chem = str(kept[5])
		plot.tilled = bool(kept[6])
	soil.seeded = kept_seeded
	soil.seed_rain = kept_rain
	meal_bed = soil.get_cell(1, 3)
	meal_bed.plant_id = "nightlantern"
	meal_bed.growth = 0.55
	meal_bed.chem = "nightloam"
	meal_bed.moisture = 1.0
	meal_bed.fertility = 0.6
	meal_bed.wilt = 0.0
	meal_bed.taken = true
	if _plot_line(meal_bed).find("Growing back.") == -1:
		push_error("smoke: the bitten lantern hid the recovery")
		get_tree().quit(1)
		return
	soil.tick(80.0, "clear")
	if meal_bed.growth < 0.95 or meal_bed.plant_id != "nightlantern" or meal_bed.taken or _plot_line(meal_bed).find("Growing back.") != -1 or Trust.level("nessa") != dusk_trust or Economy.coins != dusk_tin:
		push_error("smoke: the bitten lantern did not grow back")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the regrown lantern did not save")
		get_tree().quit(1)
		return
	var grew := false
	for entry in SaveGame.read_slot(1).get("soil", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("ix", -1)) == 1 and int(entry.get("iz", -1)) == 3 and str(entry.get("plant_id", "")) == "nightlantern" and float(entry.get("growth", 0.0)) >= 0.95:
			grew = true
	if not grew:
		push_error("smoke: the regrown lantern did not reload")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: Array = meal_back["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(kept[0])
		plot.growth = float(kept[1])
		plot.wilt = float(kept[2])
		plot.plant_id = str(kept[3])
		plot.fertility = float(kept[4])
		plot.chem = str(kept[5])
		plot.tilled = bool(kept[6])
	soil.seeded = kept_seeded
	soil.seed_rain = kept_rain
	meal_bed = soil.get_cell(1, 3)
	meal_bed.plant_id = "nightlantern"
	meal_bed.growth = 0.55
	meal_bed.chem = "base"
	meal_bed.moisture = 1.0
	meal_bed.fertility = 0.6
	meal_bed.wilt = 0.0
	meal_bed.taken = true
	if _plot_line(meal_bed).find("Needs night-loam.") == -1 or _plot_line(meal_bed).find("Growing back.") != -1:
		push_error("smoke: a bare lantern claimed it was growing back")
		get_tree().quit(1)
		return
	soil.tick(80.0, "clear")
	if meal_bed.growth > 0.6 or meal_bed.plant_id != "nightlantern" or not meal_bed.taken:
		push_error("smoke: a lantern grew back without night-loam")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: Array = meal_back["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(kept[0])
		plot.growth = float(kept[1])
		plot.wilt = float(kept[2])
		plot.plant_id = str(kept[3])
		plot.fertility = float(kept[4])
		plot.chem = str(kept[5])
		plot.tilled = bool(kept[6])
	soil.seeded = kept_seeded
	soil.seed_rain = kept_rain
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "peach" and not (plot.ix == 0 and plot.iz == 3):
			plot.plant_id = ""
	soil.get_cell(0, 3).growth = 0.55
	pear.life = "resident"
	pear.leaving = false
	pear.bite_wait = 2.0
	pear.tier = 2
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	Clock.set_hour(10.0)
	_update_creatures(0.016)
	if pear.use_berth or pear.goal.distance_to(GardenLayout.cell_center(0, 3)) > 0.2:
		push_error("smoke: morning left the bitten peach")
		get_tree().quit(1)
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		var kept: Array = meal_back["%d,%d" % [plot.ix, plot.iz]]
		plot.moisture = float(kept[0])
		plot.growth = float(kept[1])
		plot.wilt = float(kept[2])
		plot.plant_id = str(kept[3])
		plot.fertility = float(kept[4])
		plot.chem = str(kept[5])
		plot.tilled = bool(kept[6])
	soil.seeded = kept_seeded
	soil.seed_rain = kept_rain
	pear.life = "resident"
	pear.leaving = false
	pear.tier = 2
	Clock.set_hour(18.0)
	_force_plant(0, 3, "peach", 1.0)
	_force_plant(1, 3, "nightlantern", 1.0)
	pear.bite_wait = 0.0
	pear.global_position = camera.global_position + camera.global_transform.basis.z * 8.0
	pear.global_position.y = 0.0
	if camera.is_position_in_frustum(pear.global_position) or pear.global_position.distance_to(GardenLayout.cell_center(1, 3)) < 1.6:
		push_error("smoke: the hidden pegapear was still by the lantern")
		get_tree().quit(1)
		return
	_browse(0.1)
	if soil.get_cell(1, 3).growth > 0.6 or soil.get_cell(0, 3).growth < 0.95 or pear.bite_wait < 3.0:
		push_error("smoke: a hidden dusk left the lantern whole")
		get_tree().quit(1)
		return
	_force_plant(0, 3, "peach", 1.0)
	_force_plant(1, 3, "nightlantern", 1.0)
	Clock.set_hour(10.0)
	pear.life = "resident"
	pear.bite_wait = 0.0
	pear.global_position = GardenLayout.cell_center(0, 3)
	_browse(0.1)
	if soil.get_cell(0, 3).growth > 0.6 or soil.get_cell(1, 3).growth < 0.95 or pear.bite_wait < 3.0 or Trust.level("nessa") != dusk_trust or Economy.coins != dusk_tin:
		push_error("smoke: morning ate the lantern")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the dusk meal did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	pear = ecology.first("pegapear")
	if pear == null or pear.life != "resident" or soil.get_cell(0, 3).growth > 0.6 or soil.get_cell(1, 3).growth < 0.95 or pear.bite_wait < 3.0 or Trust.level("nessa") != dusk_trust or Economy.coins != dusk_tin:
		push_error("smoke: the dusk meal did not reload")
		get_tree().quit(1)
		return
	_force_plant(0, 3, "peach", 1.0)
	_force_plant(1, 3, "nightlantern", 1.0)
	Clock.set_hour(22.0)
	pear.bite_wait = 0.0
	pear.global_position = GardenLayout.cell_center(1, 3)
	_browse(0.1)
	if soil.get_cell(0, 3).growth < 0.95 or soil.get_cell(1, 3).growth < 0.95 or pear.bite_wait > 0.05:
		push_error("smoke: night took a bite")
		get_tree().quit(1)
		return
	_force_plant(0, 3, "peach", 1.0)
	_force_plant(1, 3, "nightlantern", 1.0)
	pear.life = "resident"
	pear.leaving = false
	pear.bite_wait = 2.0
	pear.tier = 2
	Clock.set_hour(18.0)
	Clock.set_hour(21.0)
	var dusk_kit := Vector3(-6.0, 0.0, 1.0)
	home_points.append(dusk_kit)
	pear.global_position = Vector3(-8.0, 0.0, 2.0)
	_update_creatures(0.016)
	if not pear.wants_sleep or not pear.use_berth or pear.goal.distance_to(dusk_kit) > 0.2:
		push_error("smoke: night sent pegapear to the lantern")
		get_tree().quit(1)
		return
	home_points.pop_back()
	var horn := ecology.first("gushorn")
	if horn == null:
		horn = ecology.force_spawn("gushorn")
	horn.life = "visitor"
	horn.leaving = false
	horn.held = false
	horn.bite_wait = 2.0
	horn.reduce_motion = false
	var loam_bed := soil.get_cell(8, 6)
	loam_bed.plant_id = ""
	loam_bed.chem = "nightloam"
	var loam_n := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.chem == "nightloam":
			loam_n += 1
	Clock.set_hour(15.3)
	var loam_at := _nearest_loam(Vector3(10.5, 0.0, -8.5))
	horn.global_position = Vector3(10.5, 0.0, -8.5)
	var loam_far := horn.global_position.distance_to(loam_at)
	_update_creatures(0.016)
	if horn.use_berth or horn.goal.distance_to(loam_at) > 0.2:
		push_error("smoke: gushorn missed the night-loam")
		get_tree().quit(1)
		return
	horn.tier = 2
	horn._process(2.0)
	if horn.global_position.distance_to(loam_at) > loam_far - 0.8:
		push_error("smoke: gushorn stayed off the night-loam")
		get_tree().quit(1)
		return
	horn.global_position = Vector3(10.5, 0.0, -8.5)
	hidden_far = horn.global_position.distance_to(loam_at)
	_update_creatures(0.016)
	horn.tier = 3
	horn._process(2.0)
	if horn.visible or horn.global_position.distance_to(loam_at) > hidden_far - 0.8:
		push_error("smoke: a hidden gushorn stayed off the night-loam")
		get_tree().quit(1)
		return
	Clock.set_hour(20.0)
	horn.life = "visitor"
	horn.leaving = false
	horn.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	awning = GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
	if not horn.use_berth or horn.goal.distance_to(awning) > 0.2:
		push_error("smoke: rain let gushorn leave the awning")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	horn.leaving = true
	horn.goal = GardenLayout.GATE
	horn.attract = GardenLayout.GATE
	_update_creatures(0.016)
	if horn.goal.distance_to(GardenLayout.GATE) > 0.2:
		push_error("smoke: a leaving gushorn walked to the night-loam")
		get_tree().quit(1)
		return
	horn.leaving = false
	var loam_tin := Economy.coins
	var loam_trust := Trust.level("nessa")
	loam_hours = 3.2
	_hold_loam(1.0)
	var loam_left := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.chem == "nightloam":
			loam_left += 1
	if loam_left != loam_n - 1 or loam_hours > 0.3 or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: night-loam stayed without a settled crown")
		get_tree().quit(1)
		return
	if events.is_empty() or str(events[0]).find("thinned") == -1:
		push_error("smoke: the parish did not notice the thin loam")
		get_tree().quit(1)
		return
	var bulb := soil.get_cell(9, 6)
	bulb.tilled = true
	bulb.plant_id = "nightlantern"
	bulb.growth = 0.4
	bulb.moisture = 0.8
	bulb.fertility = 0.7
	bulb.chem = "nightloam"
	bulb.wilt = 0.0
	soil.tick(60.0, "clear")
	if bulb.growth < 0.5:
		push_error("smoke: a nightlantern ignored the loam")
		get_tree().quit(1)
		return
	bulb.chem = "base"
	bulb.moisture = 0.9
	var stalled := bulb.growth
	soil.tick(60.0, "clear")
	if bulb.growth > stalled + 0.01:
		push_error("smoke: a nightlantern grew after the loam thinned")
		get_tree().quit(1)
		return
	horn.life = "resident"
	loam_hours = 3.2
	var held_n := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.chem == "nightloam":
			held_n += 1
	_hold_loam(1.0)
	var held_after := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.chem == "nightloam":
			held_after += 1
	if held_after != held_n or loam_hours > 0.01 or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: a settled gushorn let the loam thin")
		get_tree().quit(1)
		return
	loam_hours = 1.5
	horn.global_position = Vector3(10.5, 0.0, -8.5)
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the night-loam did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	horn = ecology.first("gushorn")
	if horn == null or horn.life != "resident" or absf(loam_hours - 1.5) > 0.05 or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: the night-loam did not reload")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	loam_at = _nearest_loam(horn.global_position)
	_update_creatures(0.016)
	if horn.goal.distance_to(loam_at) > 0.2:
		push_error("smoke: the night-loam walk did not reload")
		get_tree().quit(1)
		return
	Clock.set_hour(21.0)
	var loam_kit := Vector3(-6.0, 0.0, 1.0)
	home_points.append(loam_kit)
	horn.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	if not horn.wants_sleep or not horn.use_berth or horn.goal.distance_to(loam_kit) > 0.2:
		push_error("smoke: night sent gushorn to the loam")
		get_tree().quit(1)
		return
	home_points.pop_back()
	for cell in soil.all():
		var plot: SoilCell = cell
		plot.chem = "base"
	soil.get_cell(8, 4).plant_id = ""
	soil.get_cell(8, 4).chem = "nightloam"
	soil.get_cell(8, 5).plant_id = ""
	soil.get_cell(8, 5).chem = "nightloam"
	soil.get_cell(8, 6).plant_id = ""
	soil.get_cell(8, 6).chem = "nightloam"
	bulb.chem = "base"
	nip = ecology.first("dusknip")
	if nip == null:
		nip = ecology.force_spawn("dusknip")
	nip.life = "visitor"
	nip.leaving = false
	_restore_loam()
	if _loam_count() != 3 or bulb.chem != "base":
		push_error("smoke: a visitor dusknip laid night-loam")
		get_tree().quit(1)
		return
	nip.life = "resident"
	_restore_loam()
	if _loam_count() < 4 or bulb.chem != "nightloam" or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: dusknip left the night-loam thin")
		get_tree().quit(1)
		return
	if events.is_empty() or str(events[0]).find("worked the night-loam") == -1:
		push_error("smoke: the parish did not notice the new loam")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the restored loam did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	bulb = soil.get_cell(9, 6)
	if _loam_count() < 4 or bulb.chem != "nightloam" or bulb.plant_id != "nightlantern" or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: the restored loam did not reload")
		get_tree().quit(1)
		return
	horn = ecology.first("gushorn")
	if horn == null:
		horn = ecology.force_spawn("gushorn")
	horn.life = "visitor"
	horn.leaving = true
	horn.site_time = 3.0
	horn.global_position = Vector3(10.5, 0.0, -8.5)
	_force_plant(6, 2, "mosspear", 1.0)
	_force_plant(6, 3, "mosspear", 1.0)
	_feed_beds()
	ecology.tick(0.2, world_snapshot())
	var loam_back := false
	for line in events:
		if str(line).find("turns back") != -1:
			loam_back = true
	if horn.leaving or not loam_back or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: gushorn did not turn back for the loam")
		get_tree().quit(1)
		return
	var vine := ecology.first("grapling")
	if vine == null:
		vine = ecology.force_spawn("grapling")
	vine.life = "visitor"
	vine.leaving = false
	vine.held = false
	vine.bite_wait = 2.0
	vine.reduce_motion = false
	_force_plant(4, 2, "bramble", 1.0)
	var cane := soil.get_cell(4, 2)
	cane.moisture = 0.8
	cane.fertility = 0.55
	Clock.set_hour(15.3)
	var cane_at := GardenLayout.cell_center(4, 2)
	vine.global_position = Vector3(10.5, 0.0, -8.5)
	var vine_plot := _nearest_bramble(vine.global_position)
	if vine_plot == null:
		push_error("smoke: grapling had no cane")
		get_tree().quit(1)
		return
	var vine_at := GardenLayout.cell_center(vine_plot.ix, vine_plot.iz)
	cane_far = vine.global_position.distance_to(vine_at)
	_update_creatures(0.016)
	if vine.use_berth or vine.goal.distance_to(vine_at) > 0.2:
		push_error("smoke: grapling missed the cane")
		get_tree().quit(1)
		return
	vine.tier = 2
	vine._process(2.0)
	var cane_moved := cane_far - vine.global_position.distance_to(vine_at)
	if cane_moved < 0.45 or cane_moved > 1.05:
		push_error("smoke: grapling was not vine-slow")
		get_tree().quit(1)
		return
	vine.global_position = Vector3(10.5, 0.0, -8.5)
	hidden_far = vine.global_position.distance_to(vine_at)
	_update_creatures(0.016)
	vine.tier = 3
	vine._process(2.0)
	var cane_hidden := hidden_far - vine.global_position.distance_to(vine_at)
	if vine.visible or cane_hidden < 0.45 or cane_hidden > 1.05:
		push_error("smoke: a hidden grapling was not vine-slow")
		get_tree().quit(1)
		return
	Clock.set_hour(20.0)
	vine.life = "visitor"
	vine.leaving = false
	vine.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	awning = GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
	if not vine.use_berth or vine.goal.distance_to(awning) > 0.2:
		push_error("smoke: rain let grapling leave the awning")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	vine.leaving = true
	vine.goal = GardenLayout.GATE
	vine.attract = GardenLayout.GATE
	_update_creatures(0.016)
	if vine.goal.distance_to(GardenLayout.GATE) > 0.2:
		push_error("smoke: a leaving grapling walked to the cane")
		get_tree().quit(1)
		return
	vine.leaving = false
	vine.life = "visitor"
	vine.global_position = cane_at
	cane.moisture = 0.8
	cane.fertility = 0.55
	soil.tick(60.0, "clear")
	_hold_cane(1.0)
	if cane.fertility > 0.53 or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: a visitor grapling fed the cane")
		get_tree().quit(1)
		return
	vine.life = "resident"
	vine.global_position = cane_at
	cane.moisture = 0.8
	cane.fertility = 0.55
	soil.tick(60.0, "clear")
	_hold_cane(1.0)
	if cane.fertility < 0.55 or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: grapling let the cane tire")
		get_tree().quit(1)
		return
	cane.moisture = 0.05
	cane.fertility = 0.55
	_hold_cane(1.0)
	if absf(cane.fertility - 0.55) > 0.01:
		push_error("smoke: grapling fed a dry cane")
		get_tree().quit(1)
		return
	cane.moisture = 0.8
	cane.fertility = 0.55
	vine.global_position = cane_at
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the cane did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	vine = ecology.first("grapling")
	cane = soil.get_cell(4, 2)
	if vine == null or vine.life != "resident" or cane.plant_id != "bramble" or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: the cane did not reload")
		get_tree().quit(1)
		return
	vine.global_position = GardenLayout.cell_center(4, 2)
	cane.moisture = 0.8
	cane.fertility = 0.55
	soil.tick(60.0, "clear")
	_hold_cane(1.0)
	if cane.fertility < 0.55:
		push_error("smoke: the reloaded grapling let the cane tire")
		get_tree().quit(1)
		return
	Clock.set_hour(21.0)
	var cane_kit := Vector3(-6.0, 0.0, 1.0)
	home_points.append(cane_kit)
	vine.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	if not vine.wants_sleep or not vine.use_berth or vine.goal.distance_to(cane_kit) > 0.2:
		push_error("smoke: night sent grapling to the cane")
		get_tree().quit(1)
		return
	home_points.pop_back()
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "bramble":
			plot.growth = 1.0
			plot.moisture = 0.8
			plot.fertility = 0.7
	var bitten := soil.get_cell(5, 2)
	bitten.plant_id = "bramble"
	bitten.growth = 0.6
	bitten.tilled = true
	bitten.moisture = 0.8
	bitten.fertility = 0.7
	var berry := ecology.first("berrypatch")
	if berry == null:
		berry = ecology.force_spawn("berrypatch")
	berry.life = "visitor"
	berry.leaving = false
	berry.held = false
	berry.bite_wait = 2.0
	berry.reduce_motion = false
	Clock.set_hour(15.3)
	var bitten_at := GardenLayout.cell_center(5, 2)
	berry.global_position = Vector3(10.5, 0.0, -8.5)
	var berry_far := berry.global_position.distance_to(bitten_at)
	_update_creatures(0.016)
	if berry.use_berth or berry.goal.distance_to(bitten_at) > 0.2 or berry.goal.distance_to(GardenLayout.cell_center(4, 2)) < 0.3:
		push_error("smoke: berrypatch missed the bitten cane")
		get_tree().quit(1)
		return
	berry.tier = 2
	berry._process(2.0)
	if berry.global_position.distance_to(bitten_at) > berry_far - 0.8:
		push_error("smoke: berrypatch stayed off the bitten cane")
		get_tree().quit(1)
		return
	berry.global_position = Vector3(10.5, 0.0, -8.5)
	hidden_far = berry.global_position.distance_to(bitten_at)
	_update_creatures(0.016)
	berry.tier = 3
	berry._process(2.0)
	if berry.visible or berry.global_position.distance_to(bitten_at) > hidden_far - 0.8:
		push_error("smoke: a hidden berrypatch stayed off the bitten cane")
		get_tree().quit(1)
		return
	Clock.set_hour(20.0)
	berry.life = "visitor"
	berry.leaving = false
	berry.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	awning = GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
	if not berry.use_berth or berry.goal.distance_to(awning) > 0.2:
		push_error("smoke: rain let berrypatch leave the awning")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	berry.leaving = true
	berry.goal = GardenLayout.GATE
	berry.attract = GardenLayout.GATE
	_update_creatures(0.016)
	if berry.goal.distance_to(GardenLayout.GATE) > 0.2:
		push_error("smoke: a leaving berrypatch walked to the cane")
		get_tree().quit(1)
		return
	berry.leaving = false
	berry.life = "visitor"
	berry.global_position = bitten_at
	bitten.growth = 0.6
	_hold_fruit(1.0)
	if bitten.growth > 0.65 or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: a visitor berrypatch ripened the cane")
		get_tree().quit(1)
		return
	berry.life = "resident"
	bitten.moisture = 0.05
	_hold_fruit(1.0)
	if bitten.growth > 0.65:
		push_error("smoke: berrypatch ripened a dry cane")
		get_tree().quit(1)
		return
	bitten.moisture = 0.8
	bitten.fertility = 0.1
	_hold_fruit(1.0)
	if bitten.growth > 0.65:
		push_error("smoke: berrypatch ripened a tired cane")
		get_tree().quit(1)
		return
	bitten.fertility = 0.7
	_hold_fruit(1.0)
	if bitten.growth < 0.9 or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: berrypatch left the fruit bitten")
		get_tree().quit(1)
		return
	bitten.growth = 0.6
	berry.global_position = bitten_at
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the fruit did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	berry = ecology.first("berrypatch")
	bitten = soil.get_cell(5, 2)
	if berry == null or berry.life != "resident" or bitten.plant_id != "bramble" or bitten.growth > 0.7 or Trust.level("nessa") != loam_trust or Economy.coins != loam_tin:
		push_error("smoke: the fruit did not reload")
		get_tree().quit(1)
		return
	berry.global_position = GardenLayout.cell_center(5, 2)
	bitten.moisture = 0.8
	bitten.fertility = 0.7
	_hold_fruit(1.0)
	if bitten.growth < 0.9:
		push_error("smoke: the reloaded berrypatch left the fruit bitten")
		get_tree().quit(1)
		return
	Clock.set_hour(21.0)
	var berry_kit := Vector3(-6.0, 0.0, 1.0)
	home_points.append(berry_kit)
	berry.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	if not berry.wants_sleep or not berry.use_berth or berry.goal.distance_to(berry_kit) > 0.2:
		push_error("smoke: night sent berrypatch to the cane")
		get_tree().quit(1)
		return
	home_points.pop_back()
	bram.has_chore = false
	bram_feeding = false
	bram_bed = Vector2i(-1, -1)
	Clock.set_hour(15.3)
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "":
			plot.fertility = 0.8
	_force_plant(0, 1, "meadowbell", 1.0)
	var other := soil.get_cell(0, 1)
	other.fertility = 0.05
	other.moisture = 0.8
	cane = soil.get_cell(4, 2)
	cane.plant_id = "bramble"
	cane.growth = 1.0
	cane.tilled = true
	cane.fertility = 0.05
	cane.moisture = 0.8
	vine = ecology.first("grapling")
	if vine == null:
		vine = ecology.force_spawn("grapling")
	vine.life = "resident"
	vine.leaving = false
	vine.global_position = GardenLayout.cell_center(4, 2)
	var kept_tin := Economy.coins
	var kept_pouch := Economy.count("fertilizer")
	_notice_hunger()
	if not bram.has_chore or not bram_feeding or bram_bed != Vector2i(0, 1) or Economy.coins != kept_tin or Economy.count("fertilizer") != kept_pouch:
		push_error("smoke: bram fed a cane the grapling was keeping")
		get_tree().quit(1)
		return
	bram.has_chore = false
	bram_feeding = false
	other.fertility = 0.8
	_notice_hunger()
	if bram.has_chore or bram.speech == null or bram.speech.text != "That cane is kept. I will leave it." or Economy.coins != kept_tin or Economy.count("fertilizer") != kept_pouch:
		push_error("smoke: bram took the kept cane")
		get_tree().quit(1)
		return
	vine.life = "visitor"
	_notice_hunger()
	if not bram.has_chore or bram_bed != Vector2i(4, 2) or Economy.coins != kept_tin or Economy.count("fertilizer") != kept_pouch or Trust.level("nessa") != loam_trust:
		push_error("smoke: a visitor grapling stopped the feed")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the kept cane did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if not bram_feeding or bram_bed != Vector2i(4, 2) or Economy.coins != kept_tin or Economy.count("fertilizer") != kept_pouch:
		push_error("smoke: the kept cane did not reload")
		get_tree().quit(1)
		return
	var readout := soil.get_cell(4, 2)
	readout.plant_id = "bramble"
	readout.tilled = true
	readout.growth = 0.6
	readout.moisture = 0.1
	readout.fertility = 0.7
	var bed_line := _plot_line(readout)
	if bed_line.find("Needs water.") == -1:
		push_error("smoke: a dry cane hid its thirst")
		get_tree().quit(1)
		return
	readout.moisture = 0.8
	readout.fertility = 0.05
	bed_line = _plot_line(readout)
	if bed_line.find("Needs feed.") == -1 or bed_line.find("Needs water.") != -1:
		push_error("smoke: a tired cane hid its feed")
		get_tree().quit(1)
		return
	readout.fertility = 0.7
	berry = ecology.first("berrypatch")
	if berry == null:
		berry = ecology.force_spawn("berrypatch")
	berry.life = "visitor"
	berry.leaving = false
	berry.global_position = GardenLayout.cell_center(4, 2)
	if _plot_line(readout).find("Fruit returning.") != -1:
		push_error("smoke: a visitor ripened the readout")
		get_tree().quit(1)
		return
	berry.life = "resident"
	if _plot_line(readout).find("Fruit returning.") == -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the readout hid the returning fruit")
		get_tree().quit(1)
		return
	readout.growth = 1.0
	vine = ecology.first("grapling")
	if vine == null:
		vine = ecology.force_spawn("grapling")
	vine.life = "visitor"
	vine.leaving = false
	vine.global_position = GardenLayout.cell_center(4, 2)
	if _plot_line(readout).find("Cane kept.") != -1:
		push_error("smoke: a visitor kept the readout")
		get_tree().quit(1)
		return
	vine.life = "resident"
	bed_line = _plot_line(readout)
	if bed_line.find("Cane kept.") == -1 or bed_line.find("Fruit returning.") != -1:
		push_error("smoke: the readout hid the kept cane")
		get_tree().quit(1)
		return
	readout.moisture = 0.1
	if _plot_line(readout).find("Needs water.") == -1 or _plot_line(readout).find("Cane kept.") != -1:
		push_error("smoke: a dry kept cane skipped its thirst")
		get_tree().quit(1)
		return
	readout.moisture = 0.8
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the readout did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	readout = soil.get_cell(4, 2)
	vine = ecology.first("grapling")
	if vine == null or vine.life != "resident" or _plot_line(readout).find("Cane kept.") == -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the readout did not reload")
		get_tree().quit(1)
		return
	Clock.day = 1
	Clock.set_hour(15.3)
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "meadowbell":
			plot.growth = 1.0
	_force_plant(1, 1, "meadowbell", 0.55)
	var short_bell := soil.get_cell(1, 1)
	short_bell.moisture = 0.8
	short_bell.fertility = 0.4
	var bell_at := GardenLayout.cell_center(1, 1)
	bell = ecology.first("bellhelp")
	if bell == null:
		push_error("smoke: bellhelp left before cirlark")
		get_tree().quit(1)
		return
	bell.leaving = false
	bell.held = false
	bell.global_position = Vector3(-8.0, 0.0, 2.0)
	var lark := ecology.first("cirlark")
	if lark == null:
		lark = ecology.force_spawn("cirlark")
	lark.life = "visitor"
	lark.leaving = false
	lark.held = false
	lark.global_position = Vector3(10.5, 0.0, -8.5)
	var lark_far := lark.global_position.distance_to(bell.global_position)
	_update_creatures(0.016)
	if lark.use_berth or lark.goal.distance_to(bell.global_position) > 0.3 or lark.goal.distance_to(bell_at) < 0.3:
		push_error("smoke: a visitor cirlark left bellhelp")
		get_tree().quit(1)
		return
	lark.tier = 2
	lark._process(2.0)
	if lark.global_position.distance_to(bell.global_position) > lark_far - 0.8:
		push_error("smoke: a visitor cirlark stayed off bellhelp")
		get_tree().quit(1)
		return
	lark.global_position = Vector3(10.5, 0.0, -8.5)
	hidden_far = lark.global_position.distance_to(bell.global_position)
	_update_creatures(0.016)
	lark.tier = 3
	lark._process(2.0)
	if lark.visible or lark.global_position.distance_to(bell.global_position) > hidden_far - 0.8:
		push_error("smoke: a hidden visitor cirlark stayed off bellhelp")
		get_tree().quit(1)
		return
	Clock.set_hour(20.0)
	lark.life = "visitor"
	lark.leaving = false
	lark.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	awning = GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
	if not lark.use_berth or lark.goal.distance_to(awning) > 0.2:
		push_error("smoke: rain let cirlark leave the awning")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	lark.life = "resident"
	lark.leaving = false
	lark.global_position = Vector3(10.5, 0.0, -8.5)
	lark_far = lark.global_position.distance_to(bell_at)
	_update_creatures(0.016)
	if lark.use_berth or lark.goal.distance_to(bell_at) > 0.2 or lark.goal.distance_to(bell.global_position) < 0.3:
		push_error("smoke: cirlark missed the short bell")
		get_tree().quit(1)
		return
	lark.tier = 2
	lark._process(2.0)
	if lark.global_position.distance_to(bell_at) > lark_far - 0.8:
		push_error("smoke: cirlark stayed off the short bell")
		get_tree().quit(1)
		return
	lark.global_position = Vector3(10.5, 0.0, -8.5)
	hidden_far = lark.global_position.distance_to(bell_at)
	_update_creatures(0.016)
	lark.tier = 3
	lark._process(2.0)
	if lark.visible or lark.global_position.distance_to(bell_at) > hidden_far - 0.8:
		push_error("smoke: a hidden cirlark stayed off the short bell")
		get_tree().quit(1)
		return
	lark.leaving = true
	lark.goal = GardenLayout.GATE
	lark.attract = GardenLayout.GATE
	_update_creatures(0.016)
	if lark.use_berth or lark.goal.distance_to(GardenLayout.GATE) > 0.2:
		push_error("smoke: a departure left the cirlark gate")
		get_tree().quit(1)
		return
	lark.leaving = false
	lark.life = "bonded"
	lark.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	stand = camera.target
	stand.y = 0.0
	if lark.goal.distance_to(bell_at) < 0.3 or lark.goal.distance_to(stand) > 0.3:
		push_error("smoke: a bonded cirlark left the gardener")
		get_tree().quit(1)
		return
	lark.life = "visitor"
	lark.global_position = bell_at
	short_bell.growth = 0.55
	short_bell.moisture = 0.8
	short_bell.fertility = 0.4
	_hold_bells(1.0)
	if short_bell.growth > 0.6 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: a visitor cirlark filled the bell")
		get_tree().quit(1)
		return
	lark.life = "resident"
	short_bell.moisture = 0.05
	_hold_bells(1.0)
	if short_bell.growth > 0.6:
		push_error("smoke: cirlark filled a dry bell")
		get_tree().quit(1)
		return
	short_bell.moisture = 0.8
	short_bell.fertility = 0.05
	_hold_bells(1.0)
	if short_bell.growth > 0.6:
		push_error("smoke: cirlark filled a tired bell")
		get_tree().quit(1)
		return
	short_bell.fertility = 0.4
	_hold_bells(1.0)
	if short_bell.growth < 0.9 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: cirlark left the bell short")
		get_tree().quit(1)
		return
	short_bell.growth = 0.55
	lark.global_position = bell_at
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the bell did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	lark = ecology.first("cirlark")
	short_bell = soil.get_cell(1, 1)
	if lark == null or lark.life != "resident" or short_bell.plant_id != "meadowbell" or short_bell.growth > 0.6 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the bell did not reload")
		get_tree().quit(1)
		return
	lark.global_position = bell_at
	short_bell.moisture = 0.8
	short_bell.fertility = 0.4
	_hold_bells(1.0)
	if short_bell.growth < 0.9:
		push_error("smoke: the reloaded cirlark left the bell short")
		get_tree().quit(1)
		return
	Clock.set_hour(21.0)
	var lark_kit := Vector3(-6.0, 0.0, 1.0)
	home_points.append(lark_kit)
	lark.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	if not lark.wants_sleep or not lark.use_berth or lark.goal.distance_to(lark_kit) > 0.2:
		push_error("smoke: night sent cirlark to the bell")
		get_tree().quit(1)
		return
	home_points.pop_back()
	Clock.set_hour(15.3)
	lark.life = "visitor"
	lark.leaving = false
	lark.wants_sleep = false
	lark.use_berth = false
	lark.global_position = bell_at
	short_bell.growth = 0.55
	short_bell.moisture = 0.1
	short_bell.fertility = 0.4
	bed_line = _plot_line(short_bell)
	if bed_line.find("Needs water.") == -1 or bed_line.find("Bells filling.") != -1:
		push_error("smoke: a dry bell hid its thirst")
		get_tree().quit(1)
		return
	short_bell.moisture = 0.8
	short_bell.fertility = 0.05
	bed_line = _plot_line(short_bell)
	if bed_line.find("Needs feed.") == -1 or bed_line.find("Bells filling.") != -1:
		push_error("smoke: a tired bell hid its feed")
		get_tree().quit(1)
		return
	short_bell.fertility = 0.4
	if _plot_line(short_bell).find("Bells filling.") != -1:
		push_error("smoke: a visitor filled the readout")
		get_tree().quit(1)
		return
	lark.life = "resident"
	bed_line = _plot_line(short_bell)
	if bed_line.find("Bells filling.") == -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the readout hid the filling bells")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the bell line did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	lark = ecology.first("cirlark")
	short_bell = soil.get_cell(1, 1)
	if lark == null or lark.life != "resident" or _plot_line(short_bell).find("Bells filling.") == -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the bell line did not reload")
		get_tree().quit(1)
		return
	Clock.day = 1
	Clock.set_hour(15.3)
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "reed":
			plot.growth = 0.2
	_force_plant(8, 5, "reed", 1.0)
	var reed_bed := soil.get_cell(8, 5)
	reed_bed.moisture = 0.8
	reed_bed.fertility = 0.4
	var reed_at := GardenLayout.cell_center(8, 5)
	rush = ecology.first("bulrush")
	if rush == null:
		push_error("smoke: bulrush left before reedic")
		get_tree().quit(1)
		return
	rush.leaving = false
	rush.held = false
	rush.global_position = Vector3(6.0, 0.0, -2.0)
	reed = ecology.first("reedic")
	if reed == null:
		reed = ecology.force_spawn("reedic")
	reed.life = "visitor"
	reed.leaving = false
	reed.held = false
	reed.global_position = Vector3(10.5, 0.0, -8.5)
	reed_far = reed.global_position.distance_to(rush.global_position)
	_update_creatures(0.016)
	if reed.use_berth or reed.goal.distance_to(rush.global_position) > 0.3 or reed.goal.distance_to(reed_at) < 0.3:
		push_error("smoke: a visitor reedic left bulrush")
		get_tree().quit(1)
		return
	reed.tier = 2
	reed._process(2.0)
	if reed.global_position.distance_to(rush.global_position) > reed_far - 0.8:
		push_error("smoke: a visitor reedic stayed off bulrush")
		get_tree().quit(1)
		return
	reed.global_position = Vector3(10.5, 0.0, -8.5)
	hidden_far = reed.global_position.distance_to(rush.global_position)
	_update_creatures(0.016)
	reed.tier = 3
	reed._process(2.0)
	if reed.visible or reed.global_position.distance_to(rush.global_position) > hidden_far - 0.8:
		push_error("smoke: a hidden visitor reedic stayed off bulrush")
		get_tree().quit(1)
		return
	Clock.set_hour(20.0)
	reed.life = "visitor"
	reed.leaving = false
	reed.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	awning = GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
	if not reed.use_berth or reed.goal.distance_to(awning) > 0.2:
		push_error("smoke: rain let reedic leave the awning")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	reed.life = "resident"
	reed.leaving = false
	reed.global_position = Vector3(10.5, 0.0, -8.5)
	reed_far = reed.global_position.distance_to(reed_at)
	_update_creatures(0.016)
	if reed.use_berth or reed.goal.distance_to(reed_at) > 0.2 or reed.goal.distance_to(rush.global_position) < 0.3:
		push_error("smoke: reedic missed the reed")
		get_tree().quit(1)
		return
	reed.tier = 2
	reed._process(2.0)
	if reed.global_position.distance_to(reed_at) > reed_far - 0.8:
		push_error("smoke: reedic stayed off the reed")
		get_tree().quit(1)
		return
	reed.global_position = Vector3(10.5, 0.0, -8.5)
	hidden_far = reed.global_position.distance_to(reed_at)
	_update_creatures(0.016)
	reed.tier = 3
	reed._process(2.0)
	if reed.visible or reed.global_position.distance_to(reed_at) > hidden_far - 0.8:
		push_error("smoke: a hidden reedic stayed off the reed")
		get_tree().quit(1)
		return
	reed.leaving = true
	reed.goal = GardenLayout.GATE
	reed.attract = GardenLayout.GATE
	_update_creatures(0.016)
	if reed.use_berth or reed.goal.distance_to(GardenLayout.GATE) > 0.2:
		push_error("smoke: a departure left the reedic gate")
		get_tree().quit(1)
		return
	reed.leaving = false
	reed.life = "bonded"
	reed.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	var reed_shore := _shore_point(0.7)
	if reed.goal.distance_to(reed_at) < 0.3 or reed.goal.distance_to(reed_shore) > 0.2 or reed.goal.distance_to(_shore_point(0.0)) < 0.3:
		push_error("smoke: a bonded reedic left the bank")
		get_tree().quit(1)
		return
	reed.life = "visitor"
	reed.global_position = reed_at
	reed_bed.growth = 1.0
	reed_bed.moisture = 0.62
	reed_bed.fertility = 0.4
	reed_bed.wilt = 0.0
	_prime_reed(1.0)
	soil.tick(60.0, "clear")
	if reed_bed.moisture > 0.5 or reed_bed.wilt <= 0.0 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: a visitor reedic held the reed")
		get_tree().quit(1)
		return
	reed.life = "resident"
	reed_bed.growth = 1.0
	reed_bed.moisture = 0.2
	reed_bed.wilt = 0.0
	_prime_reed(1.0)
	soil.tick(60.0, "clear")
	if reed_bed.moisture > 0.25 or reed_bed.wilt <= 0.0:
		push_error("smoke: reedic watered a dry reed")
		get_tree().quit(1)
		return
	reed_bed.growth = 1.0
	reed_bed.moisture = 0.62
	reed_bed.fertility = 0.4
	reed_bed.wilt = 0.0
	_prime_reed(1.0)
	soil.tick(60.0, "clear")
	if reed_bed.moisture < 0.6 or reed_bed.wilt > 0.05 or reed_bed.growth < 0.95 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: reedic let the reed dry")
		get_tree().quit(1)
		return
	reed_bed.growth = 1.0
	reed_bed.moisture = 0.62
	reed_bed.wilt = 0.0
	reed.global_position = reed_at
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the reed did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	reed = ecology.first("reedic")
	reed_bed = soil.get_cell(8, 5)
	if reed == null or reed.life != "resident" or reed_bed.plant_id != "reed" or reed_bed.moisture < 0.55 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the reed did not reload")
		get_tree().quit(1)
		return
	reed.global_position = reed_at
	reed_bed.growth = 1.0
	reed_bed.moisture = 0.62
	reed_bed.fertility = 0.4
	reed_bed.wilt = 0.0
	_prime_reed(1.0)
	soil.tick(60.0, "clear")
	if reed_bed.moisture < 0.6 or reed_bed.wilt > 0.05:
		push_error("smoke: the reloaded reedic let the reed dry")
		get_tree().quit(1)
		return
	Clock.set_hour(21.0)
	var disc_kit := Vector3(-6.0, 0.0, 1.0)
	home_points.append(disc_kit)
	reed.global_position = Vector3(10.5, 0.0, -8.5)
	_update_creatures(0.016)
	if not reed.wants_sleep or not reed.use_berth or reed.goal.distance_to(disc_kit) > 0.2:
		push_error("smoke: night sent reedic to the reed")
		get_tree().quit(1)
		return
	home_points.pop_back()
	Clock.set_hour(15.3)
	reed.life = "visitor"
	reed.leaving = false
	reed.wants_sleep = false
	reed.use_berth = false
	reed.global_position = reed_at
	reed_bed.moisture = 0.1
	reed_bed.fertility = 0.4
	bed_line = _plot_line(reed_bed)
	if bed_line.find("Needs water.") == -1 or bed_line.find("Reed kept.") != -1:
		push_error("smoke: a dry reed hid its thirst")
		get_tree().quit(1)
		return
	reed_bed.moisture = 0.8
	reed_bed.fertility = 0.05
	bed_line = _plot_line(reed_bed)
	if bed_line.find("Needs feed.") == -1 or bed_line.find("Reed kept.") != -1:
		push_error("smoke: a tired reed hid its feed")
		get_tree().quit(1)
		return
	reed_bed.fertility = 0.4
	if _plot_line(reed_bed).find("Reed kept.") != -1:
		push_error("smoke: a visitor kept the reed readout")
		get_tree().quit(1)
		return
	reed.life = "resident"
	bed_line = _plot_line(reed_bed)
	if bed_line.find("Reed kept.") == -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the readout hid the kept reed")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the reed line did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	reed = ecology.first("reedic")
	reed_bed = soil.get_cell(8, 5)
	if reed == null or reed.life != "resident" or _plot_line(reed_bed).find("Reed kept.") == -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the reed line did not reload")
		get_tree().quit(1)
		return
	nessa = _person("nessa")
	nessa.present = true
	nessa_filing = false
	nessa_drafting = false
	nessa_farewell = false
	nessa.has_chore = false
	farewell_names.clear()
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "bramble":
			plot.growth = 0.2
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "berrypatch" or body.species_id == "grapling":
			body.life = "visitor"
			body.leaving = false
			body.held = false
			body.site_time = 3.0
			body.global_position = Vector3(-4.0, 0.0, -2.0)
		elif ecology.rules.rank_of(body.life) < ecology.rules.rank_of("settler"):
			body.life = "resident"
	ecology.tick(0.1, world_snapshot())
	if farewell_names.size() != 2 or not farewell_names.has("Berrypatch") or not farewell_names.has("Grapling") or not nessa_farewell or nessa.chore.distance_to(GardenLayout.GATE) > 0.2 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: nessa kept one departure %s" % str(farewell_names))
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the departure page did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	nessa = _person("nessa")
	if farewell_names.size() != 2 or not farewell_names.has("Berrypatch") or not farewell_names.has("Grapling") or not nessa_farewell or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the departure page did not reload")
		get_tree().quit(1)
		return
	var ripe_canes := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "bramble":
			continue
		if ripe_canes < 2:
			plot.growth = 1.0
			ripe_canes += 1
		else:
			plot.growth = 0.2
	berry = ecology.first("berrypatch")
	vine = ecology.first("grapling")
	if berry == null or vine == null:
		push_error("smoke: the departure pair is missing")
		get_tree().quit(1)
		return
	berry.global_position = Vector3(-4.0, 0.0, -2.0)
	vine.global_position = Vector3(-3.2, 0.0, -2.0)
	berry.site_time = 3.0
	vine.site_time = 3.0
	berry.leaving = true
	vine.leaving = true
	ecology.tick(0.1, world_snapshot())
	if berry.leaving or farewell_names.has("Berrypatch") or not farewell_names.has("Grapling") or farewell_names.size() != 1 or not nessa_farewell or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: a turn back cleared the other name %s" % str(farewell_names))
		get_tree().quit(1)
		return
	nessa.global_position = GardenLayout.GATE
	nessa.chore = GardenLayout.GATE
	nessa.has_chore = true
	_drift_people(0.1, world_snapshot())
	if nessa_farewell or farewell_names.size() != 0 or nessa.speech == null or nessa.speech.text.find("Grapling") == -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: nessa wrote the wrong departure")
		get_tree().quit(1)
		return
	if events.is_empty() or str(events[0]).find("departure") == -1:
		push_error("smoke: the second departure missed the book")
		get_tree().quit(1)
		return
	Clock.day = 1
	Clock.set_hour(15.3)
	bell_day = -1
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "meadowbell":
			plot.growth = 0.4
	var first_bed := soil.get_cell(0, 1)
	first_bed.plant_id = ""
	first_bed.growth = 0.0
	first_bed.wilt = 0.0
	first_bed.tilled = true
	first_bed.fertility = 0.4
	first_bed.chem = "base"
	var second_bed := soil.get_cell(1, 1)
	second_bed.plant_id = ""
	second_bed.growth = 0.0
	second_bed.wilt = 0.0
	second_bed.tilled = true
	second_bed.fertility = 0.4
	second_bed.chem = "base"
	var kept_seed := soil.seeded
	bell = ecology.first("bellhelp")
	if bell == null:
		push_error("smoke: bellhelp left before the ring")
		get_tree().quit(1)
		return
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "bellhelp":
			body.life = "visitor"
			body.leaving = false
	var ring_notes := events.size()
	_ring_bells(world_snapshot())
	if bell_day != -1 or events.size() != ring_notes or first_bed.plant_id != "" or second_bed.plant_id != "" or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: a thin meadow rang")
		get_tree().quit(1)
		return
	_force_plant(0, 0, "meadowbell", 1.0)
	_force_plant(1, 0, "meadowbell", 1.0)
	_force_plant(2, 0, "meadowbell", 1.0)
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "bellhelp":
			body.life = "curious"
			body.leaving = false
	_ring_bells(world_snapshot())
	if bell_day != -1 or events.size() != ring_notes or first_bed.plant_id != "" or second_bed.plant_id != "":
		push_error("smoke: a curious bellhelp rang")
		get_tree().quit(1)
		return
	for actor in ecology.actors:
		var body: Jelly = actor
		if body.species_id == "bellhelp":
			body.life = "visitor"
			body.leaving = true
	_ring_bells(world_snapshot())
	if bell_day != -1 or events.size() != ring_notes or first_bed.plant_id != "" or second_bed.plant_id != "":
		push_error("smoke: a departure rang")
		get_tree().quit(1)
		return
	bell = ecology.first("bellhelp")
	bell.life = "visitor"
	bell.leaving = false
	Clock.weather = "rain"
	_ring_bells(world_snapshot())
	if bell_day != -1 or events.size() != ring_notes or first_bed.plant_id != "" or Economy.coins != kept_tin or Trust.level("nessa") != loam_trust:
		push_error("smoke: the bell rang in the rain")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	_ring_bells(world_snapshot())
	if bell_day != 1 or events.is_empty() or str(events[0]).find("rings") == -1 or str(events[0]).find("took the next bed") == -1 or events.size() != ring_notes + 1 or first_bed.plant_id != "meadowbell" or first_bed.growth > 0.3 or second_bed.plant_id != "" or soil.seeded != kept_seed or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin or bee_day != 1 or bee_flower.distance_to(GardenLayout.cell_center(first_bed.ix, first_bed.iz)) > 0.2:
		push_error("smoke: bellhelp stayed silent")
		get_tree().quit(1)
		return
	var hurry_g := first_bed.growth
	_bee_growth(0.16)
	if first_bed.growth < hurry_g + 0.08 or first_bed.growth > 0.32 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the bees did not hurry the seedling")
		get_tree().quit(1)
		return
	var hurry_rain := Clock.weather
	Clock.weather = "rain"
	var rain_g := first_bed.growth
	_bee_growth(0.16)
	Clock.weather = hurry_rain
	bee_day = -1
	_bee_growth(0.16)
	bee_day = 1
	if first_bed.growth != rain_g or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the rain hurried the seedling")
		get_tree().quit(1)
		return
	if _plot_line(first_bed).find("Bees hurrying.") == -1:
		push_error("smoke: the bed did not say the bees were hurrying %s" % _plot_line(first_bed))
		get_tree().quit(1)
		return
	var hurry_wet := first_bed.moisture
	first_bed.moisture = 0.1
	if _plot_line(first_bed).find("Needs water.") == -1 or _plot_line(first_bed).find("Bees hurrying.") != -1:
		push_error("smoke: a dry bed said the bees were hurrying")
		get_tree().quit(1)
		return
	first_bed.moisture = hurry_wet
	Clock.weather = "rain"
	if _plot_line(first_bed).find("Bees hurrying.") != -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the rain still said the bees were hurrying")
		get_tree().quit(1)
		return
	Clock.weather = hurry_rain
	bee_day = -1
	if _plot_line(first_bed).find("Bees hurrying.") != -1:
		push_error("smoke: a quiet day said the bees were hurrying")
		get_tree().quit(1)
		return
	bee_day = 1
	bees.tick(0.8, false, "clear", bee_flower, true)
	if bees.bodies[0].position.distance_to(bee_flower) > 1.2:
		push_error("smoke: the bees stayed off the bell")
		get_tree().quit(1)
		return
	var split_at := _second_bell()
	bees.tick(0.8, false, "clear", bee_flower, true, split_at)
	var split_near := 0
	var split_far := 0
	for split_i in bees.bodies.size():
		if bees.bodies[split_i].position.distance_to(bee_flower) < 1.2:
			split_near += 1
		if bees.bodies[split_i].position.distance_to(split_at) < 1.2:
			split_far += 1
	if split_at == Vector3.ZERO or split_near != 6 or split_far != 2 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the flight stayed on one bed")
		get_tree().quit(1)
		return
	for split_ix in [0, 1, 2]:
		soil.get_cell(split_ix, 0).growth = 0.4
	bees.tick(0.8, false, "clear", bee_flower, true, _second_bell())
	split_near = 0
	for split_i in bees.bodies.size():
		if bees.bodies[split_i].position.distance_to(bee_flower) < 1.2:
			split_near += 1
	if split_near != 8 or _second_bell() != Vector3.ZERO or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: one ripe bed split the flight")
		get_tree().quit(1)
		return
	for split_ix in [0, 1, 2]:
		soil.get_cell(split_ix, 0).growth = 1.0
	nip = ecology.first("dusknip")
	if nip == null:
		push_error("smoke: dusknip was gone before the bees")
		get_tree().quit(1)
		return
	var poll_life := nip.life
	var poll_goal := nip.goal
	var poll_pos := nip.global_position
	var poll_weather := Clock.weather
	nip.life = "resident"
	nip.leaving = false
	nip.held = false
	nip.use_berth = false
	nip.wants_sleep = false
	nip.global_position = bee_flower + Vector3(3.2, 0.0, 0.4)
	nip.goal = Vector3(8.0, 0.0, 6.0)
	Clock.weather = "clear"
	_seek_bees()
	if nip.goal.distance_to(bee_flower) > 0.2 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: dusknip stayed off the bees")
		get_tree().quit(1)
		return
	nip.goal = Vector3(8.0, 0.0, 6.0)
	Clock.weather = "rain"
	_seek_bees()
	bee_day = -1
	Clock.weather = "clear"
	_seek_bees()
	if nip.goal.distance_to(Vector3(8.0, 0.0, 6.0)) > 0.2 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: a quiet day walked dusknip to the bees")
		get_tree().quit(1)
		return
	bee_day = 1
	nip.life = "visitor"
	_seek_bees()
	if nip.goal.distance_to(Vector3(8.0, 0.0, 6.0)) > 0.2:
		push_error("smoke: a visitor dusknip walked to the bees")
		get_tree().quit(1)
		return
	nip.life = poll_life
	nip.goal = poll_goal
	nip.global_position = poll_pos
	nip.held = false
	Clock.weather = poll_weather
	bees.tick(0.0, true, "rain")
	_ring_bells(world_snapshot())
	if bell_day != 1 or events.size() != ring_notes + 1 or second_bed.plant_id != "" or soil.seeded != kept_seed:
		push_error("smoke: bellhelp rang twice in a day")
		get_tree().quit(1)
		return
	Clock.set_hour(22.0)
	bell_day = -1
	_ring_bells(world_snapshot())
	if bell_day != -1 or events.size() != ring_notes + 1 or second_bed.plant_id != "" or first_bed.plant_id != "meadowbell":
		push_error("smoke: bellhelp rang at night")
		get_tree().quit(1)
		return
	Clock.day = 2
	Clock.set_hour(10.0)
	_ring_bells(world_snapshot())
	if bell_day != 2 or second_bed.plant_id != "meadowbell" or second_bed.growth > 0.3 or first_bed.plant_id != "meadowbell" or soil.seeded != kept_seed or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the next day stayed silent")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the ring did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if bell_day != 2 or bee_day != 2 or bee_flower.distance_to(GardenLayout.cell_center(second_bed.ix, second_bed.iz)) > 0.2 or first_bed.plant_id != "meadowbell" or second_bed.plant_id != "meadowbell" or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the ring did not reload")
		get_tree().quit(1)
		return
	ring_notes = events.size()
	var sprout_n := 0
	for cell in soil.all():
		var sprout: SoilCell = cell
		if sprout.plant_id == "meadowbell" and sprout.growth <= 0.3:
			sprout_n += 1
	_ring_bells(world_snapshot())
	var sprout_after := 0
	for cell in soil.all():
		var sprout: SoilCell = cell
		if sprout.plant_id == "meadowbell" and sprout.growth <= 0.3:
			sprout_after += 1
	if bell_day != 2 or events.size() != ring_notes or sprout_after != sprout_n or soil.seeded != kept_seed:
		push_error("smoke: a reload rang again the same day")
		get_tree().quit(1)
		return
	var book_n := events.size()
	var book_audit := Trust.audit.size()
	Clock.weather = "rain"
	_note_bees()
	if events.size() != book_n or bee_note_day != -1 or Trust.audit.size() != book_audit or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the rain wrote the bees into the book")
		get_tree().quit(1)
		return
	var pod := _person("nessa")
	pod.present = true
	pod.visible = true
	nessa_filing = false
	nessa_drafting = false
	nessa_farewell = false
	nessa_bees = false
	nessa_watch = null
	pod.has_chore = false
	pod.global_position = GardenLayout.GATE
	Clock.weather = "clear"
	_note_bees()
	var book_row: Dictionary = Trust.audit[Trust.audit.size() - 1] if not Trust.audit.is_empty() else {}
	if events.is_empty() or str(events[0]).find("other Meadowbell") == -1 or str(events[1]).find("that bed") == -1 or events.size() != book_n + 2 or bee_note_day != Clock.day or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin or Trust.audit.size() != book_audit + 2:
		push_error("smoke: the bees were not written into the book")
		get_tree().quit(1)
		return
	if str(book_row.get("action", "")) != "parish_bee_note" or bool(book_row.get("external", true)) or int(book_row.get("cost", -1)) != 0 or str(book_row.get("note", "")).find("other Meadowbell") == -1:
		push_error("smoke: the bee note left the parish")
		get_tree().quit(1)
		return
	var quiet_held: Array = []
	for quiet_cell in soil.all():
		var quiet_plot: SoilCell = quiet_cell
		if quiet_plot.plant_id != "meadowbell" or quiet_plot.growth < 0.85:
			continue
		if GardenLayout.cell_center(quiet_plot.ix, quiet_plot.iz).distance_to(bee_flower) <= 0.45:
			continue
		quiet_held.append([quiet_plot, quiet_plot.growth])
		quiet_plot.growth = 0.4
	bee_note_day = -1
	var quiet_n := events.size()
	var quiet_audit := Trust.audit.size()
	_note_bees()
	if _second_bell() != Vector3.ZERO or events.size() != quiet_n + 1 or str(events[0]).find("other Meadowbell") != -1 or Trust.audit.size() != quiet_audit + 1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: one ripe bed named a second bell")
		get_tree().quit(1)
		return
	events.pop_front()
	Trust.audit.pop_back()
	bee_note_day = Clock.day
	for quiet_row in quiet_held:
		var quiet_back: SoilCell = quiet_row[0]
		quiet_back.growth = quiet_row[1]
	if not nessa_bees or not pod.has_chore or pod.chore.distance_to(bee_flower) > 0.2 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: nessa did not walk to the bees")
		get_tree().quit(1)
		return
	_note_bees()
	if events.size() != book_n + 2 or bee_note_day != Clock.day or Trust.audit.size() != book_audit + 2 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the bees were written twice")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the bee note did not save")
		get_tree().quit(1)
		return
	apply_state(SaveGame.read_slot(1))
	if bee_note_day != 2 or bee_day != 2 or not nessa_bees or not pod.has_chore or pod.chore.distance_to(bee_flower) > 0.2 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the bee note did not reload")
		get_tree().quit(1)
		return
	var book_back := events.size()
	pod.global_position = pod.chore
	_finish_bee_walk()
	if nessa_bees or pod.has_chore or events.size() != book_back or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: the bee walk wrote a second line")
		get_tree().quit(1)
		return
	var cut_bed := soil.get_cell(4, 6)
	_force_plant(4, 6, "peach", 1.0)
	cut_bed.moisture = 0.8
	cut_bed.fertility = 0.5
	var peach_n := Economy.count("peach")
	_tend(cut_bed)
	if Economy.count("peach") != peach_n + 1 or cut_bed.growth > 0.4 or not cut_bed.taken or _plot_line(cut_bed).find("Growing back.") == -1 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin:
		push_error("smoke: a harvest did not leave the peach growing back")
		get_tree().quit(1)
		return
	cut_bed.moisture = 0.1
	if _plot_line(cut_bed).find("Needs water.") == -1 or _plot_line(cut_bed).find("Growing back.") != -1:
		push_error("smoke: a dry harvest hid the thirst")
		get_tree().quit(1)
		return
	if not Economy.take("peach", 1) or not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the harvest did not save")
		get_tree().quit(1)
		return
	var kept_cut := false
	for entry in SaveGame.read_slot(1).get("soil", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("ix", -1)) == 4 and int(entry.get("iz", -1)) == 6 and bool(entry.get("taken", false)) and float(entry.get("growth", 1.0)) <= 0.4:
			kept_cut = true
	if not kept_cut or Economy.count("peach") != peach_n:
		push_error("smoke: the harvest did not reload")
		get_tree().quit(1)
		return
	var lamp_hour := Clock.hour()
	var lamp_day := Clock.day
	var lamp_light := get_tree().get_first_node_in_group("parish_lantern") as OmniLight3D
	var stall_lamp := get_tree().get_first_node_in_group("parish_stall_lamp") as OmniLight3D
	if lamp_light == null:
		push_error("smoke: the path lanterns are missing")
		get_tree().quit(1)
		return
	if stall_lamp == null:
		push_error("smoke: the stall lamp is missing")
		get_tree().quit(1)
		return
	Clock.set_hour(15.3)
	_lamps()
	if lamp_light.light_energy > 0.4 or Economy.coins != kept_tin or Trust.level("nessa") != loam_trust:
		push_error("smoke: the afternoon lit the path lanterns")
		get_tree().quit(1)
		return
	if stall_lamp.light_energy < 0.5:
		push_error("smoke: the open stall left its lamp dim")
		get_tree().quit(1)
		return
	if not _rooms_asleep():
		push_error("smoke: the afternoon lit the rooms")
		get_tree().quit(1)
		return
	if not _awning_matches(true):
		push_error("smoke: the open stall left the awning cool")
		get_tree().quit(1)
		return
	Clock.set_hour(20.4)
	_lamps()
	if lamp_light.light_energy < 0.9 or Economy.coins != kept_tin or Trust.level("nessa") != loam_trust:
		push_error("smoke: dusk left the path lanterns dim")
		get_tree().quit(1)
		return
	if stall_lamp.light_energy > 0.12:
		push_error("smoke: the shut stall left its lamp lit")
		get_tree().quit(1)
		return
	if not _rooms_awake():
		push_error("smoke: dusk left the rooms dim")
		get_tree().quit(1)
		return
	if not _awning_matches(false):
		push_error("smoke: the shut stall left the awning warm")
		get_tree().quit(1)
		return
	Clock.day = 2
	Clock.set_hour(17.2)
	_lamps()
	if Clock.weather != "mist" or lamp_light.light_energy < 0.9 or Economy.coins != kept_tin or Trust.level("nessa") != loam_trust:
		push_error("smoke: the mist left the path lanterns dim")
		get_tree().quit(1)
		return
	Clock.day = 1
	Clock.set_hour(15.3)
	_lamps()
	if Clock.weather != "golden" or lamp_light.light_energy > 0.4 or Economy.coins != kept_tin or Trust.level("nessa") != loam_trust:
		push_error("smoke: the golden afternoon lit the path lanterns")
		get_tree().quit(1)
		return
	var lane_bed: SoilCell = soil.get_cell(3, 3)
	var lane_id := lane_bed.plant_id
	var lane_growth := lane_bed.growth
	var lane_taken := lane_bed.taken
	lane_bed.plant_id = ""
	lane_bed.growth = 0.0
	lane_bed.taken = false
	var lane_before := _lane_passers()
	lane_bed.plant_id = "peach"
	lane_bed.growth = 1.0
	var lane_stats := _place_stats(world_snapshot())
	var park: Dictionary = ContentDB.venues.get("grove_park", {})
	var lane_bodies := _present_people() + ecology.resident_total()
	_lamps()
	var lane_sign := ""
	for node in get_tree().get_nodes_in_group("parish_stall_sign"):
		var sign := node as Label3D
		if sign:
			lane_sign = sign.text
	var cloth_held := true
	for node in get_tree().get_nodes_in_group("parish_awning"):
		var stripe := node as MeshInstance3D
		if stripe and stripe.material_override is StandardMaterial3D:
			var got := (stripe.material_override as StandardMaterial3D).albedo_color
			if got != stripe.get_meta("open_color"):
				cloth_held = false
	if _lane_passers() != lane_before + 1 or int(lane_stats.get("lane_passers", -1)) != lane_before + 1 or int(lane_stats.get("stall_demand", -1)) != lane_bodies + lane_before + 1 or lane_sign != "Petal Stall  +1" or not cloth_held or bool(park.get("active", true)) or Economy.coins != kept_tin or Trust.level("nessa") != loam_trust:
		push_error("smoke: a golden afternoon ignored a ripe bed on the lane")
		get_tree().quit(1)
		return
	var lane_bells := Economy.count("meadowbell")
	Economy.add("meadowbell", 1)
	sell("meadowbell")
	if Economy.coins != kept_tin + 6 or Economy.count("meadowbell") != lane_bells or Trust.level("nessa") != loam_trust or Trust.lane_sale_day != Clock.day:
		push_error("smoke: a lane afternoon paid the book price")
		get_tree().quit(1)
		return
	var lane_notes := 0
	for entry in Trust.audit:
		if str(entry.get("action", "")) == "parish_lane_sale":
			lane_notes += 1
			if bool(entry.get("external", true)) or int(entry.get("cost", -1)) != 0:
				push_error("smoke: the lane line left the parish")
				get_tree().quit(1)
				return
	if lane_notes != 1:
		push_error("smoke: the lane sale missed the parish book")
		get_tree().quit(1)
		return
	Economy.add("meadowbell", 1)
	sell("meadowbell")
	var lane_notes_again := 0
	for entry in Trust.audit:
		if str(entry.get("action", "")) == "parish_lane_sale":
			lane_notes_again += 1
	if Economy.coins != kept_tin + 12 or lane_notes_again != 1 or Trust.level("nessa") != loam_trust:
		push_error("smoke: a second lane sale wrote another line")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the lane line did not save")
		get_tree().quit(1)
		return
	var lane_loaded := SaveGame.read_slot(1)
	if int(lane_loaded.get("trust", {}).get("lane_sale_day", -1)) != Clock.day:
		push_error("smoke: the lane line did not reload")
		get_tree().quit(1)
		return
	Economy.spend(12)
	lane_bed.growth = 0.4
	if _lane_passers() != lane_before:
		push_error("smoke: a short bed counted on the lane")
		get_tree().quit(1)
		return
	lane_bed.growth = 1.0
	Clock.day = 2
	Clock.set_hour(15.0)
	_lamps()
	_lamps()
	lane_sign = ""
	for node in get_tree().get_nodes_in_group("parish_stall_sign"):
		var rain_sign := node as Label3D
		if rain_sign:
			lane_sign = rain_sign.text
	if Clock.weather != "rain" or _lane_passers() != 0 or int(_place_stats(world_snapshot()).get("stall_demand", -1)) != lane_bodies or lane_sign != "Petal Stall" or lamp_light.light_energy > 0.4 or Economy.coins != kept_tin or Trust.level("nessa") != loam_trust:
		push_error("smoke: the rain counted the lane or lit the lanterns")
		get_tree().quit(1)
		return
	Economy.add("meadowbell", 1)
	sell("meadowbell")
	if Economy.coins != kept_tin + 5 or Economy.count("meadowbell") != lane_bells or Trust.level("nessa") != loam_trust:
		push_error("smoke: the rain paid the lane price")
		get_tree().quit(1)
		return
	Economy.spend(5)
	Clock.day = 1
	Clock.set_hour(20.4)
	if _lane_passers() != 0:
		push_error("smoke: the night counted the lane")
		get_tree().quit(1)
		return
	Clock.set_hour(10.0)
	if Clock.weather != "clear" or _lane_passers() != lane_before + 1:
		push_error("smoke: a clear hour ignored a ripe bed on the lane")
		get_tree().quit(1)
		return
	Clock.day = 2
	Clock.set_hour(17.2)
	if Clock.weather != "mist" or _lane_passers() != 0:
		push_error("smoke: the mist counted the lane")
		get_tree().quit(1)
		return
	var rumour_saved: Array[int] = []
	for saved_day in lane_afternoon_days:
		rumour_saved.append(saved_day)
	lane_afternoon_days.clear()
	accept_road()
	if Trust.has_action("parish_road_rumour"):
		push_error("smoke: an unknown road was filed")
		get_tree().quit(1)
		return
	if not road.all_hidden() or _hem_east_line() != "" or _hem_east_rumour_count() != 0 or _hem_card_line() != "" or _hem_stone_line() != "" or _hem_stone_rumour_count() != 0 or _hem_stone_card_line() != "" or _hem_stone_bell_line() != "" or _hem_stone_bell_rumour_count() != 0 or _hem_stone_bell_card_line() != "" or _hem_stone_on_bell_line() != "" or _hem_stone_on_bell_rumour_count() != 0 or _hem_stone_on_bell_card_line() != "" or _hem_stone_far_bell_line() != "" or _hem_stone_far_bell_rumour_count() != 0 or _hem_stone_far_bell_card_line() != "" or _outer_strip_bell_stone_line() != "" or _meadow_strip_bell_line() != "" or _meadow_stone_strip_line() != "" or _farther_strip_bell_line() != "" or _last_bell_stone_line() != "" or _last_strip_bell_line() != "" or _end_strip_stone_line() != "" or _far_bell_stone_line() != "" or _far_stone_strip_line() != "" or _outer_stone_strip_line() != "" or _hem_stone_out_bell_line() != "" or _hem_stone_out_bell_rumour_count() != 0 or _meadow_stone_strip_rumour_count() != 0 or _last_bell_stone_rumour_count() != 0 or _end_strip_stone_rumour_count() != 0 or _far_stone_strip_rumour_count() != 0 or _hem_stone_out_bell_card_line() != "" or _meadow_stone_strip_card_line() != "" or _margin_east_line() != "" or _brink_east_line() != "" or _field_east_line() != "" or _reach_east_line() != "" or _span_east_line() != "" or _span_east_rumour_count() != 0 or _further_east_line() != "" or _further_east_rumour_count() != 0 or _outer_east_line() != "" or _end_step_line() != "" or _end_step_rumour_count() != 0 or _west_turn_line() != "" or _west_turn_rumour_count() != 0 or _south_step_line() != "" or _west_gate_bell_line() != "" or _west_gate_bell_rumour_count() != 0 or _east_closer_bell_line() != "" or _east_closer_bell_rumour_count() != 0 or _parish_sale_line() != "" or _gate_sale_line() != "" or _gate_sale_rumour_count() != 0 or _parish_sale_rumour_count() != 0 or _east_near_line() != "" or _east_far_line() != "" or _east_past_line() != "" or _east_past_rumour_count() != 0 or _east_line() != "" or _far_bell_line() != "" or _join_line() != "" or _south_line() != "" or _lane_south_line() != "" or _end_line() != "" or _end_rumour_count() != 0 or _south_rumour_count() != 0 or _bell_rumour_count() != 0 or _lane_busy_line() != "" or _busy_rumour_count() != 0 or _reached_rumour_count() != 0:
		push_error("smoke: stones marked a road that was not filed")
		get_tree().quit(1)
		return
	var rumour_clock_day := Clock.day
	var rumour_clock_hour := Clock.hour()
	Clock.day = 1
	Clock.set_hour(15.3)
	_note_lane_afternoon()
	Clock.day = 3
	Clock.set_hour(15.3)
	_note_lane_afternoon()
	if _road_rumoured() or lane_afternoon_days.size() != 2 or _road_line() != "The road beyond the hedge is not yet a rumour.":
		push_error("smoke: two afternoons already rumoured the road")
		get_tree().quit(1)
		return
	Clock.day = 5
	Clock.set_hour(15.3)
	_note_lane_afternoon()
	_note_lane_afternoon()
	var rumour_park: Dictionary = ContentDB.venues.get("grove_park", {})
	if not _road_rumoured() or lane_afternoon_days.size() != 3 or _road_line() != "The road beyond the hedge is a rumour." or _road_card_line() != "" or bool(rumour_park.get("active", true)) or Economy.coins != kept_tin or Trust.level("nessa") != loam_trust:
		push_error("smoke: three afternoons left the road unknown")
		get_tree().quit(1)
		return
	var nessa_open := false
	for row in _people_rows(world_snapshot()):
		if str(row.get("name", "")) == "Nessa Pod" and bool(row.get("can_road", false)) and str(row.get("road_line", "x")) == "" and str(row.get("join_line", "x")) == "" and str(row.get("parish_bell_line", "x")) == "" and str(row.get("parish_sale_line", "x")) == "" and str(row.get("hem_card_line", "x")) == "" and str(row.get("hem_stone_card_line", "x")) == "" and str(row.get("hem_stone_bell_card_line", "x")) == "" and str(row.get("hem_stone_on_bell_card_line", "x")) == "" and str(row.get("hem_stone_far_bell_card_line", "x")) == "" and str(row.get("hem_stone_out_bell_card_line", "x")) == "" and str(row.get("meadow_stone_strip_card_line", "x")) == "":
			nessa_open = true
	if not nessa_open:
		push_error("smoke: the card hid the rumour before it was filed")
		get_tree().quit(1)
		return
	accept_road()
	var road_row: Dictionary = {}
	for entry in Trust.audit:
		if str(entry.get("action", "")) == "parish_road_rumour":
			road_row = entry
	if road_row.is_empty() or bool(road_row.get("external", true)) or int(road_row.get("cost", -1)) != 0 or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin or bool(rumour_park.get("active", true)):
		push_error("smoke: the approved rumour left the parish")
		get_tree().quit(1)
		return
	accept_road()
	var road_notes := 0
	for entry in Trust.audit:
		if str(entry.get("action", "")) == "parish_road_rumour":
			road_notes += 1
	if road_notes != 1 or _road_line() != "The book keeps the rumour of the road beyond the hedge." or _road_card_line() != "The road is only a rumour.":
		push_error("smoke: the rumour was filed twice")
		get_tree().quit(1)
		return
	if not road.all_shown() or _hem_east_line() != "The way steps past the margin strip." or _hem_east_rumour_count() != 1 or _hem_card_line() != "The way steps past the margin strip." or _hem_stone_line() != "The way steps past the hem strip." or _hem_stone_rumour_count() != 1 or _hem_stone_card_line() != "The way steps past the hem strip." or _hem_stone_bell_line() != "The way steps east of the hem stone." or _hem_stone_bell_rumour_count() != 1 or _hem_stone_bell_card_line() != "The way steps east of the hem stone." or _hem_stone_on_bell_line() != "The way steps east of the hem-stone bell." or _hem_stone_on_bell_rumour_count() != 1 or _hem_stone_on_bell_card_line() != "The way steps east of the hem-stone bell." or _hem_stone_far_bell_line() != "The way steps past the hem-stone bell." or _hem_stone_far_bell_rumour_count() != 1 or _hem_stone_far_bell_card_line() != "The way steps past the hem-stone bell." or _outer_strip_bell_stone_line() != "The way steps past the outer-strip bell." or _meadow_strip_bell_line() != "The way steps past the meadow-strip bell." or _meadow_stone_strip_line() != "The way steps east of the meadow-strip stone." or _farther_strip_bell_line() != "The way steps past the farther-strip bell." or _last_bell_stone_line() != "The way steps past the last bell stone." or _last_strip_bell_line() != "The way steps past the last-strip bell." or _end_strip_stone_line() != "The way steps east of the last-strip's stone." or _far_bell_stone_line() != "The way steps past the far bell stone." or _far_stone_strip_line() != "The way steps east of the far bell stone." or _outer_stone_strip_line() != "The way steps past the outer stone." or _hem_stone_out_bell_line() != "The way steps east of the far bell." or _hem_stone_out_bell_rumour_count() != 1 or _meadow_stone_strip_rumour_count() != 1 or _last_bell_stone_rumour_count() != 1 or _end_strip_stone_rumour_count() != 1 or _far_stone_strip_rumour_count() != 1 or _hem_stone_out_bell_card_line() != "The way steps east of the far bell." or _meadow_stone_strip_card_line() != "The way steps east of the meadow-strip stone." or _margin_east_line() != "The way steps past the edge-end bell." or _brink_east_line() != "The way steps past the verge-end bell." or _field_east_line() != "The way steps past the reach-end bell." or _reach_east_line() != "The way steps east of the reach-end bell." or _span_east_line() != "The way steps past the east-end bell." or _span_east_rumour_count() != 1 or _further_east_line() != "The way steps further east of the outer bell." or _further_east_rumour_count() != 1 or _outer_east_line() != "The way steps east of the outer-end bell." or _end_step_line() != "The way steps toward the end stone." or _end_step_rumour_count() != 1 or _west_turn_line() != "The way turns west of the far-south bell." or _west_turn_rumour_count() != 1 or _south_step_line() != "The way steps south of the gate-side bell." or _west_gate_bell_line() != "A bell stands beside the way toward the gate." or _west_gate_bell_rumour_count() != 1 or _east_closer_bell_line() != "A bell stands at the parish end." or _parish_sale_line() != "" or _gate_sale_line() != "" or _gate_sale_rumour_count() != 0 or _parish_sale_rumour_count() != 0 or _east_closer_bell_rumour_count() != 1 or _east_near_line() != "The way steps closer to the parish." or _east_far_line() != "A stone marks the east end." or _east_past_line() != "The way continues east past the bell." or _east_past_rumour_count() != 1 or _east_line() != "The way turns east at the end stone." or _far_bell_line() != "Three bells stand on the far lawn." or _bell_sale_line() != "" or _join_line() != "One stone marks the gate opening." or _south_line() != "The way south ends at a stone." or _end_line() != "The way ends past the bench." or _end_rumour_count() != 1 or _south_rumour_count() != 1 or _bell_rumour_count() != 1 or bool(ContentDB.venues.get("grove_park", {}).get("active", true)):
		push_error("smoke: the filed rumour left the gate bare")
		get_tree().quit(1)
		return
	var bell_sale_coins := Economy.coins
	var bell_sale_peach := Economy.count("peach")
	var bell_sale_day := Trust.lane_sale_day
	var bell_sale_audit := Trust.audit.size()
	Economy.add("peach", 1)
	var bell_sale_price := _sell_price("peach")
	sell("peach")
	if Economy.coins != bell_sale_coins + bell_sale_price or Economy.count("peach") != bell_sale_peach or events.size() < 4 or str(events[0]) != "A bell stands beside the way toward the gate." or str(events[1]) != "A bell stands at the parish end." or str(events[2]) != "Three bells stand on the far lawn." or str(events[3]).find("Sold") == -1 or _bell_sale_line() != "A sale named the far-lawn bells." or _parish_sale_line() != "A sale named the parish-end bell." or _parish_sale_rumour_count() != 1 or _sale_rumour_count() != 1 or _west_gate_bell_rumour_count() != 1 or _gate_sale_line() != "A sale named the bell toward the gate." or _gate_sale_rumour_count() != 1 or Trust.gate_bell_named_day != Clock.day or Trust.level("nessa") != loam_trust:
		push_error("smoke: a sale hid the far-lawn bells")
		get_tree().quit(1)
		return
	var nessa_sale := false
	for row in _people_rows(world_snapshot()):
		var sale_card := str(row.get("parish_sale_line", ""))
		if str(row.get("name", "")) == "Nessa Pod" and sale_card == "A sale named the parish-end bell.":
			nessa_sale = true
		elif sale_card != "":
			nessa_sale = false
			break
	if not nessa_sale:
		push_error("smoke: the card hid the parish-end sale")
		get_tree().quit(1)
		return
	Economy.coins = bell_sale_coins
	Trust.lane_sale_day = bell_sale_day
	Trust.bell_named_day = -1
	Trust.parish_bell_named_day = -1
	Trust.gate_bell_named_day = -1
	if _bell_sale_line() != "" or _sale_rumour_count() != 0 or _parish_sale_line() != "" or _gate_sale_line() != "" or _gate_sale_rumour_count() != 0 or _parish_sale_rumour_count() != 0:
		push_error("smoke: the sale line stayed before the day")
		get_tree().quit(1)
		return
	while Trust.audit.size() > bell_sale_audit:
		Trust.audit.pop_back()
	events.pop_front()
	events.pop_front()
	events.pop_front()
	events.pop_front()
	var nessa_kept := false
	for row in _people_rows(world_snapshot()):
		if str(row.get("name", "")) == "Nessa Pod" and str(row.get("road_line", "")) == "The road is only a rumour." and str(row.get("join_line", "")) == "One stone marks the gate opening." and str(row.get("parish_bell_line", "")) == "A bell stands at the parish end." and str(row.get("parish_sale_line", "x")) == "" and str(row.get("hem_card_line", "")) == "The way steps past the margin strip." and str(row.get("hem_stone_card_line", "")) == "The way steps past the hem strip." and str(row.get("hem_stone_bell_card_line", "")) == "The way steps east of the hem stone." and str(row.get("hem_stone_on_bell_card_line", "")) == "The way steps east of the hem-stone bell." and str(row.get("hem_stone_far_bell_card_line", "")) == "The way steps past the hem-stone bell." and str(row.get("hem_stone_out_bell_card_line", "")) == "The way steps east of the far bell." and str(row.get("meadow_stone_strip_card_line", "")) == "The way steps east of the meadow-strip stone." and not bool(row.get("can_road", false)):
			nessa_kept = true
	if not nessa_kept:
		push_error("smoke: the card hid the filed rumour")
		get_tree().quit(1)
		return
	if (_lane_passers() > 0) != (_lane_south_line() == "The lane has reached the south stone."):
		push_error("smoke: the lane line ignored the passer count")
		get_tree().quit(1)
		return
	lane_bed.plant_id = lane_id if lane_id != "" else "meadowbell"
	lane_bed.growth = 1.0
	if _lane_passers() < 1 or _lane_south_line() != "The lane has reached the south stone." or _reached_rumour_count() != 1 or _road_south_bench_count() != 1 or (_lane_passers() < 3 and _lane_busy_line() != "") or (_lane_passers() >= 3 and _lane_busy_line() != "The lane is busy past the bench."):
		push_error("smoke: a passer did not reach the south stone")
		get_tree().quit(1)
		return
	var busy_near: SoilCell = soil.get_cell(1, 1)
	var busy_far: SoilCell = soil.get_cell(2, 1)
	var busy_near_id := busy_near.plant_id
	var busy_near_growth := busy_near.growth
	var busy_far_id := busy_far.plant_id
	var busy_far_growth := busy_far.growth
	busy_near.plant_id = busy_near_id if busy_near_id != "" else "meadowbell"
	busy_far.plant_id = busy_far_id if busy_far_id != "" else "meadowbell"
	busy_near.growth = 1.0
	busy_far.growth = 1.0
	if _lane_passers() < 3 or _lane_busy_line() != "The lane is busy past the bench." or _busy_rumour_count() != 1 or _lane_south_line() != "The lane has reached the south stone." or _reached_rumour_count() != 1:
		push_error("smoke: three passers left the lane quiet")
		get_tree().quit(1)
		return
	busy_near.plant_id = busy_near_id
	busy_near.growth = busy_near_growth
	busy_far.plant_id = busy_far_id
	busy_far.growth = busy_far_growth
	lane_bed.plant_id = lane_id
	lane_bed.growth = lane_growth
	if (_lane_passers() >= 3) != (_lane_busy_line() == "The lane is busy past the bench.") or (_lane_busy_line() == "" and _busy_rumour_count() != 0) or (_lane_busy_line() != "" and _busy_rumour_count() != 1) or (_lane_south_line() == "" and _reached_rumour_count() != 0) or (_lane_south_line() != "" and _reached_rumour_count() != 1):
		push_error("smoke: the busy line stayed after the passers left")
		get_tree().quit(1)
		return
	if (_lane_passers() > 0) != (_lane_south_line() == "The lane has reached the south stone."):
		push_error("smoke: the lane line stayed after the passer left")
		get_tree().quit(1)
		return
	for notice in Trust.notices():
		if str(notice).find("road") != -1 or str(notice).find("book keeps") != -1:
			push_error("smoke: the board gained the road rumour")
			get_tree().quit(1)
			return
	Clock.day = 2
	Clock.set_hour(15.0)
	_note_lane_afternoon()
	if lane_afternoon_days.size() != 3 or Clock.weather != "rain" or _lane_passers() != 0:
		push_error("smoke: the rain rumoured the road")
		get_tree().quit(1)
		return
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: the road rumour did not save")
		get_tree().quit(1)
		return
	var rumour_loaded := SaveGame.read_slot(1)
	var rumour_saved_days = rumour_loaded.get("lane_afternoon_days", [])
	if typeof(rumour_saved_days) != TYPE_ARRAY or rumour_saved_days.size() != 3:
		push_error("smoke: the road rumour did not reload")
		get_tree().quit(1)
		return
	var wiped: Array = []
	for entry in Trust.audit:
		if str(entry.get("action", "")) != "parish_road_rumour":
			wiped.append(entry)
	Trust.audit = wiped
	road.sync(Trust.has_action("parish_road_rumour"))
	var quiet_sale_coins := Economy.coins
	var quiet_sale_peach := Economy.count("peach")
	var quiet_sale_day := Trust.lane_sale_day
	var quiet_sale_audit := Trust.audit.size()
	Economy.add("peach", 1)
	var quiet_sale_price := _sell_price("peach")
	sell("peach")
	if Economy.coins != quiet_sale_coins + quiet_sale_price or Economy.count("peach") != quiet_sale_peach or events.is_empty() or str(events[0]).find("Sold") == -1 or str(events[0]) == "Three bells stand on the far lawn." or str(events[0]) == "A bell stands at the parish end." or str(events[0]) == "A bell stands beside the way toward the gate." or _bell_sale_line() != "" or _parish_sale_line() != "" or _gate_sale_line() != "" or _gate_sale_rumour_count() != 0 or _parish_sale_rumour_count() != 0 or _sale_rumour_count() != 0 or _west_gate_bell_rumour_count() != 0 or Trust.bell_named_day != -1 or Trust.parish_bell_named_day != -1 or _gate_sale_line() != "" or _gate_sale_rumour_count() != 0 or Trust.gate_bell_named_day != -1 or Trust.level("nessa") != loam_trust:
		push_error("smoke: a quiet sale named the far-lawn bells")
		get_tree().quit(1)
		return
	Economy.coins = quiet_sale_coins
	Trust.lane_sale_day = quiet_sale_day
	while Trust.audit.size() > quiet_sale_audit:
		Trust.audit.pop_back()
	events.pop_front()
	if not road.all_hidden() or _road_line() == "The book keeps the rumour of the road beyond the hedge." or _road_card_line() != "" or _hem_east_line() != "" or _hem_east_rumour_count() != 0 or _hem_card_line() != "" or _hem_stone_line() != "" or _hem_stone_rumour_count() != 0 or _hem_stone_card_line() != "" or _hem_stone_bell_line() != "" or _hem_stone_bell_rumour_count() != 0 or _hem_stone_bell_card_line() != "" or _hem_stone_on_bell_line() != "" or _hem_stone_on_bell_rumour_count() != 0 or _hem_stone_on_bell_card_line() != "" or _hem_stone_far_bell_line() != "" or _hem_stone_far_bell_rumour_count() != 0 or _hem_stone_far_bell_card_line() != "" or _outer_strip_bell_stone_line() != "" or _meadow_strip_bell_line() != "" or _meadow_stone_strip_line() != "" or _farther_strip_bell_line() != "" or _last_bell_stone_line() != "" or _last_strip_bell_line() != "" or _end_strip_stone_line() != "" or _far_bell_stone_line() != "" or _far_stone_strip_line() != "" or _outer_stone_strip_line() != "" or _hem_stone_out_bell_line() != "" or _hem_stone_out_bell_rumour_count() != 0 or _meadow_stone_strip_rumour_count() != 0 or _last_bell_stone_rumour_count() != 0 or _end_strip_stone_rumour_count() != 0 or _far_stone_strip_rumour_count() != 0 or _hem_stone_out_bell_card_line() != "" or _meadow_stone_strip_card_line() != "" or _margin_east_line() != "" or _brink_east_line() != "" or _field_east_line() != "" or _reach_east_line() != "" or _span_east_line() != "" or _span_east_rumour_count() != 0 or _further_east_line() != "" or _further_east_rumour_count() != 0 or _outer_east_line() != "" or _end_step_line() != "" or _end_step_rumour_count() != 0 or _west_turn_line() != "" or _west_turn_rumour_count() != 0 or _south_step_line() != "" or _west_gate_bell_line() != "" or _west_gate_bell_rumour_count() != 0 or _east_closer_bell_line() != "" or _east_closer_bell_rumour_count() != 0 or _parish_sale_line() != "" or _gate_sale_line() != "" or _gate_sale_rumour_count() != 0 or _parish_sale_rumour_count() != 0 or _east_near_line() != "" or _east_far_line() != "" or _east_past_line() != "" or _east_past_rumour_count() != 0 or _east_line() != "" or _far_bell_line() != "" or _join_line() != "" or _south_line() != "" or _lane_south_line() != "" or _end_line() != "" or _end_rumour_count() != 0 or _south_rumour_count() != 0 or _bell_rumour_count() != 0 or _lane_busy_line() != "" or _busy_rumour_count() != 0 or _reached_rumour_count() != 0:
		push_error("smoke: the book line stayed after the filing was cleared")
		get_tree().quit(1)
		return
	var loaded_trust = rumour_loaded.get("trust", {})
	if typeof(loaded_trust) != TYPE_DICTIONARY:
		push_error("smoke: the road rumour save lost the book")
		get_tree().quit(1)
		return
	Trust.apply_state(loaded_trust)
	road.sync(Trust.has_action("parish_road_rumour"))
	var nessa_reloaded := false
	for row in _people_rows(world_snapshot()):
		if str(row.get("name", "")) == "Nessa Pod" and str(row.get("road_line", "")) == "The road is only a rumour." and str(row.get("join_line", "")) == "One stone marks the gate opening." and str(row.get("parish_bell_line", "")) == "A bell stands at the parish end." and str(row.get("parish_sale_line", "x")) == "" and str(row.get("hem_card_line", "")) == "The way steps past the margin strip." and str(row.get("hem_stone_card_line", "")) == "The way steps past the hem strip." and str(row.get("hem_stone_bell_card_line", "")) == "The way steps east of the hem stone." and str(row.get("hem_stone_on_bell_card_line", "")) == "The way steps east of the hem-stone bell." and str(row.get("hem_stone_far_bell_card_line", "")) == "The way steps past the hem-stone bell." and str(row.get("hem_stone_out_bell_card_line", "")) == "The way steps east of the far bell." and str(row.get("meadow_stone_strip_card_line", "")) == "The way steps east of the meadow-strip stone." and not bool(row.get("can_road", false)):
			nessa_reloaded = true
	if not road.all_shown() or _road_line() != "The book keeps the rumour of the road beyond the hedge." or not nessa_reloaded or Trust.level("nessa") != loam_trust or Economy.coins != kept_tin or _hem_east_line() != "The way steps past the margin strip." or _hem_east_rumour_count() != 1 or _hem_card_line() != "The way steps past the margin strip." or _hem_stone_line() != "The way steps past the hem strip." or _hem_stone_rumour_count() != 1 or _hem_stone_card_line() != "The way steps past the hem strip." or _hem_stone_bell_line() != "The way steps east of the hem stone." or _hem_stone_bell_rumour_count() != 1 or _hem_stone_bell_card_line() != "The way steps east of the hem stone." or _hem_stone_on_bell_line() != "The way steps east of the hem-stone bell." or _hem_stone_on_bell_rumour_count() != 1 or _hem_stone_on_bell_card_line() != "The way steps east of the hem-stone bell." or _hem_stone_far_bell_line() != "The way steps past the hem-stone bell." or _hem_stone_far_bell_rumour_count() != 1 or _hem_stone_far_bell_card_line() != "The way steps past the hem-stone bell." or _outer_strip_bell_stone_line() != "The way steps past the outer-strip bell." or _meadow_strip_bell_line() != "The way steps past the meadow-strip bell." or _meadow_stone_strip_line() != "The way steps east of the meadow-strip stone." or _farther_strip_bell_line() != "The way steps past the farther-strip bell." or _last_bell_stone_line() != "The way steps past the last bell stone." or _last_strip_bell_line() != "The way steps past the last-strip bell." or _end_strip_stone_line() != "The way steps east of the last-strip's stone." or _far_bell_stone_line() != "The way steps past the far bell stone." or _far_stone_strip_line() != "The way steps east of the far bell stone." or _outer_stone_strip_line() != "The way steps past the outer stone." or _hem_stone_out_bell_line() != "The way steps east of the far bell." or _hem_stone_out_bell_rumour_count() != 1 or _meadow_stone_strip_rumour_count() != 1 or _last_bell_stone_rumour_count() != 1 or _end_strip_stone_rumour_count() != 1 or _far_stone_strip_rumour_count() != 1 or _hem_stone_out_bell_card_line() != "The way steps east of the far bell." or _meadow_stone_strip_card_line() != "The way steps east of the meadow-strip stone." or _margin_east_line() != "The way steps past the edge-end bell." or _brink_east_line() != "The way steps past the verge-end bell." or _field_east_line() != "The way steps past the reach-end bell." or _reach_east_line() != "The way steps east of the reach-end bell." or _span_east_line() != "The way steps past the east-end bell." or _span_east_rumour_count() != 1 or _further_east_line() != "The way steps further east of the outer bell." or _further_east_rumour_count() != 1 or _outer_east_line() != "The way steps east of the outer-end bell." or _end_step_line() != "The way steps toward the end stone." or _end_step_rumour_count() != 1 or _west_turn_line() != "The way turns west of the far-south bell." or _west_turn_rumour_count() != 1 or _south_step_line() != "The way steps south of the gate-side bell." or _west_gate_bell_line() != "A bell stands beside the way toward the gate." or _west_gate_bell_rumour_count() != 1 or _east_closer_bell_line() != "A bell stands at the parish end." or _parish_sale_line() != "" or _gate_sale_line() != "" or _gate_sale_rumour_count() != 0 or _parish_sale_rumour_count() != 0 or _east_closer_bell_rumour_count() != 1 or _east_near_line() != "The way steps closer to the parish." or _east_far_line() != "A stone marks the east end." or _east_past_line() != "The way continues east past the bell." or _east_past_rumour_count() != 1 or _east_line() != "The way turns east at the end stone." or _far_bell_line() != "Three bells stand on the far lawn." or _join_line() != "One stone marks the gate opening." or _south_line() != "The way south ends at a stone." or _end_line() != "The way ends past the bench." or _end_rumour_count() != 1 or _south_rumour_count() != 1 or _bell_rumour_count() != 1 or _lane_south_line() != "" or _lane_busy_line() != "" or _busy_rumour_count() != 0 or _reached_rumour_count() != 0 or bool(ContentDB.venues.get("grove_park", {}).get("active", true)):
		push_error("smoke: a reload lost the filed rumour")
		get_tree().quit(1)
		return
	lane_afternoon_days.clear()
	for saved_day in rumour_saved:
		lane_afternoon_days.append(saved_day)
	Clock.day = rumour_clock_day
	Clock.set_hour(rumour_clock_hour)
	lane_bed.plant_id = lane_id
	lane_bed.growth = lane_growth
	lane_bed.taken = lane_taken
	var step_stones := get_tree().get_nodes_in_group("parish_stall_step")
	if step_stones.size() != 3:
		push_error("smoke: the stall step lost a stone")
		get_tree().quit(1)
		return
	for node in step_stones:
		var stone := node as Node3D
		if GardenLayout.on_track(stone.global_position.x, stone.global_position.z):
			push_error("smoke: a stall stone sat on the worn path")
			get_tree().quit(1)
			return
	Clock.day = lamp_day
	Clock.set_hour(lamp_hour)
	_lamps()
	var show_pear := soil.get_cell(9, 7)
	var pear_saved := show_pear.to_dict()
	_force_plant(9, 7, "mosspear", 0.72)
	show_pear.moisture = 0.74
	show_pear.fertility = 0.7
	if _plot_line(show_pear).find("Pear showing.") == -1 or _plot_line(show_pear).find("Pear-sweet.") != -1:
		push_error("smoke: a tall young mosspear stayed on its percent")
		get_tree().quit(1)
		return
	show_pear.growth = 0.5
	if _plot_line(show_pear).find("Pear showing.") != -1:
		push_error("smoke: a short mosspear said the pear was showing")
		get_tree().quit(1)
		return
	show_pear.growth = 0.72
	show_pear.fertility = 0.4
	if _plot_line(show_pear).find("Pear showing.") != -1 or _plot_line(show_pear).find("Needs feed.") == -1:
		push_error("smoke: a hungry mosspear said the pear was showing")
		get_tree().quit(1)
		return
	show_pear.fertility = 0.7
	show_pear.growth = 1.0
	if _plot_line(show_pear).find("Pear showing.") != -1:
		push_error("smoke: a ripe mosspear kept the young pear line")
		get_tree().quit(1)
		return
	show_pear.apply_dict(pear_saved)
	var show_bulb := soil.get_cell(8, 7)
	var bulb_saved := show_bulb.to_dict()
	_force_plant(8, 7, "nightlantern", 0.72)
	show_bulb.moisture = 0.74
	show_bulb.fertility = 0.5
	show_bulb.chem = "nightloam"
	if _plot_line(show_bulb).find("Light showing.") == -1 or _plot_line(show_bulb).find("Pegapear") != -1:
		push_error("smoke: a tall young nightlantern stayed on its percent")
		get_tree().quit(1)
		return
	show_bulb.chem = "base"
	if _plot_line(show_bulb).find("Light showing.") != -1 or _plot_line(show_bulb).find("Needs night-loam.") == -1:
		push_error("smoke: a lantern without loam said the light was showing")
		get_tree().quit(1)
		return
	show_bulb.chem = "nightloam"
	show_bulb.growth = 0.5
	if _plot_line(show_bulb).find("Light showing.") != -1:
		push_error("smoke: a short nightlantern said the light was showing")
		get_tree().quit(1)
		return
	show_bulb.growth = 1.0
	if _plot_line(show_bulb).find("Light showing.") != -1:
		push_error("smoke: a ripe nightlantern kept the young light line")
		get_tree().quit(1)
		return
	show_bulb.apply_dict(bulb_saved)
	var head_view := PlantView.new()
	add_child(head_view)
	head_view.show_plant("reed", 0.7, 0.8, 0.5)
	var young_heads := 0
	var young_warm := 0
	for head_node in head_view.get_children():
		var head_mesh := head_node as MeshInstance3D
		if head_mesh == null or not (head_mesh.mesh is SphereMesh):
			continue
		young_heads += 1
		var young_albedo: Color = (head_mesh.material_override as StandardMaterial3D).albedo_color
		if young_albedo.is_equal_approx(Color("#9a7040")):
			young_warm += 1
	head_view.show_plant("reed", 1.0, 0.8, 0.5)
	var ripe_heads := 0
	var ripe_warm := 0
	for ripe_node in head_view.get_children():
		var ripe_mesh := ripe_node as MeshInstance3D
		if ripe_mesh == null or not (ripe_mesh.mesh is SphereMesh):
			continue
		ripe_heads += 1
		var ripe_albedo: Color = (ripe_mesh.material_override as StandardMaterial3D).albedo_color
		if ripe_albedo.is_equal_approx(Color("#9a7040")):
			ripe_warm += 1
	if young_heads != 3 or young_warm != 0 or ripe_heads != 3 or ripe_warm != 3:
		push_error("smoke: a ripe reed head stayed brown")
		get_tree().quit(1)
		return
	head_view.queue_free()
	var pear_view := PlantView.new()
	add_child(pear_view)
	pear_view.show_plant("mosspear", 1.0, 0.8, 0.7)
	var pear_leaves := 0
	for pear_node in pear_view.get_children():
		var pear_mesh := pear_node as MeshInstance3D
		if pear_mesh == null or not (pear_mesh.mesh is BoxMesh):
			continue
		var pear_albedo: Color = (pear_mesh.material_override as StandardMaterial3D).albedo_color
		if pear_albedo.is_equal_approx(Color("#2f4a28")):
			pear_leaves += 1
	if pear_leaves != 2:
		push_error("smoke: the mosspear fruit had no leaf")
		get_tree().quit(1)
		return
	pear_view.queue_free()
	var lamp_view := PlantView.new()
	add_child(lamp_view)
	lamp_view.show_plant("nightlantern", 1.0, 0.8, 0.5)
	var lamp_leaves := 0
	var lamp_bulb := Color(0, 0, 0)
	var lamp_radius := 0.0
	for lamp_node in lamp_view.get_children():
		var lamp_mesh := lamp_node as MeshInstance3D
		if lamp_mesh == null:
			continue
		var lamp_albedo: Color = (lamp_mesh.material_override as StandardMaterial3D).albedo_color
		if lamp_mesh.mesh is BoxMesh and lamp_albedo.is_equal_approx(Color("#243628")):
			lamp_leaves += 1
		if lamp_mesh.mesh is SphereMesh and lamp_albedo.is_equal_approx(Color("#ffd27a")):
			lamp_bulb = lamp_albedo
			lamp_radius = (lamp_mesh.mesh as SphereMesh).radius
	if lamp_leaves != 2 or not lamp_bulb.is_equal_approx(Color("#ffd27a")) or absf(lamp_radius - 0.09) > 0.001:
		push_error("smoke: the nightlantern leaves changed the bulb")
		get_tree().quit(1)
		return
	lamp_view.queue_free()
	var cane_view := PlantView.new()
	add_child(cane_view)
	cane_view.show_plant("bramble", 0.78, 0.8, 0.5)
	var cane_leaves := 0
	var dark_berry := 0.0
	var lit_berry := 0.0
	for cane_node in cane_view.get_children():
		var cane_mesh := cane_node as MeshInstance3D
		if cane_mesh == null:
			continue
		var cane_albedo: Color = (cane_mesh.material_override as StandardMaterial3D).albedo_color
		if cane_mesh.mesh is BoxMesh and cane_albedo.is_equal_approx(Color("#1e3a22")):
			cane_leaves += 1
		if cane_mesh.mesh is SphereMesh and cane_albedo.is_equal_approx(Color("#5a1834")):
			dark_berry = (cane_mesh.mesh as SphereMesh).radius
		if cane_mesh.mesh is SphereMesh and cane_albedo.is_equal_approx(Color("#6a2040")):
			lit_berry = (cane_mesh.mesh as SphereMesh).radius
	if cane_leaves != 2 or absf(dark_berry - 0.22) > 0.001 or absf(lit_berry - 0.2) > 0.001:
		push_error("smoke: the bramble leaves changed the berries")
		get_tree().quit(1)
		return
	cane_view.queue_free()
	var ga: SoilCell = soil.get_cell(8, 6)
	var gb: SoilCell = soil.get_cell(9, 6)
	var gc: SoilCell = soil.get_cell(8, 7)
	var g_side: SoilCell = soil.get_cell(7, 6)
	var g_back: SoilCell = soil.get_cell(8, 5)
	var gene_snap: Array = [ga.to_dict(), gb.to_dict(), gc.to_dict(), g_side.to_dict(), g_back.to_dict()]
	var muted: Array = []
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "meadowbell" and plot.growth >= 1.0:
			muted.append([plot, plot.growth])
			plot.growth = 0.4
	ga.tilled = true
	gb.tilled = true
	gc.tilled = true
	g_side.tilled = false
	g_back.tilled = false
	g_side.plant_id = ""
	g_back.plant_id = ""
	ga.plant_id = "meadowbell"
	gb.plant_id = "meadowbell"
	gc.plant_id = ""
	ga.growth = 1.0
	gb.growth = 1.0
	ga.hue = 0.2
	gb.hue = 0.8
	ga.stature = 0.7
	gb.stature = 1.4
	ga.crop_yield = 0.6
	gb.crop_yield = 1.5
	ga.moisture = 0.9
	gb.moisture = 0.9
	gc.moisture = 0.9
	gc.fertility = 0.5
	if soil.seed_from("meadowbell") != "meadowbell" or gc.plant_id != "meadowbell" or gc.hue <= 0.2 or gc.hue >= 0.8 or _cross_line() == "":
		push_error("smoke: a cross did not take after both parents")
		get_tree().quit(1)
		return
	if PlantGenetics.price(10, 1.5) != 15 or PlantGenetics.price(5, 1.0) != 5:
		push_error("smoke: yield did not change the stall price")
		get_tree().quit(1)
		return
	ga.apply_dict(gene_snap[0])
	gb.apply_dict(gene_snap[1])
	gc.apply_dict(gene_snap[2])
	g_side.apply_dict(gene_snap[3])
	g_back.apply_dict(gene_snap[4])
	for pair in muted:
		var plot: SoilCell = pair[0]
		plot.growth = float(pair[1])
	var settle := ecology.force_spawn("bellhelp")
	settle.life = "visitor"
	settle.site_time = 20.0
	PetalDecide.forced = "keep visiting"
	ecology.try_promote(settle)
	if settle.life != "visitor":
		push_error("smoke: a keep-visiting decide still settled")
		get_tree().quit(1)
		return
	PetalDecide.forced = "settle"
	ecology.try_promote(settle)
	if settle.life != "settler":
		push_error("smoke: a settle decide left the visitor")
		get_tree().quit(1)
		return
	settle.queue_free()
	var shop_coins := Economy.coins
	var shop_peach := Economy.count("peach")
	Economy.add("peach", 1)
	var shopper := _person("nessa")
	shopper.present = true
	shopper.want = "peach"
	PetalDecide.forced = "buy"
	var deal := VillageShop.trade(shopper)
	if str(deal.get("choice", "")) != "buy" or int(deal.get("price", 0)) != 12 or Economy.coins != shop_coins + 12 or Economy.count("peach") != shop_peach:
		push_error("smoke: nessa did not buy the peach")
		get_tree().quit(1)
		return
	PetalDecide.forced = ""
	shopper.want = ""
	var pa: SoilCell = soil.get_cell(8, 6)
	var pb: SoilCell = soil.get_cell(9, 6)
	var plant_snap: Array = [pa.to_dict(), pb.to_dict()]
	var plant_muted: Array = []
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "meadowbell" and plot.growth >= 1.0:
			plant_muted.append([plot, plot.growth])
			plot.growth = 0.4
	pa.tilled = true
	pb.tilled = true
	pb.plant_id = "meadowbell"
	pb.growth = 1.0
	pb.hue = 0.2
	pb.stature = 0.7
	pb.crop_yield = 0.6
	pa.plant_id = ""
	pa.growth = 0.0
	pa.hue = 0.5
	pa.stature = 1.0
	pa.crop_yield = 1.0
	Economy.add("meadowbell_seed", 1)
	Economy.selected_seed = "meadowbell_seed"
	_plant(pa)
	if pa.plant_id != "meadowbell" or absf(pa.hue - 0.5) <= 0.02 or _plot_line(pa).find("Mixed.") == -1:
		push_error("smoke: a seed beside a ripe parent stayed the default")
		get_tree().quit(1)
		return
	pa.apply_dict(plant_snap[0])
	pb.apply_dict(plant_snap[1])
	for pair in plant_muted:
		var muted_plot: SoilCell = pair[0]
		muted_plot.growth = float(pair[1])
	shopper.present = true
	shopper.want = ""
	PetalDecide.forced = "peach"
	VillageShop.wish(shopper)
	if shopper.want != "peach" or _want_line() != "Nessa Pod is looking for Peach.":
		push_error("smoke: nessa did not ask for a peach")
		get_tree().quit(1)
		return
	Clock.set_hour(10.0)
	Economy.add("peach", 1)
	var filled_coins := Economy.coins
	var filled_price := _sell_price("peach")
	sell("peach")
	if Economy.coins != filled_coins + filled_price + 1 or shopper.want != "" or _want_line() != "":
		push_error("smoke: selling the peach nessa wanted did not pay the extra petal")
		get_tree().quit(1)
		return
	PetalDecide.forced = ""
	shopper.want = ""
	crate_yields = {"peach": [1.5]}
	if not SaveGame.write_slot(1, to_state()):
		push_error("smoke: a harvest yield did not save")
		get_tree().quit(1)
		return
	crate_yields = {}
	apply_state(SaveGame.read_slot(1))
	var kept_yield = crate_yields.get("peach", [])
	if typeof(kept_yield) != TYPE_ARRAY or kept_yield.is_empty() or absf(float(kept_yield[0]) - 1.5) > 0.001:
		push_error("smoke: a harvest yield did not survive a reload")
		get_tree().quit(1)
		return
	crate_yields = {}
	var look := ecology.force_spawn("bellhelp")
	look.global_position = GardenLayout.cell_center(2, 2)
	_inspect_face(look)
	if not look.inspected or look.mood != "happy" or str(events[0]).find("looks back") == -1 or bus.last_text("inspect") != "Bellhelp":
		push_error("smoke: a face click did not look back")
		get_tree().quit(1)
		return
	_clear_inspect()
	if look.inspected:
		push_error("smoke: a face stayed inspected")
		get_tree().quit(1)
		return
	Clock.running = true
	_toggle_time()
	if Clock.running or bus.last_text("time") != "rest":
		push_error("smoke: time would not rest")
		get_tree().quit(1)
		return
	_toggle_time()
	if not Clock.running:
		push_error("smoke: time would not move")
		get_tree().quit(1)
		return
	print("PETAL_SMOKE_OK")
	get_tree().quit(0)

func _awning_matches(open_hours: bool) -> bool:
	var stripes := get_tree().get_nodes_in_group("parish_awning")
	if stripes.size() != 7:
		return false
	for node in stripes:
		var stripe := node as MeshInstance3D
		if stripe == null or not (stripe.material_override is StandardMaterial3D):
			return false
		var got := (stripe.material_override as StandardMaterial3D).albedo_color
		var want: Color = stripe.get_meta("open_color") if open_hours else stripe.get_meta("shut_color")
		if absf(got.r - want.r) > 0.02 or absf(got.g - want.g) > 0.02 or absf(got.b - want.b) > 0.02:
			return false
	return true

func _rooms_asleep() -> bool:
	if get_tree().get_nodes_in_group("parish_room").size() != 3 or get_tree().get_nodes_in_group("parish_room_glass").size() != 5:
		return false
	for node in get_tree().get_nodes_in_group("parish_room"):
		var house_lamp := node as OmniLight3D
		if house_lamp == null or house_lamp.light_energy > float(house_lamp.get_meta("day_energy", 0.1)) * 1.15:
			return false
	for node in get_tree().get_nodes_in_group("parish_room_glass"):
		var pane := node as MeshInstance3D
		if pane == null or not (pane.material_override is StandardMaterial3D):
			return false
		if (pane.material_override as StandardMaterial3D).emission_energy_multiplier > 0.05:
			return false
	return true

func _rooms_awake() -> bool:
	if get_tree().get_nodes_in_group("parish_room").size() != 3 or get_tree().get_nodes_in_group("parish_room_glass").size() != 5:
		return false
	for node in get_tree().get_nodes_in_group("parish_room"):
		var house_lamp := node as OmniLight3D
		if house_lamp == null or house_lamp.light_energy < float(house_lamp.get_meta("day_energy", 0.1)) * 3.0:
			return false
	for node in get_tree().get_nodes_in_group("parish_room_glass"):
		var pane := node as MeshInstance3D
		if pane == null or not (pane.material_override is StandardMaterial3D):
			return false
		if (pane.material_override as StandardMaterial3D).emission_energy_multiplier < 0.9:
			return false
	return true

func _lamps() -> void:
	# ponytail: path lamps take the night and the mist; a second schedule if the rain should light them too.
	var night := Clock.hour() >= 19.5 or Clock.hour() < 5.0
	var lit := night or Clock.weather == "mist"
	var energy := 1.05 if lit else 0.35
	var glow := 1.55 if lit else 0.22
	for node in get_tree().get_nodes_in_group("parish_lantern"):
		var lamp := node as OmniLight3D
		if lamp:
			lamp.light_energy = energy
	for node in get_tree().get_nodes_in_group("parish_lantern_glass"):
		var glass := node as MeshInstance3D
		if glass and glass.material_override is ShaderMaterial:
			(glass.material_override as ShaderMaterial).set_shader_parameter("glow", glow)
	# ponytail: one stall lamp follows open hours; a second lamp if the shed should keep its own.
	var stall_energy := 0.62 if _stall_open() else 0.05
	for node in get_tree().get_nodes_in_group("parish_stall_lamp"):
		var stall_lamp := node as OmniLight3D
		if stall_lamp:
			stall_lamp.light_energy = stall_energy
	var stall_open := _stall_open()
	for node in get_tree().get_nodes_in_group("parish_awning"):
		var stripe := node as MeshInstance3D
		if stripe and stripe.material_override is StandardMaterial3D:
			var cloth: Color = stripe.get_meta("open_color") if stall_open else stripe.get_meta("shut_color")
			(stripe.material_override as StandardMaterial3D).albedo_color = cloth
	var sign_text := "Petal Stall  +1" if _lane_passers() > 0 else "Petal Stall"
	for node in get_tree().get_nodes_in_group("parish_stall_sign"):
		var sign := node as Label3D
		if sign:
			sign.text = sign_text
	var room_glow := 1.15 if night else 0.0
	for node in get_tree().get_nodes_in_group("parish_room"):
		var house_lamp := node as OmniLight3D
		if house_lamp:
			house_lamp.light_energy = float(house_lamp.get_meta("day_energy", 0.1)) * (4.5 if night else 1.0)
	for node in get_tree().get_nodes_in_group("parish_room_glass"):
		var pane := node as MeshInstance3D
		if pane and pane.material_override is StandardMaterial3D:
			(pane.material_override as StandardMaterial3D).emission_energy_multiplier = room_glow

func _run_capture() -> void:
	Settings.reduce_motion = true
	camera.snap_home()
	for spec in [[0, 0, "meadowbell"], [1, 0, "meadowbell"], [2, 1, "peach"], [3, 2, "bramble"], [4, 1, "mosspear"], [6, 5, "reed"], [7, 6, "reed"], [8, 5, "reed"]]:
		_force_plant(spec[0], spec[1], spec[2], 1.0)
	debug_grow()
	# ponytail: debug_grow ripens every bed; put the opening canes back so the shot shows berries that read and stay short of ripe.
	_force_plant(4, 2, "bramble", 0.78)
	_force_plant(5, 2, "bramble", 0.74)
	_force_plant(7, 5, "reed", 0.70)
	_force_plant(1, 1, "meadowbell", 0.76)
	_force_plant(1, 2, "meadowbell", 0.70)
	_sync_plants()
	Clock.set_hour(15.3)
	ecology.tick(0.2, world_snapshot())
	var jelly := ecology.first("bellhelp")
	if jelly == null:
		jelly = ecology.force_spawn("bellhelp")
	if jelly:
		jelly.reduce_motion = true
		jelly.global_position = GardenLayout.cell_center(1, 1) + Vector3(0.55, 0.15, 0.2)
		jelly.rotation.y = PI
		jelly.vel = Vector3.ZERO
	atmosphere.apply(Clock.hour(), Clock.weather, camera)
	await get_tree().create_timer(1.1).timeout
	await _shot("/workspace/docs/screenshots/wave1_overview.png")
	if jelly:
		jelly.reduce_motion = true
		jelly.global_position = Vector3(-10.6, 0.2, -1.4)
		jelly.rotation.y = PI
		jelly.vel = Vector3.ZERO
		camera.focus_on(jelly.global_position + Vector3(0, 0.28, 0), 2.15)
		await get_tree().create_timer(0.45).timeout
		await _shot("/workspace/docs/screenshots/wave1_jelly.png")
		_inspect_face(jelly)
		await get_tree().create_timer(0.45).timeout
		await _shot("/workspace/docs/screenshots/wave1_face.png")
		_clear_inspect()
	camera.focus_on(_person("lumen").global_position + Vector3(0, 0.62, 0), 5.4)
	await get_tree().create_timer(0.35).timeout
	await _shot("/workspace/docs/screenshots/wave1_lumen.png")
	camera.focus_on(GardenLayout.STALL + Vector3(0, 0.8, 0), 6.2)
	await get_tree().create_timer(0.35).timeout
	await _shot("/workspace/docs/screenshots/wave1_stall.png")
	hud.toggle_journal()
	refresh_panels()
	await get_tree().create_timer(0.3).timeout
	await _shot("/workspace/docs/screenshots/wave1_journal.png")
	hud.journal.visible = false
	Clock.set_hour(20.4)
	atmosphere.apply(Clock.hour(), Clock.weather, camera)
	camera.snap_home()
	await get_tree().create_timer(0.6).timeout
	await _shot("/workspace/docs/screenshots/wave1_night.png")
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var at := GardenLayout.POND_CENTER + Vector3(cos(angle), 0.0, sin(angle)) * (GardenLayout.POND_RADIUS + 0.5)
		_scoop(at)
	camera.focus_on(GardenLayout.POND_CENTER, 8.5)
	await get_tree().create_timer(0.45).timeout
	await _shot("/workspace/docs/screenshots/wave1_pond.png")
	print("PETAL_CAPTURE_OK")
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("/workspace/docs/screenshots")
	var err := image.save_png(path)
	print("SHOT ", path, " ", err, " ", image.get_width(), "x", image.get_height())

func _opening_plants() -> void:
	# ponytail: tall enough for the bells to read; ripe bells if Bellhelp should visit on the first day.
	_force_plant(1, 1, "meadowbell", 0.76)
	_force_plant(2, 1, "meadowbell", 0.72)
	_force_plant(1, 2, "meadowbell", 0.70)
	# ponytail: tall enough for the one fruit to read; a ripe peach if the lane should count it.
	_force_plant(3, 2, "peach", 0.72, 2)
	# ponytail: one young cane beside the peach; a ripe pear if the lane should count on the first day.
	_force_plant(4, 2, "bramble", 0.78, 2)
	# ponytail: the second cane is across the path; a tilled empty bed if rain should set it later.
	_force_plant(5, 2, "bramble", 0.74, 2)
	# ponytail: tall enough for the seed heads to read; a ripe reed if Bulrush should come on the first day.
	_force_plant(7, 5, "reed", 0.70, 2)
	# ponytail: one fed young pear so the leaf and the line are in the first garden.
	_force_plant(4, 1, "mosspear", 0.72)
	soil.get_cell(4, 1).fertility = 0.7
	# ponytail: one young lantern on night-loam so the leaves and the page are in the first garden.
	_force_plant(6, 4, "nightlantern", 0.72)
	var opening_lamp := soil.get_cell(6, 4)
	opening_lamp.moisture = 0.74
	opening_lamp.fertility = 0.5
	opening_lamp.chem = "nightloam"

func _feed_beds() -> void:
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.tilled:
			plot.fertility = maxf(plot.fertility, 0.7)

func _seed_open(seed_id: String) -> bool:
	for row in _stock(world_snapshot()):
		var item: Dictionary = row
		if str(item.get("id", "")) == seed_id:
			return not bool(item.get("locked", true))
	return false

func _force_plant(ix: int, iz: int, plant_id: String, growth: float, grow_day: int = 1) -> void:
	var plot := soil.get_cell(ix, iz)
	plot.tilled = true
	plot.plant_id = plant_id
	plot.growth = growth
	plot.moisture = 0.74
	plot.fertility = 0.38
	plot.taken = false
	plot.eaten_by = ""
	plot.grow_from_day = grow_day

func _build_patches() -> void:
	soil_lid = BoxMesh.new()
	soil_lid.size = Vector3(GardenLayout.CELL_W * 0.9, 0.03, GardenLayout.CELL_D * 0.88)
	# ponytail: overlapping lids hide the seam; one mesh per plot if the join still reads.
	bed_lid = BoxMesh.new()
	bed_lid.size = Vector3(GardenLayout.CELL_W * 1.06, 0.03, GardenLayout.CELL_D * 1.06)
	for cell in soil.all():
		var plot: SoilCell = cell
		var node := MeshInstance3D.new()
		node.mesh = soil_lid
		var material := StandardMaterial3D.new()
		material.roughness = 0.95
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		var shift := _row_shift(plot.ix, plot.iz)
		node.position = Vector3(center.x, 0.055, center.z) + shift
		node.rotation.y = float((plot.ix * 3 + plot.iz) % 5) * 0.22
		add_child(node)
		_scallop_patch(node, plot.ix, plot.iz)
		patches["%d,%d" % [plot.ix, plot.iz]] = node
	_build_bed_meadow()
	_scallop_lawn()
	highlight = MeshInstance3D.new()
	var cursor := BoxMesh.new()
	cursor.size = Vector3(GardenLayout.CELL_W * 0.94, 0.035, GardenLayout.CELL_D * 0.92)
	highlight.mesh = cursor
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.85, 0.45, 0.38)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight.material_override = material
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.visible = false
	add_child(highlight)

func _build_bed_meadow() -> void:
	# ponytail: leaf discs plus eight stems; a second rank if the rectangle still shows.
	var leaf := CylinderMesh.new()
	leaf.top_radius = 0.22
	leaf.bottom_radius = 0.24
	leaf.height = 0.02
	leaf.radial_segments = 7
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color("#163018")
	leaf_mat.roughness = 0.96
	leaf_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_add_bed_mesh(leaf, leaf_mat)
	var palette: Array[Color] = [
		Color("#6a3848"),
		# ponytail: the tan petal read as soil; this coral clipped to 255 under the sun.
		Color("#8d4a44"),
		Color("#4e6a40"),
		Color("#6a5078"),
	]
	# ponytail: the sun clips these petals to 255; cap the light, drop the cap if they go dull.
	var flower_mat := ShaderMaterial.new()
	flower_mat.shader = load("res://shaders/bed_flower.gdshader")
	for color in palette:
		_add_bed_mesh(_bed_flower(color), flower_mat)
	# ponytail: interior ranks are meadow; the shared blooms still dress the walks.
	var inside_leaf := StandardMaterial3D.new()
	inside_leaf.albedo_color = Color("#3e7a34")
	inside_leaf.roughness = 0.96
	inside_leaf.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_add_inside_mesh(leaf, inside_leaf)
	var inside_colors: Array[Color] = [Color("#3f6a32"), Color("#8d4a44"), Color("#4e7a36"), Color("#4a6e34")]
	for color in inside_colors:
		_add_inside_mesh(_bed_flower(color), flower_mat)
	_build_bed_turf()
	_build_bed_blades()
	_build_bed_frame()
	_bridge_lids()

func _build_bed_turf() -> void:
	# ponytail: flat discs over empty cells; a blade scatter if the discs still read as paint.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.36
	disc.bottom_radius = 0.38
	disc.height = 0.025
	disc.radial_segments = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#4e7a36")
	material.roughness = 0.96
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = disc
	bed_turf = MultiMeshInstance3D.new()
	bed_turf.name = "BedTurf"
	bed_turf.multimesh = multi
	bed_turf.material_override = material
	bed_turf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed_turf)

func _build_bed_blades() -> void:
	# ponytail: blades over the paint discs; a second mesh if the lids still read flat.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bed_blade_tri(tool, Vector3(-0.07, 0.0, 0.0), Vector3(0.07, 0.0, 0.0), Vector3(0.0, 0.46, 0.0))
	_bed_blade_tri(tool, Vector3(0.0, 0.0, -0.07), Vector3(0.0, 0.0, 0.07), Vector3(0.0, 0.4, 0.0))
	tool.generate_normals()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = tool.commit()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/lawn_tuft.gdshader")
	bed_blades = MultiMeshInstance3D.new()
	bed_blades.name = "BedBlades"
	bed_blades.multimesh = multi
	bed_blades.material_override = material
	bed_blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed_blades)

func _bed_blade_tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.set_uv(Vector2(0.0, 1.0))
	tool.add_vertex(a)
	tool.set_uv(Vector2(1.0, 1.0))
	tool.add_vertex(b)
	tool.set_uv(Vector2(0.5, 0.0))
	tool.add_vertex(c)

func _build_bed_frame() -> void:
	# ponytail: darker than the leaf discs; those rims clip to white under this sun.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.34
	disc.bottom_radius = 0.36
	disc.height = 0.02
	disc.radial_segments = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#345c2c")
	material.roughness = 0.96
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = disc
	bed_frame = MultiMeshInstance3D.new()
	bed_frame.name = "BedFrame"
	bed_frame.multimesh = multi
	bed_frame.material_override = material
	bed_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bed_frame.custom_aabb = AABB(Vector3(-14.0, -1.0, -12.0), Vector3(28.0, 4.0, 24.0))
	add_child(bed_frame)

func _bed_flower_count() -> int:
	var n := 0
	for bloom_i in bed_blooms.size():
		n += bed_blooms[bloom_i].multimesh.instance_count
	for bloom_i in bed_inside.size():
		n += bed_inside[bloom_i].multimesh.instance_count
	return n

func _add_bed_mesh(mesh: Mesh, material: Material) -> void:
	bed_blooms.append(_make_bed_mesh(mesh, material))

func _add_inside_mesh(mesh: Mesh, material: Material) -> void:
	bed_inside.append(_make_bed_mesh(mesh, material))

func _make_bed_mesh(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = multi
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.material_override = material
	add_child(inst)
	return inst

func _bed_flower(petal: Color) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_h := 0.32
	var stem_w := 0.014
	var stem_color := Color("#243c28")
	for flip in 2:
		var yaw := float(flip) * PI * 0.5
		var c := cos(yaw)
		var s := sin(yaw)
		var a := Vector3(-stem_w * c, 0.0, -stem_w * s)
		var b := Vector3(stem_w * c, 0.0, stem_w * s)
		var top := Vector3(stem_w * c, stem_h, stem_w * s)
		var tip := Vector3(-stem_w * c, stem_h, -stem_w * s)
		for point in [a, b, top, a, top, tip]:
			tool.set_color(stem_color)
			tool.add_vertex(point)
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var outer := Vector3(cos(angle) * 0.11, stem_h + 0.04, sin(angle) * 0.11)
		var left := Vector3(cos(angle - 0.5) * 0.04, stem_h + 0.01, sin(angle - 0.5) * 0.04)
		var right := Vector3(cos(angle + 0.5) * 0.04, stem_h + 0.01, sin(angle + 0.5) * 0.04)
		var heart := Vector3(0.0, stem_h + 0.02, 0.0)
		for point in [heart, left, outer, heart, outer, right]:
			tool.set_color(petal)
			tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()

func _bed_spot(center: Vector3, offset: Vector3, ix: int, iz: int, i: int) -> Vector3:
	# ponytail: a fixed nudge off the cell row; drop it if the flower lands on a worn walk.
	var jx := (float((ix * 5 + iz * 3 + i * 7) % 7) - 3.0) * 0.16
	var jz := (float((ix * 3 + iz * 5 + i * 11) % 5) - 2.0) * 0.16
	var nudged := center + offset + Vector3(jx, 0.0, jz) + _row_shift(ix, iz)
	if GardenLayout.on_path(nudged.x, nudged.z) or GardenLayout.on_track(nudged.x, nudged.z):
		return _edge_wave(center + offset)
	if GardenLayout.pond_distance(nudged.x, nudged.z) < GardenLayout.POND_RADIUS:
		return _edge_wave(center + offset)
	return _edge_wave(nudged)

func _row_shift(ix: int, iz: int) -> Vector3:
	# ponytail: interior cells leave the row; the outer wave still owns the rim.
	var interior := (ix == 1 or ix == 2 or ix == 3 or ix == 6 or ix == 7 or ix == 8) and (iz == 1 or iz == 2 or iz == 5 or iz == 6)
	if not interior:
		return Vector3.ZERO
	var jx := (float((ix * 5 + iz * 3) % 5) - 2.0) * 0.42
	var jz := (float((ix * 3 + iz * 5) % 5) - 2.0) * 0.34
	var center := GardenLayout.cell_center(ix, iz)
	if GardenLayout.on_path(center.x + jx, center.z + jz) or GardenLayout.on_track(center.x + jx, center.z + jz):
		return Vector3.ZERO
	if GardenLayout.pond_distance(center.x + jx, center.z + jz) < GardenLayout.POND_RADIUS:
		return Vector3.ZERO
	return Vector3(jx, 0.0, jz)

func _south_bed_x(x: float) -> bool:
	return (x >= -7.45 and x <= -2.75) or (x >= -1.95 and x <= 2.75)

func _west_bed_z(z: float) -> bool:
	return (z >= -5.45 and z <= -1.9) or (z >= -0.9 and z <= 2.65)

func _edge_wave(point: Vector3) -> Vector3:
	# ponytail: pull the outer rank onto a sine edge; leave it if the wave hits a walk.
	var x := point.x
	var z := point.z
	if _south_bed_x(x) and z < -4.3 and z > -6.0:
		var edge := -5.2 + sin(x * 1.6) * 0.62
		if z < edge:
			z = edge
	if _west_bed_z(z) and x < -6.0 and x > -8.0:
		var edge := -7.15 + sin(z * 1.7) * 0.55
		if x < edge:
			x = edge
	if _west_bed_z(z) and x > 1.5 and x < 3.5:
		var edge := 2.45 + sin(z * 1.7) * 0.5
		if x > edge:
			x = edge
	if _south_bed_x(x) and z > 1.5 and z < 3.2:
		var edge := 2.15 + sin(x * 1.6) * 0.4
		if z > edge:
			z = edge
	if _west_bed_z(z) and x > -3.7 and x < -2.65:
		var edge := -3.12 + sin(z * 1.7) * 0.32
		if x > edge:
			x = edge
	if _west_bed_z(z) and x > -2.05 and x < -1.05:
		var edge := -1.58 - sin(z * 1.7) * 0.32
		if x < edge:
			x = edge
	if GardenLayout.on_path(x, z) or GardenLayout.on_track(x, z):
		return point
	if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS:
		return point
	return Vector3(x, point.y, z)

func _outer_bite(x: float, z: float) -> bool:
	if not GardenLayout.in_plots(x, z, 0.0):
		return false
	if z <= -4.4 and z >= -5.55 and _south_bed_x(x):
		return true
	if x <= -6.4 and x >= -7.55 and _west_bed_z(z):
		return true
	if x >= 1.85 and x <= 2.85 and _west_bed_z(z):
		return true
	if z >= 1.7 and z <= 2.75 and _south_bed_x(x):
		return true
	return false

func _scallop_patch(node: MeshInstance3D, ix: int, iz: int) -> void:
	# ponytail: the outer lid face follows the same wave; a mesh per plot if the boxes still square.
	var center := GardenLayout.cell_center(ix, iz)
	var lid_x := GardenLayout.CELL_W * 1.06
	var lid_z := GardenLayout.CELL_D * 1.06
	if iz == 0:
		var wave_z := -5.2 + sin(center.x * 1.6) * 0.62
		var bite := wave_z - (center.z - lid_z * 0.5)
		if bite > 0.08:
			node.scale.z = maxf(0.35, (lid_z - bite) / lid_z)
			node.position.z += bite * 0.5
	if iz == 7:
		var wave_z := 2.15 + sin(center.x * 1.6) * 0.4
		var bite := (center.z + lid_z * 0.5) - wave_z
		if bite > 0.08:
			node.scale.z = maxf(0.35, (lid_z - bite) / lid_z)
			node.position.z -= bite * 0.5
	if ix == 0:
		var wave_x := -7.15 + sin(center.z * 1.7) * 0.55
		var bite := wave_x - (center.x - lid_x * 0.5)
		if bite > 0.08:
			node.scale.x = maxf(0.35, (lid_x - bite) / lid_x)
			node.position.x += bite * 0.5
	if ix == 9:
		var wave_x := 2.45 + sin(center.z * 1.7) * 0.5
		var bite := (center.x + lid_x * 0.5) - wave_x
		if bite > 0.08:
			node.scale.x = maxf(0.35, (lid_x - bite) / lid_x)
			node.position.x -= bite * 0.5
	if ix == 4:
		var wave_x := -3.12 + sin(center.z * 1.7) * 0.32
		var bite := (center.x + lid_x * 0.5) - wave_x
		if bite > 0.08:
			node.scale.x = maxf(0.35, (lid_x - bite) / lid_x)
			node.position.x -= bite * 0.5
	if ix == 5:
		var wave_x := -1.58 - sin(center.z * 1.7) * 0.32
		var bite := wave_x - (center.x - lid_x * 0.5)
		if bite > 0.08:
			node.scale.x = maxf(0.35, (lid_x - bite) / lid_x)
			node.position.x += bite * 0.5

func _scallop_lawn() -> void:
	# ponytail: meadow discs in the bites so the brown furrow does not draw the old line.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.28
	disc.bottom_radius = 0.3
	disc.height = 0.02
	disc.radial_segments = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#4e7a36")
	material.roughness = 0.96
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = disc
	var spots: Array[Vector3] = []
	var x := -7.2
	while x <= 2.5:
		if _south_bed_x(x):
			var wave := sin(x * 1.6) * 0.42
			if wave > 0.08:
				spots.append(Vector3(x, 0.07, -5.38 + wave * 0.5))
			var north := sin(x * 1.6 + 1.2) * 0.32
			if north < -0.06:
				spots.append(Vector3(x, 0.07, 2.45 + north * 0.5))
		x += 0.46
	var z := -5.2
	while z <= 2.4:
		if _west_bed_z(z):
			var wave := sin(z * 1.7) * 0.38
			if wave > 0.08:
				spots.append(Vector3(-7.28 + wave * 0.5, 0.07, z))
			var east := sin(z * 1.7 + 0.8) * 0.32
			if east < -0.06:
				spots.append(Vector3(2.55 + east * 0.5, 0.07, z))
			var seam := sin(z * 1.7) * 0.32
			if seam < -0.08:
				spots.append(Vector3(-3.05 + seam * 0.5, 0.07, z))
				spots.append(Vector3(-1.65 - seam * 0.5, 0.07, z))
		z += 0.46
	multi.instance_count = spots.size()
	for i in spots.size():
		var basis := Basis(Vector3.UP, float(i) * 0.4)
		multi.set_instance_transform(i, Transform3D(basis, spots[i]))
	var node := MultiMeshInstance3D.new()
	node.name = "BedScallop"
	node.multimesh = multi
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func _fill_bed_meadow() -> void:
	var leaves: Array[Vector3] = [
		Vector3(-0.26, 0.04, -0.2),
		Vector3(0.0, 0.045, -0.22),
		Vector3(0.26, 0.04, -0.18),
		Vector3(-0.24, 0.04, 0.02),
		Vector3(0.02, 0.05, 0.0),
		Vector3(0.26, 0.04, 0.04),
		Vector3(-0.22, 0.04, 0.22),
		Vector3(0.04, 0.045, 0.22),
		Vector3(0.26, 0.04, 0.2),
	]
	var spots: Array[Vector3] = [
		Vector3(-0.28, 0.03, -0.22),
		Vector3(-0.06, 0.03, -0.24),
		Vector3(0.16, 0.03, -0.16),
		Vector3(0.3, 0.03, 0.0),
		Vector3(-0.24, 0.03, 0.08),
		Vector3(0.02, 0.03, 0.1),
		Vector3(0.22, 0.03, 0.2),
		Vector3(-0.04, 0.03, 0.26),
	]
	var buckets: Array = [[], [], [], [], []]
	var inside_rows: Array = [[], [], [], [], []]
	var turf: Array[Transform3D] = []
	var blades: Array[Transform3D] = []
	var blade_tints: Array[Color] = []
	var blade_colors: Array[Color] = [Color("#2f5a28"), Color("#3a6840"), Color("#345c30")]
	var turf_offsets: Array[Vector3] = [
		Vector3(-0.2, 0.16, -0.14),
		Vector3(0.2, 0.16, -0.12),
		Vector3(-0.16, 0.16, 0.16),
		Vector3(0.18, 0.16, 0.14),
		Vector3(0.0, 0.16, 0.0),
	]
	for cell in soil.all():
		var plot: SoilCell = cell
		if not _meadow_cell(plot):
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		for n in turf_offsets.size():
			# ponytail: stay on the cell; _bed_spot walks the flowers, and that shift uncovered the furrow.
			var jx := (float((plot.ix * 3 + n * 5) % 5) - 2.0) * 0.05
			var jz := (float((plot.iz * 3 + n * 7) % 5) - 2.0) * 0.05
			var cover := center + turf_offsets[n] + Vector3(jx, 0.0, jz)
			if GardenLayout.on_path(cover.x, cover.z) or GardenLayout.on_track(cover.x, cover.z):
				continue
			if GardenLayout.pond_distance(cover.x, cover.z) < GardenLayout.POND_RADIUS:
				continue
			var turf_spin := float((plot.ix + plot.iz + n) % 5) * 0.4
			var turf_scale := 1.35 + float((plot.ix + n) % 3) * 0.08
			var reach := 0.36 * turf_scale
			var hits_ns := absf(cover.x + 2.35) < 0.22 + reach and cover.z > -6.2 and cover.z < 3.35
			var hits_north := absf(cover.z - 3.5) < 0.22 + reach and cover.x > -7.2 and cover.x < -1.0
			var hits_south := absf(cover.z + 6.35) < 0.22 + reach and cover.x > -8.2 and cover.x < 1.2
			if hits_ns or hits_north or hits_south:
				continue
			var turf_basis := Basis(Vector3.UP, turf_spin).scaled(Vector3(turf_scale, 1.0, turf_scale))
			turf.append(Transform3D(turf_basis, cover))
			for b in 3:
				var bspin := turf_spin + float(b) * 1.2
				var bscale := 0.85 + float(b) * 0.18
				var bbasis := Basis(Vector3.UP, bspin).scaled(Vector3(bscale, bscale * 1.15, bscale))
				blades.append(Transform3D(bbasis, cover + Vector3(0.0, 0.02, 0.0)))
				blade_tints.append(blade_colors[b])
		var at := Vector3.ZERO
		var spin := 0.0
		var scale := 1.0
		var basis := Basis.IDENTITY
		# ponytail: one fuller clump per empty cell; a third rank if the lid still draws a square.
		for i in leaves.size():
			at = _bed_spot(center, leaves[i], plot.ix, plot.iz, i)
			spin = float((plot.ix * 3 + plot.iz + i) % 5) * 0.4
			scale = 1.35 + float((plot.iz + i) % 3) * 0.16
			basis = Basis(Vector3.UP, spin).scaled(Vector3(scale, 1.0, scale))
			inside_rows[0].append(Transform3D(basis, at))
		for i in spots.size():
			at = _bed_spot(center, spots[i], plot.ix, plot.iz, i)
			spin = float((plot.ix * 5 + plot.iz * 3 + i) % 7) * 0.35
			scale = 1.45 + float((plot.ix + i) % 3) * 0.28
			basis = Basis(Vector3.UP, spin).scaled(Vector3.ONE * scale)
			inside_rows[1 + (plot.ix + plot.iz + i) % 4].append(Transform3D(basis, at))
		var gaps: Array[Vector3] = [
			Vector3(-0.14, 0.03, -0.06),
			Vector3(0.12, 0.03, 0.02),
			Vector3(-0.08, 0.03, 0.16),
			Vector3(0.18, 0.03, -0.14),
		]
		for i in gaps.size():
			at = _bed_spot(center, gaps[i], plot.ix, plot.iz, i)
			spin = float((plot.ix + plot.iz + i) % 6) * 0.5
			basis = Basis(Vector3.UP, spin).scaled(Vector3.ONE * 1.25)
			inside_rows[1 + (plot.ix + i) % 4].append(Transform3D(basis, at))
	# ponytail: eight flowers on the rim of a planted cell; the stem stays clear.
	var rim: Array[Vector3] = [
		Vector3(-0.38, 0.03, -0.32),
		Vector3(0.38, 0.03, -0.30),
		Vector3(-0.36, 0.03, 0.32),
		Vector3(0.36, 0.03, 0.34),
		Vector3(0.0, 0.03, -0.38),
		Vector3(0.0, 0.03, 0.38),
		Vector3(-0.40, 0.03, 0.0),
		Vector3(0.40, 0.03, 0.02),
	]
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "" or not _joined_bed(plot):
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		for i in rim.size():
			var at := _bed_spot(center, rim[i], plot.ix, plot.iz, i)
			if GardenLayout.on_path(at.x, at.z):
				continue
			if GardenLayout.pond_distance(at.x, at.z) < GardenLayout.POND_RADIUS:
				continue
			var spin := float((plot.ix + plot.iz + i) % 6) * 0.45
			var basis := Basis(Vector3.UP, spin).scaled(Vector3.ONE * 1.05)
			inside_rows[1 + (plot.ix + i) % 4].append(Transform3D(basis, at))
	_bridge_into(buckets)
	_path_lips(buckets)
	_bed_skirt(buckets)
	_edge_lips(buckets)
	_stone_gaps(buckets)
	_wide_shoulders(buckets)
	_track_meadow(buckets)
	_worn_lips(buckets)
	_meadow_outline(inside_rows)
	_bed_frames()
	for i in bed_blooms.size():
		var multi := bed_blooms[i].multimesh
		var rows: Array = buckets[i]
		multi.instance_count = rows.size()
		for n in rows.size():
			multi.set_instance_transform(n, rows[n])
	for i in bed_inside.size():
		var inside_multi := bed_inside[i].multimesh
		var inside: Array = inside_rows[i]
		inside_multi.instance_count = inside.size()
		for n in inside.size():
			inside_multi.set_instance_transform(n, inside[n])
	if bed_turf != null:
		var turf_multi := bed_turf.multimesh
		turf_multi.instance_count = turf.size()
		for n in turf.size():
			turf_multi.set_instance_transform(n, turf[n])
	if bed_blades != null:
		var blade_multi := bed_blades.multimesh
		blade_multi.instance_count = blades.size()
		for n in blades.size():
			blade_multi.set_instance_transform(n, blades[n])
			blade_multi.set_instance_color(n, blade_tints[n])
			blade_multi.set_instance_custom_data(n, Color(float(n % 7) / 7.0, 0.0, 0.0, 1.0))

func _meadow_outline(inside_rows: Array) -> void:
	# ponytail: one ribbon joins the four beds across the seam; a hull if the boxes still read apart.
	var n := 0
	var x := -7.15
	while x <= 2.45:
		if absf(x + 2.35) > 1.15:
			var z := -2.22
			while z <= -0.58:
				_outline_drop(inside_rows, x, z + sin(x * 1.15) * 0.08, n)
				n += 1
				z += 0.26
		x += 0.32

func _outline_drop(inside_rows: Array, x: float, z: float, n: int) -> void:
	if GardenLayout.on_path(x, z) or GardenLayout.on_track(x, z):
		return
	if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.35:
		return
	# ponytail: flat discs above the seam flowers; sun-facing petals clip to white.
	var scale := 2.8
	var reach := 0.22 * scale
	if absf(x + 2.35) < 0.46 + reach and z > -6.2 and z < 3.35:
		return
	var y := GardenLayout.height_at(x, z) + 0.78
	var spin := float(n % 5) * 0.5
	var basis := Basis(Vector3.UP, spin).scaled(Vector3(scale, 1.0, scale))
	inside_rows[0].append(Transform3D(basis, Vector3(x, y, z)))

func _bed_frames() -> void:
	# ponytail: meadow over the dark lid edges; a hull if the four boxes still read.
	if bed_frame == null:
		return
	var rows: Array[Transform3D] = []
	var n := 0
	var bands: Array[Rect2] = [
		Rect2(-7.2, -5.2, 9.7, 3.05),
		Rect2(-7.2, -0.75, 9.7, 3.15),
	]
	for band in bands:
		var x := band.position.x
		while x <= band.position.x + band.size.x:
			if absf(x + 2.35) > 1.15:
				var z := band.position.y
				while z <= band.position.y + band.size.y:
					_frame_drop(rows, x, z + sin(x * 1.3) * 0.06, n)
					n += 1
					z += 0.46
			x += 0.48
	var corners: Array[Vector3] = [
		Vector3(-7.28, 1.3, -5.4),
		Vector3(2.55, 1.6, -6.15),
		Vector3(2.55, 1.4, 2.35),
		Vector3(-7.2, 1.4, 2.35),
	]
	for corner in corners:
		_corner_drop(rows, corner.x, corner.z, corner.y, n)
		_corner_drop(rows, corner.x + 0.16, corner.z + 0.1, corner.y, n + 1)
		_corner_drop(rows, corner.x - 0.14, corner.z + 0.12, corner.y, n + 2)
		n += 3
	_meadow_hull(rows, n)
	var multi := bed_frame.multimesh
	multi.instance_count = rows.size()
	for i in rows.size():
		multi.set_instance_transform(i, rows[i])

func _frame_drop(rows: Array[Transform3D], x: float, z: float, n: int) -> void:
	if GardenLayout.on_path(x, z) or GardenLayout.on_track(x, z):
		return
	if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.35:
		return
	var scale := 2.0
	var reach := 0.34 * scale
	if absf(x + 2.35) < 0.46 + reach and z > -6.2 and z < 3.35:
		return
	if absf(z + 6.35) < 0.5 + reach and x > -8.2 and x < 1.2:
		return
	if absf(z - 3.5) < 0.46 + reach and x > -7.2 and x < -1.0:
		return
	var y := GardenLayout.height_at(x, z) + 0.22
	var spin := float(n % 5) * 0.5
	var basis := Basis(Vector3.UP, spin).scaled(Vector3(scale, 1.0, scale))
	rows.append(Transform3D(basis, Vector3(x, y, z)))

func _meadow_hull(rows: Array[Transform3D], n: int) -> void:
	# ponytail: lip above the skirt flowers; 0.78 sat under the petals.
	var z := -5.2
	while z <= 2.5:
		var sway := sin(z * 1.2) * 0.1
		_hull_drop(rows, 3.15 - sway, z, 2.2, 1.45, n)
		n += 1
		z += 0.42
	z = -4.7
	while z <= 2.55:
		var swayw := sin(z * 1.2) * 0.1
		_hull_drop(rows, -8.05 + swayw, z, 2.2, 1.45, n)
		n += 1
		z += 0.42
	_hull_drop(rows, 2.9, -5.35, 2.2, 1.45, n)
	_hull_drop(rows, 2.9, 2.7, 2.2, 1.45, n + 1)
	_hull_drop(rows, -8.0, 2.55, 2.2, 1.45, n + 2)
	n += 3
	# ponytail: scale stays under the path reach; a wider lip would cover the worn walks.
	var x := -7.5
	while x <= 2.6:
		var swayn := sin(x * 1.3) * 0.05
		_hull_drop(rows, x, 2.48 + swayn, 1.55, 1.45, n)
		_hull_drop(rows, x, -5.28 + swayn, 1.55, 1.45, n + 1)
		n += 2
		x += 0.36

func _hull_drop(rows: Array[Transform3D], x: float, z: float, scale: float, lift: float, n: int) -> void:
	if GardenLayout.on_path(x, z) or GardenLayout.on_track(x, z):
		return
	if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.35:
		return
	var reach := 0.34 * scale
	if absf(x + 2.35) < 0.46 + reach and z > -6.2 and z < 3.35:
		return
	if absf(z + 6.35) < 0.5 + reach and x > -8.2 and x < 1.2:
		return
	if absf(z - 3.5) < 0.46 + reach and x > -7.2 and x < -1.0:
		return
	var y := GardenLayout.height_at(x, z) + lift
	var spin := float(n % 5) * 0.5
	var basis := Basis(Vector3.UP, spin).scaled(Vector3(scale, 1.0, scale))
	rows.append(Transform3D(basis, Vector3(x, y, z)))

func _corner_drop(rows: Array[Transform3D], x: float, z: float, scale: float, n: int) -> void:
	# ponytail: small discs on the tan corners; the south path is 0.7 m away.
	if GardenLayout.on_path(x, z) or GardenLayout.on_track(x, z):
		return
	if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.35:
		return
	var reach := 0.34 * scale
	if absf(x + 2.35) < 0.46 + reach and z > -6.2 and z < 3.35:
		return
	if absf(z + 6.35) < 0.5 + reach and x > -8.2 and x < 1.2:
		return
	if absf(z - 3.5) < 0.46 + reach and x > -7.2 and x < -1.0:
		return
	var y := GardenLayout.height_at(x, z) + 0.45
	var spin := float(n % 5) * 0.5
	var basis := Basis(Vector3.UP, spin).scaled(Vector3(scale, 8.0, scale))
	rows.append(Transform3D(basis, Vector3(x, y, z)))

func _bridge_lids() -> void:
	# ponytail: two strips between the north and south plots; the path stays open.
	_bridge_lid("BedBridgeWest", Vector3(-5.12, 0.055, -1.4), Vector3(4.2, 0.03, 0.95))
	_bridge_lid("BedBridgeEast", Vector3(0.42, 0.055, -1.4), Vector3(4.2, 0.03, 0.95))

func _bridge_lid(node_name: String, at: Vector3, size: Vector3) -> void:
	# ponytail: short planks on the sine; one mesh again if the strip has to read as a board.
	var root := Node3D.new()
	root.name = node_name
	add_child(root)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#1c3420")
	material.roughness = 0.96
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var x0 := at.x - size.x * 0.5
	var i := 0
	while float(i) * 0.42 < size.x - 0.05:
		if i % 3 != 2:
			var mid := x0 + float(i) * 0.42 + 0.21
			var wave := sin(mid * 1.7) * 0.72
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.3, size.y, size.z * 0.62)
			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.position = Vector3(mid, at.y, at.z + wave)
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(node)
		i += 1

func _bridge_into(buckets: Array) -> void:
	# ponytail: tighter blooms on the two strips; the worn center stays the gap.
	var bands: Array[Rect2] = [
		Rect2(-7.25, -1.88, 4.25, 0.95),
		Rect2(-1.72, -1.88, 4.25, 0.95),
	]
	var n := 0
	for band in bands:
		var x := band.position.x + 0.14
		while x <= band.position.x + band.size.x - 0.14:
			var z := band.position.y + 0.12
			while z <= band.position.y + band.size.y - 0.12:
				if not GardenLayout.on_path(x, z) and not GardenLayout.on_track(x, z):
					var spot := _bridge_spot(x, z, n, band)
					var wave := sin(spot.x * 1.7) * 0.72
					var zz := spot.y + wave
					if GardenLayout.on_path(spot.x, zz) or GardenLayout.on_track(spot.x, zz):
						zz = spot.y
					if GardenLayout.pond_distance(spot.x, zz) < GardenLayout.POND_RADIUS:
						zz = spot.y
					var at := Vector3(spot.x, GardenLayout.height_at(spot.x, zz) + 0.05, zz)
					var spin := float((n * 3) % 5) * 0.5
					var leaf_scale := 0.95 + float(n % 3) * 0.12
					var bloom_scale := 1.85 + float(n % 3) * 0.25
					var basis := Basis(Vector3.UP, spin).scaled(Vector3(leaf_scale, 1.0, leaf_scale))
					buckets[0].append(Transform3D(basis, at))
					basis = Basis(Vector3.UP, spin).scaled(Vector3.ONE * bloom_scale)
					buckets[1 + (n % 4)].append(Transform3D(basis, at + Vector3(0.06, 0.0, 0.04)))
					n += 1
				z += 0.22
			x += 0.28

func _bridge_spot(x: float, z: float, n: int, band: Rect2) -> Vector2:
	# ponytail: columns clump and leave a gap; drop the nudge if the bloom leaves the strip or the walk. n stays for a later per-bloom break.
	var col := int(round((x - band.position.x) / 0.28))
	var row := int(round((z - band.position.y) / 0.22))
	var jx := (float((col * 3) % 5) - 2.0) * 0.16
	var jz := (float((row * 2 + col) % 3) - 1.0) * 0.06
	var nudged := Vector2(x + jx, z + jz)
	if not band.grow(0.06).has_point(nudged):
		return Vector2(x, z)
	if GardenLayout.on_path(nudged.x, nudged.y) or GardenLayout.on_track(nudged.x, nudged.y):
		return Vector2(x, z)
	if GardenLayout.pond_distance(nudged.x, nudged.y) < GardenLayout.POND_RADIUS:
		return Vector2(x, z)
	return nudged

func _bed_skirt(buckets: Array) -> void:
	# ponytail: the outer sides wave in and out; a deeper bay if a side still reads straight.
	var step := 0
	var z := -5.7
	while z <= 2.75:
		var side := -1.0
		while side <= 1.0:
			var edge := -7.46 if side < 0.0 else 2.76
			var wave := sin(z * 1.7 + side) * 0.72
			var at := edge + side * (0.28 + wave)
			_skirt_drop(buckets, at, z, step, false, false, true)
			_skirt_drop(buckets, at + side * 0.16, z + 0.1, step + 1, false, false, true)
			_skirt_drop(buckets, at - side * 0.1, z - 0.08, step + 2, false, false, true)
			step += 3
			side += 2.0
		z += 0.38
	var x := -7.5
	while x <= 2.9:
		var sway := sin(x * 1.6) * 0.62
		_skirt_drop(buckets, x, -5.2 + sway, step, false, false, true)
		_skirt_drop(buckets, x + 0.18, -5.2 + sin(x * 1.6 + 0.9) * 0.62, step + 1, false, false, true)
		_skirt_drop(buckets, x, 2.35 + sway * 0.75, step + 2, false, false, true)
		_skirt_drop(buckets, x + 0.18, 2.35 + sin(x * 1.6 + 0.9) * 0.46, step + 3, false, false, true)
		step += 4
		x += 0.42
	# ponytail: four corner clumps past the box; drop one if it lands on a worn walk.
	var corners: Array[Vector3] = [
		Vector3(-8.5, 0.0, -5.65),
		Vector3(-8.85, 0.0, -6.15),
		Vector3(-8.35, 0.0, -6.55),
		Vector3(3.55, 0.0, -5.65),
		Vector3(3.95, 0.0, -6.2),
		Vector3(3.4, 0.0, -6.6),
		Vector3(-8.5, 0.0, 2.95),
		Vector3(-8.85, 0.0, 3.4),
		Vector3(-8.35, 0.0, 3.7),
		Vector3(3.55, 0.0, 2.95),
		Vector3(3.95, 0.0, 3.4),
		Vector3(3.4, 0.0, 3.7),
	]
	for corner in corners:
		_skirt_drop(buckets, corner.x, corner.z, step)
		step += 1

func _edge_lips(buckets: Array) -> void:
	# ponytail: flowers on the south and north lips; the track center stays open.
	var step := 0
	var x := -7.3
	while x <= 0.7:
		if absf(x + 2.35) > 0.3:
			_skirt_drop(buckets, x, -6.68, step, true)
			_skirt_drop(buckets, x, -6.02, step + 1, true)
			step += 2
		x += 0.42
	x = -6.8
	while x <= -1.3:
		if absf(x + 2.35) > 0.3:
			_skirt_drop(buckets, x, 3.22, step, true)
			_skirt_drop(buckets, x, 3.78, step + 1, true)
			step += 2
		x += 0.42

func _stone_gaps(buckets: Array) -> void:
	# ponytail: a clump beside the worn line; the center stays open.
	var step := 0
	for run in GardenLayout._narrow_runs():
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var dir := b - a
		dir.y = 0.0
		var span := dir.length()
		if span < 0.2:
			continue
		dir /= span
		var side := Vector3(-dir.z, 0.0, dir.x)
		var along := 0.85
		while along < span - 0.55:
			for hand in [-1.0, 1.0]:
				var side_step := float(hand)
				var heart := a + dir * along + side * (side_step * 0.34)
				for petal in 3:
					var spin := float(petal) * TAU / 3.0 + side_step
					var at := heart + Vector3(cos(spin) * 0.07, 0.0, sin(spin) * 0.07)
					if GardenLayout.on_track(at.x, at.z) or GardenLayout.in_plots(at.x, at.z, 0.0):
						continue
					_skirt_drop(buckets, at.x, at.z, step, false, true)
					step += 1
			along += 1.25

func _wide_center(at: Vector3) -> bool:
	if absf(at.x + 4.55) < 0.18 and at.z > 3.2 and at.z < 5.5:
		return true
	return absf(at.z + 2.5) < 0.18 and at.x > 2.2 and at.x < 6.8

func _wide_shoulders(buckets: Array) -> void:
	# ponytail: taller blooms on the outer half; drop the scale if they cover the worn center.
	var runs: Array = [
		[Vector3(-4.55, 0.0, 3.55), Vector3(-4.55, 0.0, 4.7)],
		[Vector3(2.75, 0.0, -2.5), Vector3(4.35, 0.0, -2.5)],
	]
	var step := 0
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var dir := b - a
		dir.y = 0.0
		var span := dir.length()
		if span < 0.2:
			continue
		dir /= span
		var side := Vector3(-dir.z, 0.0, dir.x)
		var along := 0.15
		while along < span - 0.1:
			for hand in [-1.0, 1.0]:
				var side_step := float(hand)
				var heart := a + dir * along + side * (side_step * 0.4)
				if _wide_center(heart):
					continue
				var y := GardenLayout.height_at(heart.x, heart.z) + 0.05
				for petal in 5:
					var spin := float(petal) * TAU / 5.0 + side_step
					var at := heart + Vector3(cos(spin) * 0.1, 0.0, sin(spin) * 0.1)
					if _wide_center(at):
						continue
					if GardenLayout.pond_distance(at.x, at.z) < GardenLayout.POND_RADIUS + 0.35:
						continue
					if GardenLayout.in_plots(at.x, at.z, 0.0):
						continue
					var basis := Basis(Vector3.UP, spin).scaled(Vector3.ONE * 1.8)
					var pos := Vector3(at.x, y, at.z)
					buckets[0].append(Transform3D(basis, pos))
					buckets[1 + (step % 4)].append(Transform3D(basis, pos))
					step += 1
			along += 0.32

func _track_meadow(buckets: Array) -> void:
	# ponytail: flowers on the old bed tracks; a worn line if feet need one.
	var step := 0
	var offsets: Array[float] = [-0.28, 0.0, 0.28]
	for run in GardenLayout._narrow_runs():
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var dir := b - a
		dir.y = 0.0
		var span := dir.length()
		if span < 0.2:
			continue
		dir /= span
		var side := Vector3(-dir.z, 0.0, dir.x)
		var along := 0.2
		while along < span - 0.15:
			for lateral in offsets:
				var at := a + dir * along + side * lateral
				_skirt_drop(buckets, at.x, at.z, step, false, true)
				step += 1
			along += 0.42

func _skirt_drop(buckets: Array, x: float, z: float, step: int, shoulders := false, open_track := false, rim := false) -> void:
	var blocked := false
	if not open_track:
		blocked = GardenLayout.on_track(x, z) if shoulders else GardenLayout.on_path(x, z)
	if blocked or GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.35:
		return
	if GardenLayout.in_plots(x, z, 0.0) and not (rim and _outer_bite(x, z)):
		return
	var at := Vector3(x, GardenLayout.height_at(x, z) + 0.05, z)
	var spin := float(step % 5) * 0.55
	var scale := 0.86 + float(step % 3) * 0.14
	var basis := Basis(Vector3.UP, spin).scaled(Vector3(scale, 1.0, scale))
	buckets[0].append(Transform3D(basis, at))
	if step % 2 == 0:
		basis = Basis(Vector3.UP, spin + 0.4).scaled(Vector3.ONE * (scale + 0.1))
		buckets[1 + (step % 4)].append(Transform3D(basis, at + Vector3(0.05, 0.0, 0.04)))

func _path_lips(buckets: Array) -> void:
	# ponytail: the lips wave into the beds; the worn center stays dirt.
	var step := 0
	var z := -5.0
	while z < 2.35:
		var wave := sin(z * 1.7) * 0.32
		var west := -3.12 + wave
		var east := -1.58 - wave
		if not GardenLayout.on_path(west, z) and not GardenLayout.on_track(west, z) and GardenLayout.pond_distance(west, z) >= GardenLayout.POND_RADIUS:
			_lip_bloom(buckets, west, z, step)
			_lip_bloom(buckets, west - 0.16, z + 0.06, step + 1)
			step += 2
		if not GardenLayout.on_path(east, z) and not GardenLayout.on_track(east, z) and GardenLayout.pond_distance(east, z) >= GardenLayout.POND_RADIUS:
			_lip_bloom(buckets, east, z, step)
			_lip_bloom(buckets, east + 0.16, z + 0.06, step + 1)
			step += 2
		z += 0.38

func _lip_bloom(buckets: Array, x: float, z: float, step: int) -> void:
	var at := Vector3(x, GardenLayout.height_at(x, z) + 0.05, z)
	var spin := float(step % 5) * 0.55
	var scale := 0.85 + float(step % 3) * 0.1
	var basis := Basis(Vector3.UP, spin).scaled(Vector3(scale, 1.0, scale))
	buckets[0].append(Transform3D(basis, at))
	if step % 2 == 0:
		basis = Basis(Vector3.UP, spin).scaled(Vector3.ONE * (scale + 0.15))
		buckets[1 + (step % 4)].append(Transform3D(basis, at))

func _worn_lips(buckets: Array) -> void:
	# ponytail: flowers beside the spur and the pond path; the worn center stays open.
	var step := _lip_run(buckets, Vector3(-4.55, 0.0, 3.55), Vector3(-4.55, 0.0, 4.75), 0)
	_lip_run(buckets, Vector3(2.75, 0.0, -2.5), Vector3(4.55, 0.0, -2.5), step)

func _lip_run(buckets: Array, a: Vector3, b: Vector3, step: int) -> int:
	var dir := b - a
	dir.y = 0.0
	var span := dir.length()
	if span < 0.2:
		return step
	dir /= span
	var side := Vector3(-dir.z, 0.0, dir.x)
	var laterals: Array[float] = [0.58, 0.76, -0.58, -0.76]
	var along := 0.12
	while along < span - 0.08:
		for lateral in laterals:
			var at := a + dir * along + side * lateral
			_skirt_drop(buckets, at.x, at.z, step)
			step += 1
		along += 0.34
	return step

func _spawn_people() -> void:
	for id in ContentDB.people_order:
		var person := VegPerson.new()
		add_child(person)
		person.setup(ContentDB.person(id))
		people[id] = person
	_apply_shift(true)

func _apply_shift(snap: bool) -> void:
	# ponytail: mist uses the rain routes; a separate mist round if the rooms should differ.
	var night := Clock.hour() >= 19.5 or Clock.hour() < 5.0
	var shower := (Clock.weather == "rain" or Clock.weather == "mist") and not night
	var key := "day"
	if night:
		key = "night%d-%d" % [home_points.size(), Trust.level("nessa")]
	elif shower:
		key = "rain"
	if key == shift and not snap:
		return
	shift = key
	if shower:
		_person("lumen").set_route([
			GardenLayout.STALL + Vector3(0, 0, 0.95),
			GardenLayout.STALL + Vector3(0.9, 0, 0.2),
		], snap)
		_person("bram").set_route([
			GardenLayout.SHED + Vector3(1.1, 0, -0.6),
			GardenLayout.STALL + Vector3(-0.9, 0, 0.35),
		], snap)
		_person("nessa").set_route([
			GardenLayout.TEA + Vector3(0, 0, -1.15),
			GardenLayout.HUT + Vector3(0, 0, -1.05),
			GardenLayout.FOUNDRY + Vector3(0, 0, -0.95),
		], snap)
		return
	if night:
		_person("lumen").set_route([GardenLayout.STALL + Vector3(0, 0, 0.95)], snap)
		_person("bram").set_route([GardenLayout.SHED + Vector3(1.1, 0, -0.6)], snap)
		var nessa_at := GardenLayout.GATE
		if Trust.level("nessa") >= 1:
			# ponytail: the hut desk is her night home once the notes are filed.
			nessa_at = GardenLayout.HUT + Vector3(0, 0, -1.05)
		elif not home_points.is_empty():
			nessa_at = home_points[0]
		_person("nessa").set_route([nessa_at], snap)
		return
	_person("lumen").set_route([
		GardenLayout.STALL + Vector3(0, 0, 0.95),
		GardenLayout.STALL + Vector3(1.15, 0, 0.85),
		GardenLayout.STALL + Vector3(-0.2, 0, 0.95),
	], snap)
	_person("bram").set_route([
		GardenLayout.cell_center(0, 0),
		GardenLayout.cell_center(4, 3),
		GardenLayout.cell_center(5, 4),
		GardenLayout.cell_center(1, 6),
	], snap)
	_person("nessa").set_route([
		GardenLayout.TEA + Vector3(0, 0, -1.15),
		GardenLayout.GATE,
		Vector3(-3.4, 0, -2.0),
		GardenLayout.POND_CENTER + Vector3(-2.4, 0, 0.5),
	], snap)

func _person(id: String) -> VegPerson:
	return people.get(id)

func _primary_down() -> void:
	if _over_ui() or held:
		return
	var face := _pick_face()
	if face:
		_inspect_face(face)
		return
	var hit = _ground_hit()
	if tool == "hands":
		var jelly := _pick_jelly()
		if jelly:
			var point: Vector3 = hit if hit != null else jelly.global_position
			point.y = 0.85
			jelly.grab(point)
			held = jelly
			focus = jelly
			return
		var person := _pick_person()
		if person:
			if person.person_id == "bram":
				_ask_bram()
				return
			person.relation = minf(1.0, person.relation + 0.04)
			person.belonging = minf(1.0, person.belonging + 0.03)
			person.say(_greet(person.person_id))
			return
		return
	if hit == null:
		return
	if tool == "scoop":
		_scoop(hit)
		return
	if tool == "home":
		_place_kit(hit)
		return
	var cell_id := GardenLayout.world_to_cell(hit)
	if cell_id.x < 0:
		toast("The beds are inside the frames.")
		return
	_use_on_cell(soil.get_cell(cell_id.x, cell_id.y))

func _primary_up() -> void:
	if held:
		held.release()
		held = null

func _use_on_cell(plot: SoilCell) -> void:
	match tool:
		"till":
			if plot.plant_id != "":
				plot.plant_id = ""
				plot.growth = 0.0
				toast("Uprooted.")
			else:
				plot.tilled = true
				toast("Soil turned.")
			audio.play_kind("till")
		"seed":
			_plant(plot)
		"water":
			plot.moisture = 1.0
			audio.play_kind("water", -10)
			toast("Watered.")
		"feed":
			if not Economy.take("fertilizer", 1):
				toast("No fertiliser in the pouch.")
				return
			plot.fertility = minf(1.0, plot.fertility + 0.34)
			plot.tilled = true
			audio.play_kind("plant")
			toast("Fed the soil.")
			_person("bram").purpose = minf(1.0, _person("bram").purpose + 0.04)
		"tend":
			_tend(plot)
	_sync_plants()
	_refresh_soil_colors()

func _plant(plot: SoilCell) -> void:
	if not plot.tilled:
		toast("Till this soil first.")
		return
	if plot.plant_id != "":
		toast("Something is already growing here.")
		return
	var seed_id := Economy.selected_seed
	var item := ContentDB.item(seed_id)
	var plant_id := str(item.get("plant", ""))
	if plant_id == "":
		toast("Choose a seed.")
		return
	var definition := ContentDB.plant(plant_id)
	var chem := str(definition.get("chem", ""))
	if chem != "" and plot.chem != chem:
		toast("This seed wants night-loam. Dusknip leaves it.")
		return
	if not Economy.take(seed_id, 1):
		toast("No %s in the pouch." % item.get("name", "seed"))
		return
	plot.plant_id = plant_id
	plot.growth = 0.04
	plot.taken = false
	plot.eaten_by = ""
	plot.moisture = maxf(plot.moisture, 0.45)
	var mixed := soil.inherit_into(plot)
	audio.play_kind("plant")
	if mixed and (absf(plot.hue - 0.5) > 0.05 or absf(plot.stature - 1.0) > 0.05 or absf(plot.crop_yield - 1.0) > 0.05):
		toast("Planted %s. A seedling took after both parents." % definition.get("name", plant_id))
	else:
		toast("Planted %s." % definition.get("name", plant_id))

func _tend(plot: SoilCell) -> void:
	if plot.plant_id == "" or plot.growth < 1.0:
		var percent := int(plot.growth * 100.0) if plot.plant_id != "" else 0
		toast("Not ready." if plot.plant_id == "" else "Growing · %d%%" % percent)
		return
	var name := str(ContentDB.plant(plot.plant_id).get("name", plot.plant_id))
	Economy.add(plot.plant_id, 1)
	_store_yield(plot.plant_id, plot.crop_yield)
	plot.growth = 0.32
	plot.taken = true
	plot.eaten_by = ""
	audio.play_kind("harvest")
	toast("Harvested %s." % name)
	var bram := _person("bram")
	bram.relation = minf(1.0, bram.relation + 0.03)
	bram.purpose = minf(1.0, bram.purpose + 0.05)
	if bram.relation > 0.28 and bram.mood != "pleased":
		bram.mood = "pleased"
		bram.say("You have a decent hand with a bed.")

func _scoop(point: Vector3) -> void:
	var distance := GardenLayout.pond_distance(point.x, point.z)
	if distance < GardenLayout.POND_RADIUS - 0.3 or distance > GardenLayout.POND_RADIUS + 2.0:
		toast("Work the bank beside the willow.")
		return
	if scooped.size() >= 12:
		toast("The bank is as wide as it will go today.")
		return
	scooped.append(point)
	_add_scoop_mesh(point)
	_grow_pond()
	audio.play_kind("water")
	toast("The pond takes another step. %d scoops." % scooped.size())

func _place_kit(point: Vector3) -> void:
	if Economy.count("home_kit") < 1:
		toast("Home kits are at the stall.")
		return
	if GardenLayout.pond_distance(point.x, point.z) < GardenLayout.POND_RADIUS:
		toast("Not in the water.")
		return
	Economy.take("home_kit", 1)
	structures["home_kit"] = int(structures.get("home_kit", 0)) + 1
	home_points.append(point)
	_place_home(point, false)
	audio.play_kind("plant")
	toast("A home marker is set.")
	_person("bram").say("A door where a door belongs.")

func _add_scoop_mesh(point: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.55
	mesh.height = 0.04
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#2f6f68")
	material.roughness = 0.18
	node.material_override = material
	node.position = Vector3(point.x, -0.02, point.z)
	scoop_root.add_child(node)

func _grow_pond() -> void:
	var pond := get_node_or_null("Pond") as MeshInstance3D
	if pond == null:
		return
	var radius := GardenLayout.POND_RADIUS + float(scooped.size()) * 0.11
	GardenDressing.resize_pond(pond, radius)

func _place_home(point: Vector3, _saved := false) -> void:
	var root := Node3D.new()
	root.name = "HomeKit"
	root.position = Vector3(point.x, 0.0, point.z)
	_home_box(root, Vector3(0.08, 0.42, 0.08), Vector3(-0.22, 0.22, 0.16), Color("#3e2c22"))
	_home_box(root, Vector3(0.08, 0.42, 0.08), Vector3(0.22, 0.22, 0.16), Color("#3e2c22"))
	_home_box(root, Vector3(0.52, 0.36, 0.08), Vector3(0.0, 0.2, -0.16), Color("#4a382c"))
	var roof := _home_box(root, Vector3(0.7, 0.08, 0.58), Vector3(0.0, 0.48, 0.0), Color("#2f4a30"))
	roof.rotation.x = -0.18
	home_root.add_child(root)

func _home_box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	return node

func _ground_hit():
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		return null
	var t := -origin.y / direction.y
	if t < 0.0:
		return null
	return origin + direction * t

func _pick_jelly() -> Jelly:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var best: Jelly
	var best_distance := 0.72
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or not jelly.visible:
			continue
		var center := jelly.global_position + Vector3(0, 0.35, 0)
		var along := (center - origin).dot(direction)
		if along < 0.0:
			continue
		var distance := origin.distance_to(center) if false else (origin + direction * along).distance_to(center)
		if distance < best_distance:
			best = jelly
			best_distance = distance
	return best

func _pick_face() -> Jelly:
	if camera == null or ecology == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var best: Jelly
	var best_distance := 0.28
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or not jelly.visible:
			continue
		var center := jelly.face_point()
		var along := (center - origin).dot(direction)
		if along < 0.0:
			continue
		var distance := (origin + direction * along).distance_to(center)
		if distance < best_distance:
			best = jelly
			best_distance = distance
	return best

func _inspect_face(jelly: Jelly) -> void:
	if jelly == null or not is_instance_valid(jelly):
		return
	if focus != null and focus != jelly and is_instance_valid(focus):
		focus.clear_inspect()
	focus = jelly
	jelly.inspect_face()
	if camera:
		camera.focus_on(jelly.face_point(), 3.6)
	bus.note("inspect", jelly.display_name)
	toast("%s looks back." % jelly.display_name)
	if hud:
		hud.show_inspect(_inspect_card(jelly))
	if audio:
		audio.play_kind("squish", -18)

func _inspect_card(jelly: Jelly) -> Dictionary:
	return {
		"name": jelly.display_name,
		"mood": jelly.mood,
		"life": jelly.life,
		"bond": jelly.bond,
	}

func _clear_inspect() -> void:
	if focus != null and is_instance_valid(focus):
		focus.clear_inspect()
	if hud:
		hud.hide_inspect()

func _pick_person() -> VegPerson:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var best: VegPerson
	var best_distance := 0.7
	for id in people.keys():
		var person: VegPerson = people[id]
		if not person.present:
			continue
		var center := person.global_position + Vector3(0, 0.6, 0)
		var along := (center - origin).dot(direction)
		if along < 0.0:
			continue
		var distance := (origin + direction * along).distance_to(center)
		if distance < best_distance:
			best = person
			best_distance = distance
	return best

func _over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _update_highlight() -> void:
	if held:
		var hit = _ground_hit()
		if hit != null:
			var point: Vector3 = hit
			point.y = 0.9
			held.hold_target = point
	if _over_ui():
		highlight.visible = false
		return
	if _pick_face() != null:
		highlight.visible = false
		return
	var hit = _ground_hit()
	if hit == null:
		highlight.visible = false
		return
	var cell_id := GardenLayout.world_to_cell(hit)
	if cell_id.x < 0:
		highlight.visible = false
		return
	var center := GardenLayout.cell_center(cell_id.x, cell_id.y)
	highlight.position = Vector3(center.x, 0.08, center.z)
	highlight.visible = tool != "hands"

func _update_status() -> void:
	var seed_name := "Empty"
	var item := ContentDB.item(Economy.selected_seed)
	if not item.is_empty():
		seed_name = str(item.get("name", "Seed")).replace(" seed", "")
	hud.set_status(Clock.clock_label(), Clock.weather, Economy.coins, _hover_text(), seed_name)

func _hover_text() -> String:
	var face := _pick_face()
	if face:
		return "%s's face  ·  click" % face.display_name
	var hit = _ground_hit()
	if hit == null or _over_ui():
		return SaveGame.garden_name
	var cell_id := GardenLayout.world_to_cell(hit)
	if cell_id.x < 0:
		if GardenLayout.pond_distance(hit.x, hit.z) < GardenLayout.POND_RADIUS + 1.2:
			return "Pond  ·  %d reaches" % (GardenLayout.BASE_POND_CELLS + scooped.size())
		return SaveGame.garden_name
	return _plot_line(soil.get_cell(cell_id.x, cell_id.y))

func _plot_line(plot: SoilCell) -> String:
	var soil_name := "Night-loam" if plot.chem == "nightloam" else ("Tilled" if plot.tilled else "Grass")
	if plot.plant_id == "":
		var bare := "%s  ·  water %d%%  ·  feed %d%%" % [soil_name, int(plot.moisture * 100.0), int(plot.fertility * 100.0)]
		if plot.tilled and plot.moisture < 0.38:
			bare += "  ·  Needs water."
		return bare
	var definition: Dictionary = ContentDB.plant(plot.plant_id)
	var name := str(definition.get("name", plot.plant_id))
	var line := "%s  ·  %d%%  ·  water %d%%  ·  feed %d%%" % [name, int(plot.growth * 100.0), int(plot.moisture * 100.0), int(plot.fertility * 100.0)]
	if absf(plot.hue - 0.5) > 0.05 or absf(plot.stature - 1.0) > 0.05 or absf(plot.crop_yield - 1.0) > 0.05:
		line += "  ·  Mixed."
	if plot.moisture < float(definition.get("water_need", 0.3)):
		return line + "  ·  Needs water."
	if plot.fertility < float(definition.get("fertility_need", 0.2)):
		return line + "  ·  Needs feed."
	if plot.plant_id == "bramble" and plot.growth < 1.0 and _fruit_returning(plot):
		return line + "  ·  Fruit returning."
	# ponytail: the tall young cane only; a short cane stays on the percent.
	if plot.plant_id == "bramble" and plot.growth >= 0.7 and plot.growth < 1.0:
		return line + "  ·  Berries showing."
	if plot.plant_id == "peach" and plot.growth >= 0.7 and plot.growth < 1.0:
		return line + "  ·  Fruit showing."
	if plot.plant_id == "reed" and plot.growth >= 0.7 and plot.growth < 1.0:
		return line + "  ·  Heads showing."
	# ponytail: the tall fed mosspear only; a short pear stays on the percent.
	if plot.plant_id == "mosspear" and plot.growth >= 0.7 and plot.growth < 1.0:
		return line + "  ·  Pear showing."
	# ponytail: the tall lantern on night-loam only; bare soil still asks for loam.
	if plot.plant_id == "nightlantern" and plot.growth >= 0.7 and plot.growth < 1.0 and plot.chem == "nightloam":
		return line + "  ·  Light showing."
	if _cane_kept(plot):
		return line + "  ·  Cane kept."
	if _bees_hurrying(plot):
		return line + "  ·  Bees hurrying."
	if plot.plant_id == "meadowbell" and plot.growth < 1.0 and _bells_filling(plot):
		return line + "  ·  Bells filling."
	# ponytail: the tall young bell only; a short bell stays on the percent.
	if plot.plant_id == "meadowbell" and plot.growth >= 0.7 and plot.growth < 1.0:
		return line + "  ·  Bells showing."
	if plot.plant_id == "reed" and _reed_kept(plot):
		return line + "  ·  Reed kept."
	var chem_need := str(definition.get("chem", ""))
	if chem_need != "" and plot.chem != chem_need:
		return line + "  ·  Needs night-loam."
	# ponytail: the bed remembers who ate it until the fruit is ripe again.
	if plot.taken and plot.growth < 1.0:
		return line + "  ·  Growing back."
	if _rich_cane(plot):
		return line + "  ·  Rich enough."
	if _pear_sweet(plot):
		return line + "  ·  Pear-sweet."
	if _looked_after(plot):
		return line + "  ·  The parish is looked after."
	if _follower_bell(plot):
		return line + "  ·  A follower is close."
	if _wet_bank(plot):
		return line + "  ·  The bank is wet enough."
	return line

func _looked_after(plot: SoilCell) -> bool:
	# ponytail: ripe bells only, and only once a resident Bellhelp has a looked-after garden.
	if plot.plant_id != "meadowbell" or plot.growth < 1.0:
		return false
	if ecology.rules.rank_of(str(ecology.states.get("bellhelp", "rumoured"))) < ecology.rules.rank_of("resident"):
		return false
	if ecology.rules.rank_of(str(ecology.states.get("cirlark", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return false
	return float(world_snapshot().get("garden_quality", 0.0)) >= 0.42

func _wet_bank(plot: SoilCell) -> bool:
	# ponytail: ripe reeds only, and only after Bulrush has visited into wet beds.
	if plot.plant_id != "reed" or plot.growth < 1.0:
		return false
	if ecology.rules.rank_of(str(ecology.states.get("bulrush", "rumoured"))) < ecology.rules.rank_of("visitor"):
		return false
	if ecology.rules.rank_of(str(ecology.states.get("reedic", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return false
	return float(world_snapshot().get("moisture", 0.0)) >= 0.5

func _follower_bell(plot: SoilCell) -> bool:
	# ponytail: ripe bells only, and only after Bellhelp has visited.
	if plot.plant_id != "meadowbell" or plot.growth < 1.0:
		return false
	if ecology.rules.rank_of(str(ecology.states.get("bellhelp", "rumoured"))) < ecology.rules.rank_of("visitor"):
		return false
	if ecology.rules.rank_of(str(ecology.states.get("dusknip", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return false
	return true

func _pear_sweet(plot: SoilCell) -> bool:
	# ponytail: ripe mosspears only, and only while the night-loam and the feed are both in.
	if plot.plant_id != "mosspear" or plot.growth < 1.0:
		return false
	if ecology.rules.rank_of(str(ecology.states.get("gushorn", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return false
	var world := world_snapshot()
	if float(world.get("fertility", 0.0)) < 0.6:
		return false
	var chem: Dictionary = world.get("chem", {})
	if int(chem.get("nightloam", 0)) < 4:
		return false
	var mature: Dictionary = world.get("mature", {})
	return int(mature.get("mosspear", 0)) >= 2

func _rich_cane(plot: SoilCell) -> bool:
	# ponytail: the ripe canes only, and only while three of them stand in rich soil.
	if plot.plant_id != "bramble" or plot.growth < 1.0:
		return false
	if ecology.rules.rank_of(str(ecology.states.get("grapling", "rumoured"))) >= ecology.rules.rank_of("sighted"):
		return false
	var world := world_snapshot()
	if float(world.get("fertility", 0.0)) < 0.55:
		return false
	var mature: Dictionary = world.get("mature", {})
	return int(mature.get("bramble", 0)) >= 3

func _bees_hurrying(plot: SoilCell) -> bool:
	# ponytail: the rung seedling only; the other ripe bell if that bed should say so too.
	if bee_day != Clock.day or Clock.weather == "rain":
		return false
	if plot.plant_id != "meadowbell" or plot.growth <= 0.0 or plot.growth >= 1.0:
		return false
	return GardenLayout.cell_center(plot.ix, plot.iz).distance_to(bee_flower) < 0.35

func _bite_lines() -> Array:
	# ponytail: one line per bitten bed; a page if the parish keeps a season of meals.
	var lines: Array = []
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.eaten_by == "" or not plot.taken or plot.growth >= 1.0:
			continue
		var name := str(ContentDB.plant(plot.plant_id).get("name", plot.plant_id))
		lines.append("%s ate the %s." % [plot.eaten_by, name])
	return lines

func _fruit_returning(plot: SoilCell) -> bool:
	# ponytail: one settled berrypatch on the bitten cane; a row if several ripen separate canes.
	if plot.plant_id != "bramble":
		return false
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "berrypatch" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		var flat := Vector2(jelly.global_position.x - center.x, jelly.global_position.z - center.z)
		if flat.length() <= 1.6:
			return true
	return false

func _sync_plants() -> void:
	var live := {}
	for cell in soil.all():
		var plot: SoilCell = cell
		var key := "%d,%d" % [plot.ix, plot.iz]
		if plot.plant_id == "":
			continue
		live[key] = true
		var view: PlantView = plant_views.get(key)
		if view == null or not is_instance_valid(view):
			view = PlantView.new()
			add_child(view)
			var center := GardenLayout.cell_center(plot.ix, plot.iz)
			view.position = Vector3(center.x, 0.06, center.z) + _row_shift(plot.ix, plot.iz)
			plant_views[key] = view
		view.show_plant(plot.plant_id, plot.growth, plot.moisture, plot.fertility, PlantGenetics.from_cell(plot))
	for key in plant_views.keys():
		if not live.has(key) and is_instance_valid(plant_views[key]):
			plant_views[key].free()
			plant_views.erase(key)

func _clear_plants() -> void:
	for key in plant_views.keys():
		if is_instance_valid(plant_views[key]):
			plant_views[key].free()
	plant_views.clear()

func _refresh_soil_colors() -> void:
	for cell in soil.all():
		var plot: SoilCell = cell
		var patch: MeshInstance3D = patches.get("%d,%d" % [plot.ix, plot.iz])
		if patch == null:
			continue
		var material := patch.material_override as StandardMaterial3D
		if _joined_bed(plot):
			patch.mesh = bed_lid
			material.albedo_color = Color("#1c3420")
		else:
			patch.mesh = soil_lid
			material.albedo_color = _soil_color(plot)
	_fill_bed_meadow()

func _meadow_cell(plot: SoilCell) -> bool:
	return plot.plant_id == "" and not plot.tilled and _joined_bed(plot)

func _joined_bed(plot: SoilCell) -> bool:
	# ponytail: a planted cell keeps the meadow lid; a soil disc under the stem if the crop needs bare earth.
	if plot.chem == "nightloam":
		return false
	if plot.plant_id == "" and plot.tilled:
		return false
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	if GardenLayout.on_path(center.x, center.z):
		return false
	if GardenLayout.pond_distance(center.x, center.z) < GardenLayout.POND_RADIUS:
		return false
	return true

func _soil_color(plot: SoilCell) -> Color:
	# ponytail: flat grass tops clip to white under this sun; raise if the beds go dull.
	var color := Color("#4f6e34")
	if plot.tilled:
		color = Color("#6d4632")
	if plot.chem == "nightloam":
		color = Color("#3c3154")
	color = color.lerp(Color("#241910"), clampf(plot.moisture * 0.35, 0.0, 0.4))
	if plot.fertility > 0.62 and plot.tilled:
		color = color.lerp(Color("#5d6b32"), 0.22)
	return color

func _wire_jellies() -> void:
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly):
			continue
		if not jelly.reacted.is_connected(_on_jelly):
			jelly.reacted.connect(_on_jelly)
		jelly.attract = _attractor_for(ContentDB.species_def(jelly.species_id))
		jelly.reduce_motion = Settings.reduce_motion

func _update_creatures(delta: float) -> void:
	var night := Clock.hour() >= 21.0 or Clock.hour() < 5.0
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly):
			continue
		var resident := ecology.rules.rank_of(jelly.life) >= ecology.rules.rank_of("resident")
		jelly.wants_sleep = night and resident and not jelly.held
		if jelly.wants_sleep and jelly.mood != "dizzy" and jelly.mood != "panic":
			jelly.mood = "sleepy"
		var tier := 0
		if not jelly.held and jelly != focus:
			if camera.is_position_in_frustum(jelly.global_position):
				var distance := camera.global_position.distance_to(jelly.global_position)
				tier = SimLod.classify(distance, false, false)
				if tier >= 3:
					tier = 2
			else:
				tier = 3
		var wet := Clock.weather == "rain"
		jelly.use_berth = false
		# ponytail: one spot under the awning; a line if several visitors arrive together.
		if resident and not jelly.leaving and not jelly.held and not home_points.is_empty() and (tier >= 3 or jelly.wants_sleep or wet):
			jelly.berth = _nearest_home(jelly.global_position)
			jelly.use_berth = true
			if jelly.wants_sleep or wet:
				jelly.goal = jelly.berth
				jelly.attract = jelly.berth
		elif (wet or night) and not resident and not jelly.leaving and not jelly.held:
			var cover := GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
			jelly.berth = cover
			jelly.use_berth = true
			jelly.goal = cover
			jelly.attract = cover
		elif night and resident and home_points.is_empty() and not jelly.leaving and not jelly.held:
			# ponytail: the awning is the bed until a kit is placed; a shed cot if the parish builds one.
			var cover := GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
			jelly.berth = cover
			jelly.use_berth = true
			jelly.goal = cover
			jelly.attract = cover
		elif not resident and not jelly.leaving and not jelly.held:
			var stand := _attractor_for(ContentDB.species_def(jelly.species_id))
			jelly.attract = stand
			var cover := GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
			if jelly.goal.distance_to(cover) < 0.3 and stand.distance_to(jelly.global_position) > 1.1:
				jelly.goal = stand
		if resident and jelly.life != "bonded" and not jelly.use_berth and not night and not wet and not jelly.leaving and not jelly.held:
			var cover := GardenLayout.STALL + Vector3(0.9, 0.0, 0.2)
			if jelly.goal.distance_to(cover) < 0.3:
				var stand := _attractor_for(ContentDB.species_def(jelly.species_id))
				jelly.attract = stand
				if stand.distance_to(jelly.global_position) > 1.1:
					jelly.goal = stand
		if jelly.life == "bonded" and not jelly.wants_sleep and not jelly.use_berth and not jelly.held and not jelly.leaving:
			var stand := camera.target
			stand.y = 0.0
			# ponytail: water species keep the pond; a bank path if more than Bulrush and Reedic bond.
			if jelly.species_id == "bulrush" or jelly.species_id == "reedic":
				stand = _attractor_for(ContentDB.species_def(jelly.species_id))
			jelly.attract = stand
			if jelly.global_position.distance_to(stand) > 1.2:
				jelly.goal = stand
		jelly.tier = tier
	_keep_company()
	_follow_hosts()
	_seek_bite()
	_seek_dusk()
	_seek_loam()
	_seek_cane()
	_seek_fruit()
	_seek_bells()
	_seek_reeds()
	_seek_bees()
	_walk_shore()

func _bowl_line(at: Vector3) -> float:
	var rim := GardenLayout.POND_RADIUS
	var pond := get_node_or_null("Pond") as Node3D
	if pond != null:
		rim = float(pond.get_meta("rim", rim))
	return GardenLayout.pond_surface(at.x, at.z, rim) + 0.05

func _shore_point(offset: float) -> Vector3:
	# ponytail: one loop a day; a second ring if more than the pair wade.
	var angle := Clock.hour() / 24.0 * TAU + offset
	var radius := GardenLayout.POND_RADIUS + 0.55
	return GardenLayout.POND_CENTER + Vector3(cos(angle), 0.0, sin(angle)) * radius

func _bank_step(at: Vector3, toward: Vector3) -> Vector3:
	# ponytail: step along the ring; a chord across the water if the bank should be a shortcut.
	var center := GardenLayout.POND_CENTER
	var radius := GardenLayout.POND_RADIUS + 0.55
	var flat := Vector2(at.x - center.x, at.z - center.z)
	var aim := Vector2(toward.x - center.x, toward.z - center.z)
	var aim_angle := atan2(aim.y, aim.x)
	var out_angle := aim_angle
	if flat.length() > 0.15:
		out_angle = atan2(flat.y, flat.x)
	if flat.length() < radius - 0.2:
		return center + Vector3(cos(out_angle), 0.0, sin(out_angle)) * radius
	var delta := wrapf(aim_angle - out_angle, -PI, PI)
	var next := out_angle + clampf(delta, -0.35, 0.35)
	return center + Vector3(cos(next), 0.0, sin(next)) * radius

func _walk_shore() -> void:
	# ponytail: the bonded crown leads; Reedic stays a step behind on the same bank.
	var lead := _shore_point(0.0)
	var follow := _shore_point(0.7)
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.life != "bonded":
			continue
		if jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep:
			continue
		if jelly.species_id == "bulrush":
			jelly.attract = lead
			jelly.goal = lead
		elif jelly.species_id == "reedic":
			jelly.attract = follow
			jelly.goal = follow
	for actor in ecology.actors:
		var young: Jelly = actor
		if not is_instance_valid(young) or not young.young or young.species_id != "bulrush":
			continue
		if young.leaving or young.held or young.use_berth or young.wants_sleep:
			continue
		var step := _bank_step(young.global_position, lead)
		young.attract = step
		young.goal = step

func _nearest_home(at: Vector3) -> Vector3:
	var berth: Vector3 = home_points[0]
	var best := at.distance_squared_to(berth)
	for point in home_points:
		var dist := at.distance_squared_to(point)
		if dist < best:
			best = dist
			berth = point
	return berth

func _follow_hosts() -> void:
	# ponytail: one host; a flock if several of that species are out. Bonded keep the gardener.
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep or jelly.life == "bonded":
			continue
		var host_id := ""
		for req in ContentDB.species_def(jelly.species_id).get("requirements", []):
			if str(req.get("type", "")) == "species_state":
				host_id = str(req.get("species", ""))
				break
		if host_id == "":
			continue
		var host := ecology.first(host_id)
		if host == null or host == jelly or not is_instance_valid(host) or host.leaving or host.held:
			continue
		jelly.attract = host.global_position
		if jelly.global_position.distance_to(host.global_position) > 1.1:
			jelly.goal = host.global_position

func _keep_company() -> void:
	# ponytail: one shared kit for a breeding pair; a ring of homes if a parish keeps more than two.
	for id in ContentDB.species_order:
		if ecology.rules.rank_of(str(ecology.states.get(id, ""))) < ecology.rules.rank_of("breeding"):
			continue
		var anchor: Jelly = null
		var shared := Vector3.ZERO
		for actor in ecology.actors:
			var jelly: Jelly = actor
			if not is_instance_valid(jelly) or jelly.species_id != id:
				continue
			if jelly.young and anchor != null:
				# ponytail: the young keeps the parent; rain cover returns once they have grown.
				jelly.use_berth = false
				jelly.attract = anchor.global_position
				jelly.goal = anchor.global_position
				continue
			if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("resident"):
				continue
			if jelly.leaving or jelly.held:
				continue
			if anchor == null:
				anchor = jelly
				if not home_points.is_empty():
					shared = _nearest_home(anchor.global_position)
				continue
			if jelly.use_berth and not home_points.is_empty():
				var heading_home := jelly.wants_sleep or jelly.goal.distance_to(jelly.berth) < 0.25
				jelly.berth = shared
				if heading_home:
					jelly.goal = shared
					jelly.attract = shared
				continue
			if jelly.use_berth and home_points.is_empty():
				jelly.use_berth = false
				jelly.attract = anchor.global_position
				if jelly.global_position.distance_to(anchor.global_position) > 1.1:
					jelly.goal = anchor.global_position
				continue
			if jelly.use_berth:
				continue
			jelly.attract = anchor.global_position
			if jelly.global_position.distance_to(anchor.global_position) > 1.1:
				jelly.goal = anchor.global_position

func _on_jelly(kind: String, jelly: Jelly) -> void:
	if kind == "land":
		var now := Time.get_ticks_msec()
		if now - last_land > 220:
			last_land = now
			audio.play_kind("squish", -16)
		return
	if kind == "throw":
		audio.play_kind("squish", -8)
		toast("%s spins, dizzy." % jelly.display_name)
		var bram := _person("bram")
		if bram and bram.present:
			bram.relation = maxf(0.0, bram.relation - 0.06)
			bram.mood = "cross"
			bram.say("Hands are for helping, not for hurling.")
	elif kind == "drop":
		toast("%s looks unimpressed." % jelly.display_name)
	elif kind == "pet":
		toast("%s bounces." % jelly.display_name)
		audio.play_kind("squish", -18)
	elif kind == "poke":
		audio.play_kind("squish", -18)

func _farewell_name(text: String) -> String:
	var slip := " slips back toward the hedge."
	var back := " turns back from the hedge."
	if text.ends_with(slip):
		return text.substr(0, text.length() - slip.length())
	if text.ends_with(back):
		return text.substr(0, text.length() - back.length())
	return ""

func _on_ecology(text: String) -> void:
	toast(text)
	var nessa := _person("nessa")
	if "turns back" in text:
		if nessa != null and nessa.present and nessa_farewell and not nessa_filing and not nessa_drafting:
			var who := _farewell_name(text)
			if who != "":
				farewell_names.erase(who)
			if farewell_names.is_empty():
				nessa_farewell = false
				nessa.has_chore = false
				nessa_watch = null
				nessa.say("They turned back. The page stays blank.")
		return
	if "slips" in text:
		audio.play_kind("ui", -16)
		# ponytail: the names on this page; a second page if she is already filing.
		if nessa != null and nessa.present and not nessa_filing and not nessa_drafting:
			var who := _farewell_name(text)
			if who != "" and not farewell_names.has(who):
				farewell_names.append(who)
			nessa_bees = false
			nessa_farewell = true
			nessa_watch = null
			nessa.chore = GardenLayout.GATE
			nessa.has_chore = true
			if farewell_names.size() > 1:
				nessa.say("More than one is leaving. I will write them down.")
			elif farewell_names.size() == 1:
				nessa.say("%s is leaving. I will write it down." % farewell_names[0])
			else:
				nessa.say("Someone is leaving. I will write it down.")
		return
	audio.play_kind("discovery", -12)
	if nessa == null or not nessa.present or nessa_filing or nessa_drafting or nessa_farewell or nessa_bees:
		return
	# ponytail: one name in the book; a page per species if the journal grows sections.
	var watched: Jelly = null
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if is_instance_valid(jelly) and text.find(jelly.display_name) != -1:
			watched = jelly
			break
	if watched == null:
		return
	nessa_watch = watched
	nessa.chore = watched.global_position
	nessa.has_chore = true
	nessa.say("I will write down who came through the gate.")

func _apply_soil_effect(effect: Dictionary) -> int:
	var count := soil.apply_chem(str(effect.get("chem", "nightloam")), int(effect.get("count", 4)))
	_refresh_soil_colors()
	return count

func _own_meal(jelly: Jelly) -> SoilCell:
	# ponytail: the bed with their name; a second plate if two of that species both ate.
	var plant_id := _feed_plant(jelly.species_id)
	if plant_id == "":
		return null
	var best: SoilCell = null
	var best_d := 80.0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.eaten_by != jelly.display_name or plot.plant_id != plant_id:
			continue
		if not plot.taken or plot.growth <= 0.0 or plot.growth >= 1.0:
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		var dist := Vector2(jelly.global_position.x - center.x, jelly.global_position.z - center.z).length()
		if dist < best_d:
			best_d = dist
			best = plot
	return best

func _seek_bite() -> void:
	# ponytail: the bed they ate, until it is ripe; the nearest ripe plant after that.
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("resident"):
			continue
		var kept := _own_meal(jelly)
		if kept != null:
			var at := GardenLayout.cell_center(kept.ix, kept.iz)
			jelly.attract = at
			if at.distance_to(jelly.global_position) > 1.1:
				jelly.goal = at
			continue
		if jelly.bite_wait > 0.0:
			continue
		var plant_id := _feed_plant(jelly.species_id)
		if plant_id == "":
			continue
		var plot := _ripe_near(jelly.global_position, plant_id, 40.0)
		if plot == null:
			continue
		var at := GardenLayout.cell_center(plot.ix, plot.iz)
		if at.distance_to(jelly.global_position) <= 1.6:
			continue
		if not camera.is_position_in_frustum(jelly.global_position):
			continue
		jelly.goal = at
		jelly.attract = at

func _browse(hours: float) -> void:
	# ponytail: one ripe plant per resident; a diet if a species keeps two crops.
	if hours <= 0.0 or Clock.hour() >= 21.0 or Clock.hour() < 5.0:
		return
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.held or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("resident"):
			continue
		jelly.bite_wait = maxf(0.0, jelly.bite_wait - hours)
		if jelly.bite_wait > 0.0:
			continue
		if _own_meal(jelly) != null:
			continue
		var plant_id := _feed_plant(jelly.species_id)
		if plant_id == "":
			continue
		var plot := _ripe_near(jelly.global_position, plant_id, 1.6)
		if plot == null and not camera.is_position_in_frustum(jelly.global_position):
			plot = _ripe_near(jelly.global_position, plant_id, 40.0)
		if plot == null:
			continue
		plot.growth = 0.55
		plot.taken = true
		plot.eaten_by = jelly.display_name
		jelly.bite_wait = 4.0
		toast("%s takes a bite." % jelly.display_name)

func _seek_dusk() -> void:
	# ponytail: peach by day, the nightlantern from 16 to 22; a third stop if a species keeps more crops.
	var hour := Clock.hour()
	var dusk := hour >= 16.0 and hour < 22.0
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "pegapear":
			continue
		if jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep or jelly.life == "bonded":
			continue
		if not dusk and ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		var plant_id := "nightlantern" if dusk else "peach"
		# ponytail: a ripe stand wins; a bitten one still holds them until it grows back.
		var at := _meal_spot(plant_id, jelly.global_position)
		jelly.attract = at
		if jelly.global_position.distance_to(at) > 1.1:
			jelly.goal = at

func _seek_loam() -> void:
	# ponytail: the nearest night-loam bed; a circuit if the crown keeps more than one.
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "gushorn":
			continue
		if jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep or jelly.life == "bonded":
			continue
		var at := _nearest_loam(jelly.global_position)
		jelly.attract = at
		if jelly.global_position.distance_to(at) > 1.1:
			jelly.goal = at

func _seek_cane() -> void:
	# ponytail: the nearest ripe cane; a thicket route if several graplings settle.
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "grapling":
			continue
		if jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep or jelly.life == "bonded":
			continue
		var plot := _nearest_bramble(jelly.global_position)
		if plot == null:
			continue
		var at := GardenLayout.cell_center(plot.ix, plot.iz)
		jelly.attract = at
		if jelly.global_position.distance_to(at) > 1.1:
			jelly.goal = at

func _seek_fruit() -> void:
	# ponytail: the bitten cane first; the nearest ripe one if every bramble is whole.
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "berrypatch":
			continue
		if jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep or jelly.life == "bonded":
			continue
		var plot := _bitten_bramble(jelly.global_position)
		if plot == null:
			plot = _nearest_bramble(jelly.global_position)
		if plot == null:
			continue
		var at := GardenLayout.cell_center(plot.ix, plot.iz)
		jelly.attract = at
		if jelly.global_position.distance_to(at) > 1.1:
			jelly.goal = at

func _seek_bells() -> void:
	# ponytail: the short meadowbell; a row if more than one cirlark settles.
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "cirlark":
			continue
		if jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep or jelly.life == "bonded":
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		var plot := _short_bell(jelly.global_position)
		if plot == null:
			continue
		var at := GardenLayout.cell_center(plot.ix, plot.iz)
		jelly.attract = at
		if jelly.global_position.distance_to(at) > 1.1:
			jelly.goal = at

func _short_bell(at: Vector3) -> SoilCell:
	var best: SoilCell = null
	var best_d := 9999.0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "meadowbell" or plot.growth >= 1.0:
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		var dist := Vector2(at.x - center.x, at.z - center.z).length()
		if best == null or dist < best_d:
			best = plot
			best_d = dist
	return best

func _hold_bells(hours: float) -> void:
	# ponytail: the bell under their body; a row of short bells if more than one cirlark settles.
	if hours <= 0.0:
		return
	var keeper: Jelly = null
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "cirlark" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		keeper = jelly
		break
	if keeper == null:
		return
	var plot := _short_bell(keeper.global_position)
	if plot == null:
		return
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	if Vector2(keeper.global_position.x - center.x, keeper.global_position.z - center.z).length() > 1.6:
		return
	var definition: Dictionary = ContentDB.plant("meadowbell")
	if plot.moisture < float(definition.get("water_need", 0.38)):
		return
	if plot.fertility < float(definition.get("fertility_need", 0.18)):
		return
	var grow_hours := maxf(0.2, float(definition.get("grow_hours", 1.6)))
	plot.growth = minf(1.0, plot.growth + hours / grow_hours)

func _bells_filling(plot: SoilCell) -> bool:
	# ponytail: one settled cirlark on the short bell; a row if several fill separate bells.
	if plot.plant_id != "meadowbell" or plot.growth >= 1.0:
		return false
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "cirlark" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		if Vector2(jelly.global_position.x - center.x, jelly.global_position.z - center.z).length() <= 1.6:
			return true
	return false

func _seek_bees() -> void:
	# ponytail: the rung bed while the flight is out; Bellhelp again once the day turns.
	if bee_day != Clock.day or Clock.weather == "rain":
		return
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "dusknip":
			continue
		if jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep or jelly.life == "bonded":
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("resident"):
			continue
		jelly.attract = bee_flower
		if bee_flower.distance_to(jelly.global_position) > 1.1:
			jelly.goal = bee_flower

func _seek_reeds() -> void:
	# ponytail: the nearest reed stand; a bank circuit if more than one reedic settles.
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "reedic":
			continue
		if jelly.leaving or jelly.held or jelly.use_berth or jelly.wants_sleep or jelly.life == "bonded":
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		var plot := _nearest_reed(jelly.global_position)
		if plot == null:
			continue
		var at := GardenLayout.cell_center(plot.ix, plot.iz)
		jelly.attract = at
		if jelly.global_position.distance_to(at) > 1.1:
			jelly.goal = at

func _nearest_reed(at: Vector3) -> SoilCell:
	var best: SoilCell = null
	var best_d := 9999.0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "reed" or plot.growth < 0.5:
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		var dist := Vector2(at.x - center.x, at.z - center.z).length()
		if best == null or dist < best_d:
			best = plot
			best_d = dist
	return best

func _dew(hours: float) -> void:
	# ponytail: one damp hour after opening; a fog if the morning should linger past seven.
	if hours <= 0.0:
		return
	var h := Clock.hour()
	if h < 5.0 or h >= 7.0 or Clock.weather == "rain":
		return
	for cell in soil.all():
		var plot: SoilCell = cell
		if not plot.tilled and plot.plant_id == "":
			continue
		plot.moisture = minf(1.0, plot.moisture + hours * 0.45)

func _prime_reed(hours: float) -> void:
	# ponytail: one wet reed; the dry drain is 0.22 an hour, so 0.28 keeps it above the line.
	if hours <= 0.0:
		return
	var keeper: Jelly = null
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "reedic" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		keeper = jelly
		break
	if keeper == null:
		return
	var plot := _nearest_reed(keeper.global_position)
	if plot == null:
		return
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	if Vector2(keeper.global_position.x - center.x, keeper.global_position.z - center.z).length() > 1.6:
		return
	var need := float(ContentDB.plant("reed").get("water_need", 0.5))
	if plot.moisture < need:
		return
	plot.moisture = minf(1.0, plot.moisture + hours * 0.28)

func _reed_kept(plot: SoilCell) -> bool:
	# ponytail: one settled reedic on the reed; a bank if several keep separate stands.
	if plot.plant_id != "reed":
		return false
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "reedic" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		if Vector2(jelly.global_position.x - center.x, jelly.global_position.z - center.z).length() <= 1.6:
			return true
	return false

func _bitten_bramble(at: Vector3) -> SoilCell:
	var best: SoilCell = null
	var best_d := 9999.0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "bramble" or plot.growth < 0.5 or plot.growth >= 1.0:
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		var dist := Vector2(at.x - center.x, at.z - center.z).length()
		if best == null or dist < best_d:
			best = plot
			best_d = dist
	return best

func _hold_fruit(hours: float) -> void:
	# ponytail: the cane under their body; a row of bitten fruit if more than one berrypatch settles.
	if hours <= 0.0:
		return
	var keeper: Jelly = null
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "berrypatch" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		keeper = jelly
		break
	if keeper == null:
		return
	var plot := _nearest_bramble(keeper.global_position)
	if plot == null or plot.growth >= 1.0:
		return
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	if Vector2(keeper.global_position.x - center.x, keeper.global_position.z - center.z).length() > 1.6:
		return
	var definition: Dictionary = ContentDB.plant("bramble")
	if plot.moisture < float(definition.get("water_need", 0.36)):
		return
	if plot.fertility < float(definition.get("fertility_need", 0.24)):
		return
	var grow_hours := maxf(0.2, float(definition.get("grow_hours", 2.2)))
	plot.growth = minf(1.0, plot.growth + hours / grow_hours)

func _nearest_bramble(at: Vector3) -> SoilCell:
	var best: SoilCell = null
	var best_d := 9999.0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "bramble" or plot.growth < 0.5:
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		var dist := Vector2(at.x - center.x, at.z - center.z).length()
		if best == null or dist < best_d:
			best = plot
			best_d = dist
	return best

func _hold_cane(hours: float) -> void:
	# ponytail: the cane under their body; a whole row if more than one grapling settles.
	if hours <= 0.0:
		return
	var keeper: Jelly = null
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "grapling" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		keeper = jelly
		break
	if keeper == null:
		return
	var plot := _nearest_bramble(keeper.global_position)
	if plot == null:
		return
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	if Vector2(keeper.global_position.x - center.x, keeper.global_position.z - center.z).length() > 1.6:
		return
	var need := float(ContentDB.plant("bramble").get("water_need", 0.36))
	if plot.moisture < need:
		return
	plot.fertility = minf(1.0, plot.fertility + hours * 0.04)

func _nearest_loam(at: Vector3) -> Vector3:
	var best := _average_plant("mosspear")
	var best_d := 9999.0
	var found := false
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.chem != "nightloam":
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		var dist := Vector2(at.x - center.x, at.z - center.z).length()
		if not found or dist < best_d:
			found = true
			best_d = dist
			best = center
	return best

func _hold_loam(hours: float) -> void:
	# ponytail: one bed thins every four hours; a parish fade if several crowns are gone.
	if _loam_kept():
		loam_hours = 0.0
		_restore_loam()
		return
	var pending := false
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.chem == "nightloam":
			pending = true
			break
	if not pending:
		_restore_loam()
		return
	loam_hours += maxf(0.0, hours)
	var thinned := false
	while loam_hours >= 4.0:
		var chosen: SoilCell = null
		for cell in soil.all():
			var plot: SoilCell = cell
			if plot.chem != "nightloam":
				continue
			if plot.plant_id == "":
				chosen = plot
				break
			if chosen == null:
				chosen = plot
		if chosen == null:
			loam_hours = 0.0
			break
		chosen.chem = "base"
		loam_hours -= 4.0
		thinned = true
	if thinned:
		toast("The night-loam thinned.")
	_restore_loam()

func _restore_loam() -> void:
	# ponytail: one laying when the beds fall under four; a round if Dusknip keeps more than one patch.
	if _loam_count() >= 4 or not _dusknip_home():
		return
	var laid := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "nightlantern" and plot.chem != "nightloam":
			plot.chem = "nightloam"
			laid += 1
	laid += soil.apply_chem("nightloam", 5)
	if laid <= 0:
		return
	toast("Dusknip worked the night-loam back into the beds.")

func _loam_count() -> int:
	var total := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.chem == "nightloam":
			total += 1
	return total

func _dusknip_home() -> bool:
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "dusknip" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) >= ecology.rules.rank_of("resident"):
			return true
	return false

func _loam_kept() -> bool:
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "gushorn" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) >= ecology.rules.rank_of("settler"):
			return true
	return false

func _feed_plant(species_id: String) -> String:
	# ponytail: pegapear eats the lantern from 16 to 22 and the peach otherwise; a diet table if another species keeps two crops.
	if species_id == "pegapear":
		var hour := Clock.hour()
		if hour >= 16.0 and hour < 22.0:
			return "nightlantern"
		return "peach"
	for req in ContentDB.species_def(species_id).get("requirements", []):
		if str(req.get("type", "")) == "mature_plant":
			return str(req.get("plant", ""))
	return ""

func _ripe_near(at: Vector3, plant_id: String, reach: float) -> SoilCell:
	var best: SoilCell = null
	var best_d := reach
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != plant_id or plot.growth < 1.0:
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		var dist := Vector2(at.x - center.x, at.z - center.z).length()
		if dist < best_d:
			best_d = dist
			best = plot
	return best

func _attractor_for(definition: Dictionary) -> Vector3:
	var id := str(definition.get("id", ""))
	# ponytail: the reeds let them in; the stand is the water, not the reed bed.
	if id == "bulrush" or id == "reedic":
		return GardenLayout.POND_CENTER + Vector3(-1.6, 0, 0.3)
	for req in definition.get("requirements", []):
		if str(req.get("type", "")) == "mature_plant":
			return _average_plant(str(req.get("plant", "")))
	return Vector3(-3.6, 0.0, -1.6)

func _meal_spot(plant_id: String, at: Vector3) -> Vector3:
	var ripe_total := Vector3.ZERO
	var ripe_n := 0
	var near: SoilCell = null
	var near_d := 80.0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != plant_id or plot.growth <= 0.0:
			continue
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		if plot.growth >= 0.85:
			ripe_total += center
			ripe_n += 1
		elif Vector2(at.x - center.x, at.z - center.z).length() < near_d:
			near_d = Vector2(at.x - center.x, at.z - center.z).length()
			near = plot
	if ripe_n > 0:
		return ripe_total / float(ripe_n)
	if near != null:
		return GardenLayout.cell_center(near.ix, near.iz)
	return Vector3(-3.6, 0.0, -1.6)

func _bee_growth(hours: float) -> void:
	# ponytail: one extra hour on the rung seedling; the other ripe bell if that bed should fill too.
	if hours <= 0.0 or bee_day != Clock.day or Clock.weather == "rain":
		return
	var id := GardenLayout.world_to_cell(bee_flower)
	if id.x < 0:
		return
	var plot := soil.get_cell(id.x, id.y)
	if plot.plant_id != "meadowbell" or plot.growth <= 0.0 or plot.growth >= 1.0:
		return
	var definition: Dictionary = ContentDB.plant("meadowbell")
	if plot.moisture < float(definition.get("water_need", 0.3)):
		return
	if plot.fertility < float(definition.get("fertility_need", 0.2)):
		return
	var grow_hours := maxf(0.2, float(definition.get("grow_hours", 2.0)))
	plot.growth = minf(1.0, plot.growth + hours / grow_hours)

func _second_bell() -> Vector3:
	# ponytail: farthest ripe bell; the whole flight if that bed is the only one.
	var best := Vector3.ZERO
	var best_d := 0.45
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id != "meadowbell" or plot.growth < 0.85:
			continue
		var at := GardenLayout.cell_center(plot.ix, plot.iz)
		var dist := at.distance_to(bee_flower)
		if dist > best_d:
			best_d = dist
			best = at
	return best

func _average_plant(plant_id: String) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == plant_id and plot.growth >= 0.85:
			total += GardenLayout.cell_center(plot.ix, plot.iz)
			count += 1
	if count == 0:
		return Vector3(-3.6, 0.0, -1.6)
	return total / float(count)

func _check_nessa(world: Dictionary) -> void:
	var nessa := _person("nessa")
	if nessa.present:
		return
	var definition: Dictionary = ContentDB.person("nessa")
	if ecology.rules.all_met({"requirements": definition.get("arrive", [])}, world):
		nessa.present = true
		nessa.visible = true
		nessa.global_position = GardenLayout.GATE
		nessa.say("A Bellhelp lives here. I brought a notebook and nothing else.")
		toast("Nessa Pod walked in from the lane.")

func _ask_bram() -> void:
	var bram := _person("bram")
	bram.relation = minf(1.0, bram.relation + 0.04)
	bram.belonging = minf(1.0, bram.belonging + 0.03)
	var driest: SoilCell = null
	for cell in soil.all():
		var plot: SoilCell = cell
		if not plot.tilled:
			continue
		if driest == null or plot.moisture < driest.moisture:
			driest = plot
	if driest == null:
		bram.has_chore = false
		bram_feeding = false
		bram.say("The frames are empty. Till one and I will walk it.")
		return
	bram.chore = GardenLayout.cell_center(driest.ix, driest.iz)
	bram.has_chore = true
	bram_feeding = false
	bram_bed = Vector2i(driest.ix, driest.iz)
	bram.say("That bed is thirsty. I will walk it.")

func _notice_thirst() -> void:
	# ponytail: the driest bed under the water line; a round of the frames if several dry at once.
	var bram := _person("bram")
	if bram == null or not bram.present or bram.has_chore:
		return
	var hour := Clock.hour()
	if hour >= 19.5 or hour < 5.0:
		return
	var driest: SoilCell = null
	for cell in soil.all():
		var plot: SoilCell = cell
		if not plot.tilled:
			continue
		var line := 0.38
		if plot.plant_id != "":
			line = float(ContentDB.plant(plot.plant_id).get("water_need", 0.38))
		if plot.moisture >= line:
			continue
		if driest == null or plot.moisture < driest.moisture:
			driest = plot
	if driest == null:
		return
	bram.chore = GardenLayout.cell_center(driest.ix, driest.iz)
	bram.has_chore = true
	bram_feeding = false
	bram_bed = Vector2i(driest.ix, driest.iz)
	bram.say("That bed is thirsty. I will walk it.")

func _cane_kept(plot: SoilCell) -> bool:
	# ponytail: the cane under one settled grapling; a row if several keep separate canes.
	if plot.plant_id != "bramble":
		return false
	var center := GardenLayout.cell_center(plot.ix, plot.iz)
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly) or jelly.species_id != "grapling" or jelly.leaving:
			continue
		if ecology.rules.rank_of(jelly.life) < ecology.rules.rank_of("settler"):
			continue
		var flat := Vector2(jelly.global_position.x - center.x, jelly.global_position.z - center.z)
		if flat.length() <= 1.6:
			return true
	return false

func _notice_hunger() -> void:
	# ponytail: the hungriest planted bed under its line; thirst still wins.
	var bram := _person("bram")
	if bram == null or not bram.present or bram.has_chore:
		return
	var hour := Clock.hour()
	if hour >= 19.5 or hour < 5.0:
		return
	var hungry: SoilCell = null
	var skipped := false
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "":
			continue
		var line := float(ContentDB.plant(plot.plant_id).get("fertility_need", 0.2))
		if plot.fertility >= line:
			continue
		if _cane_kept(plot):
			skipped = true
			continue
		if hungry == null or plot.fertility < hungry.fertility:
			hungry = plot
	if hungry == null:
		if skipped and bram.speech != null and bram.speech.text != "That cane is kept. I will leave it.":
			bram.say("That cane is kept. I will leave it.")
		return
	bram.chore = GardenLayout.cell_center(hungry.ix, hungry.iz)
	bram.has_chore = true
	bram_feeding = true
	bram_bed = Vector2i(hungry.ix, hungry.iz)
	bram.say("That bed is tired. I will feed it.")

func _drift_people(delta: float, world: Dictionary) -> void:
	_notice_thirst()
	_notice_hunger()
	var lumen := _person("lumen")
	var bram := _person("bram")
	if bram.has_chore and bram_bed.x >= 0 and bram.global_position.distance_to(bram.chore) < 0.35:
		var plot := soil.get_cell(bram_bed.x, bram_bed.y)
		if bram_feeding:
			plot.fertility = minf(1.0, plot.fertility + 0.34)
			bram_feeding = false
			bram.say("That bed can grow again.")
		else:
			plot.moisture = minf(1.0, plot.moisture + 0.22)
			bram.say("That one will hold till the next rain.")
		bram.has_chore = false
		_refresh_soil_colors()
	lumen.purpose = move_toward(lumen.purpose, 0.82, delta * 0.02)
	lumen.energy = move_toward(lumen.energy, 0.7, delta * 0.01)
	bram.purpose = move_toward(bram.purpose, clampf(float(world.get("garden_quality", 0.3)) + 0.2, 0.2, 0.9), delta * 0.03)
	var nessa := _person("nessa")
	if nessa.present and nessa.has_chore:
		if nessa_drafting:
			if nessa.global_position.distance_to(nessa.chore) < 0.55:
				_keep_draft()
				nessa_drafting = false
				nessa.has_chore = false
				nessa_watch = null
		elif nessa_filing:
			if nessa.global_position.distance_to(nessa.chore) < 0.55:
				_file_nessa()
				nessa_filing = false
				nessa.has_chore = false
				nessa_watch = null
		elif nessa_bees:
			_finish_bee_walk()
		elif nessa_farewell:
			if nessa.global_position.distance_to(nessa.chore) < 0.55:
				var line := "Noted. They have gone back to the hedge."
				if farewell_names.size() == 1:
					line = "Noted. %s has gone back to the hedge." % farewell_names[0]
				elif farewell_names.size() > 1:
					var packed := PackedStringArray()
					for entry in farewell_names:
						packed.append(entry)
					line = "Noted. %s have gone back to the hedge." % ", ".join(packed)
				nessa_farewell = false
				nessa.has_chore = false
				nessa_watch = null
				farewell_names.clear()
				nessa.say(line)
				toast("Nessa wrote the departure into the parish book.")
		else:
			if nessa_watch != null and is_instance_valid(nessa_watch):
				nessa.chore = nessa_watch.global_position
			if nessa.global_position.distance_to(nessa.chore) < 0.55:
				var noted := "someone"
				if nessa_watch != null and is_instance_valid(nessa_watch):
					noted = nessa_watch.display_name
				nessa.has_chore = false
				nessa_watch = null
				nessa.say("Noted. %s is in the parish book." % noted)
				toast("Nessa wrote %s into the parish book." % noted)
	if nessa.present:
		nessa.belonging = move_toward(nessa.belonging, 0.75 if ecology.resident_total() > 0 else 0.4, delta * 0.03)
		nessa.purpose = move_toward(nessa.purpose, 0.8, delta * 0.02)

func _has_young(id: String) -> bool:
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if is_instance_valid(jelly) and jelly.species_id == id and jelly.young and not jelly.leaving:
			return true
	return false

func _journal_rows(world: Dictionary) -> Array:
	var rows: Array = []
	for id in ContentDB.species_order:
		var definition := ContentDB.species_def(id)
		var known := ecology.rules.rank_of(str(ecology.states.get(id, "rumoured"))) >= ecology.rules.rank_of("sighted")
		var met: PackedStringArray = ecology.rules.met_labels(definition, world)
		var unmet: PackedStringArray = ecology.rules.unmet(definition, world)
		if not known:
			met = _without_hidden_names(met)
			unmet = _without_hidden_names(unmet)
		var status := ecology.status_line(id, world)
		var romance := ""
		if known:
			romance = ecology.rules.romance_label(definition)
		if status == "breeding":
			romance = "A pair in the parish"
		var trusts := false
		for actor in ecology.actors:
			var body: Jelly = actor
			if is_instance_valid(body) and body.species_id == id and body.life == "bonded":
				trusts = true
				break
		if trusts and status == "breeding":
			romance = "A pair in the parish. One trusts your hands."
		elif trusts and status == "bonded":
			romance = "Trusts your hands."
		if status == "breeding" and _has_young(id):
			romance += " A young one is with them."
		rows.append({
			"name": definition.get("name", id) if known else "A rumour",
			"status": status,
			"met": met,
			"unmet": unmet,
			"blurb": definition.get("blurb", "") if known else _rumour_blurb(id),
			"romance": romance,
			"romance_met": ecology.rules.romance_met(definition, world),
			"residents": int(ecology.resident_counts().get(id, 0)),
		})
	if _far_bell_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "Three bells stand on the far lawn.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _bell_sale_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "A sale named the far-lawn bells.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _east_past_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way continues east past the bell.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _east_closer_bell_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "A bell stands at the parish end.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _parish_sale_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "A sale named the parish-end bell.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _gate_sale_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "A sale named the bell toward the gate.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _west_turn_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way turns west of the far-south bell.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _end_step_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps toward the end stone.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _further_east_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps further east of the outer bell.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _span_east_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps past the east-end bell.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _hem_east_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps past the margin strip.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _hem_stone_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps past the hem strip.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _hem_stone_bell_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps east of the hem stone.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _hem_stone_on_bell_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps east of the hem-stone bell.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _hem_stone_far_bell_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps past the hem-stone bell.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _hem_stone_out_bell_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps east of the far bell.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _meadow_stone_strip_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps east of the meadow-strip stone.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _last_bell_stone_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps past the last bell stone.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _end_strip_stone_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps east of the last-strip's stone.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _far_stone_strip_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way steps east of the far bell stone.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _west_gate_bell_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "A bell stands beside the way toward the gate.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _south_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way south ends at a stone.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _end_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The way ends past the bench.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _lane_south_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The lane has reached the south stone.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _lane_busy_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": "The lane is busy past the bench.",
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	if _cross_line() != "":
		rows.append({
			"name": "A rumour",
			"status": "",
			"met": PackedStringArray(),
			"unmet": PackedStringArray(),
			"blurb": _cross_line(),
			"romance": "",
			"romance_met": false,
			"residents": 0,
		})
	return rows

func _without_hidden_names(lines: PackedStringArray) -> PackedStringArray:
	# ponytail: a label scan; a sightings set if the journal grows past nine species.
	var kept := PackedStringArray()
	for line in lines:
		var leak := false
		for id in ContentDB.species_order:
			var creature := str(ContentDB.species_def(id).get("name", ""))
			if creature == "" or line.find(creature) == -1:
				continue
			if ecology.rules.rank_of(str(ecology.states.get(id, "rumoured"))) < ecology.rules.rank_of("sighted"):
				leak = true
				break
		if not leak:
			kept.append(line)
	return kept

func _people_rows(world: Dictionary) -> Array:
	var rows: Array = []
	for id in ContentDB.people_order:
		var person := _person(id)
		var definition := ContentDB.person(id)
		var unmet: Array = []
		for req in definition.get("arrive", []):
			if not ecology.rules.requirement_met(req, world):
				unmet.append(req.get("label", "Condition"))
		var home := str(definition.get("home", ""))
		if id == "nessa" and person.present and Trust.level("nessa") >= 1:
			home = "The research hut"
		elif id == "nessa" and person.present and int(structures.get("home_kit", 0)) >= 1:
			home = "A placed home kit"
		rows.append({
			"name": person.display_name,
			"role": person.role,
			"home": home,
			"job": definition.get("job", ""),
			"state": "not arrived" if not person.present else ("home for the night" if shift.begins_with("night") else "at their job"),
			"blurb": definition.get("blurb", ""),
			"present": person.present,
			"mood": person.mood,
			"energy": person.energy,
			"belonging": person.belonging,
			"purpose": person.purpose,
			"relation": person.relation,
			"unmet": unmet,
			"can_file": person.present and id == "nessa",
			"can_draft": person.present and id == "nessa" and Trust.level("nessa") >= 1 and not Trust.has_action("parish_draft"),
			"can_road": person.present and id == "nessa" and _road_rumoured() and not Trust.has_action("parish_road_rumour"),
			"road_line": _road_card_line() if id == "nessa" else "",
			"join_line": _join_line() if id == "nessa" else "",
			"parish_bell_line": _east_closer_bell_line() if id == "nessa" else "",
			"parish_sale_line": _parish_sale_line() if id == "nessa" else "",
			"hem_card_line": _hem_card_line() if id == "nessa" else "",
			"hem_stone_card_line": _hem_stone_card_line() if id == "nessa" else "",
			"hem_stone_bell_card_line": _hem_stone_bell_card_line() if id == "nessa" else "",
			"hem_stone_on_bell_card_line": _hem_stone_on_bell_card_line() if id == "nessa" else "",
			"hem_stone_far_bell_card_line": _hem_stone_far_bell_card_line() if id == "nessa" else "",
			"hem_stone_out_bell_card_line": _hem_stone_out_bell_card_line() if id == "nessa" else "",
			"meadow_stone_strip_card_line": _meadow_stone_strip_card_line() if id == "nessa" else "",
			"want_line": ("%s is looking for %s." % [person.display_name, ContentDB.plant(person.want).get("name", person.want)]) if person.want != "" else "",
		})
	return rows

func _trust_lines() -> Array:
	var lines: Array = []
	for id in ContentDB.people_order:
		var level := Trust.level(id)
		lines.append("%s · %s" % [ContentDB.person(id).get("name", id), Trust.level_name(level)])
		lines.append(Trust.blurb(level))
	return lines

func _place_stats(world: Dictionary) -> Dictionary:
	SimLod.note_population(_present_people(), ecology.resident_total(), float(world.get("garden_quality", 0.0)), Economy.coins)
	var stats := SimLod.district_stats.duplicate()
	stats["tiers"] = SimLod.tiers.duplicate()
	stats["phase"] = ContentDB.district.get("phase", "A")
	stats["bees"] = bees.bodies.size() if bees else 0
	stats["birds"] = birds.bodies.size() if birds else 0
	stats["bird_state"] = "perched" if Clock.hour() >= 19.5 or Clock.weather == "rain" else "crossing"
	stats["stall_demand"] = _present_people() + ecology.resident_total() + _lane_passers()
	stats["lane_passers"] = _lane_passers()
	stats["road_rumour"] = _road_rumoured()
	stats["road_line"] = _road_line()
	stats["far_bell_line"] = _far_bell_line()
	stats["bell_sale_line"] = _bell_sale_line()
	stats["join_line"] = _join_line()
	stats["south_line"] = _south_line()
	stats["lane_south_line"] = _lane_south_line()
	stats["end_line"] = _end_line()
	stats["lane_busy_line"] = _lane_busy_line()
	stats["east_line"] = _east_line()
	stats["east_past_line"] = _east_past_line()
	stats["east_far_line"] = _east_far_line()
	stats["east_near_line"] = _east_near_line()
	stats["east_closer_bell_line"] = _east_closer_bell_line()
	stats["west_gate_bell_line"] = _west_gate_bell_line()
	stats["south_step_line"] = _south_step_line()
	stats["west_turn_line"] = _west_turn_line()
	stats["end_step_line"] = _end_step_line()
	stats["outer_east_line"] = _outer_east_line()
	stats["further_east_line"] = _further_east_line()
	stats["span_east_line"] = _span_east_line()
	stats["reach_east_line"] = _reach_east_line()
	stats["field_east_line"] = _field_east_line()
	stats["brink_east_line"] = _brink_east_line()
	stats["margin_east_line"] = _margin_east_line()
	stats["hem_east_line"] = _hem_east_line()
	stats["hem_stone_line"] = _hem_stone_line()
	stats["hem_stone_bell_line"] = _hem_stone_bell_line()
	stats["hem_stone_on_bell_line"] = _hem_stone_on_bell_line()
	stats["hem_stone_far_bell_line"] = _hem_stone_far_bell_line()
	stats["hem_stone_out_bell_line"] = _hem_stone_out_bell_line()
	stats["outer_stone_strip_line"] = _outer_stone_strip_line()
	stats["outer_strip_bell_stone_line"] = _outer_strip_bell_stone_line()
	stats["meadow_strip_bell_line"] = _meadow_strip_bell_line()
	stats["meadow_stone_strip_line"] = _meadow_stone_strip_line()
	stats["farther_strip_bell_line"] = _farther_strip_bell_line()
	stats["last_bell_stone_line"] = _last_bell_stone_line()
	stats["last_strip_bell_line"] = _last_strip_bell_line()
	stats["end_strip_stone_line"] = _end_strip_stone_line()
	stats["far_bell_stone_line"] = _far_bell_stone_line()
	stats["far_stone_strip_line"] = _far_stone_strip_line()
	stats["gate_sale_line"] = _gate_sale_line()
	stats["parish_sale_line"] = _parish_sale_line()
	stats["cross_line"] = _cross_line()
	stats["want_line"] = _want_line()
	stats["cane_line"] = _cane_line()
	stats["bell_line"] = _bell_line()
	stats["peach_line"] = _peach_line()
	stats["reed_line"] = _reed_line()
	stats["pear_line"] = _pear_line()
	stats["lantern_line"] = _lantern_line()
	stats["seed_line"] = _seed_line()
	stats["leaf_line"] = _leaf_line()
	stats["grow_line"] = _grow_line()
	stats["sweet_line"] = _sweet_line()
	stats["ripe_line"] = _ripe_cane_line()
	stats["wade_line"] = _wade_line()
	stats["dusk_line"] = _dusk_line()
	stats["lane_afternoons"] = lane_afternoon_days.size()
	stats["shed_demand"] = 1 if _person("bram").present else 0
	stats["tea_demand"] = 1 if _person("nessa").present else 0
	stats["hut_demand"] = 1 if Trust.level("nessa") >= 1 else 0
	stats["foundry_demand"] = 1 if Trust.has_action("parish_draft") else 0
	var notices := Trust.notices()
	stats["hall_demand"] = notices.size()
	stats["notices"] = notices
	var venue_lines: Array[String] = []
	for id in ContentDB.venues.keys():
		var venue: Dictionary = ContentDB.venues[id]
		# ponytail: this garden has these rooms; the shared file stays inactive so the sidelined grove does not claim them.
		var built := "open" if bool(venue.get("active", false)) or str(id) == "tea_house" or str(id) == "research_hut" or str(id) == "media_foundry" or str(id) == "town_hall" else "not built"
		venue_lines.append("%s · %s" % [str(venue.get("name", id)), built])
	venue_lines.append("Potting Shed · open")
	stats["venues"] = venue_lines
	return stats

func _stock(world: Dictionary) -> Array:
	var rows: Array = []
	for id in ContentDB.shop.get("buy", []):
		var item := ContentDB.item(str(id))
		var locked := not _shop_unlocked(item, world)
		rows.append({
			"id": id,
			"name": item.get("name", id),
			"price": item.get("price", 0),
			"locked": locked,
			"lock_note": item.get("lock_reason", "") if locked else "",
		})
	return rows

func _produce() -> Array:
	var rows: Array = []
	for id in ContentDB.plant_order:
		var count := Economy.count(id)
		if count <= 0:
			continue
		rows.append({
			"id": id,
			"name": ContentDB.plant(id).get("name", id),
			"price": _sell_price(id),
			"count": count,
		})
	return rows

func _shop_unlocked(item: Dictionary, world: Dictionary = {}) -> bool:
	if str(item.get("lock", "")) != "nightloam":
		return true
	if world.is_empty():
		world = world_snapshot()
	return int(world.get("chem", {}).get("nightloam", 0)) > 0

func _present_people() -> int:
	var count := 0
	for id in people.keys():
		if _person(id).present:
			count += 1
	return count

func _cycle_seed(step: int) -> void:
	var ids := Economy.seed_ids()
	if ids.is_empty():
		return
	var index := ids.find(Economy.selected_seed)
	if index < 0:
		index = 0
	index = posmod(index + step, ids.size())
	Economy.selected_seed = ids[index]

func _greet(id: String) -> String:
	match id:
		"lumen":
			return "The trays are labelled. Ask before you spend the tin."
		"bram":
			return "Mind the frames. The soil remembers feet."
		"nessa":
			return "I am only writing what the garden already did."
		_:
			return "Hello."

func _focus_next() -> void:
	var found := false
	for actor in ecology.actors:
		var jelly: Jelly = actor
		if not is_instance_valid(jelly):
			continue
		if focus == null or found:
			focus = jelly
			camera.focus_on(jelly.global_position, 4.4)
			toast(jelly.display_name)
			return
		if jelly == focus:
			found = true
	focus = null
	camera.snap_home()

func _toggle_photo() -> void:
	photo = not photo
	hud.set_photo(photo)
	Clock.running = not photo
	if photo:
		var attributes := CameraAttributesPractical.new()
		attributes.dof_blur_far_enabled = true
		attributes.dof_blur_far_distance = 14.0
		attributes.dof_blur_amount = 0.04
		camera.attributes = attributes
	else:
		camera.attributes = null

func _esc() -> void:
	if photo:
		_toggle_photo()
		return
	if focus != null and is_instance_valid(focus) and focus.inspected:
		_clear_inspect()
		return
	if get_tree().paused:
		resume()
	else:
		get_tree().paused = true
		Clock.running = false
		hud.show_pause(true)

func _debug_text() -> String:
	var draw := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var memory := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var frame := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var look_name := "-"
	if focus != null and is_instance_valid(focus) and focus.inspected:
		look_name = focus.display_name
	return "FPS %d\nprocess %.2f ms\ndraws %d\nprims %d\nRAM %.0f MB\nVRAM %.0f MB\ntiers %s\n%s · %s\ntool %s\nface %s" % [
		Engine.get_frames_per_second(),
		frame,
		int(draw),
		int(prims),
		memory,
		vram,
		str(SimLod.tiers),
		Clock.clock_label(),
		Clock.weather,
		tool,
		look_name,
	]

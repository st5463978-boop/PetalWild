extends Node3D

var soil := SoilField.new()
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
var plant_views := {}
var structures := {"home_kit": 0}
var home_points: Array = []
var shift := ""
var bram_bed := Vector2i(-1, -1)
var nessa_watch: Jelly = null
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
		soil.tick(minutes, Clock.weather)
	var world := world_snapshot()
	ecology.tick(delta, world)
	_wire_jellies()
	_update_creatures(delta)
	_check_nessa(world)
	_apply_shift(false)
	_drift_people(delta, world)
	camera.nudge(delta)
	if bees:
		bees.tick(delta, Settings.reduce_motion, Clock.weather)
	if birds:
		birds.tick(delta, Settings.reduce_motion, Clock.hour(), Clock.weather)
	visual_timer += delta
	if visual_timer > 0.2:
		visual_timer = 0.0
		_sync_plants()
		_refresh_soil_colors()
	_update_highlight()
	atmosphere.apply(Clock.hour(), Clock.weather, camera)
	audio.set_weather(Clock.weather)
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
		hud.show_journal(_journal_rows(world), events, ecology.resident_total())
	if hud.shop.visible:
		hud.show_shop(_stock(world), _produce(), Trust.lumen_proposal_day != Clock.day)

func buy(item_id: String) -> void:
	var item := ContentDB.item(item_id)
	if item.is_empty():
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

func sell(plant_id: String) -> void:
	if Economy.count(plant_id) <= 0:
		return
	var price := int(ContentDB.plant(plant_id).get("sell_price", 1))
	Economy.take(plant_id, 1)
	Economy.earn(price)
	audio.play_kind("coin")
	toast("Sold %s for %d petal." % [ContentDB.plant(plant_id).get("name", plant_id), price])
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

func accept_nessa() -> void:
	Trust.file_notes("nessa", "Pollinator notes filed in the parish book. No external action.")
	toast("Nessa filed the notes. Nothing left the garden.")
	if _person("nessa").present:
		_person("nessa").say("Filed. The book stays on the shelf.")
	refresh_panels()

func quick_save() -> void:
	if SaveGame.write_slot(SaveGame.active_slot, to_state()):
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
	if hud:
		hud.toast(text)

func world_snapshot() -> Dictionary:
	var mature := {}
	var chem := {}
	var moisture := 0.0
	var fertility := 0.0
	var count := 0
	for cell in soil.all():
		var plot: SoilCell = cell
		count += 1
		moisture += plot.moisture
		fertility += plot.fertility
		chem[plot.chem] = int(chem.get(plot.chem, 0)) + 1
		if plot.plant_id != "" and plot.growth >= 1.0:
			mature[plot.plant_id] = int(mature.get(plot.plant_id, 0)) + 1
	var mature_total := 0
	for value in mature.values():
		mature_total += int(value)
	var quality := clampf(float(mature_total) / 10.0, 0.0, 1.0) * 0.75
	quality += clampf(moisture / maxf(float(count), 1.0), 0.0, 1.0) * 0.25
	return {
		"mature": mature,
		"pond_cells": GardenLayout.BASE_POND_CELLS + scooped.size(),
		"moisture": moisture / maxf(float(count), 1.0),
		"fertility": fertility / maxf(float(count), 1.0),
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
		"ecology": ecology.to_state(),
		"structures": structures.duplicate(),
		"homes": homes,
		"scooped": ponds,
		"people": cast,
		"events": events.slice(0, 20),
		"gossip_done": gossip_done,
	}

func apply_state(data: Dictionary) -> void:
	Clock.apply_state(data.get("clock", {}))
	Economy.apply_state(data.get("economy", {}))
	Trust.apply_state(data.get("trust", {}))
	soil.apply_state(data.get("soil", []))
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
	for entry in data.get("people", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var person := _person(str(entry.get("id", "")))
		if person:
			person.apply_state(entry)
	events = data.get("events", []).duplicate()
	gossip_done = bool(data.get("gossip_done", true))
	_clear_plants()
	_sync_plants()
	_refresh_soil_colors()

func _run_smoke() -> void:
	for cell in soil.all():
		var plot: SoilCell = cell
		plot.plant_id = ""
		plot.growth = 0.0
		plot.tilled = false
	for i in 3:
		_force_plant(i, 1, "meadowbell", 1.0)
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
	var bell := ecology.first("bellhelp")
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
	if demand != _present_people() + ecology.resident_total() or demand < 1:
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
	var walk := bram.global_position.distance_to(bram.waypoints[0])
	bram._process(3.0)
	if bram.global_position.distance_to(bram.waypoints[0]) > walk - 0.8:
		push_error("smoke: bram did not walk home")
		get_tree().quit(1)
		return
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
	var damp := dry.moisture
	bram.global_position = bram.chore
	_drift_people(0.1, world_snapshot())
	if dry.moisture < damp + 0.2:
		push_error("smoke: bram did not water the bed")
		get_tree().quit(1)
		return
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
			if str(entry.get("blurb", "")) != "Not sighted yet.":
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
	print("PETAL_SMOKE_OK")
	get_tree().quit(0)

func _run_capture() -> void:
	Settings.reduce_motion = true
	camera.snap_home()
	for spec in [[0, 0, "meadowbell"], [1, 0, "meadowbell"], [2, 1, "peach"], [3, 2, "bramble"], [6, 5, "reed"], [7, 6, "reed"], [8, 5, "reed"]]:
		_force_plant(spec[0], spec[1], spec[2], 1.0)
	debug_grow()
	Clock.set_hour(15.3)
	ecology.tick(0.2, world_snapshot())
	var jelly := ecology.first("bellhelp")
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
	print("PETAL_CAPTURE_OK")
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("/workspace/docs/screenshots")
	var err := image.save_png(path)
	print("SHOT ", path, " ", err, " ", image.get_width(), "x", image.get_height())

func _opening_plants() -> void:
	_force_plant(1, 1, "meadowbell", 0.58)
	_force_plant(2, 1, "meadowbell", 0.44)
	_force_plant(1, 2, "meadowbell", 0.36)
	_force_plant(3, 2, "peach", 0.28)
	_force_plant(7, 5, "reed", 0.22)

func _force_plant(ix: int, iz: int, plant_id: String, growth: float) -> void:
	var plot := soil.get_cell(ix, iz)
	plot.tilled = true
	plot.plant_id = plant_id
	plot.growth = growth
	plot.moisture = 0.74
	plot.fertility = 0.38

func _build_patches() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(GardenLayout.CELL_W * 0.9, 0.03, GardenLayout.CELL_D * 0.88)
	for cell in soil.all():
		var plot: SoilCell = cell
		var node := MeshInstance3D.new()
		node.mesh = mesh
		var material := StandardMaterial3D.new()
		material.roughness = 0.95
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var center := GardenLayout.cell_center(plot.ix, plot.iz)
		node.position = Vector3(center.x, 0.055, center.z)
		add_child(node)
		patches["%d,%d" % [plot.ix, plot.iz]] = node
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

func _spawn_people() -> void:
	for id in ContentDB.people_order:
		var person := VegPerson.new()
		add_child(person)
		person.setup(ContentDB.person(id))
		people[id] = person
	_apply_shift(true)

func _apply_shift(snap: bool) -> void:
	# ponytail: one day loop and one home point; a room clock when a second venue is built.
	var night := Clock.hour() >= 19.5 or Clock.hour() < 6.0
	var key := "day"
	if night:
		key = "night%d" % home_points.size()
	if key == shift and not snap:
		return
	shift = key
	if night:
		_person("lumen").set_route([GardenLayout.STALL + Vector3(0, 0, 0.95)], snap)
		_person("bram").set_route([GardenLayout.SHED + Vector3(1.1, 0, -0.6)], snap)
		var nessa_at := GardenLayout.GATE
		if not home_points.is_empty():
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
		GardenLayout.GATE,
		Vector3(-3.4, 0, -2.0),
		GardenLayout.POND_CENTER + Vector3(-2.4, 0, 0.5),
	], snap)

func _person(id: String) -> VegPerson:
	return people.get(id)

func _primary_down() -> void:
	if _over_ui():
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
	plot.moisture = maxf(plot.moisture, 0.45)
	audio.play_kind("plant")
	toast("Planted %s." % definition.get("name", plant_id))

func _tend(plot: SoilCell) -> void:
	if plot.plant_id == "" or plot.growth < 1.0:
		var percent := int(plot.growth * 100.0) if plot.plant_id != "" else 0
		toast("Not ready." if plot.plant_id == "" else "Growing · %d%%" % percent)
		return
	var name := str(ContentDB.plant(plot.plant_id).get("name", plot.plant_id))
	Economy.add(plot.plant_id, 1)
	plot.growth = 0.32
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

func _place_home(point: Vector3, _saved := false) -> void:
	var root := Node3D.new()
	root.position = Vector3(point.x, 0.0, point.z)
	var post := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.55, 0.28)
	post.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#f4f0e6")
	post.material_override = material
	post.position = Vector3(0, 0.28, 0)
	root.add_child(post)
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(0.48, 0.08, 0.4)
	roof.mesh = roof_mesh
	var roof_material := StandardMaterial3D.new()
	roof_material.albedo_color = Color("#c47c74")
	roof.material_override = roof_material
	roof.position = Vector3(0, 0.58, 0)
	root.add_child(roof)
	home_root.add_child(root)

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
	var hit = _ground_hit()
	if hit == null or _over_ui():
		return SaveGame.garden_name
	var cell_id := GardenLayout.world_to_cell(hit)
	if cell_id.x < 0:
		if GardenLayout.pond_distance(hit.x, hit.z) < GardenLayout.POND_RADIUS + 1.2:
			return "Pond  ·  %d reaches" % (GardenLayout.BASE_POND_CELLS + scooped.size())
		return SaveGame.garden_name
	var plot := soil.get_cell(cell_id.x, cell_id.y)
	var soil_name := "Night-loam" if plot.chem == "nightloam" else ("Tilled" if plot.tilled else "Grass")
	if plot.plant_id == "":
		return "%s  ·  water %d%%  ·  feed %d%%" % [soil_name, int(plot.moisture * 100.0), int(plot.fertility * 100.0)]
	var name := str(ContentDB.plant(plot.plant_id).get("name", plot.plant_id))
	return "%s  ·  %d%%  ·  water %d%%" % [name, int(plot.growth * 100.0), int(plot.moisture * 100.0)]

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
			view.position = Vector3(center.x, 0.06, center.z)
			plant_views[key] = view
		view.show_plant(plot.plant_id, plot.growth)
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
		material.albedo_color = _soil_color(plot)

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
		jelly.use_berth = false
		if tier >= 3 and resident and not jelly.leaving and not home_points.is_empty():
			var berth: Vector3 = home_points[0]
			var best := jelly.global_position.distance_squared_to(berth)
			for point in home_points:
				var dist := jelly.global_position.distance_squared_to(point)
				if dist < best:
					best = dist
					berth = point
			jelly.berth = berth
			jelly.use_berth = true
		jelly.tier = tier

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

func _on_ecology(text: String) -> void:
	toast(text)
	if "slips" in text:
		audio.play_kind("ui", -16)
		return
	audio.play_kind("discovery", -12)
	var nessa := _person("nessa")
	if not nessa.present:
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

func _attractor_for(definition: Dictionary) -> Vector3:
	for req in definition.get("requirements", []):
		if str(req.get("type", "")) == "mature_plant":
			return _average_plant(str(req.get("plant", "")))
	var id := str(definition.get("id", ""))
	if id == "bulrush" or id == "reedic":
		return GardenLayout.POND_CENTER + Vector3(-1.6, 0, 0.3)
	return Vector3(-3.6, 0.0, -1.6)

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
		bram.say("The frames are empty. Till one and I will walk it.")
		return
	bram.chore = GardenLayout.cell_center(driest.ix, driest.iz)
	bram.has_chore = true
	bram_bed = Vector2i(driest.ix, driest.iz)
	bram.say("That bed is thirsty. I will walk it.")

func _drift_people(delta: float, world: Dictionary) -> void:
	var lumen := _person("lumen")
	var bram := _person("bram")
	if bram.has_chore and bram_bed.x >= 0 and bram.global_position.distance_to(bram.chore) < 0.35:
		var plot := soil.get_cell(bram_bed.x, bram_bed.y)
		plot.moisture = minf(1.0, plot.moisture + 0.22)
		bram.has_chore = false
		bram.say("That one will hold till the next rain.")
		_refresh_soil_colors()
	lumen.purpose = move_toward(lumen.purpose, 0.82, delta * 0.02)
	lumen.energy = move_toward(lumen.energy, 0.7, delta * 0.01)
	bram.purpose = move_toward(bram.purpose, clampf(float(world.get("garden_quality", 0.3)) + 0.2, 0.2, 0.9), delta * 0.03)
	var nessa := _person("nessa")
	if nessa.present and nessa.has_chore:
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
		rows.append({
			"name": definition.get("name", id) if known else "A rumour",
			"status": ecology.status_line(id, world),
			"met": met,
			"unmet": unmet,
			"blurb": definition.get("blurb", "") if known else "Not sighted yet.",
			"romance": ecology.rules.romance_label(definition) if known else "",
			"romance_met": ecology.rules.romance_met(definition, world),
			"residents": int(ecology.resident_counts().get(id, 0)),
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
		if id == "nessa" and person.present and int(structures.get("home_kit", 0)) >= 1:
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
	stats["stall_demand"] = _present_people() + ecology.resident_total()
	stats["shed_demand"] = 1 if _person("bram").present else 0
	var venue_lines: Array[String] = []
	for id in ContentDB.venues.keys():
		var venue: Dictionary = ContentDB.venues[id]
		var built := "open" if bool(venue.get("active", false)) else "not built"
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
			"price": ContentDB.plant(id).get("sell_price", 1),
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
	return "FPS %d\nprocess %.2f ms\ndraws %d\nprims %d\nRAM %.0f MB\nVRAM %.0f MB\ntiers %s\n%s · %s\ntool %s" % [
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
	]

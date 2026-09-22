extends Node3D

const ViewScript = preload("res://scripts/presentation/grove_view.gd")
const RigScript = preload("res://scripts/presentation/camera_rig.gd")
const UiScript = preload("res://scripts/presentation/grove_ui.gd")

var view
var rig
var ui
var tool := 0
var tool_sub := 0
var hover := Vector2i(-1, -1)
var grabbing := ""
var grab_from := Vector3.ZERO
var grab_moved := 0.0
var last_plane := Vector3.ZERO
var plane_normal := Vector3.FORWARD
var plane_point := Vector3.ZERO
var autosave := 0.0
var shot := ""


func _ready() -> void:
	view = ViewScript.new()
	view.bind(self)
	add_child(view)
	rig = RigScript.new()
	add_child(rig)
	ui = UiScript.new()
	ui.game = self
	add_child(ui)
	var settings := PetalSave.load_settings()
	PetalAudio.set_volume(float(settings.get("volume", 0.8)))
	PetalWorld.reduce_motion = bool(settings.get("reduce_motion", false))
	shot = OS.get_environment("PETALWILD_SHOT")
	if shot != "":
		await _shot_boot(shot)
	else:
		rig.title_pose()
		ui.show_title()


func state() -> Dictionary:
	return PetalWorld.state


func plot_world(x: int, y: int) -> Vector3:
	return view.plot_world(x, y)


func world_to_plot(point: Vector3) -> Vector2i:
	return view.world_to_plot(point)


func random_walkable() -> Vector2i:
	var options: Array[Vector2i] = []
	var width := int(PetalWorld.state["width"])
	var height := int(PetalWorld.state["height"])
	for y in height:
		for x in width:
			var ground := String(PetalWorld.state["plots"][y * width + x].get("g", ""))
			if ground != "pond":
				options.append(Vector2i(x, y))
	if options.is_empty():
		return Vector2i(1, 1)
	return options[randi() % options.size()]


func anchor_for(person_id: String, tag: String) -> Vector3:
	return view.anchor_for(person_id, tag)


func resident_def(person_id: String) -> Dictionary:
	return PetalContent.residents.get(person_id, {})


func jelly_count() -> int:
	return view.jellies.size()


func set_tool(index: int) -> void:
	tool = index
	PetalAudio.play("ui")


func cycle_context() -> void:
	if tool == 1:
		var seeds: Array = PetalSim.available_seeds(PetalWorld.state, PetalContent.catalogs())
		if seeds.is_empty():
			return
		var current := seeds.find(String(PetalWorld.state.get("selected_seed", "")))
		var next: String = seeds[(current + 1) % seeds.size()]
		PetalWorld.state["selected_seed"] = next
	else:
		tool_sub = (tool_sub + 1) % 5
	PetalAudio.play("ui")


func new_slot(slot: int) -> void:
	_begin(slot, true)


func continue_slot(slot: int) -> void:
	var loaded := PetalSave.load_slot(slot)
	if loaded.is_empty():
		_begin(slot, true)
		return
	PetalWorld.adopt(loaded, slot)
	_enter_play()
	ui.toast("The grove remembers day %d." % int(PetalWorld.state["day"]))


func _begin(slot: int, fresh: bool) -> void:
	if fresh:
		PetalWorld.start_new(slot)
		PetalSave.save_slot(slot, PetalWorld.state)
	_enter_play()


func _enter_play() -> void:
	view.build(PetalWorld.state)
	ui.hide_title()
	rig.play_pose()
	PetalAudio.start_bed()
	PetalWorld.playing = true


func save_current() -> void:
	if PetalWorld.state.is_empty():
		return
	var ok := PetalSave.save_slot(PetalWorld.slot, PetalWorld.state)
	ui.toast("Grove %d saved." % PetalWorld.slot if ok else "The save did not take.", "ok" if ok else "error")


func to_title() -> void:
	PetalAudio.stop_bed()
	PetalWorld.playing = false
	ui.show_title()
	rig.title_pose()


func open_shop() -> void:
	ui.show_shop()


func buy(item_id: String) -> void:
	_events(PetalSim.try_buy(PetalWorld.state, PetalContent.catalogs(), item_id))
	ui.show_shop()


func sell(item_id: String) -> void:
	_events(PetalSim.try_sell(PetalWorld.state, PetalContent.catalogs(), item_id))
	ui.show_shop()


func bump_trust(person_id: String, delta: int) -> void:
	var level := int(PetalWorld.state["people"][person_id].get("trust", 0)) + delta
	_events(PetalSim.set_trust(PetalWorld.state, person_id, level))


func ask_proposal(approve: bool) -> void:
	_events(PetalSim.propose(PetalWorld.state, PetalContent.catalogs(), "oshi", approve))


func set_clock(minute: int) -> void:
	PetalWorld.state["minute"] = minute


func set_weather(weather: String) -> void:
	PetalWorld.state["weather"] = weather


func add_coins(amount: int) -> void:
	PetalWorld.state["coins"] = int(PetalWorld.state.get("coins", 0)) + amount


func grow_all() -> void:
	for plot in PetalWorld.state["plots"]:
		if String(plot.get("plant", "")) != "":
			plot["growth"] = 1.0
			plot["m"] = 0.8


func soak() -> void:
	for plot in PetalWorld.state["plots"]:
		if String(plot.get("g", "")) != "path":
			plot["m"] = 1.0


func force_species(species_id: String, to_state: String) -> void:
	PetalSim.force_species(PetalWorld.state, species_id, to_state)
	view.sync(PetalWorld.state)


func focus_plot(x: int, y: int) -> void:
	rig.focus_on(view.plot_world(x, y), 8.0)


func _process(delta: float) -> void:
	if not PetalWorld.playing:
		if not PetalWorld.state.is_empty():
			ui.refresh(PetalWorld.state, hover)
		return
	PetalClock.apply(PetalWorld.state, delta)
	var events: Array = PetalSim.tick(PetalWorld.state, PetalContent.catalogs(), delta)
	_events(events)
	view.sync(PetalWorld.state)
	_move_camera(delta)
	_hover()
	ui.refresh(PetalWorld.state, hover)
	autosave += delta
	if autosave > 45.0:
		autosave = 0.0
		PetalSave.save_slot(PetalWorld.slot, PetalWorld.state)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rig.drag(event.relative.x, event.relative.y)
	if event is InputEventMouseMotion and grabbing != "":
		_drag_grab()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		rig.zoom(1)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		rig.zoom(-1)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press()
		else:
			_release()
	if event.is_action_pressed("ui_cancel"):
		ui.toggle_pause()
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event.keycode)


func _key(code: Key) -> void:
	match code:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			set_tool(int(code) - KEY_1)
		KEY_R:
			cycle_context()
		KEY_J:
			ui._toggle(ui.journal)
		KEY_M:
			ui._toggle(ui.map_panel)
		KEY_C:
			ui._toggle(ui.city)
		KEY_F:
			_focus_nearest()
		KEY_G:
			_feed_nearest()
		KEY_P:
			_photo()
		KEY_SPACE:
			PetalClock.paused = not PetalClock.paused
			ui.toast("Time rests." if PetalClock.paused else "Time moves.")
		KEY_BRACKETLEFT:
			PetalWorld.state["time_scale"] = maxf(0.25, float(PetalWorld.state.get("time_scale", 1.0)) * 0.5)
		KEY_BRACKETRIGHT:
			PetalWorld.state["time_scale"] = minf(8.0, float(PetalWorld.state.get("time_scale", 1.0)) * 2.0)
		KEY_F3:
			ui.toggle_debug()
		KEY_F5:
			save_current()
		KEY_F9:
			continue_slot(PetalWorld.slot)
		KEY_E:
			_interact_nearest()


func _photo() -> void:
	var on: bool = not bool(ui.photo_label.visible)
	ui.photo(on)


func _move_camera(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if move == Vector2.ZERO:
		return
	rig.pan(move.x * delta * 7.0, move.y * delta * 7.0)


func _hover() -> void:
	var hit := _ray()
	if hit.is_empty():
		hover = view.world_to_plot(_plane(0.0))
	else:
		hover = Vector2i(-1, -1)
	view.hover(hover)


func _press() -> void:
	if not PetalWorld.playing:
		return
	var hit := _ray()
	if not hit.is_empty():
		var kind := String(hit.collider.get_meta("kind", ""))
		var id := String(hit.collider.get_meta("id", ""))
		if kind == "jelly":
			grabbing = id
			grab_moved = 0.0
			var actor = view.jellies[id]
			plane_point = actor.global_position
			plane_normal = -rig.camera.global_basis.z
			last_plane = plane_point
			grab_from = plane_point
			return
		if kind == "person":
			_talk(id)
			return
		if kind == "stall":
			_events(PetalSim.interact_stall(PetalWorld.state))
			return
	if hover.x < 0:
		return
	_use_tool(hover.x, hover.y)


func _drag_grab() -> void:
	if not view.jellies.has(grabbing):
		return
	var point := _plane_hit(plane_normal, plane_point)
	grab_moved += last_plane.distance_to(point)
	var actor = view.jellies[grabbing]
	actor.hold_at(point, point.distance_to(grab_from) * 0.8)
	last_plane = point


func _release() -> void:
	if grabbing == "":
		return
	var id := grabbing
	grabbing = ""
	if not view.jellies.has(id):
		return
	var actor = view.jellies[id]
	if grab_moved < 0.35:
		actor.release(Vector3.ZERO)
		_events(PetalSim.pet(PetalWorld.state, PetalContent.catalogs(), id))
		PetalAudio.play("squish")
		return
	var velocity := (last_plane - grab_from) * 3.2
	velocity.y += 2.0
	actor.release(velocity)
	var hard := velocity.length() > 4.0
	_events(PetalSim.toss(PetalWorld.state, PetalContent.catalogs(), id, hard))
	PetalAudio.play("squish")


func _use_tool(x: int, y: int) -> void:
	var catalogs := PetalContent.catalogs()
	var events: Array = []
	match tool:
		0:
			events = PetalSim.till(PetalWorld.state, x, y)
			PetalAudio.play("dig")
		1:
			events = PetalSim.plant(PetalWorld.state, catalogs, x, y)
			PetalAudio.play("dig")
		2:
			events = PetalSim.water(PetalWorld.state, x, y)
			PetalAudio.play("water")
		3:
			events = PetalSim.fertilise(PetalWorld.state, x, y)
			PetalAudio.play("dig")
		4:
			events = PetalSim.tend(PetalWorld.state, catalogs, x, y, Input.is_key_pressed(KEY_SHIFT))
			PetalAudio.play("harvest")
		5:
			events = PetalSim.pond(PetalWorld.state, x, y)
			PetalAudio.play("water")
		6:
			events = _home(x, y)
	_events(events)


func _home(x: int, y: int) -> Array:
	match tool_sub % 5:
		0:
			return PetalSim.interact_stall(PetalWorld.state)
		1:
			var plot := WorldState.plot_at(PetalWorld.state, x, y)
			if plot.is_empty() or String(plot.get("plant", "")) != "":
				return [{"type": "error", "text": "Paths go on empty ground."}]
			plot["g"] = "path"
			return [{"type": "ok", "text": "You lay a path."}]
		2:
			return PetalSim.place_prop(PetalWorld.state, x, y, "lamp")
		3:
			return PetalSim.place_prop(PetalWorld.state, x, y, "bench")
		_:
			return PetalSim.place_prop(PetalWorld.state, x, y, "lantern")


func _events(events: Array) -> void:
	for event in events:
		var kind := String(event.get("type", ""))
		var text := String(event.get("text", ""))
		if text != "" and kind != "shop":
			ui.toast(text, "error" if kind == "error" else "ok")
		if kind == "error":
			PetalAudio.play("error")
		elif kind in ["species", "unlock", "arrival", "variant"]:
			PetalAudio.play("chime")
		elif kind == "coin":
			PetalAudio.play("coin")
		elif kind == "shop":
			ui.show_shop()
		elif kind == "stall":
			PetalAudio.play("chime")
	if ui.journal.visible:
		ui._fill_journal(PetalWorld.state)


func _talk(person_id: String) -> void:
	var def: Dictionary = PetalContent.residents[person_id]
	var lines: Array = PetalContent.dialogue.get(person_id, {}).get("greeting", ["Hello."])
	var line := String(lines[randi() % lines.size()])
	ui.say(def.get("name", person_id), line, person_id == "cara")
	PetalAudio.play("talk")


func _focus_nearest() -> void:
	var best: Node3D = null
	var best_d: float = 99999.0
	for id in view.jellies.keys():
		var jelly: Node3D = view.jellies[id]
		var focus_point: Vector3 = rig.focus
		var dist: float = focus_point.distance_to(jelly.global_position)
		if dist < best_d:
			best_d = dist
			best = jelly
	if best != null:
		rig.focus_on(best.global_position, 3.4)


func _feed_nearest() -> void:
	_focus_nearest()
	var best_id := ""
	var best_d: float = 6.0
	var cam_pos: Vector3 = rig.camera.global_position
	for id in view.jellies.keys():
		var jelly: Node3D = view.jellies[id]
		var dist: float = cam_pos.distance_to(jelly.global_position)
		if dist < best_d:
			best_d = dist
			best_id = id
	if best_id != "":
		_events(PetalSim.feed(PetalWorld.state, PetalContent.catalogs(), best_id))


func _interact_nearest() -> void:
	_events(PetalSim.interact_stall(PetalWorld.state))


func _ray() -> Dictionary:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var camera: Camera3D = rig.camera
	var from: Vector3 = camera.project_ray_origin(mouse)
	var dir: Vector3 = camera.project_ray_normal(mouse)
	var to: Vector3 = from + dir * 80.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 2
	return get_world_3d().direct_space_state.intersect_ray(query)


func _plane(height: float) -> Vector3:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var camera: Camera3D = rig.camera
	var from: Vector3 = camera.project_ray_origin(mouse)
	var dir: Vector3 = camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return from
	var t: float = (height - from.y) / dir.y
	return from + dir * t


func _plane_hit(normal: Vector3, point: Vector3) -> Vector3:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var camera: Camera3D = rig.camera
	var from: Vector3 = camera.project_ray_origin(mouse)
	var dir: Vector3 = camera.project_ray_normal(mouse)
	var denom: float = dir.dot(normal)
	if absf(denom) < 0.0001:
		return point
	var t: float = (point - from).dot(normal) / denom
	return from + dir * t


func _shot_boot(mode: String) -> void:
	PetalWorld.start_new(1)
	if mode == "night":
		PetalWorld.state["minute"] = 22 * 60
	elif mode == "rain":
		PetalWorld.state["weather"] = "rain"
		PetalWorld.state["minute"] = 14 * 60
	elif mode == "shop":
		PetalWorld.state["stall_open"] = true
		PetalWorld.state["minute"] = 11 * 60
	elif mode == "golden" or mode == "overview":
		PetalWorld.state["minute"] = 17 * 60 + 20
		PetalWorld.state["weather"] = "golden"
	_enter_play()
	if mode == "creature":
		PetalSim.force_species(PetalWorld.state, "sunburst", "visitor")
		view.sync(PetalWorld.state)
		if view.jellies.has("sunburst"):
			rig.focus_on(view.jellies["sunburst"].global_position + Vector3(0, 0.3, 0), 3.2)
	elif mode == "person":
		rig.focus_on(view.anchor_for("cara", "stall"), 4.2)
	elif mode == "shop":
		ui.show_shop()
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "/workspace/docs/screenshots/petalwild_%s.png" % mode
	var err: Error = image.save_png(path)
	print("SHOT ", path, " err ", err, " size ", image.get_width(), "x", image.get_height())
	get_tree().quit()

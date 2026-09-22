extends Node3D

const ViewScript = preload("res://game/world/garden_view.gd")
const CameraScript = preload("res://game/camera/garden_camera.gd")
const AudioScript = preload("res://game/audio/garden_audio.gd")
const HudScript = preload("res://game/ui/hud.gd")
const JellyScript = preload("res://game/jelly/jelly_body.gd")
const VegScript = preload("res://game/residents/veg_body.gd")
const SimLod = preload("res://game/sim/sim_lod.gd")

var view: Node3D
var camera_rig
var audio
var hud
var jellies: Dictionary = {}
var veg_people: Dictionary = {}
var held = null
var sync_timer := 0.0
var shot_dir := ""
var shot_step := 0
var shot_time := 0.0
var shot_busy := false


func _ready() -> void:
	view = ViewScript.new()
	add_child(view)
	view.build()
	camera_rig = CameraScript.new()
	add_child(camera_rig)
	camera_rig.build()
	audio = AudioScript.new()
	add_child(audio)
	audio.build()
	hud = HudScript.new()
	add_child(hud)
	_spawn_bodies()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shots" and i + 1 < args.size():
			shot_dir = args[i + 1]


func _process(delta: float) -> void:
	var playing := Session.playing and not Session.paused
	if playing:
		var input_x := 0.0
		var input_z := 0.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			input_x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			input_x += 1.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			input_z += 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			input_z -= 1.0
		if held == null:
			camera_rig.pan(input_x, input_z, delta)
	Session.advance(delta)
	_simulate_jellies(delta)
	_simulate_people(delta)
	view.apply_atmosphere(Session.hour, Session.weather, Session.season)
	audio.set_weather(Session.weather)
	_hover()
	sync_timer += delta
	if sync_timer > 0.35:
		sync_timer = 0.0
		view.sync_plots(Session.garden.plots, Session.content.plants)
	if shot_dir != "" and not shot_busy:
		_shots(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		camera_rig.dragging = event.pressed
		return
	if event is InputEventMouseMotion and camera_rig.dragging:
		camera_rig.orbit(event.relative.x, event.relative.y)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_rig.zoom(0.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.zoom(-0.14)
		elif event.button_index == MOUSE_BUTTON_LEFT and not hud.over_ui():
			_primary(event.position)
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_release()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_hotkey(event.keycode)


func _primary(mouse: Vector2) -> void:
	if not Session.playing or Session.paused:
		return
	var jelly = _pick_jelly(mouse)
	if jelly != null:
		held = jelly
		held.held = true
		held.velocity = Vector3.ZERO
		held.set_mood("curious")
		return
	var point: Vector3 = camera_rig.ground_ray(mouse, 0.12)
	var cell: Vector2i = view.field.cell_from_world(point)
	if not Session.garden.in_bounds(cell.x, cell.y):
		return
	var before := Session.log_lines.size()
	Session.use_tool(cell.x, cell.y)
	if Session.log_lines.size() != before:
		audio.ui()
	view.sync_plots(Session.garden.plots, Session.content.plants)


func _release() -> void:
	if held == null:
		return
	var speed: Vector3 = held.velocity
	if speed.length() < 0.45:
		Session.ecology.adjust_bond(str(held.spec.id), 0.06, "happy")
		held.held = false
		held.velocity = Vector3.ZERO
		held.set_mood("happy")
		audio.ui()
	else:
		var mood := "annoyed" if speed.length() > 3.2 else "playful"
		var delta_bond := -0.1 if speed.length() > 3.2 else 0.02
		Session.ecology.adjust_bond(str(held.spec.id), delta_bond, mood)
		held.launch(speed)
		audio.impact()
	held = null


func _hotkey(key: Key) -> void:
	match key:
		KEY_1:
			Session.tool = "till"
		KEY_2:
			Session.tool = "seed"
		KEY_3:
			Session.tool = "water"
		KEY_4:
			Session.tool = "fert"
		KEY_5:
			Session.tool = "tend"
		KEY_6:
			Session.tool = "scoop"
		KEY_7:
			Session.tool = "home"
		KEY_J:
			hud.toggle_journal()
		KEY_B:
			hud.toggle_shop()
		KEY_ESCAPE:
			hud.toggle_pause()
		KEY_F3:
			hud.toggle_debug()
		KEY_P:
			hud.toggle_photo()
		KEY_F:
			_focus_nearest()
		KEY_BRACKETLEFT:
			Session.speed = 1.0
		KEY_BRACKETRIGHT:
			Session.speed = 3.0


func _spawn_bodies() -> void:
	var index := 0
	for spec in Session.content.species:
		var body = JellyScript.new()
		body.setup(spec)
		var angle := float(index) / 8.0 * TAU
		body.position = Vector3(cos(angle) * 3.5, 0.4, 5.0 + sin(angle) * 2.5)
		body.visible = false
		add_child(body)
		jellies[str(spec.id)] = body
		index += 1
	for spec in Session.content.residents:
		var person = VegScript.new()
		person.setup(spec)
		person.visible = false
		add_child(person)
		veg_people[str(spec.id)] = person


func _simulate_jellies(delta: float) -> void:
	for id in jellies.keys():
		var body = jellies[id]
		var rec: Dictionary = Session.ecology.records[id]
		var show: bool = bool(rec.present) and Session.playing
		body.visible = show or body == held
		if not body.visible:
			continue
		body.set_mood(str(rec.mood))
		if bool(body.get_meta("pinned", false)):
			body.moving = false
			body.animate(delta)
			continue
		var cam_pos: Vector3 = camera_rig.camera.global_position
		var fidelity: int = SimLod.fidelity_for(cam_pos.distance_to(body.global_position), body == held, true)
		body.set_fidelity(fidelity)
		rec.fidelity = fidelity
		if body == held:
			var desired: Vector3 = camera_rig.ground_ray(get_viewport().get_mouse_position(), 1.05)
			var gap: Vector3 = desired - body.global_position
			body.velocity += gap * 9.0 * delta
			body.velocity *= exp(-2.4 * delta)
			body.global_position += body.velocity * delta
			body.impact = clampf(body.velocity.length() / 6.5, 0.0, 1.0)
			body.moving = false
			body.animate(delta)
			continue
		if body.velocity.length() > 0.35:
			body.velocity.y -= 12.0 * delta
			body.global_position += body.velocity * delta
			var ground: float = float(view.field.height(body.global_position.x, body.global_position.z)) + 0.28
			if body.global_position.y <= ground:
				body.global_position.y = ground
				if absf(body.velocity.y) > 1.1:
					body.impact = clampf(absf(body.velocity.y) / 7.0, 0.2, 1.0)
					body.velocity.y = -body.velocity.y * 0.42
					body.velocity.x *= 0.65
					body.velocity.z *= 0.65
					audio.impact()
				else:
					body.velocity = Vector3.ZERO
			body.moving = false
			body.animate(delta)
			continue
		var target: Vector3 = body.get_meta("wander", body.global_position)
		if body.global_position.distance_to(target) < 0.4 or not body.has_meta("wander"):
			target = _wander_point(id)
			body.set_meta("wander", target)
		var step: Vector3 = target - body.global_position
		step.y = 0.0
		var speed := 1.5 if fidelity <= 1 else 0.8
		if str(body.spec.get("locomotion", "")) == "charge":
			speed = 2.4
		if step.length() > 0.01:
			body.global_position += step.normalized() * speed * delta
			body.look_at(Vector3(target.x, body.global_position.y, target.z), Vector3.UP)
		var gy: float = float(view.field.height(body.global_position.x, body.global_position.z)) + 0.28
		body.global_position.y = gy
		body.moving = true
		body.animate(delta)


func _simulate_people(delta: float) -> void:
	for id in veg_people.keys():
		var body = veg_people[id]
		var person: Dictionary = Session.people[id]
		body.visible = bool(person.unlocked) and Session.playing
		if not body.visible:
			continue
		var next := Vector3(float(person.x), 0, float(person.z))
		next.y = view.field.height(next.x, next.z)
		var moved: bool = body.global_position.distance_to(next) > 0.02
		body.global_position = next
		body.walking = str(person.mood) == "walking" or moved
		var face := Vector3(float(person.tx), next.y, float(person.tz))
		if face.distance_to(next) > 0.2:
			body.look_at(face, Vector3.UP)
		var line := ""
		if float(Session.speech.get(id, 0.0)) > 0.0:
			line = str(person.line)
		body.set_line(line)
		body.animate(delta)


func _hover() -> void:
	if not Session.playing or held != null:
		view.set_highlight(Vector2i.ZERO, false)
		return
	var mouse := get_viewport().get_mouse_position()
	var point: Vector3 = camera_rig.ground_ray(mouse, 0.12)
	var cell: Vector2i = view.field.cell_from_world(point)
	var valid: bool = bool(Session.garden.in_bounds(cell.x, cell.y))
	view.set_highlight(cell, valid and not hud.over_ui())
	if not valid:
		hud.set_plot("")
		return
	var plot: Dictionary = Session.garden.plot_at(cell.x, cell.y)
	var plant := str(plot.plant_id)
	var growth := int(float(plot.growth) * 100.0)
	var plant_name: String = Session.content.plant_name(plant) if plant != "" else "empty"
	hud.set_plot("%s · %s %s · moisture %d%% · fertility %d%%" % [
		plant_name,
		plot.soil,
		("%d%%" % growth) if plant != "" else "",
		int(float(plot.moisture) * 100.0),
		int(float(plot.fertility) * 100.0),
	])


func _pick_jelly(mouse: Vector2):
	var origin: Vector3 = camera_rig.camera.project_ray_origin(mouse)
	var dir: Vector3 = camera_rig.camera.project_ray_normal(mouse)
	var best = null
	var best_d := 0.72
	for id in jellies.keys():
		var body = jellies[id]
		if not body.visible:
			continue
		var to: Vector3 = body.global_position - origin
		var t := to.dot(dir)
		if t < 0.0:
			continue
		var dist := origin.distance_to(body.global_position + dir * 0.0)
		var closest: Vector3 = origin + dir * t
		dist = closest.distance_to(body.global_position)
		if dist < best_d:
			best_d = dist
			best = body
	return best


func _wander_point(id: String) -> Vector3:
	var rec: Dictionary = Session.ecology.records[id]
	var angle := randf() * TAU
	var radius := randf_range(1.5, 6.5)
	var point := Vector3(cos(angle) * radius, 0.3, 4.0 + sin(angle) * radius * 0.6)
	if str(rec.mood) == "flee":
		point = Vector3(cos(angle) * 12.0, 0.3, sin(angle) * 8.0)
	return point


func _focus_nearest() -> void:
	var mouse := get_viewport().get_mouse_position()
	var jelly = _pick_jelly(mouse)
	if jelly != null:
		camera_rig.focus_on(jelly.global_position)
		return
	for id in veg_people.keys():
		if veg_people[id].visible:
			camera_rig.focus_on(veg_people[id].global_position)
			return


func _shots(delta: float) -> void:
	shot_time += delta
	if shot_step == 0 and shot_time > 0.6:
		shot_busy = true
		await _shoot("01_title.png")
		Session.begin_playing()
		hud.enter_play()
		shot_step = 1
		shot_busy = false
	elif shot_step == 1 and shot_time > 5.0:
		shot_busy = true
		_snap_camera(Vector3(1.8, 0.5, 2.4), 21.0, 0.98)
		camera_rig.yaw = 0.5
		await _shoot("02_garden_overview.png")
		var rec: Dictionary = Session.ecology.records["sunburst"]
		rec.state = "VISITOR"
		rec.present = true
		rec.mood = "curious"
		shot_step = 2
		shot_busy = false
	elif shot_step == 2 and shot_time > 5.8:
		shot_busy = true
		var jelly = jellies["sunburst"]
		jelly.visible = true
		jelly.set_meta("pinned", true)
		jelly.global_position = Vector3(1.2, view.field.height(1.2, 3.4) + 0.35, 3.4)
		_snap_camera(jelly.global_position + Vector3(0, 0.2, 0), 2.6)
		await _shoot("03_jelly_closeup.png")
		var quin: Dictionary = Session.people["quin_hearth"]
		quin.unlocked = true
		quin.x = 11.6
		quin.z = 2.2
		quin.line = "The stall is open."
		Session.speech["quin_hearth"] = 6.0
		shot_step = 3
		shot_busy = false
	elif shot_step == 3 and shot_time > 6.6:
		shot_busy = true
		var person = veg_people["quin_hearth"]
		person.visible = true
		person.global_position = Vector3(11.6, view.field.height(11.6, 2.2), 2.2)
		_snap_camera(person.global_position + Vector3(0, 0.8, 0), 4.2)
		await _shoot("04_veg_person.png")
		hud.shop.visible = true
		hud.journal.visible = false
		hud._fill_shop()
		shot_step = 4
		shot_busy = false
	elif shot_step == 4 and shot_time > 7.2:
		shot_busy = true
		_snap_camera(Vector3(13.15, 1.15, 1.35), 8.4, 0.62)
		hud._fill_shop()
		await _shoot("05_shop.png")
		hud.shop.visible = false
		hud.tab = "species"
		hud.journal.visible = true
		hud._fill_journal()
		shot_step = 5
		shot_busy = false
	elif shot_step == 5 and shot_time > 7.8:
		shot_busy = true
		await _shoot("06_journal.png")
		hud.journal.visible = false
		Session.force_weather("rain")
		shot_step = 6
		shot_busy = false
	elif shot_step == 6 and shot_time > 8.6:
		shot_busy = true
		_snap_camera(Vector3(1.8, 0.5, 2.4), 21.0, 0.98)
		camera_rig.yaw = 0.5
		await _shoot("07_rain.png")
		Session.force_weather("clear")
		Session.force_hour(22.2)
		shot_step = 7
		shot_busy = false
	elif shot_step == 7 and shot_time > 9.4:
		shot_busy = true
		_snap_camera(Vector3(1.8, 0.5, 2.4), 21.0, 0.98)
		camera_rig.yaw = 0.5
		await _shoot("08_night.png")
		shot_step = 8
		shot_busy = false
		get_tree().quit()


func _snap_camera(point: Vector3, dist: float, cam_pitch: float = 0.38) -> void:
	camera_rig.intro = 1.0
	camera_rig.pivot = point
	camera_rig.target_pivot = point
	camera_rig.distance = dist
	camera_rig.target_distance = dist
	camera_rig.pitch = cam_pitch
	camera_rig.target_pitch = cam_pitch


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := shot_dir.path_join(file_name)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	image.save_png(path)
	print("SHOT %s" % path)

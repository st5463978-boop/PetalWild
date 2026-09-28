extends Node

const PLACES: Dictionary = {
	7: "apartment", 8: "apartment", 9: "apartment", 10: "apartment",
	15: "church", 16: "restaurant", 17: "cafe", 18: "clinic", 19: "school",
}
const TITLES: Dictionary = {
	"apartment": "Apartment", "church": "Church", "restaurant": "Restaurant",
	"cafe": "Cafe", "clinic": "Clinic", "school": "School",
}
const RITUALS: Array[Dictionary] = [
	{"place": "apartment", "id": "sit", "label": "Sit a minute", "room": "living", "at": Vector3(-1.3, 0.08, -0.2), "size": Vector3(0.8, 0.16, 0.7), "color": Color(0.44, 0.32, 0.55)},
	{"place": "apartment", "id": "tasks", "label": "Check the list", "room": "living", "at": Vector3(0.3, 0.1, -1.05), "size": Vector3(0.36, 0.08, 0.28), "color": Color(0.2, 0.28, 0.24)},
	{"place": "apartment", "id": "read", "label": "Read a chapter", "room": "living", "at": Vector3(1.35, 0.08, 0.15), "size": Vector3(0.34, 0.07, 0.26), "color": Color(0.55, 0.28, 0.36)},
	{"place": "apartment", "id": "walk", "label": "Take the jelly out", "room": "living", "at": Vector3(-1.9, 0.16, 1.15), "size": Vector3(0.22, 0.32, 0.22), "color": Color(0.62, 0.4, 0.28)},
	{"place": "apartment", "id": "kettle", "label": "Make something warm", "room": "kitchen", "at": Vector3(1.15, 0.18, -0.7), "size": Vector3(0.28, 0.32, 0.28), "color": Color(0.85, 0.72, 0.28)},
	{"place": "apartment", "id": "drops", "label": "Take the drops", "room": "kitchen", "at": Vector3(0.35, 0.14, -1.1), "size": Vector3(0.16, 0.26, 0.16), "color": Color(0.3, 0.5, 0.58)},
	{"place": "apartment", "id": "leaves", "label": "Steep the leaves", "room": "kitchen", "at": Vector3(-0.55, 0.08, -0.85), "size": Vector3(0.32, 0.1, 0.24), "color": Color(0.36, 0.5, 0.3)},
	{"place": "church", "id": "pew", "label": "Sit in a pew", "room": "hall", "at": Vector3(-1.2, 0.1, -0.3), "size": Vector3(0.9, 0.2, 0.4), "color": Color(0.45, 0.32, 0.22)},
	{"place": "church", "id": "candle", "label": "Light a candle", "room": "hall", "at": Vector3(1.2, 0.12, -0.8), "size": Vector3(0.12, 0.24, 0.12), "color": Color(0.92, 0.82, 0.45)},
	{"place": "church", "id": "quiet", "label": "A quiet minute", "room": "hall", "at": Vector3(0.2, 0.08, -1.15), "size": Vector3(0.5, 0.1, 0.35), "color": Color(0.55, 0.5, 0.62)},
	{"place": "restaurant", "id": "table", "label": "Take a table", "room": "hall", "at": Vector3(-1.15, 0.1, -0.2), "size": Vector3(0.7, 0.12, 0.7), "color": Color(0.62, 0.42, 0.28)},
	{"place": "restaurant", "id": "soup", "label": "Order the soup", "room": "hall", "at": Vector3(1.2, 0.16, -0.6), "size": Vector3(0.3, 0.28, 0.3), "color": Color(0.72, 0.34, 0.24)},
	{"place": "restaurant", "id": "plate", "label": "Clear the plate", "room": "hall", "at": Vector3(1.15, 0.1, 0.55), "size": Vector3(0.4, 0.08, 0.4), "color": Color(0.85, 0.82, 0.74)},
	{"place": "cafe", "id": "cup", "label": "Take a cup", "room": "hall", "at": Vector3(1.1, 0.14, -0.5), "size": Vector3(0.28, 0.22, 0.28), "color": Color(0.85, 0.7, 0.4)},
	{"place": "cafe", "id": "bite", "label": "A sweet bite", "room": "hall", "at": Vector3(1.15, 0.1, 0.4), "size": Vector3(0.36, 0.1, 0.28), "color": Color(0.72, 0.4, 0.45)},
	{"place": "cafe", "id": "window", "label": "Sit by the window", "room": "hall", "at": Vector3(-1.2, 0.1, 0.15), "size": Vector3(0.7, 0.16, 0.5), "color": Color(0.45, 0.55, 0.48)},
	{"place": "clinic", "id": "book", "label": "Sign the book", "room": "hall", "at": Vector3(1.15, 0.12, -0.4), "size": Vector3(0.5, 0.12, 0.3), "color": Color(0.75, 0.78, 0.76)},
	{"place": "clinic", "id": "wait", "label": "Wait a minute", "room": "hall", "at": Vector3(-1.2, 0.1, -0.15), "size": Vector3(0.7, 0.16, 0.45), "color": Color(0.45, 0.58, 0.56)},
	{"place": "clinic", "id": "dose", "label": "Collect the dose", "room": "hall", "at": Vector3(0.45, 0.14, -1.1), "size": Vector3(0.2, 0.24, 0.2), "color": Color(0.3, 0.5, 0.55)},
	{"place": "school", "id": "lesson", "label": "Read a lesson", "room": "hall", "at": Vector3(-1.15, 0.1, -0.35), "size": Vector3(0.8, 0.12, 0.5), "color": Color(0.55, 0.4, 0.28)},
	{"place": "school", "id": "bell", "label": "Ring the bell", "room": "hall", "at": Vector3(1.3, 0.2, -0.9), "size": Vector3(0.2, 0.36, 0.2), "color": Color(0.72, 0.62, 0.28)},
	{"place": "school", "id": "board", "label": "Check the board", "room": "hall", "at": Vector3(0.35, 0.12, -1.15), "size": Vector3(0.55, 0.2, 0.08), "color": Color(0.25, 0.38, 0.32)},
]

var open_home := false
var place := "apartment"
var rituals: Array[Dictionary] = []
var cell := Vector2i.ZERO
var room := "living"
var arranging := false
var selected := ""
var hopped := false
var done: Array[String] = []
var layout: Dictionary = {}
var jelly_at := Vector3(0, 0.25, 0.55)
var day := ""

var world: Node3D
var pivot: Node3D
var cam: Camera3D
var jelly: MeshInstance3D
var pieces: Dictionary = {}
var ui: CanvasLayer
var title: Label
var living_button: Button
var kitchen_button: Button
var count_label: Label
var list_box: VBoxContainer
var hint: Label
var street_hint: Label
var distance := 12.0

func _ready() -> void:
	day = Time.get_date_string_from_system()
	_build_world()
	_build_ui()
	world.visible = false
	ui.visible = false

func _process(_delta: float) -> void:
	if open_home:
		if Input.is_action_just_released("zoom_in"):
			distance = max(8.0, distance - 1.0)
			_apply_cam()
		if Input.is_action_just_released("zoom_out"):
			distance = min(16.0, distance + 1.0)
			_apply_cam()
		return
	var builder := get_parent().get_node_or_null("Builder")
	var grid: GridMap = get_parent().get_node("GridMap")
	if builder == null or street_hint == null:
		return
	var at: Vector3 = builder.selector.position
	var item := grid.get_cell_item(Vector3i(int(round(at.x)), 0, int(round(at.z))))
	street_hint.visible = PLACES.has(item)
	if street_hint.visible:
		street_hint.text = "Enter opens the " + str(TITLES[PLACES[item]]).to_lower()

func _unhandled_input(event: InputEvent) -> void:
	if not open_home:
		if event is InputEventKey and event.pressed and not event.echo:
			var key_event := event as InputEventKey
			if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
				var builder := get_parent().get_node("Builder")
				if try_enter(builder.selector.position):
					get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close_home()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.is_action_pressed("camera_rotate"):
		pivot.rotate_y(-event.relative.x * 0.01)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	var key := key_event.keycode
	if key == KEY_LEFT or key == KEY_RIGHT or key == KEY_UP or key == KEY_DOWN:
		var step := Vector3.ZERO
		if key == KEY_LEFT:
			step.x = -0.3
		elif key == KEY_RIGHT:
			step.x = 0.3
		elif key == KEY_UP:
			step.z = -0.3
		else:
			step.z = 0.3
		if arranging and selected != "":
			var at := _at(selected)
			hint.text = move_object(selected, at + step)
		else:
			_move_jelly(jelly_at + step)
		get_viewport().set_input_as_handled()
	elif key == KEY_SPACE:
		_space()
		get_viewport().set_input_as_handled()

func try_enter(at: Vector3) -> bool:
	var grid: GridMap = get_parent().get_node("GridMap")
	var here := Vector3i(int(round(at.x)), 0, int(round(at.z)))
	var item := grid.get_cell_item(here)
	if not PLACES.has(item):
		return false
	place = str(PLACES[item])
	rituals = _for_place(place)
	_rebuild_pieces()
	cell = Vector2i(here.x, here.z)
	_load()
	room = "living" if place == "apartment" else "hall"
	open_home = true
	arranging = false
	selected = ""
	world.visible = true
	ui.visible = true
	_apply_place_ui()
	_show_room()
	_set_city(false)
	_refresh_list()
	hint.text = "Click a ritual, or the floor to move the jelly. Arrows nudge. Space pets, or hops onto the cushion."
	return true

func close_home() -> void:
	if not open_home:
		return
	_save()
	open_home = false
	world.visible = false
	ui.visible = false
	_set_city(true)

func move_object(id: String, at: Vector3) -> String:
	var spec := _spec(id)
	var placed := Vector3(at.x, (spec["at"] as Vector3).y, at.z)
	var err := _place_check(id, placed)
	if err != "":
		return err
	layout[id] = {"x": placed.x, "y": placed.y, "z": placed.z}
	_apply_piece(id)
	_save()
	return ""

func complete(id: String) -> void:
	if done.has(id):
		hint.text = "Already done today."
		return
	done.append(id)
	_refresh_list()
	_save()
	hint.text = _spec(id)["label"]

func _click(mouse: Vector2) -> void:
	var hit: Variant = _floor_hit(mouse)
	if hit == null:
		return
	var point: Vector3 = hit
	var id := _pick(point)
	if arranging:
		selected = id
		hint.text = "Arrow keys move the piece." if id != "" else "Click a piece to move it."
		return
	if id == "walk":
		_walk()
		return
	if id != "":
		complete(id)
		return
	if _inside_point(point):
		var height := 0.45 if hopped else 0.25
		_move_jelly(Vector3(point.x, height, point.z))

func _walk() -> void:
	var door := _at("walk")
	var tw := create_tween()
	tw.tween_property(jelly, "position", Vector3(door.x, 0.25, door.z), 0.45)
	tw.tween_callback(func() -> void:
		jelly_at = Vector3(door.x, 0.25, door.z)
		hopped = false
		complete("walk")
	)

func _space() -> void:
	if room == "living" and not _spec("sit").is_empty():
		var cushion := _at("sit")
		if Vector2(jelly_at.x, jelly_at.z).distance_to(Vector2(cushion.x, cushion.z)) < 0.55:
			hopped = not hopped
			jelly_at.y = 0.45 if hopped else 0.25
			_place_jelly()
			hint.text = "Down." if not hopped else "Up on the cushion."
			return
	var tw := create_tween()
	tw.tween_property(jelly, "scale", Vector3(1.2, 0.75, 1.2), 0.12)
	tw.tween_property(jelly, "scale", Vector3.ONE, 0.12)
	hint.text = "Scratches."

func _move_jelly(at: Vector3) -> void:
	if not _inside_point(at):
		hint.text = "Keep the jelly inside the room."
		return
	for id in _ids_for(room):
		if id == "walk":
			continue
		var piece_at := _at(id)
		var size: Vector3 = _spec(id)["size"]
		if abs(at.x - piece_at.x) < size.x * 0.5 and abs(at.z - piece_at.z) < size.z * 0.5:
			hint.text = "Something is in the way."
			return
	var height := jelly_at.y if hopped else 0.25
	jelly_at = Vector3(at.x, height, at.z)
	if hopped and Vector2(jelly_at.x, jelly_at.z).distance_to(Vector2(_at("sit").x, _at("sit").z)) >= 0.55:
		hopped = false
		jelly_at.y = 0.25
	_place_jelly()

func _place_check(id: String, at: Vector3) -> String:
	var size: Vector3 = _spec(id)["size"]
	if not _inside_box(at, size):
		return "Keep the object inside the room."
	var mine := _rect(at, size)
	if mine.intersects(_jelly_pad()):
		return "The jelly needs this space."
	for other in _ids_for(_spec(id)["room"]):
		if other == id:
			continue
		if mine.intersects(_rect(_at(other), _spec(other)["size"])):
			return "Something is in the way."
	return ""

func _build_world() -> void:
	world = Node3D.new()
	world.name = "Rooms"
	add_child(world)
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(5.2, 0.08, 4.0)
	var floor_body := MeshInstance3D.new()
	floor_body.mesh = floor_mesh
	floor_body.position = Vector3(0, -0.04, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.88, 0.78)
	floor_body.material_override = mat
	world.add_child(floor_body)
	var ball := SphereMesh.new()
	ball.radius = 0.22
	ball.height = 0.44
	jelly = MeshInstance3D.new()
	jelly.mesh = ball
	var jelly_mat := StandardMaterial3D.new()
	jelly_mat.albedo_color = Color(0.35, 0.62, 0.38)
	jelly.material_override = jelly_mat
	world.add_child(jelly)
	_place_jelly()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	pivot = Node3D.new()
	world.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 32.0
	pivot.add_child(cam)
	_apply_cam()

func _build_ui() -> void:
	street_hint = Label.new()
	street_hint.text = "Enter opens the building"
	street_hint.position = Vector2(24, 78)
	street_hint.visible = false
	get_parent().get_node("CanvasLayer").add_child(street_hint)
	ui = CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(280, 0)
	ui.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	title = Label.new()
	title.text = "Apartment"
	box.add_child(title)
	count_label = Label.new()
	box.add_child(count_label)
	var rooms := HBoxContainer.new()
	box.add_child(rooms)
	living_button = _button("Living", func() -> void: _set_room("living"))
	kitchen_button = _button("Kitchen", func() -> void: _set_room("kitchen"))
	rooms.add_child(living_button)
	rooms.add_child(kitchen_button)
	rooms.add_child(_button("Arrange", func() -> void:
		arranging = not arranging
		selected = ""
		hint.text = "Click a piece, then arrow keys." if arranging else "Arrange off."
	))
	list_box = VBoxContainer.new()
	box.add_child(list_box)
	box.add_child(_button("Street", close_home))
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(260, 48)
	box.add_child(hint)

func _button(text: String, cb: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(cb)
	return button

func _apply_place_ui() -> void:
	title.text = str(TITLES[place])
	living_button.visible = place == "apartment"
	kitchen_button.visible = place == "apartment"

func _for_place(which: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for spec in RITUALS:
		if spec["place"] == which:
			found.append(spec)
	return found

func _rebuild_pieces() -> void:
	for id in pieces:
		(pieces[id] as Node3D).queue_free()
	pieces = {}
	for spec in rituals:
		var box := BoxMesh.new()
		var size: Vector3 = spec["size"]
		box.size = size
		var body := MeshInstance3D.new()
		body.mesh = box
		var piece_mat := StandardMaterial3D.new()
		piece_mat.albedo_color = spec["color"]
		body.material_override = piece_mat
		world.add_child(body)
		pieces[spec["id"]] = body
		_apply_piece(spec["id"])

func _set_room(next: String) -> void:
	room = next
	hopped = false
	jelly_at = Vector3(0, 0.25, 0.55)
	_show_room()
	_refresh_list()

func _show_room() -> void:
	for id in pieces:
		(pieces[id] as Node3D).visible = _spec(id)["room"] == room
	_place_jelly()

func _apply_piece(id: String) -> void:
	var body := pieces[id] as Node3D
	var at := _at(id)
	body.position = at + Vector3(0, (_spec(id)["size"] as Vector3).y * 0.5, 0)

func _place_jelly() -> void:
	jelly.position = jelly_at

func _apply_cam() -> void:
	cam.position = Vector3(0.72, 0.78, 0.72).normalized() * distance
	cam.look_at(Vector3(0, 0.2, 0))

func _set_city(active: bool) -> void:
	var root := get_parent()
	root.get_node("Builder").set_process(active)
	root.get_node("View").set_process(active)
	(root.get_node("View/Camera") as Camera3D).current = active
	cam.current = not active
	root.get_node("CanvasLayer").visible = active
	var bed := root.get_node("AudioStreamPlayer") as AudioStreamPlayer
	bed.stream_paused = not active

func _refresh_list() -> void:
	count_label.text = "%d / %d today" % [done.size(), rituals.size()]
	for child in list_box.get_children():
		child.queue_free()
	for spec in rituals:
		if spec["room"] != room:
			continue
		var row := Label.new()
		var mark := "· " if not done.has(spec["id"]) else "✓ "
		row.text = mark + str(spec["label"])
		list_box.add_child(row)

func _spec(id: String) -> Dictionary:
	for spec in rituals:
		if spec["id"] == id:
			return spec
	return {}

func _ids_for(which: String) -> Array[String]:
	var ids: Array[String] = []
	for spec in rituals:
		if spec["room"] == which:
			ids.append(spec["id"])
	return ids

func _at(id: String) -> Vector3:
	if layout.has(id):
		var saved: Dictionary = layout[id]
		return Vector3(float(saved["x"]), float(saved["y"]), float(saved["z"]))
	var spec := _spec(id)
	if spec.is_empty():
		return Vector3.ZERO
	return spec["at"]

func _rect(at: Vector3, size: Vector3) -> Rect2:
	return Rect2(at.x - size.x * 0.5, at.z - size.z * 0.5, size.x, size.z)

func _jelly_pad() -> Rect2:
	return Rect2(-0.35, 0.2, 0.7, 0.7)

func _inside_box(at: Vector3, size: Vector3) -> bool:
	return at.x - size.x * 0.5 >= -2.2 and at.x + size.x * 0.5 <= 2.2 and at.z - size.z * 0.5 >= -1.6 and at.z + size.z * 0.5 <= 1.6

func _inside_point(at: Vector3) -> bool:
	return at.x >= -2.2 and at.x <= 2.2 and at.z >= -1.6 and at.z <= 1.6

func _floor_hit(mouse: Vector2) -> Variant:
	var origin := cam.project_ray_origin(mouse)
	var normal := cam.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0).intersects_ray(origin, normal)

func _pick(hit: Vector3) -> String:
	var found := ""
	for id in _ids_for(room):
		var at := _at(id)
		var size: Vector3 = _spec(id)["size"]
		if abs(hit.x - at.x) <= size.x * 0.5 and abs(hit.z - at.z) <= size.z * 0.5:
			found = id
	return found

func _path() -> String:
	return "user://apartment_%d_%d.json" % [cell.x, cell.y]

func _save() -> void:
	var file := FileAccess.open(_path(), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"day": day, "done": done, "layout": layout}))

func _load() -> void:
	done = []
	layout = {}
	jelly_at = Vector3(0, 0.25, 0.55)
	hopped = false
	if not FileAccess.file_exists(_path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	if str(data.get("day", "")) == day:
		for item in data.get("done", []):
			if not _spec(str(item)).is_empty():
				done.append(str(item))
	var saved: Variant = data.get("layout", {})
	if saved is Dictionary:
		layout = saved
	for id in pieces:
		_apply_piece(id)

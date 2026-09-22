class_name VegPerson
extends Node3D

signal spoke(person_id: String, line: String)

var person_id := ""
var display_name := ""
var family := ""
var role := ""
var present := false
var mood := "steady"
var energy := 0.7
var belonging := 0.45
var purpose := 0.55
var relation := 0.1
var waypoints: Array[Vector3] = []
var index := 0
var pause := 0.0
var phase := 0.0
var speech: Label3D
var speech_time := 0.0
var body: Node3D

func setup(definition: Dictionary) -> void:
	person_id = str(definition.get("id", ""))
	display_name = str(definition.get("name", person_id))
	family = str(definition.get("family", "leek"))
	role = str(definition.get("role", ""))
	present = bool(definition.get("starts_present", false))
	visible = present
	_build_body()
	speech = Label3D.new()
	speech.font_size = 42
	speech.pixel_size = 0.0045
	speech.modulate = Color("f7f1e6")
	speech.outline_modulate = Color("1c2418")
	speech.outline_size = 10
	speech.position = Vector3(0, 1.35, 0)
	speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech.visible = false
	if ResourceLoader.exists("res://assets/fonts/Inter-SemiBold.ttf"):
		speech.font = load("res://assets/fonts/Inter-SemiBold.ttf")
	add_child(speech)

func set_route(points: Array[Vector3]) -> void:
	waypoints = points
	if not points.is_empty():
		global_position = points[0]

func say(line: String) -> void:
	if speech == null:
		return
	speech.text = line
	speech.visible = true
	speech_time = 4.2
	spoke.emit(person_id, line)

func _process(delta: float) -> void:
	if not present:
		return
	if speech_time > 0.0:
		speech_time -= delta
		if speech_time <= 0.0 and speech:
			speech.visible = false
	if waypoints.size() < 2:
		return
	if pause > 0.0:
		pause -= delta
		return
	var target := waypoints[index]
	var flat := Vector3(target.x, global_position.y, target.z) - global_position
	flat.y = 0.0
	if flat.length() < 0.18:
		index = (index + 1) % waypoints.size()
		pause = randf_range(0.6, 1.8)
		return
	var step := flat.normalized() * delta * 0.55
	global_position += step
	phase += delta * 7.0
	global_position.y = absf(sin(phase)) * 0.045
	rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), minf(1.0, delta * 6.0))
	if body:
		var squash := 1.0 + sin(phase * 2.0) * 0.035
		body.scale = Vector3(1.0 / squash, squash, 1.0)

func _build_body() -> void:
	body = Node3D.new()
	add_child(body)
	match family:
		"beet":
			_beet()
		"pea":
			_pea()
		_:
			_leek()

func _leek() -> void:
	_capsule(body, Vector3(0, 0.48, 0), 0.16, 0.62, Color("#f3efe2"))
	_capsule(body, Vector3(0, 0.86, 0), 0.11, 0.28, Color("#dfe8c8"))
	_leaf_fan(Color("#3e8f45"), 0.98)
	_arm(Vector3(-0.2, 0.62, 0), Color("#efe6c9"))
	_arm(Vector3(0.2, 0.62, 0), Color("#efe6c9"))
	_apron(Color("#d9815a"))
	_spectacles()
	_feet(Color("#c4b49a"))

func _beet() -> void:
	_sphere(body, Vector3(0, 0.42, 0), 0.28, Color("#8d2438"), Vector3(1.05, 0.9, 1.05))
	_sphere(body, Vector3(0, 0.68, 0), 0.16, Color("#a83348"))
	_leaf_fan(Color("#2f6b32"), 0.86)
	_hat()
	_arm(Vector3(-0.24, 0.48, 0), Color("#7a2034"))
	_arm(Vector3(0.24, 0.48, 0), Color("#7a2034"))
	_boots()
	_brow()

func _pea() -> void:
	_sphere(body, Vector3(0, 0.22, 0), 0.16, Color("#7dbe55"))
	_sphere(body, Vector3(0, 0.46, 0), 0.13, Color("#8ed062"))
	_sphere(body, Vector3(0, 0.66, 0), 0.1, Color("#b6e07a"))
	_vine()
	_arm(Vector3(-0.16, 0.48, 0), Color("#8ed062"))
	_arm(Vector3(0.16, 0.48, 0), Color("#8ed062"))
	_feet(Color("#5c8a3c"))
	_pack()

func _capsule(parent: Node3D, at: Vector3, radius: float, height: float, color: Color) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var node := _paint(mesh, color, 0.55)
	node.position = at
	parent.add_child(node)

func _sphere(parent: Node3D, at: Vector3, radius: float, color: Color, squash := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 8
	var node := _paint(mesh, color, 0.48)
	node.position = at
	node.scale = squash
	parent.add_child(node)
	return node

func _arm(at: Vector3, color: Color) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.28
	var node := _paint(mesh, color, 0.5)
	node.position = at
	node.rotation_degrees = Vector3(0, 0, 18 if at.x > 0 else -18)
	body.add_child(node)
	_sphere(body, at + Vector3(0.04 if at.x > 0 else -0.04, -0.16, 0.04), 0.045, Color("#f6f1e4"))

func _feet(color: Color) -> void:
	_sphere(body, Vector3(-0.07, 0.06, 0.02), 0.05, color, Vector3(1.2, 0.6, 1.5))
	_sphere(body, Vector3(0.07, 0.06, 0.02), 0.05, color, Vector3(1.2, 0.6, 1.5))

func _leaf_fan(color: Color, y: float) -> void:
	for i in 5:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.05, 0.28, 0.12)
		var node := _paint(mesh, color.lightened(0.08 * float(i % 2)), 0.7)
		node.position = Vector3(0, y, 0)
		node.rotation_degrees = Vector3(-28, i * 36, -18 + i * 8)
		body.add_child(node)

func _apron(color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, 0.26, 0.05)
	var node := _paint(mesh, color, 0.78)
	node.position = Vector3(0, 0.42, 0.12)
	body.add_child(node)

func _spectacles() -> void:
	for side in [-1, 1]:
		_sphere(body, Vector3(side * 0.055, 0.9, 0.1), 0.026, Color("#f4f0e2"))
		_sphere(body, Vector3(side * 0.058, 0.898, 0.122), 0.01, Color("#3d5c34"))
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.02
		mesh.outer_radius = 0.032
		mesh.rings = 8
		mesh.ring_segments = 12
		var node := _paint(mesh, Color("#c4a15a"), 0.32)
		node.position = Vector3(side * 0.055, 0.9, 0.118)
		node.rotation_degrees = Vector3(90, 0, 0)
		body.add_child(node)
	var bridge := BoxMesh.new()
	bridge.size = Vector3(0.04, 0.008, 0.008)
	var bar := _paint(bridge, Color("#c4a15a"), 0.32)
	bar.position = Vector3(0, 0.9, 0.118)
	body.add_child(bar)

func _hat() -> void:
	var brim := CylinderMesh.new()
	brim.top_radius = 0.2
	brim.bottom_radius = 0.2
	brim.height = 0.025
	var brim_node := _paint(brim, Color("#2f6b32"), 0.7)
	brim_node.position = Vector3(0, 0.84, 0)
	body.add_child(brim_node)

func _boots() -> void:
	for side in [-1, 1]:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.08, 0.08, 0.14)
		var node := _paint(mesh, Color("#3a2a24"), 0.8)
		node.position = Vector3(side * 0.08, 0.05, 0.02)
		body.add_child(node)

func _brow() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.02, 0.02)
	var node := _paint(mesh, Color("#4a1422"), 0.6)
	node.position = Vector3(0, 0.74, 0.14)
	node.rotation_degrees = Vector3(0, 0, -8)
	body.add_child(node)

func _vine() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.012
	mesh.height = 0.34
	var node := _paint(mesh, Color("#3f7a32"), 0.55)
	node.position = Vector3(0.1, 0.7, -0.02)
	node.rotation_degrees = Vector3(0, 0, 28)
	body.add_child(node)

func _pack() -> void:
	_sphere(body, Vector3(0, 0.4, -0.12), 0.08, Color("#e7d59a"))

func _paint(mesh: Mesh, color: Color, rough: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	node.material_override = material
	return node

func to_state() -> Dictionary:
	return {
		"id": person_id,
		"present": present,
		"mood": mood,
		"energy": energy,
		"belonging": belonging,
		"purpose": purpose,
		"relation": relation,
		"position": [global_position.x, global_position.y, global_position.z],
	}

func apply_state(data: Dictionary) -> void:
	present = bool(data.get("present", present))
	visible = present
	mood = str(data.get("mood", mood))
	energy = float(data.get("energy", energy))
	belonging = float(data.get("belonging", belonging))
	purpose = float(data.get("purpose", purpose))
	relation = float(data.get("relation", relation))
	var pos = data.get("position", null)
	if typeof(pos) == TYPE_ARRAY and pos.size() == 3:
		global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))

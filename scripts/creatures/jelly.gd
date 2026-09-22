class_name Jelly
extends Node3D

signal reacted(kind: String, jelly: Jelly)

var species_id := ""
var display_name := ""
var life := "curious"
var bond := 0.08
var mood := "content"
var tier := 1
var radius := 0.34
var held := false
var hold_target := Vector3.ZERO
var vel := Vector3.ZERO
var goal := Vector3.ZERO
var attract := Vector3.ZERO
var site_time := 0.0
var leaving := false
var squash := 1.0
var ripple := 0.0
var hop_wait := 0.4
var wants_sleep := false
var reduce_motion := false
var mat: ShaderMaterial
var eye_l: Node3D
var eye_r: Node3D
var mouth: Node3D
var face_z := 0.0

func setup(definition: Dictionary) -> void:
	species_id = str(definition.get("id", ""))
	display_name = str(definition.get("name", species_id))
	radius = float(definition.get("radius", 0.34))
	life = "curious"
	_build(definition)
	attract = global_position
	goal = global_position

func _build(definition: Dictionary) -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/jelly.gdshader")
	mat.set_shader_parameter("deep_color", Color(str(definition.get("deep", "#3aaa66"))))
	mat.set_shader_parameter("lit_color", Color(str(definition.get("lit", "#e7ffd2"))))
	mat.set_shader_parameter("glow_color", Color(str(definition.get("glow", "#d6ff6a"))))
	mat.set_shader_parameter("wobble", float(definition.get("wobble", 0.5)))
	var root := Node3D.new()
	root.name = "Body"
	add_child(root)
	var shape := str(definition.get("shape", "droplet"))
	face_z = radius * 1.05
	var eye_y := _shape(root, shape)
	var organ_y := eye_y * 0.5
	if shape == "bell":
		organ_y = radius * 0.95
	_organ(root, definition, organ_y)
	_face(root, definition, eye_y)

func _shape(root: Node3D, shape: String) -> float:
	match shape:
		"bell":
			_bell(root)
			face_z = radius * 0.78
			return radius * 0.62
		"pear":
			_blob(root, Vector3(0, 0.32, 0), Vector3(0.95, 1.2, 0.95))
			_blob(root, Vector3(0, 0.72, 0), Vector3(0.36, 0.3, 0.36))
			return 0.5
		"long":
			_blob(root, Vector3(0, 0.5, 0), Vector3(0.58, 1.45, 0.58))
			return 0.78
		"flat":
			_blob(root, Vector3(0, 0.18, 0), Vector3(1.35, 0.4, 1.2))
			return 0.24
		"stacked":
			_blob(root, Vector3(0, 0.2, 0), Vector3(0.78, 0.55, 0.78))
			_blob(root, Vector3(0, 0.52, 0), Vector3(0.58, 0.46, 0.58))
			_blob(root, Vector3(0, 0.84, 0), Vector3(0.36, 0.32, 0.36))
			return 0.7
		"lobes":
			_blob(root, Vector3(0, 0.26, 0), Vector3(0.78, 0.64, 0.78))
			_blob(root, Vector3(0.28, 0.22, 0.08), Vector3(0.5, 0.44, 0.5))
			_blob(root, Vector3(-0.26, 0.2, 0.1), Vector3(0.48, 0.42, 0.48))
			_blob(root, Vector3(0.02, 0.24, -0.26), Vector3(0.46, 0.4, 0.46))
			return 0.32
		"crown":
			_blob(root, Vector3(0, 0.28, 0), Vector3(0.95, 0.75, 0.95))
			for i in 5:
				var angle := TAU * float(i) / 5.0
				_blob(root, Vector3(cos(angle) * 0.28, 0.58, sin(angle) * 0.28), Vector3(0.28, 0.38, 0.28))
			return 0.42
		_:
			_blob(root, Vector3(0, 0.32, 0), Vector3(0.82, 1.08, 0.82))
			return 0.46

func _bell(root: Node3D) -> void:
	var body := MeshInstance3D.new()
	body.mesh = _bell_lathe()
	body.material_override = mat
	root.add_child(body)
	for i in 6:
		_petal(root, TAU * float(i) / 6.0, -0.12, 1.0, 1.0)
		_petal(root, TAU * float(i) / 6.0 + 0.52, 0.35, 0.72, 0.62)
	for i in 3:
		var angle := TAU * float(i) / 3.0 + 0.4
		var stamen := MeshInstance3D.new()
		var bud := SphereMesh.new()
		bud.radius = radius * 0.07
		bud.height = radius * 0.18
		stamen.mesh = bud
		stamen.material_override = mat
		stamen.position = Vector3(cos(angle) * radius * 0.12, radius * 1.28, sin(angle) * radius * 0.12)
		root.add_child(stamen)

func _bell_lathe() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile: Array[Vector2] = [
		Vector2(0.18, 0.02),
		Vector2(0.72, 0.08),
		Vector2(0.5, 0.28),
		Vector2(0.32, 0.5),
		Vector2(0.16, 0.74),
	]
	var segments := 16
	var rings: Array = []
	for row in profile:
		var ring: Array[Vector3] = []
		for seg in segments:
			var angle := TAU * float(seg) / float(segments)
			var flute := 1.0
			if row.y < 0.16:
				flute = 1.0 + 0.14 * cos(angle * 6.0)
			ring.append(Vector3(cos(angle) * row.x * flute, row.y, sin(angle) * row.x * flute) * radius)
		rings.append(ring)
	for row in rings.size() - 1:
		var a: Array = rings[row]
		var b: Array = rings[row + 1]
		for seg in segments:
			var n := (seg + 1) % segments
			_tri(tool, a[seg], b[seg], b[n])
			_tri(tool, a[seg], b[n], a[n])
	var tip: Vector3 = Vector3(0, profile[profile.size() - 1].y * radius, 0)
	var top: Array = rings[rings.size() - 1]
	for seg in segments:
		_tri(tool, top[seg], tip, top[(seg + 1) % segments])
	tool.generate_normals()
	return tool.commit()

func _petal(root: Node3D, angle: float, lift: float, reach: float, size: float) -> void:
	var petal := MeshInstance3D.new()
	petal.mesh = _petal_mesh()
	petal.material_override = mat
	var out := Vector3(cos(angle), lift, sin(angle)).normalized()
	var x_axis := Vector3.UP.cross(out).normalized()
	var y_axis := out.cross(x_axis).normalized()
	var rim := radius * 0.78 * reach
	petal.transform = Transform3D(Basis(x_axis, y_axis, out).scaled(Vector3(size, size, reach)), Vector3(cos(angle) * rim, radius * 0.1, sin(angle) * rim))
	root.add_child(petal)

func _petal_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := radius * 2.15
	var steps := 4
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in steps + 1:
		var t := float(i) / float(steps)
		var z := t * length
		var y := sin(t * PI) * radius * 0.12
		var w := radius * 0.82 * (1.0 - t * 0.45)
		var left := Vector3(-w, y, z)
		var right := Vector3(w, y, z)
		if i > 0:
			_tri(tool, prev_l, prev_r, right)
			_tri(tool, prev_l, right, left)
			_tri(tool, prev_r, prev_l, left)
			_tri(tool, prev_r, left, right)
		prev_l = left
		prev_r = right
	tool.generate_normals()
	return tool.commit()

func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)

func _blob(root: Node3D, at: Vector3, squash_scale: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.scale = squash_scale
	root.add_child(node)
	return node

func _organ(root: Node3D, definition: Dictionary, height: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius * 0.28
	mesh.height = radius * 0.56
	mesh.radial_segments = 10
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	var glow := Color(str(definition.get("glow", "#d6ff6a")))
	material.albedo_color = glow
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = 0.7
	node.material_override = material
	node.position = Vector3(0, height, 0)
	root.add_child(node)

func _face(root: Node3D, definition: Dictionary, eye_y: float) -> void:
	var eye_color := Color(str(definition.get("eye", "#fff4c8")))
	var z := face_z if face_z > 0.0 else radius * 1.05
	eye_l = _eye(root, Vector3(-radius * 0.28, eye_y, z), eye_color)
	eye_r = _eye(root, Vector3(radius * 0.28, eye_y, z), eye_color)
	mouth = _eye(root, Vector3(0, eye_y - radius * 0.34, z * 0.92), Color(str(definition.get("deep", "#1d6b38"))).darkened(0.15))
	mouth.scale = Vector3(0.85, 0.16, 0.22)

func _eye(root: Node3D, at: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	root.add_child(pivot)
	var mesh := SphereMesh.new()
	mesh.radius = radius * 0.1
	mesh.height = radius * 0.16
	mesh.radial_segments = 10
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.35
	material.roughness = 0.25
	node.material_override = material
	pivot.add_child(node)
	var pupil := MeshInstance3D.new()
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = radius * 0.038
	pupil_mesh.height = radius * 0.06
	pupil.mesh = pupil_mesh
	var pupil_material := StandardMaterial3D.new()
	pupil_material.albedo_color = Color("#3c4a28")
	pupil.material_override = pupil_material
	pupil.position = Vector3(0, 0, radius * 0.1)
	pivot.add_child(pupil)
	return pivot

func grab(point: Vector3) -> void:
	held = true
	leaving = false
	hold_target = point
	mood = "playful"
	tier = 0

func release() -> void:
	held = false
	var speed := vel.length()
	var kind := "pet"
	if speed > 3.4:
		kind = "throw"
		mood = "panic" if speed > 5.6 else "dizzy"
		bond = maxf(0.0, bond - 0.08)
		ripple = 1.0
	elif speed > 1.5:
		kind = "drop"
		mood = "annoyed"
		bond = maxf(0.0, bond - 0.03)
	else:
		kind = "pet"
		mood = "happy"
		bond = minf(1.0, bond + 0.06)
		vel.y = 2.6
	reacted.emit(kind, self)

func _process(delta: float) -> void:
	if tier >= 3:
		visible = false
		return
	visible = true
	if tier == 2:
		_coast(delta)
		return
	_full(delta)

func _full(delta: float) -> void:
	ripple = move_toward(ripple, 0.0, delta * 1.8)
	squash = move_toward(squash, 1.0, delta * 3.2)
	if held:
		var pull := hold_target - global_position
		vel += pull * delta * 26.0
		vel *= 0.84
		if pull.length() > 2.5:
			mood = "annoyed"
			bond = maxf(0.0, bond - delta * 0.04)
	else:
		vel.y -= 12.0 * delta
		hop_wait -= delta
		var grounded := global_position.y <= 0.02
		if not leaving and not wants_sleep and mood != "dizzy" and grounded and hop_wait <= 0.0:
			vel.y = randf_range(2.1, 3.3)
			hop_wait = randf_range(0.7, 1.5)
			var flat := goal - global_position
			flat.y = 0.0
			if flat.length() > 0.25:
				var hop := flat.normalized() * randf_range(0.5, 1.15)
				vel.x = hop.x
				vel.z = hop.z
		if global_position.distance_to(Vector3(goal.x, global_position.y, goal.z)) < 0.45 and not leaving:
			_pick_goal()
	global_position += vel * delta
	if global_position.y < 0.0:
		if absf(vel.y) > 1.15:
			squash = 0.7
			ripple = 1.0
			reacted.emit("land", self)
		global_position.y = 0.0
		vel.y = absf(vel.y) * 0.25
		vel.x *= 0.82
		vel.z *= 0.82
	_clamp_inside()
	var stretch := clampf(Vector2(vel.x, vel.z).length() * 0.08, 0.0, 0.32)
	if held:
		stretch = clampf(global_position.distance_to(hold_target) * 0.45, 0.0, 0.62)
	var sy := squash * (1.0 - stretch * 0.65)
	var sx := 1.0 + (1.0 - sy) * 0.5
	scale = Vector3(sx, sy, sx)
	rotation.z = sin(Time.get_ticks_msec() * 0.004) * (0.02 if reduce_motion else 0.07)
	if mat:
		mat.set_shader_parameter("ripple", 0.0 if reduce_motion else ripple)
		if reduce_motion:
			mat.set_shader_parameter("wobble", 0.0)
	_update_face()
	if not held and not leaving:
		site_time += delta

func _coast(delta: float) -> void:
	var flat := goal - global_position
	flat.y = 0.0
	if flat.length() > 0.4:
		global_position += flat.normalized() * delta * 0.7
	global_position.y = 0.0
	site_time += delta
	if global_position.distance_to(goal) < 0.5:
		_pick_goal()

func _pick_goal() -> void:
	if leaving:
		goal = GardenLayout.GATE
		return
	if mood == "panic":
		goal = global_position + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
	elif wants_sleep:
		goal = attract
	else:
		goal = attract + Vector3(randf_range(-1.3, 1.3), 0, randf_range(-1.3, 1.3))
	goal.x = clampf(goal.x, -12.0, 11.0)
	goal.z = clampf(goal.z, -8.5, 6.5)

func _clamp_inside() -> void:
	global_position.x = clampf(global_position.x, -12.6, 11.6)
	global_position.z = clampf(global_position.z, -9.2, 7.2)

func _update_face() -> void:
	if eye_l == null:
		return
	var shut := 1.0
	if wants_sleep or mood == "sleepy":
		shut = 0.18
	elif mood == "dizzy":
		shut = 0.35
	elif mood == "annoyed" or mood == "panic":
		shut = 0.55
	eye_l.scale.y = shut
	eye_r.scale.y = shut
	if mouth:
		mouth.scale.y = 0.55 if mood == "happy" or mood == "playful" else 0.22

func to_state() -> Dictionary:
	return {
		"species": species_id,
		"life": life,
		"bond": bond,
		"mood": mood,
		"site_time": site_time,
		"position": [global_position.x, global_position.y, global_position.z],
	}

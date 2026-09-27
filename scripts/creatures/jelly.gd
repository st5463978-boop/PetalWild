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
var berth := Vector3.ZERO
var use_berth := false
var site_time := 0.0
var hunger := 1.0
var bite_wait := 2.0
var leaving := false
var squash := 1.0
var ripple := 0.0
var hop_wait := 0.4
var wants_sleep := false
var young := false
var reduce_motion := false
var mat: ShaderMaterial
var eye_l: Node3D
var eye_r: Node3D
var mouth: Node3D
var face_z := 0.0
var eye_scale := 1.0

func setup(definition: Dictionary) -> void:
	species_id = str(definition.get("id", ""))
	display_name = str(definition.get("name", species_id))
	radius = float(definition.get("radius", 0.34))
	life = "curious"
	hunger = 1.0
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
	face_z = -radius * 1.05
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
			face_z = radius * 0.62
			eye_scale = 0.68
			return radius * 0.12
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
	_blob(root, Vector3(0, radius * 0.05, 0), Vector3(0.26, 0.1, 0.24))
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2, 1.35, 1.05, 0.46)
	# ponytail: the gap ring stays inside the cup so it does not glue the five lobes together.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 5.0, 1.9, 0.48, 0.28)
	# ponytail: wide short petals close the cup inside the tips. Raise reach if the center stays bare.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 10.0, 1.45, 0.62, 0.62, null, 0.0, 0.05)
	for i in 5:
		var angle := TAU * float(i) / 5.0 + 0.2
		_petal(root, angle, -0.05, 0.85, 0.42)
		_petal(root, angle, 0.25, 0.62, 0.32)
	# ponytail: lower whorl flares past the cup; raise drop if the two rims merge.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2, 0.42, 1.18, 0.42, null, radius * 0.35)
	# ponytail: third rim hangs between those tips; raise drop if it merges with the whorl above.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 5.0, 0.2, 1.28, 0.38, null, radius * 0.55)
	# ponytail: darker band under the tips; raise drop if it merges with the flared whorl.
	var band := StandardMaterial3D.new()
	band.albedo_color = Color("#1e5c30")
	band.roughness = 0.9
	band.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 10.0, 0.7, 1.05, 0.44, band, radius * 0.12, 0.4)
	# ponytail: gap tips reach past the five lobes; lower reach if they fuse into one rim.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 5.0, 1.6, 1.35, 0.28, null, -radius * 0.22, 0.1)
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
	var seed := MeshInstance3D.new()
	var seed_mesh := SphereMesh.new()
	seed_mesh.radius = radius * 0.08
	seed_mesh.height = radius * 0.14
	seed_mesh.radial_segments = 10
	seed_mesh.rings = 6
	seed.mesh = seed_mesh
	var seed_material := StandardMaterial3D.new()
	seed_material.albedo_color = Color("#8c6e28")
	seed_material.roughness = 0.92
	seed_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	seed.material_override = seed_material
	seed.position = Vector3(0.0, radius * 0.42, -radius * 0.02)
	root.add_child(seed)
	var throat_material := StandardMaterial3D.new()
	throat_material.albedo_color = Color("#163f24")
	throat_material.roughness = 0.86
	throat_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.9, 2.6, 0.34, 0.42, throat_material)

func _petal(root: Node3D, angle: float, lift: float, reach: float, size: float, material: Material = null, drop: float = 0.0, droop: float = 1.0) -> void:
	var petal := MeshInstance3D.new()
	petal.mesh = _petal_mesh(droop)
	petal.material_override = mat if material == null else material
	var out := Vector3(cos(angle), lift, sin(angle)).normalized()
	var x_axis := Vector3.UP.cross(out).normalized()
	var y_axis := out.cross(x_axis).normalized()
	var rim := radius * 0.78 * reach
	petal.transform = Transform3D(Basis(x_axis, y_axis, out).scaled(Vector3(size, size, reach)), Vector3(cos(angle) * rim, radius * 0.1 - drop, sin(angle) * rim))
	root.add_child(petal)

func _petal_mesh(droop: float = 1.0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := radius * 2.2
	var steps := 8
	var prev: Array[Vector3] = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var z := t * length * (1.0 - 0.32 * t * t)
		var y := sin(t * PI) * radius * 0.32 - pow(maxf(t - 0.55, 0.0), 2.0) * radius * 2.1 * droop
		var w := radius * (0.14 + 0.72 * sin(t * PI))
		var cup := sin(t * PI) * radius * 0.55
		var rib := sin(t * PI) * radius * 0.28
		var row: Array[Vector3] = [
			Vector3(-w, y + cup, z),
			Vector3(-w * 0.42, y + cup * 0.08, z),
			Vector3(0.0, y + rib, z),
			Vector3(w * 0.42, y + cup * 0.08, z),
			Vector3(w, y + cup, z),
		]
		if i > 0:
			for k in row.size() - 1:
				_tri(tool, prev[k], prev[k + 1], row[k + 1])
				_tri(tool, prev[k], row[k + 1], row[k])
				_tri(tool, prev[k + 1], prev[k], row[k])
				_tri(tool, prev[k + 1], row[k], row[k + 1])
		prev = row
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
	var z := face_z if face_z != 0.0 else radius * 1.05
	var bell := str(definition.get("shape", "")) == "bell"
	var spread := radius * 0.2 if bell else minf(radius * 0.26, maxf(absf(z) * 0.38, radius * 0.12))
	eye_l = _eye(root, Vector3(-spread, eye_y, z), eye_color)
	eye_r = _eye(root, Vector3(spread, eye_y, z), eye_color)
	var mouth_y := radius * 0.05 if bell else eye_y - radius * 0.22
	var mouth_z := radius * 0.7 if bell else z
	mouth = _eye(root, Vector3(0, mouth_y, mouth_z), Color(str(definition.get("deep", "#1d6b38"))).darkened(0.15))
	mouth.scale = Vector3(0.7, 0.14, 0.2)

func _eye(root: Node3D, at: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	root.add_child(pivot)
	var socket := MeshInstance3D.new()
	var socket_mesh := SphereMesh.new()
	socket_mesh.radius = radius * 0.14 * eye_scale
	socket_mesh.height = radius * 0.2 * eye_scale
	socket.mesh = socket_mesh
	var socket_material := StandardMaterial3D.new()
	socket_material.albedo_color = Color("#243024")
	socket_material.roughness = 0.8
	socket.material_override = socket_material
	socket.position = Vector3(0, 0, -radius * 0.02)
	pivot.add_child(socket)
	var mesh := SphereMesh.new()
	mesh.radius = radius * 0.1 * eye_scale
	mesh.height = radius * 0.16 * eye_scale
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
		_coast(delta)
	elif tier == 2:
		visible = true
		_coast(delta)
	else:
		visible = true
		_full(delta)
	# ponytail: linear over the eight hours; a curve if age needs to read in the mesh.
	if young:
		var fit := lerpf(0.55, 1.0, clampf(site_time / 8.0, 0.0, 1.0))
		scale = Vector3(fit, fit, fit)

func _full(delta: float) -> void:
	if reduce_motion:
		vel = Vector3.ZERO
		ripple = 0.0
		squash = 1.0
		scale = Vector3.ONE
		if mat:
			mat.set_shader_parameter("ripple", 0.0)
			mat.set_shader_parameter("wobble", 0.0)
		_update_face()
		return
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
		var heading_home := use_berth and goal.distance_to(berth) < 0.25
		if leaving:
			vel.x = 0.0
			vel.z = 0.0
			goal = GardenLayout.GATE
			var gate := GardenLayout.GATE - global_position
			gate.y = 0.0
			if gate.length() > 0.4:
				global_position += gate.normalized() * delta * 0.7
		elif heading_home:
			var home := berth - global_position
			home.y = 0.0
			if home.length() > 0.4:
				global_position += home.normalized() * delta * 0.55
		hop_wait -= delta
		var grounded := global_position.y <= _stand_y() + 0.02
		if not leaving and not wants_sleep and not heading_home and mood != "dizzy" and grounded and hop_wait <= 0.0:
			vel.y = randf_range(2.1, 3.3)
			hop_wait = randf_range(0.7, 1.5)
			var flat := goal - global_position
			flat.y = 0.0
			if flat.length() > 0.25:
				var hop := flat.normalized() * randf_range(0.5, 1.15)
				if species_id == "grapling":
					hop *= 0.45
				vel.x = hop.x
				vel.z = hop.z
		if global_position.distance_to(Vector3(goal.x, global_position.y, goal.z)) < 0.45 and not leaving:
			_pick_goal()
	global_position += vel * delta
	var floor_y := _stand_y()
	if global_position.y < floor_y:
		if absf(vel.y) > 1.15:
			squash = 0.7
			ripple = 1.0
			reacted.emit("land", self)
		global_position.y = floor_y
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
	# ponytail: one home point; a room schedule if the district grows past the kit.
	var target := berth if use_berth else goal
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() > 0.4:
		var pace := 0.32 if species_id == "grapling" else 0.7
		global_position += flat.normalized() * delta * pace
	var along := target - global_position
	along.y = 0.0
	if not use_berth and along.length() < 0.5:
		_pick_goal()
	global_position.y = _stand_y()
	site_time += delta

func _stand_y() -> float:
	# ponytail: sit on the bowl; a swim if the body should go under.
	if held or leaving or use_berth or wants_sleep:
		return 0.0
	if species_id != "bulrush" and species_id != "reedic":
		return 0.0
	if GardenLayout.pond_distance(global_position.x, global_position.z) > GardenLayout.POND_RADIUS * 0.92:
		return 0.0
	var rim := GardenLayout.POND_RADIUS
	var pond := get_tree().get_first_node_in_group("parish_pond") as Node3D
	if pond != null:
		rim = float(pond.get_meta("rim", rim))
	return GardenLayout.pond_surface(global_position.x, global_position.z, rim) + 0.05

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
		"hunger": hunger,
		"bite_wait": bite_wait,
		"leaving": leaving,
		"young": young,
		"position": [global_position.x, global_position.y, global_position.z],
	}

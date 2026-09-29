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
var hunger := 0.64
var social := 0.48
var activity := "work"
var memories: Array = []
var tier := 1
var waypoints: Array[Vector3] = []
var loop_route := true
var chore := Vector3.ZERO
var has_chore := false
var index := 0
var pause := 0.0
var phase := 0.0
var speech: Label3D
var speech_time := 0.0
var act_label: Label3D
var body: Node3D
var want := ""
var mesh_root: Node3D

func setup(definition: Dictionary) -> void:
	person_id = str(definition.get("id", ""))
	display_name = str(definition.get("name", person_id))
	family = str(definition.get("family", "leek"))
	role = str(definition.get("role", ""))
	present = bool(definition.get("starts_present", false))
	visible = present
	add_to_group("resident")
	_build_body()
	speech = Label3D.new()
	speech.font_size = 42
	speech.pixel_size = 0.0045
	speech.modulate = Color("f7f1e6")
	speech.outline_modulate = Color("1c2418")
	speech.outline_size = 10
	speech.position = Vector3(0, 2.48, 0)
	speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech.render_priority = 12
	speech.visible = false
	if ResourceLoader.exists("res://assets/fonts/Inter-SemiBold.ttf"):
		speech.font = load("res://assets/fonts/Inter-SemiBold.ttf")
	add_child(speech)
	_backing_plate(speech, Vector2(1.9, 0.3))
	act_label = Label3D.new()
	act_label.font_size = 28
	act_label.pixel_size = 0.004
	act_label.modulate = Color("d9e6c8")
	act_label.outline_modulate = Color("1c2418")
	act_label.outline_size = 8
	act_label.position = Vector3(0, 2.18, 0)
	act_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	act_label.render_priority = 12
	act_label.text = ""
	if ResourceLoader.exists("res://assets/fonts/Inter-SemiBold.ttf"):
		act_label.font = speech.font
	add_child(act_label)
	_backing_plate(act_label, Vector2(1.6, 0.24))

func set_route(points: Array[Vector3], snap := true) -> void:
	waypoints = points
	index = 0
	pause = 0.0
	if snap and not points.is_empty():
		global_position = points[0]

func say(line: String) -> void:
	if speech == null:
		return
	speech.text = line
	speech.visible = true
	_fit_plate(speech, line, 0.3)
	speech_time = 4.2
	spoke.emit(person_id, line)

func _process(delta: float) -> void:
	if not present:
		return
	if speech_time > 0.0:
		speech_time -= delta
		if speech_time <= 0.0 and speech:
			speech.visible = false
	if body:
		body.visible = present and tier < 4
	# ponytail: one point is a home; two or more is a loop. A chore is one bed, then the route resumes.
	if not has_chore and waypoints.is_empty():
		return
	if pause > 0.0 and not has_chore:
		pause -= delta
		return
	var target := chore if has_chore else waypoints[index]
	var flat := Vector3(target.x, global_position.y, target.z) - global_position
	flat.y = 0.0
	var gap := flat.length()
	if gap < 0.18:
		if has_chore:
			return
		if not loop_route and index >= waypoints.size() - 1:
			pause = 1.2
			return
		index = (index + 1) % waypoints.size()
		pause = randf_range(0.6, 1.8)
		return
	var step := flat.normalized() * minf(delta * _speed(), gap)
	global_position += step
	if tier >= 3:
		global_position.y = 0.0
		if body:
			body.scale = Vector3.ONE
		return
	if body:
		body.visible = true
	phase += delta * 7.0
	global_position.y = absf(sin(phase)) * 0.045
	rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), minf(1.0, delta * 6.0))
	if body:
		var squash := 1.0 + sin(phase * 2.0) * 0.035
		body.scale = Vector3(1.0 / squash, squash, 1.0)

func set_activity(text: String) -> void:
	activity = text
	if act_label:
		act_label.text = text
		_fit_plate(act_label, text, 0.24)
		act_label.visible = false

func _speed() -> float:
	# ponytail: L3 skips bob instead of running faster; a 6s smoke tick overshoots the porch if we scale speed.
	return 0.32 if energy < 0.35 else 0.55

func _backing_plate(host: Label3D, size: Vector2) -> void:
	var plate := MeshInstance3D.new()
	plate.name = "BackingPlate"
	var quad := QuadMesh.new()
	quad.size = size
	plate.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.08, 0.07, 0.05, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 8
	plate.material_override = mat
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position = Vector3(0, 0, 0.02)
	host.add_child(plate)

func _fit_plate(host: Label3D, line: String, height: float) -> void:
	var plate := host.get_node_or_null("BackingPlate") as MeshInstance3D
	if plate == null or not (plate.mesh is QuadMesh):
		return
	var wide := clampf(0.7 + float(line.length()) * 0.052, 1.0, 2.8)
	(plate.mesh as QuadMesh).size = Vector2(wide, height)

func _build_body() -> void:
	body = Node3D.new()
	add_child(body)
	if _mount_mesh():
		return
	match family:
		"beet":
			_beet()
		"pea":
			_pea()
		_:
			_leek()

func _mesh_path() -> String:
	match family:
		"leek":
			return "res://assets/characters/leek.glb"
		"beet":
			return "res://assets/characters/carrot.glb"
		"pea":
			return "res://assets/characters/tomato.glb"
		_:
			return "res://assets/characters/human.glb"

func _mount_mesh() -> bool:
	var path := _mesh_path()
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false
	mesh_root = packed.instantiate() as Node3D
	if mesh_root == null:
		return false
	mesh_root.name = "FolkMesh"
	body.add_child(mesh_root)
	# The leek mesh is a 8 cm stalk. The carrot is three times as wide at the same height.
	if family == "leek":
		mesh_root.scale = Vector3(1.7, 1.7, 1.7)
	elif family == "pea":
		mesh_root.scale = Vector3(1.6, 1.6, 1.6)
	_skin(mesh_root)
	return true

func _skin(node: Node) -> void:
	if not ResourceLoader.exists("res://shaders/veg_skin.gdshader"):
		return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var n := mesh_node.name.to_lower()
		if "leaf" in n or "eye" in n or "face" in n or "mouth" in n or "hat" in n or "can" in n:
			pass
		else:
			var mat := ShaderMaterial.new()
			mat.shader = load("res://shaders/veg_skin.gdshader") as Shader
			mat.set_shader_parameter("skin_tint", Color(1, 1, 1))
			mat.set_shader_parameter("roughness", 0.42)
			mat.set_shader_parameter("sss_strength", 0.35)
			var imported: Material = mesh_node.get_active_material(0)
			if imported is StandardMaterial3D:
				var std := imported as StandardMaterial3D
				if std.albedo_texture != null:
					mat.set_shader_parameter("albedo_tex", std.albedo_texture)
			mesh_node.material_override = mat
	for child in node.get_children():
		_skin(child)

func _leek() -> void:
	_stalk()
	for i in 7:
		var droop := 0.62 if i % 2 == 0 else 0.32
		var length := 0.7 if i % 2 == 0 else 0.46
		_ribbon(Color("#2c6e32").lightened(0.06 * float(i % 3)), 0.8, i * (360.0 / 7.0), droop, length)
	_arm(Vector3(-0.18, 0.5, 0), Color("#efe6c9"))
	var right := _arm(Vector3(0.2, 0.46, 0.04), Color("#efe6c9"), -18.0, 68.0)
	_apron(Color("#d9815a"))
	_satchel()
	_seed_tray(right)
	_spectacles_at(0.68)
	_mouth_at(0.62)
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

func _stalk() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radii: Array[float] = [0.16, 0.15, 0.11, 0.08, 0.05, 0.018]
	var heights: Array[float] = [0.02, 0.2, 0.4, 0.6, 0.8, 0.98]
	var tints: Array[Color] = [
		Color("#f4efe4"), Color("#efe6cc"), Color("#d5e4a4"),
		Color("#8fbf5c"), Color("#4d8a38"), Color("#2c6a30"),
	]
	var segments := 10
	var rings: Array = []
	for row in radii.size():
		var ring: Array[Vector3] = []
		for seg in segments:
			var angle := TAU * float(seg) / float(segments)
			var flute := 1.0 + 0.1 * cos(angle * 3.0 + heights[row] * 4.0)
			ring.append(Vector3(cos(angle) * radii[row] * flute, heights[row], sin(angle) * radii[row] * flute))
		rings.append(ring)
	for row in rings.size() - 1:
		var a: Array = rings[row]
		var b: Array = rings[row + 1]
		for seg in segments:
			var n := (seg + 1) % segments
			_stalk_tri(tool, a[seg], b[seg], b[n], tints[row])
			_stalk_tri(tool, a[seg], b[n], a[n], tints[row])
	var tip: Vector3 = Vector3(0, heights[heights.size() - 1], 0)
	var top: Array = rings[rings.size() - 1]
	for seg in segments:
		_stalk_tri(tool, top[seg], tip, top[(seg + 1) % segments], tints[tints.size() - 1])
	tool.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.62
	node.material_override = material
	body.add_child(node)

func _stalk_tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.add_vertex(a)
	tool.set_color(color)
	tool.add_vertex(b)
	tool.set_color(color)
	tool.add_vertex(c)

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

func _arm(at: Vector3, color: Color, pitch: float = 0.0, roll: float = 0.0) -> Node3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.28
	var node := _paint(mesh, color, 0.5)
	node.position = at
	var z_roll := roll if roll != 0.0 else (18.0 if at.x > 0.0 else -18.0)
	node.rotation_degrees = Vector3(pitch, 0, z_roll)
	body.add_child(node)
	# ponytail: pale hands clip to white under this sun; raise if the fingers go dull.
	_hand(node, Color("#6a5c4c"))
	return node

func _hand(arm: Node3D, color: Color) -> void:
	var palm := BoxMesh.new()
	palm.size = Vector3(0.1, 0.05, 0.12)
	var node := _paint(palm, color, 0.5)
	node.position = Vector3(0, -0.17, 0.02)
	arm.add_child(node)
	for i in 3:
		var finger := CapsuleMesh.new()
		finger.radius = 0.014
		finger.height = 0.09
		var tip := _paint(finger, color.lightened(0.06), 0.46)
		tip.position = Vector3(-0.028 + float(i) * 0.028, -0.02, -0.07)
		tip.rotation_degrees = Vector3(78, 0, 0)
		node.add_child(tip)
	var thumb := CapsuleMesh.new()
	thumb.radius = 0.015
	thumb.height = 0.07
	var side := _paint(thumb, color.darkened(0.04), 0.46)
	side.position = Vector3(0.055, 0.0, -0.02)
	side.rotation_degrees = Vector3(40, 0, -55)
	node.add_child(side)

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
	node.position = Vector3(0, 0.42, -0.12)
	body.add_child(node)

func _spectacles_at(y: float) -> void:
	for side in [-1, 1]:
		_sphere(body, Vector3(side * 0.05, y, -0.09), 0.022, Color("#f7f3e6"))
		_sphere(body, Vector3(side * 0.052, y, -0.108), 0.008, Color("#35502e"))
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.016
		mesh.outer_radius = 0.026
		mesh.rings = 8
		mesh.ring_segments = 12
		var node := _paint(mesh, Color("#c4a15a"), 0.32)
		node.position = Vector3(side * 0.05, y, -0.1)
		node.rotation_degrees = Vector3(90, 0, 0)
		body.add_child(node)
	var bridge := BoxMesh.new()
	bridge.size = Vector3(0.036, 0.006, 0.006)
	var bar := _paint(bridge, Color("#c4a15a"), 0.32)
	bar.position = Vector3(0, y, -0.1)
	body.add_child(bar)

func _mouth_at(y: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.028, 0.006, 0.006)
	var node := _paint(mesh, Color("#c46a58"), 0.55)
	node.position = Vector3(0, y, -0.105)
	body.add_child(node)

func _seed_tray(arm: Node3D) -> void:
	var tray := BoxMesh.new()
	tray.size = Vector3(0.16, 0.018, 0.1)
	var board := _paint(tray, Color("#c4a15a"), 0.7)
	board.position = Vector3(0.0, -0.2, 0.04)
	arm.add_child(board)
	for i in 4:
		var seed := SphereMesh.new()
		seed.radius = 0.012
		seed.height = 0.02
		var node := _paint(seed, Color("#e7d59a") if i % 2 == 0 else Color("#c46a58"), 0.45)
		node.position = Vector3(-0.045 + float(i) * 0.03, 0.016, 0.0)
		board.add_child(node)

func _satchel() -> void:
	var bag := BoxMesh.new()
	bag.size = Vector3(0.11, 0.09, 0.05)
	var node := _paint(bag, Color("#c4a15a"), 0.72)
	node.position = Vector3(0.15, 0.36, -0.08)
	body.add_child(node)
	var strap := BoxMesh.new()
	strap.size = Vector3(0.012, 0.22, 0.012)
	var band := _paint(strap, Color("#8d6238"), 0.6)
	band.position = Vector3(0.1, 0.5, -0.04)
	band.rotation_degrees = Vector3(0, 0, 18)
	body.add_child(band)

func _ribbon(color: Color, origin_y: float, yaw_deg: float, droop: float, length: float) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 5
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in steps + 1:
		var t := float(i) / float(steps)
		var y := t * length * 0.78
		var z := t * t * length * droop
		var w := lerpf(0.05, 0.012, t)
		var left := Vector3(-w, y, z)
		var right := Vector3(w, y, z)
		if i > 0:
			tool.add_vertex(prev_l)
			tool.add_vertex(prev_r)
			tool.add_vertex(right)
			tool.add_vertex(prev_l)
			tool.add_vertex(right)
			tool.add_vertex(left)
		prev_l = left
		prev_r = right
	tool.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.64
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.position = Vector3(0, origin_y, 0)
	node.rotation_degrees = Vector3(-18, yaw_deg, 0)
	body.add_child(node)

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
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
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
		"hunger": hunger,
		"social": social,
		"activity": activity,
		"memories": memories.duplicate(),
		"position": [global_position.x, global_position.y, global_position.z],
		"has_chore": has_chore,
		"chore": [chore.x, chore.y, chore.z],
		"want": want,
	}

func apply_state(data: Dictionary) -> void:
	present = bool(data.get("present", present))
	visible = present
	mood = str(data.get("mood", mood))
	energy = float(data.get("energy", energy))
	belonging = float(data.get("belonging", belonging))
	purpose = float(data.get("purpose", purpose))
	relation = float(data.get("relation", relation))
	hunger = float(data.get("hunger", hunger))
	social = float(data.get("social", social))
	activity = str(data.get("activity", activity))
	var saved_mem = data.get("memories", memories)
	if typeof(saved_mem) == TYPE_ARRAY:
		memories = saved_mem.duplicate()
	if act_label:
		act_label.text = activity
		act_label.visible = false
	var pos = data.get("position", null)
	if typeof(pos) == TYPE_ARRAY and pos.size() == 3:
		global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	has_chore = bool(data.get("has_chore", false))
	var job = data.get("chore", null)
	if typeof(job) == TYPE_ARRAY and job.size() == 3:
		chore = Vector3(float(job[0]), float(job[1]), float(job[2]))
	want = str(data.get("want", want))

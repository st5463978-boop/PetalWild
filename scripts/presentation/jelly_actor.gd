extends Node3D

var species_id := ""
var game = null
var held := false
var mood := "calm"
var airborne := Vector3.ZERO
var waypoints: Array = []
var hop := 0.0
var body: Node3D
var eyes: Node3D
var brows: Node3D
var mouth: Node3D
var material: ShaderMaterial
var home := Vector3.ZERO
var think := 0.0


func setup(id: String, definition: Dictionary, director) -> void:
	species_id = id
	game = director
	name = "Jelly_%s" % id
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_build_form(String(definition.get("form", "pear")), definition.get("colors", {}))
	_build_face(definition.get("colors", {}))
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false
	area.set_meta("kind", "jelly")
	area.set_meta("id", id)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.28
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	var pos: Array = []
	if game != null and game.state().get("species", {}).has(id):
		pos = game.state()["species"][id].get("pos", [])
	if pos.size() == 2:
		home = game.plot_world(int(pos[0]), int(pos[1]))
		home.y = 0.22
		global_position = home


func hold_at(world_pos: Vector3, stretch: float) -> void:
	held = true
	airborne = Vector3.ZERO
	global_position = world_pos
	_squash(clampf(stretch, 0.0, 0.65), world_pos - global_position)
	if material != null:
		material.set_shader_parameter("impact", clampf(stretch, 0.0, 1.0))


func release(velocity: Vector3) -> void:
	held = false
	airborne = velocity
	global_position.y = maxf(global_position.y, 0.22)


func set_mood(next: String) -> void:
	mood = next


func _process(delta: float) -> void:
	if held:
		return
	var ground_y := 0.22
	if airborne.length() > 0.15 or global_position.y > ground_y + 0.03:
		airborne.y -= 12.0 * delta
		global_position += airborne * delta
		_squash(clampf(airborne.length() * 0.04, 0.0, 0.45), airborne)
		if global_position.y <= ground_y:
			global_position.y = ground_y
			airborne.y = absf(airborne.y) * 0.42
			airborne.x *= 0.55
			airborne.z *= 0.55
			if material != null:
				material.set_shader_parameter("impact", 0.8)
			if airborne.length() < 1.1:
				airborne = Vector3.ZERO
				_squash(0.0, Vector3.ZERO)
		return
	if mood == "panic":
		_flee(delta)
	elif _should_sleep():
		_squash(0.08, Vector3.UP)
		_face(true)
	else:
		_wander(delta)
		_face(false)
	if material != null and not PetalWorld.reduce_motion:
		material.set_shader_parameter("wobble", 0.07 if mood != "panic" else 0.14)
		material.set_shader_parameter("impact", lerpf(float(material.get_shader_parameter("impact")), 0.0, delta * 2.0))


func _should_sleep() -> bool:
	if game == null:
		return false
	var phase := PetalRules.phase_for(int(game.state().get("minute", 0)))
	return phase == "night" and mood in ["calm", "happy"]


func _wander(delta: float) -> void:
	think -= delta
	if waypoints.is_empty() and think <= 0.0:
		think = randf_range(1.4, 3.2)
		_plan(game.random_walkable())
	if waypoints.is_empty():
		hop = lerpf(hop, 0.0, delta * 3.0)
		global_position.y = 0.22 + sin(Time.get_ticks_msec() * 0.004) * 0.03
		_squash(0.04, Vector3.UP)
		return
	var target: Vector3 = waypoints[0]
	var flat := Vector3(target.x, global_position.y, target.z)
	var delta_v := flat - global_position
	var dist := Vector2(delta_v.x, delta_v.z).length()
	if dist < 0.08:
		waypoints.pop_front()
		return
	var dir := delta_v / dist
	var speed := 1.15 if mood != "panic" else 2.1
	global_position += dir * minf(speed * delta, dist)
	if dir.length() > 0.01:
		look_at(global_position + Vector3(dir.x, 0.0, dir.z), Vector3.UP)
	hop += delta * 9.0
	global_position.y = 0.22 + absf(sin(hop)) * 0.16
	_squash(absf(sin(hop)) * 0.18, Vector3.UP)


func _flee(delta: float) -> void:
	if game != null and waypoints.is_empty():
		var away: Vector2i = game.random_walkable()
		_plan(away)
	_wander(delta)


func _plan(cell: Vector2i) -> void:
	if game == null or cell.x < 0:
		return
	var start: Vector2i = game.world_to_plot(global_position)
	var blocked: Dictionary = PetalPath.blocked_from_state(game.state())
	var width := int(game.state()["width"])
	var height := int(game.state()["height"])
	var path: Array = PetalPath.astar(start, cell, blocked, width, height)
	waypoints.clear()
	for step in path:
		var point: Vector3 = game.plot_world(step.x, step.y)
		point.y = 0.22
		waypoints.append(point)


func _squash(amount: float, along: Vector3) -> void:
	if body == null:
		return
	var wide := 1.0 + amount
	var tall := 1.0 - amount * 0.8
	body.scale = Vector3(wide, maxf(tall, 0.45), wide)
	if material != null and along.length() > 0.01:
		material.set_shader_parameter("push", along.normalized())


func _face(asleep: bool) -> void:
	if eyes == null:
		return
	var eye_y := 0.15 if asleep else 1.0
	match mood:
		"happy":
			eye_y = 1.05
			eyes.scale = Vector3(1.08, eye_y, 1.0)
		"annoyed":
			eyes.scale = Vector3(1.0, 0.72, 1.0)
		"dizzy":
			eyes.scale = Vector3(1.15, 0.8, 1.0)
			eyes.rotation.z = sin(Time.get_ticks_msec() * 0.01) * 0.4
		"panic":
			eyes.scale = Vector3(1.25, 1.25, 1.0)
		_:
			eyes.scale = Vector3(1.0, eye_y, 1.0)
			eyes.rotation.z = 0.0
	if brows != null:
		brows.rotation.z = 0.35 if mood == "annoyed" or mood == "panic" else 0.0
	if mouth != null:
		mouth.rotation.x = 0.4 if mood == "happy" else -0.15 if mood == "annoyed" else 0.05


func _build_form(form: String, colors: Dictionary) -> void:
	var shader := load("res://shaders/jelly.gdshader") as Shader
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("deep_color", Color(String(colors.get("deep", "#145C32"))))
	material.set_shader_parameter("lit_color", Color(String(colors.get("lit", "#B6F25A"))))
	material.set_shader_parameter("rim_color", Color(String(colors.get("rim", "#F4FFE4"))))
	material.set_shader_parameter("wobble", 0.06)
	material.set_shader_parameter("impact", 0.0)
	material.set_shader_parameter("push", Vector3.ZERO)
	var parts: Array[Node3D] = []
	match form:
		"ribbon":
			parts.append(_blob(Vector3(0.16, 0.55, 0.12), Vector3(0, 0.28, 0)))
		"stack":
			parts.append(_blob(Vector3(0.34, 0.22, 0.34), Vector3(0, 0.12, 0)))
			parts.append(_blob(Vector3(0.26, 0.2, 0.26), Vector3(0, 0.32, 0)))
			parts.append(_blob(Vector3(0.16, 0.16, 0.16), Vector3(0, 0.5, 0)))
		"flat", "squat":
			parts.append(_blob(Vector3(0.42, 0.16, 0.38), Vector3(0, 0.12, 0)))
		"droplet":
			parts.append(_blob(Vector3(0.22, 0.48, 0.22), Vector3(0, 0.28, 0)))
		"crown":
			parts.append(_blob(Vector3(0.3, 0.24, 0.3), Vector3(0, 0.16, 0)))
			for i in 5:
				var a := float(i) / 5.0 * TAU
				parts.append(_blob(Vector3(0.08, 0.14, 0.08), Vector3(cos(a) * 0.16, 0.36, sin(a) * 0.16)))
		"lobe":
			parts.append(_blob(Vector3(0.2, 0.22, 0.2), Vector3(-0.12, 0.16, 0)))
			parts.append(_blob(Vector3(0.22, 0.28, 0.2), Vector3(0.08, 0.18, 0.04)))
			parts.append(_blob(Vector3(0.12, 0.16, 0.14), Vector3(0.02, 0.34, -0.08)))
		"crest":
			parts.append(_blob(Vector3(0.24, 0.36, 0.2), Vector3(0, 0.22, 0)))
			var fin := _blob(Vector3(0.05, 0.28, 0.16), Vector3(0, 0.42, 0.12))
			parts.append(fin)
		_:
			parts.append(_blob(Vector3(0.36, 0.2, 0.32), Vector3(0, 0.1, 0)))
			parts.append(_blob(Vector3(0.22, 0.26, 0.2), Vector3(0, 0.3, 0)))
			parts.append(_blob(Vector3(0.07, 0.14, 0.06), Vector3(0, 0.5, 0)))
			var leaf := _blob(Vector3(0.16, 0.04, 0.08), Vector3(0.1, 0.48, 0))
			leaf.rotation.z = -0.6
			parts.append(leaf)
	for part in parts:
		part.material_override = material
		body.add_child(part)


func _blob(scale: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 18
	sphere.rings = 10
	mesh_node.mesh = sphere
	mesh_node.scale = scale
	mesh_node.position = at
	return mesh_node


func _build_face(colors: Dictionary) -> void:
	eyes = Node3D.new()
	eyes.position = Vector3(0, 0.24, -0.16)
	body.add_child(eyes)
	var ink := Color(String(colors.get("eye", "#1A140E")))
	for side in [-1.0, 1.0]:
		var white := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.045
		sphere.height = 0.09
		white.mesh = sphere
		white.position = Vector3(side * 0.07, 0.02, -0.02)
		white.scale = Vector3(1.0, 1.25, 0.7)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.96, 0.94, 0.9)
		mat.roughness = 0.35
		white.material_override = mat
		eyes.add_child(white)
		var pupil := MeshInstance3D.new()
		var pmesh := SphereMesh.new()
		pmesh.radius = 0.02
		pmesh.height = 0.04
		pupil.mesh = pmesh
		pupil.position = Vector3(side * 0.07, 0.02, -0.05)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = ink
		pmat.roughness = 0.4
		pupil.material_override = pmat
		eyes.add_child(pupil)
	brows = Node3D.new()
	brows.position = Vector3(0, 0.09, -0.03)
	eyes.add_child(brows)
	for side in [-1.0, 1.0]:
		var brow := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.012, 0.02)
		brow.mesh = box
		brow.position = Vector3(side * 0.07, 0, 0)
		brow.rotation.z = side * -0.2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ink
		brow.material_override = mat
		brows.add_child(brow)
	mouth = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.012
	torus.outer_radius = 0.045
	mouth.mesh = torus
	mouth.position = Vector3(0, -0.05, -0.03)
	mouth.rotation.x = 0.2
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = ink.lightened(0.15)
	mouth.material_override = mmat
	eyes.add_child(mouth)

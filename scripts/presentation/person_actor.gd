extends Node3D

var person_id := ""
var game = null
var waypoints: Array = []
var phase := ""
var bob := 0.0
var arms: Node3D


func setup(id: String, definition: Dictionary, director) -> void:
	person_id = id
	game = director
	name = "Person_%s" % id
	_build(definition)
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false
	area.set_meta("kind", "person")
	area.set_meta("id", id)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.16
	capsule.height = 0.62
	shape.shape = capsule
	shape.position.y = 0.34
	area.add_child(shape)
	add_child(area)


func _process(delta: float) -> void:
	if game == null:
		return
	var now := PetalRules.phase_for(int(game.state().get("minute", 0)))
	if now != phase or waypoints.is_empty():
		phase = now
		var tag := String(game.resident_def(person_id).get("schedule", {}).get(now, "path"))
		_plan(game.anchor_for(person_id, tag))
	if waypoints.is_empty():
		_bob(delta, false)
		return
	var target: Vector3 = waypoints[0]
	var flat := Vector3(target.x, global_position.y, target.z)
	var delta_v := flat - global_position
	var dist := Vector2(delta_v.x, delta_v.z).length()
	if dist < 0.1:
		waypoints.pop_front()
		global_position.y = 0.0
		return
	var dir := delta_v / dist
	global_position += dir * minf(0.7 * delta, dist)
	if dir.length() > 0.01:
		look_at(global_position + Vector3(dir.x, 0.0, dir.z), Vector3.UP)
	_bob(delta, true)


func _bob(delta: float, moving: bool) -> void:
	bob += delta * (6.0 if moving else 1.6)
	position.y = absf(sin(bob)) * (0.04 if moving else 0.015)
	if arms != null and not PetalWorld.reduce_motion:
		arms.rotation.x = sin(bob) * (0.5 if moving else 0.08)


func _plan(target: Vector3) -> void:
	var start: Vector2i = game.world_to_plot(global_position)
	var goal: Vector2i = game.world_to_plot(target)
	waypoints.clear()
	if start.x >= 0 and goal.x >= 0 and start != goal:
		var blocked: Dictionary = PetalPath.blocked_from_state(game.state())
		var path: Array = PetalPath.astar(start, goal, blocked, int(game.state()["width"]), int(game.state()["height"]))
		for step in path:
			waypoints.append(game.plot_world(step.x, step.y))
	waypoints.append(target)


func _build(definition: Dictionary) -> void:
	var kind := String(definition.get("body", "carrot"))
	match kind:
		"beet":
			_body_sphere(Color("7A2344"), 0.22, 0.34)
			_leaves(Color("3E7A32"))
			_boots(Color("2A2420"))
		"pea":
			_body_sphere(Color("7CB342"), 0.16, 0.22)
			_body_sphere(Color("8BC34A"), 0.13, 0.42)
			_leaves(Color("C5E1A5"))
		"onion":
			_body_sphere(Color("F3E2B8"), 0.2, 0.28)
			_ring(Color("C9A0C2"))
			_leaves(Color("8D6E63"))
		"berry":
			_body_sphere(Color("D6455D"), 0.2, 0.3)
			_seeds()
			_leaves(Color("2E7D32"))
			_apron(Color("F7E7C6"))
		_:
			_cone(Color("E07A2F"), 0.16, 0.55)
			_leaves(Color("3E8F45"))
			_apron(Color("F4EFE2"))
	_face()
	_arms_build(Color("E7B089") if kind == "carrot" else Color("F0D2B0"))


func _cone(color: Color, radius: float, height: float) -> void:
	var mesh_node := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12
	for i in segs:
		var a0 := float(i) / float(segs) * TAU
		var a1 := float(i + 1) / float(segs) * TAU
		st.set_color(color)
		st.add_vertex(Vector3(0, height, 0))
		st.add_vertex(Vector3(cos(a1) * radius, 0.02, sin(a1) * radius))
		st.add_vertex(Vector3(cos(a0) * radius, 0.02, sin(a0) * radius))
	st.generate_normals()
	mesh_node.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.72
	mesh_node.material_override = mat
	add_child(mesh_node)


func _body_sphere(color: Color, radius: float, y: float) -> void:
	var mesh_node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh_node.mesh = sphere
	mesh_node.position.y = y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.68
	mesh_node.material_override = mat
	add_child(mesh_node)


func _leaves(color: Color) -> void:
	for i in 5:
		var leaf := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.08, 0.2)
		leaf.mesh = quad
		var a := float(i) / 5.0 * TAU
		leaf.position = Vector3(cos(a) * 0.05, 0.58, sin(a) * 0.05)
		leaf.rotation = Vector3(-0.8, a, 0.2)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color.lightened(0.05 * float(i))
		mat.roughness = 0.8
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaf.material_override = mat
		add_child(leaf)


func _apron(color: Color) -> void:
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.18, 0.04)
	mesh_node.mesh = box
	mesh_node.position = Vector3(0, 0.28, -0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mesh_node.material_override = mat
	add_child(mesh_node)


func _boots(color: Color) -> void:
	for side in [-1.0, 1.0]:
		var boot := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.07, 0.06, 0.1)
		boot.mesh = box
		boot.position = Vector3(side * 0.06, 0.04, -0.02)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		boot.material_override = mat
		add_child(boot)


func _ring(color: Color) -> void:
	var mesh_node := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.16
	mesh_node.mesh = torus
	mesh_node.position.y = 0.3
	mesh_node.rotation.x = PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_node.material_override = mat
	add_child(mesh_node)


func _seeds() -> void:
	for i in 6:
		var seed := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.015
		sphere.height = 0.03
		seed.mesh = sphere
		var a := float(i) * 1.2
		seed.position = Vector3(cos(a) * 0.12, 0.32 + sin(a) * 0.04, sin(a) * -0.12)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("F6E27A")
		seed.material_override = mat
		add_child(seed)


func _face() -> void:
	var anchor := Node3D.new()
	anchor.position = Vector3(0, 0.4, -0.12)
	add_child(anchor)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.028
		sphere.height = 0.05
		eye.mesh = sphere
		eye.scale = Vector3(1.0, 1.35, 0.55)
		eye.position = Vector3(side * 0.045, 0.02, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.98, 0.96, 0.9)
		eye.material_override = mat
		anchor.add_child(eye)
		var pupil := MeshInstance3D.new()
		var pmesh := SphereMesh.new()
		pmesh.radius = 0.012
		pmesh.height = 0.02
		pupil.mesh = pmesh
		pupil.position = Vector3(side * 0.045, 0.02, -0.02)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color("2A211C")
		pupil.material_override = pmat
		anchor.add_child(pupil)
		var brow := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.008, 0.012)
		brow.mesh = box
		brow.position = Vector3(side * 0.045, 0.055, 0)
		brow.rotation.z = side * -0.25
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color("3A2A22")
		brow.material_override = bmat
		anchor.add_child(brow)
	var mouth := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.008
	torus.outer_radius = 0.028
	mouth.mesh = torus
	mouth.position = Vector3(0, -0.03, 0.01)
	mouth.rotation.x = 0.5
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color("6B3A32")
	mouth.material_override = mmat
	anchor.add_child(mouth)


func _arms_build(color: Color) -> void:
	arms = Node3D.new()
	arms.position = Vector3(0, 0.36, 0)
	add_child(arms)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.02
		capsule.height = 0.16
		arm.mesh = capsule
		arm.position = Vector3(side * 0.12, -0.06, -0.02)
		arm.rotation.z = side * 0.4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.7
		arm.material_override = mat
		arms.add_child(arm)

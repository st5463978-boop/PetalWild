class_name PlantView
extends Node3D

var plant_id := ""

func show_plant(id: String, growth: float) -> void:
	if id != plant_id:
		plant_id = id
		for child in get_children():
			child.free()
		_build(id)
	var amount := lerpf(0.18, 1.0, clampf(growth, 0.0, 1.0))
	scale = Vector3(amount, amount, amount)

func _build(id: String) -> void:
	match id:
		"meadowbell":
			_stem(0.35, 0.035, Color("#3f8f45"))
			_blossom(Vector3(0, 0.42, 0), Color("#f4ecd0"), Color("#f0c14e"))
		"peach":
			_stem(0.42, 0.05, Color("#6b4a32"))
			_ball(Vector3(0, 0.62, 0), 0.22, Color("#3f8a3a"))
			_ball(Vector3(0.16, 0.5, 0.08), 0.16, Color("#4e9a42"))
			_ball(Vector3(0.02, 0.48, 0.16), 0.09, Color("#e39a52"))
		"reed":
			_stem(0.7, 0.02, Color("#6d7a3a"), Vector3(-0.06, 0, 0))
			_stem(0.55, 0.018, Color("#8a9144"), Vector3(0.05, 0, 0.04))
			_stem(0.62, 0.016, Color("#5c6a32"), Vector3(0.0, 0, -0.05))
		"bramble":
			_ball(Vector3(0, 0.16, 0), 0.2, Color("#2f6a32"))
			_ball(Vector3(0.12, 0.14, 0.06), 0.14, Color("#3d7a38"))
			_ball(Vector3(-0.04, 0.18, 0.1), 0.045, Color("#8a3068"))
			_ball(Vector3(0.1, 0.2, -0.04), 0.04, Color("#a84478"))
		"mosspear":
			_ball(Vector3(0, 0.1, 0), 0.16, Color("#4f8a3e"))
			_ball(Vector3(0, 0.2, 0.02), 0.1, Color("#d7b15a"), Vector3(0.8, 1.2, 0.8))
		"nightlantern":
			_stem(0.48, 0.02, Color("#2c2430"))
			var bulb := _ball(Vector3(0, 0.55, 0), 0.09, Color("#ffd27a"))
			var material := bulb.material_override as StandardMaterial3D
			material.emission_enabled = true
			material.emission = Color("#ffc14a")
			material.emission_energy_multiplier = 1.4
		_:
			_ball(Vector3(0, 0.2, 0), 0.12, Color("#7eac4c"))

func _stem(height: float, radius: float, color: Color, offset := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.7
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	var node := _paint(mesh, color)
	node.position = offset + Vector3(0, height * 0.5, 0)
	add_child(node)
	return node

func _ball(at: Vector3, radius: float, color: Color, squash := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var node := _paint(mesh, color)
	node.position = at
	node.scale = squash
	add_child(node)
	return node

func _blossom(at: Vector3, petal: Color, heart: Color) -> void:
	_ball(at, 0.07, heart)
	for i in 5:
		var angle := TAU * float(i) / 5.0
		_ball(at + Vector3(cos(angle) * 0.09, 0.02, sin(angle) * 0.09), 0.045, petal)

func _paint(mesh: Mesh, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

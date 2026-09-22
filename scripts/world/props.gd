class_name GardenProps
extends RefCounted

func build(parent: Node3D) -> void:
	_stall(parent)
	_shed(parent)
	_bench(parent, Vector3(6.3, 0.0, -0.4))
	_bench(parent, Vector3(-9.4, 0.0, 1.2))
	_lantern(parent, Vector3(-2.35, 0, -6.0))
	_lantern(parent, Vector3(-6.2, 0, 3.5))
	_lantern(parent, Vector3(3.4, 0, -2.5))
	_reeds(parent)

func _stall(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "PetalStall"
	root.position = GardenLayout.STALL
	parent.add_child(root)
	_box(root, Vector3(0, 0.42, 0), Vector3(2.3, 0.78, 0.85), Color("#8d6244"))
	_box(root, Vector3(0, 0.84, 0), Vector3(2.4, 0.08, 0.95), Color("#4e3828"))
	for side in [-1.0, 1.0]:
		_cylinder(root, Vector3(side * 1.05, 1.15, 0.35), 0.05, 0.05, 1.5, Color("#6b4a32"))
	for i in 7:
		var stripe := Color("#4a3f34") if i % 2 == 0 else Color("#3d6f9a")
		_box(root, Vector3(-1.05 + float(i) * 0.35, 1.72, 0.15), Vector3(0.34, 0.06, 1.15), stripe)
	_crate(root, Vector3(-1.35, 0.16, 0.7))
	_crate(root, Vector3(1.25, 0.16, 0.62))
	for i in 5:
		_sphere(root, Vector3(-0.3 + float(i) * 0.14, 0.96, 0.15), 0.08, Color("#e39a52"))
	var sign := Label3D.new()
	sign.text = "Petal Stall"
	sign.font_size = 56
	sign.pixel_size = 0.004
	sign.position = Vector3(0, 1.35, 0.5)
	sign.shaded = false
	sign.modulate = Color("#8d6a45")
	sign.outline_modulate = Color("2a2118")
	sign.outline_size = 12
	if ResourceLoader.exists("res://assets/fonts/Inter-SemiBold.ttf"):
		sign.font = load("res://assets/fonts/Inter-SemiBold.ttf")
	root.add_child(sign)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.5, 0.4)
	light.light_color = Color("ffd2a4")
	light.light_energy = 0.16
	light.omni_range = 4.5
	light.shadow_enabled = false
	root.add_child(light)

func _shed(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "PottingShed"
	root.position = GardenLayout.SHED
	parent.add_child(root)
	_box(root, Vector3(0, 0.85, 0), Vector3(2.3, 1.7, 1.8), Color("#4a453e"))
	_box(root, Vector3(0, 0.75, 0.9), Vector3(0.55, 1.15, 0.06), Color("#3f6a5c"))
	_box(root, Vector3(-0.7, 1.05, 0.92), Vector3(0.42, 0.42, 0.05), Color("#2f5c56"))
	_box(root, Vector3(0.72, 1.05, 0.92), Vector3(0.42, 0.42, 0.05), Color("#2f5c56"))
	var roof_l := _box(root, Vector3(0, 1.95, -0.15), Vector3(2.6, 0.08, 1.15), Color("#c47c74"))
	roof_l.rotation_degrees = Vector3(-22, 0, 0)
	var roof_r := _box(root, Vector3(0, 1.95, 0.35), Vector3(2.6, 0.08, 1.15), Color("#524c44"))
	roof_r.rotation_degrees = Vector3(22, 0, 0)
	_cylinder(root, Vector3(-0.85, 0.16, 1.15), 0.12, 0.14, 0.22, Color("#c46a45"))
	_sphere(root, Vector3(-0.85, 0.38, 1.15), 0.12, Color("#3f8a3a"))
	_cylinder(root, Vector3(0.9, 0.12, 1.2), 0.1, 0.12, 0.18, Color("#b85b3c"))
	_sphere(root, Vector3(0.9, 0.32, 1.2), 0.1, Color("#e07a92"))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.2, 0.2)
	light.light_color = Color("ffc98a")
	light.light_energy = 0.16
	light.omni_range = 3.2
	light.shadow_enabled = false
	root.add_child(light)

func _bench(parent: Node3D, at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	_box(root, Vector3(0, 0.32, 0), Vector3(1.1, 0.06, 0.38), Color("#8d6244"))
	_box(root, Vector3(0, 0.52, -0.16), Vector3(1.1, 0.36, 0.06), Color("#a87852"))
	_box(root, Vector3(-0.48, 0.16, 0), Vector3(0.06, 0.32, 0.32), Color("#6b4a32"))
	_box(root, Vector3(0.48, 0.16, 0), Vector3(0.06, 0.32, 0.32), Color("#6b4a32"))

func _lantern(parent: Node3D, at: Vector3) -> void:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	_cylinder(root, Vector3(0, 0.55, 0), 0.03, 0.04, 1.1, Color("#4a4038"))
	var glow := _box(root, Vector3(0, 1.18, 0), Vector3(0.16, 0.22, 0.16), Color("#ffd7a1"))
	var material := glow.material_override as StandardMaterial3D
	material.emission_enabled = true
	material.emission = Color("#ffc98a")
	material.emission_energy_multiplier = 1.2
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.18, 0)
	light.light_color = Color("ffd2a4")
	light.light_energy = 0.35
	light.omni_range = 3.4
	light.shadow_enabled = false
	root.add_child(light)

func _reeds(parent: Node3D) -> void:
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var radius := GardenLayout.POND_RADIUS + 0.15
		var at := GardenLayout.POND_CENTER + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if at.x < 5.2:
			continue
		_cylinder(parent, at + Vector3(0, 0.45, 0), 0.02, 0.025, 0.9, Color("#6d7a3a"))

func _crate(parent: Node3D, at: Vector3) -> void:
	_box(parent, at, Vector3(0.32, 0.32, 0.32), Color("#a56b3c"))

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.74
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	node.material_override = material
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, at: Vector3, top: float, bottom: float, height: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	node.material_override = material
	parent.add_child(node)

func _sphere(parent: Node3D, at: Vector3, radius: float, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	node.material_override = material
	parent.add_child(node)

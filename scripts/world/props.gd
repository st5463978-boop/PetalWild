class_name GardenProps
extends RefCounted

func build(parent: Node3D) -> void:
	_stall(parent)
	_shed(parent)
	_tea(parent)
	_hut(parent)
	_foundry(parent)
	_hall(parent)
	_park(parent)
	_bench(parent, Vector3(6.3, 0.0, -0.4))
	_bench(parent, Vector3(-9.4, 0.0, 1.2))
	_lantern(parent, Vector3(-2.35, 0, -6.0))
	_lantern(parent, Vector3(-6.2, 0, 3.5))
	_lantern(parent, Vector3(3.4, 0, -2.5))
	_reeds(parent)
	_gate_crate(parent)

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
		# ponytail: the blue cloth clips to sky under this sun; raise if the stripe goes black.
		var shut := Color("#4a3f34") if i % 2 == 0 else Color("#263444")
		var open := Color("#c4895a") if i % 2 == 0 else Color("#8a5344")
		var stripe := _box(root, Vector3(-1.05 + float(i) * 0.35, 1.74, 0.22), Vector3(0.34, 0.07, 1.28), shut)
		stripe.rotation_degrees = Vector3(14, 0, 0)
		stripe.set_meta("open_color", open)
		stripe.set_meta("shut_color", shut)
		stripe.add_to_group("parish_awning")
	var crate_l := _crate(root, Vector3(-1.35, 0.16, 0.7))
	crate_l.name = "StallCrateL"
	crate_l.add_to_group("signoff_cam05_hide")
	_crate(root, Vector3(1.25, 0.16, 0.62))
	var cup := _sphere(root, Vector3(-1.35, 0.42, 0.7), 0.08, Color("#c4a070"))
	cup.add_to_group("parish_cup")
	cup.visible = false
	var jar := _sphere(root, Vector3(1.25, 0.42, 0.62), 0.07, Color("#8a3a48"))
	jar.add_to_group("parish_jar")
	jar.visible = false
	# ponytail: three flats beside the spur; the worn center stays |x+4.55|<0.42.
	for at in [Vector3(-0.72, 0.06, -0.72), Vector3(0.78, 0.06, -0.66), Vector3(-0.82, 0.06, -1.05)]:
		var stone := _box(root, at, Vector3(0.42, 0.06, 0.28), Color("#3a322c"))
		stone.add_to_group("parish_stall_step")
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
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.add_to_group("parish_stall_sign")
	sign.visible = false
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
	light.add_to_group("parish_stall_lamp")

func _shed(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "PottingShed"
	root.position = GardenLayout.SHED
	parent.add_child(root)
	_box(root, Vector3(0, 0.85, 0), Vector3(2.3, 1.7, 1.8), Color("#4a453e"))
	_box(root, Vector3(0, 0.75, 0.9), Vector3(0.55, 1.15, 0.06), Color("#3f6a5c"))
	_warm_pane(root, Vector3(-0.7, 1.05, 0.92), Vector3(0.42, 0.42, 0.05), Color("#2f5c56"))
	_warm_pane(root, Vector3(0.72, 1.05, 0.92), Vector3(0.42, 0.42, 0.05), Color("#2f5c56"))
	_warm_pane(root, Vector3(0.0, 1.05, -0.92), Vector3(0.42, 0.42, 0.05), Color("#2f5c56"))
	var roof_l := _box(root, Vector3(0, 1.95, -0.15), Vector3(2.6, 0.08, 1.15), Color("#c47c74"))
	roof_l.rotation_degrees = Vector3(-22, 0, 0)
	var roof_r := _box(root, Vector3(0, 1.95, 0.35), Vector3(2.6, 0.08, 1.15), Color("#524c44"))
	roof_r.rotation_degrees = Vector3(22, 0, 0)
	_cylinder(root, Vector3(-0.85, 0.16, 1.15), 0.12, 0.14, 0.22, Color("#c46a45"))
	_sphere(root, Vector3(-0.85, 0.38, 1.15), 0.12, Color("#3f8a3a"))
	_cylinder(root, Vector3(0.9, 0.12, 1.2), 0.1, 0.12, 0.18, Color("#b85b3c"))
	_sphere(root, Vector3(0.9, 0.32, 1.2), 0.1, Color("#e07a92"))
	var pan := _cylinder(root, Vector3(0.0, 0.2, 1.08), 0.12, 0.14, 0.2, Color("#c47c4a"))
	pan.add_to_group("parish_pan")
	var jam_steam := _sphere(root, Vector3(0.0, 0.46, 1.08), 0.1, Color("#f2e6d2"))
	jam_steam.add_to_group("parish_jam_steam")
	jam_steam.visible = false
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.2, 0.2)
	light.light_color = Color("ffc98a")
	light.light_energy = 0.16
	light.omni_range = 3.2
	light.shadow_enabled = false
	root.add_child(light)
	_room_lamp(light, 0.16)
	_unmark_ok(root)

func _tea(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "HedgeTeaHouse"
	root.position = GardenLayout.TEA
	parent.add_child(root)
	_box(root, Vector3(0, 0.7, 0), Vector3(1.8, 1.4, 1.5), Color("#4a3a30"))
	_box(root, Vector3(0, 0.55, -0.76), Vector3(0.46, 0.9, 0.06), Color("#2c4038"))
	_warm_pane(root, Vector3(0.48, 0.85, -0.78), Vector3(0.32, 0.32, 0.05), Color("#6a5340"))
	_box(root, Vector3(0, 1.52, 0), Vector3(2.05, 0.1, 1.75), Color("#3a322c"))
	_box(root, Vector3(0, 0.08, -1.05), Vector3(1.1, 0.08, 0.4), Color("#5c4a3c"))
	_cylinder(root, Vector3(-0.55, 0.18, -0.95), 0.08, 0.1, 0.16, Color("#2a3034"))
	var kettle := _cylinder(root, Vector3(0.48, 0.22, -0.95), 0.09, 0.11, 0.28, Color("#2a3034"))
	kettle.add_to_group("parish_kettle")
	var steam := _sphere(root, Vector3(0.48, 0.54, -0.95), 0.11, Color("#efe8dc"))
	steam.add_to_group("parish_steam")
	steam.visible = false
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.05, -0.3)
	light.light_color = Color("ffd2a4")
	light.light_energy = 0.1
	light.omni_range = 2.6
	light.shadow_enabled = false
	root.add_child(light)
	_room_lamp(light, 0.1)
	_unmark_ok(root)

func _hut(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "ResearchHut"
	root.position = GardenLayout.HUT
	parent.add_child(root)
	_box(root, Vector3(0, 0.72, 0), Vector3(1.45, 1.44, 1.25), Color("#3e342c"))
	_box(root, Vector3(0, 0.58, -0.64), Vector3(0.4, 0.86, 0.06), Color("#243830"))
	_warm_pane(root, Vector3(0.42, 0.88, -0.66), Vector3(0.28, 0.28, 0.05), Color("#4a4034"))
	var roof_l := _box(root, Vector3(0, 1.58, -0.28), Vector3(1.7, 0.08, 0.78), Color("#322c28"))
	roof_l.rotation_degrees = Vector3(18, 0, 0)
	var roof_r := _box(root, Vector3(0, 1.58, 0.28), Vector3(1.7, 0.08, 0.78), Color("#2a2622"))
	roof_r.rotation_degrees = Vector3(-18, 0, 0)
	_cylinder(root, Vector3(0.48, 1.72, 0.15), 0.08, 0.1, 0.42, Color("#3a3430"))
	_box(root, Vector3(0, 0.06, -0.9), Vector3(0.9, 0.08, 0.32), Color("#4a3e34"))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.05, -0.2)
	light.light_color = Color("ffd2a4")
	light.light_energy = 0.08
	light.omni_range = 2.2
	light.shadow_enabled = false
	root.add_child(light)
	_room_lamp(light, 0.08)
	_unmark_ok(root)

func _foundry(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "MediaFoundry"
	root.position = GardenLayout.FOUNDRY
	parent.add_child(root)
	_box(root, Vector3(0, 0.52, 0), Vector3(2.2, 1.04, 1.15), Color("#3a342e"))
	_box(root, Vector3(-0.55, 0.42, -0.59), Vector3(0.42, 0.72, 0.06), Color("#243028"))
	_box(root, Vector3(0, 1.12, 0), Vector3(2.4, 0.08, 1.35), Color("#2e2a26"))
	for i in 3:
		_box(root, Vector3(0.35 + float(i) * 0.16, 0.72, -0.62), Vector3(0.1, 0.22, 0.04), Color("#5c4a3c"))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.9, -0.2)
	light.light_color = Color("ffd2a4")
	light.light_energy = 0.06
	light.omni_range = 2.0
	light.shadow_enabled = false
	root.add_child(light)
	_unmark_ok(root)

func _hall(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "TownHall"
	root.position = GardenLayout.HALL
	parent.add_child(root)
	_cylinder(root, Vector3(-0.42, 0.55, 0), 0.04, 0.05, 1.1, Color("#4a4038"))
	_cylinder(root, Vector3(0.42, 0.55, 0), 0.04, 0.05, 1.1, Color("#4a4038"))
	_box(root, Vector3(0, 1.15, 0), Vector3(1.15, 0.62, 0.06), Color("#4a3e34"))
	_box(root, Vector3(0, 1.42, 0.02), Vector3(0.7, 0.08, 0.04), Color("#3a322c"))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.2, 0.15)
	light.light_color = Color("ffd2a4")
	light.light_energy = 0.05
	light.omni_range = 1.6
	light.shadow_enabled = false
	root.add_child(light)
	_unmark_ok(root)

func _park(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "GrovePark"
	root.position = GardenLayout.PARK
	root.visible = false
	root.add_to_group("grove_park")
	parent.add_child(root)
	_box(root, Vector3(0, 0.02, 0), Vector3(4.6, 0.04, 3.2), Color("#3f6a32"))
	_box(root, Vector3(0, 0.035, 1.5), Vector3(0.72, 0.03, 2.6), Color("#6b5340"))
	# One worn strip from the lawn to the hedge gate. Separate slabs read as debris.
	var gate_z := GardenLayout.GATE.z - GardenLayout.PARK.z
	var path_end := gate_z - 0.35
	var path_start := 1.55
	var walk := _box(root, Vector3(0.0, 0.028, (path_start + path_end) * 0.5), Vector3(1.35, 0.04, path_end - path_start), Color("#6a5a48"))
	walk.name = "ParkPath"
	_box(root, Vector3(-1.6, 0.04, -1.1), Vector3(0.7, 0.08, 0.5), Color("#4a4038"))
	_box(root, Vector3(1.5, 0.04, 0.9), Vector3(0.6, 0.07, 0.42), Color("#4a4038"))
	_bench(root, Vector3(-1.2, 0.0, 0.6))
	_bench(root, Vector3(1.1, 0.0, -0.7))
	_bench(root, Vector3(0.15, 0.0, -1.15))
	var sign := Label3D.new()
	sign.name = "ParkSign"
	sign.text = "Grove Park"
	sign.font_size = 48
	sign.pixel_size = 0.004
	sign.position = Vector3(0, 1.28, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.shaded = false
	sign.modulate = Color("#8d6a45")
	sign.outline_modulate = Color("2a2118")
	root.add_child(sign)
	var count := Label3D.new()
	count.name = "ParkCount"
	count.text = "the lawn is quiet"
	count.font_size = 28
	count.pixel_size = 0.004
	count.position = Vector3(0, 0.92, 0)
	count.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	count.shaded = false
	count.modulate = Color("#f3ead8")
	count.outline_modulate = Color("2a2118")
	root.add_child(count)

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
	# ponytail: lantern glass clips to white under this sun; raise the emission if the lamps go out.
	var glow := _box(root, Vector3(0, 1.18, 0), Vector3(0.16, 0.22, 0.16), Color("#a56b32"))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/lantern_glass.gdshader")
	material.set_shader_parameter("glow", 0.22)
	glow.material_override = material
	glow.add_to_group("parish_lantern_glass")
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.18, 0)
	light.light_color = Color("ffd2a4")
	light.light_energy = 0.35
	light.omni_range = 3.4
	light.shadow_enabled = false
	root.add_child(light)
	light.add_to_group("parish_lantern")

func _reeds(parent: Node3D) -> void:
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var radius := GardenLayout.POND_RADIUS + 0.15
		var at := GardenLayout.POND_CENTER + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if at.x < 5.2:
			continue
		_cylinder(parent, at + Vector3(0, 0.45, 0), 0.02, 0.025, 0.9, Color("#6d7a3a"))

func _gate_crate(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "ValeCrate"
	root.position = GardenLayout.GATE + Vector3(0.95, 0.0, 0.55)
	root.visible = false
	root.add_to_group("vale_crate")
	parent.add_child(root)
	_crate(root, Vector3(0, 0.16, 0))
	var sign := Label3D.new()
	sign.text = "Vale cart"
	sign.font_size = 42
	sign.pixel_size = 0.004
	sign.position = Vector3(0, 0.72, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.shaded = false
	sign.modulate = Color("#c4a070")
	sign.outline_modulate = Color("2a2118")
	sign.outline_size = 10
	sign.add_to_group("vale_crate_sign")
	if ResourceLoader.exists("res://assets/fonts/Inter-SemiBold.ttf"):
		sign.font = load("res://assets/fonts/Inter-SemiBold.ttf")
	root.add_child(sign)

func _crate(parent: Node3D, at: Vector3) -> MeshInstance3D:
	return _box(parent, at, Vector3(0.32, 0.32, 0.32), Color("#a56b3c"))

func _room_lamp(light: OmniLight3D, day: float) -> void:
	light.set_meta("day_energy", day)
	light.add_to_group("parish_room")

func _warm_pane(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var pane := _box(parent, at, size, color)
	var material := pane.material_override as StandardMaterial3D
	# ponytail: panes stay dark by day; raise the night emission if the glass stays dull.
	material.emission_enabled = true
	material.emission = Color("#c47a28")
	material.emission_energy_multiplier = 0.0
	pane.add_to_group("parish_room_glass")

func _unmark_ok(root: Node) -> void:
	root.add_to_group("signoff_hide")
	if root is GeometryInstance3D:
		root.remove_from_group("signoff_ok")
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		n.remove_from_group("signoff_ok")

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
	node.add_to_group("signoff_ok")
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, at: Vector3, top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
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
	node.add_to_group("signoff_ok")
	parent.add_child(node)
	return node

func _sphere(parent: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
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
	node.add_to_group("signoff_ok")
	parent.add_child(node)
	return node

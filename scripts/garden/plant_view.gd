class_name PlantView
extends Node3D

var plant_id := ""
var built_ripe := false

func show_plant(id: String, growth: float, water: float, fertility: float) -> void:
	var want_ripe := id == "reed" and growth >= 1.0
	if id != plant_id or want_ripe != built_ripe:
		plant_id = id
		built_ripe = want_ripe
		for child in get_children():
			child.free()
		_build(id)
	var amount := lerpf(0.18, 1.0, clampf(growth, 0.0, 1.0))
	var need := float(ContentDB.plant(id).get("water_need", 0.3))
	var limp := water < need
	# ponytail: a tired crop stands shorter; a color shift if the squat still reads as healthy.
	var tired := not limp and fertility < float(ContentDB.plant(id).get("fertility_need", 0.2))
	var squat := 0.62 if limp else (0.78 if tired else 1.0)
	scale = Vector3(amount, amount * squat, amount)
	rotation.z = 0.35 if limp else 0.0

func _build(id: String) -> void:
	match id:
		"meadowbell":
			_meadowbell()
		"peach":
			_peach()
		"reed":
			_reed()
		"bramble":
			_ball(Vector3(0, 0.16, 0), 0.2, Color("#2f6a32"))
			_ball(Vector3(0.12, 0.14, 0.06), 0.14, Color("#3d7a38"))
			# ponytail: berries under 0.05 did not read; darken if a larger fruit clips.
			_ball(Vector3(-0.16, 0.55, -0.16), 0.22, Color("#5a1834"))
			_ball(Vector3(0.16, 0.52, -0.16), 0.2, Color("#6a2040"))
		"mosspear":
			_mosspear()
		"nightlantern":
			_stem(0.48, 0.02, Color("#2c2430"))
			var bulb := _ball(Vector3(0, 0.55, 0), 0.09, Color("#ffd27a"))
			var material := bulb.material_override as StandardMaterial3D
			material.emission_enabled = true
			material.emission = Color("#ffc14a")
			material.emission_energy_multiplier = 1.4
			# ponytail: two dark leaves under the bulb; the bulb stays this size and color.
			for side in [-1.0, 1.0]:
				var leaf := BoxMesh.new()
				leaf.size = Vector3(0.16, 0.018, 0.07)
				var card := _paint(leaf, Color("#243628"))
				card.position = Vector3(side * 0.1, 0.4, 0.0)
				card.rotation = Vector3(0.2, 0.0, side * 0.8)
				add_child(card)
		_:
			_ball(Vector3(0, 0.2, 0), 0.12, Color("#7eac4c"))
	_rosette()

func _rosette() -> void:
	# ponytail: eight short blades; a wider fan if they still read as discs.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.05, 0.22, 0.012)
		var leaf := _paint(mesh, Color("#2c5a30"))
		leaf.position = Vector3(cos(angle) * 0.26, 0.1, sin(angle) * 0.26)
		leaf.rotation = Vector3(-0.65, -angle, 0.0)
		add_child(leaf)

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

func _peach() -> void:
	# ponytail: one warm fruit on a short stem; a leaf if the fruit still reads as a ball in the air.
	_stem(0.28, 0.04, Color("#6b4a32"))
	# ponytail: a brighter fruit clips to 255 under this sun.
	_ball(Vector3(0.02, 0.46, 0.02), 0.16, Color("#8a4e22"))

func _mosspear() -> void:
	# ponytail: one fruit on a short stem; a brighter pear clips under this sun.
	_stem(0.22, 0.035, Color("#3d4a28"))
	_ball(Vector3(0.0, 0.42, 0.0), 0.15, Color("#4e5c2e"), Vector3(0.82, 1.55, 0.82))
	# ponytail: one dark leaf beside the fruit; a second leaf if it still reads as a bare pear.
	var leaf := BoxMesh.new()
	leaf.size = Vector3(0.18, 0.02, 0.09)
	var card := _paint(leaf, Color("#2f4a28"))
	card.position = Vector3(0.14, 0.5, 0.02)
	card.rotation = Vector3(0.35, 0.4, 0.7)
	add_child(card)

func _reed() -> void:
	# ponytail: a seed head on each stick; a blade fan if the heads still read as dots.
	var stems: Array = [
		[0.7, 0.02, Color("#6d7a3a"), Vector3(-0.06, 0, 0)],
		[0.55, 0.018, Color("#8a9144"), Vector3(0.05, 0, 0.04)],
		[0.62, 0.016, Color("#5c6a32"), Vector3(0.0, 0, -0.05)],
	]
	for stem in stems:
		var height: float = stem[0]
		var at: Vector3 = stem[3]
		_stem(height, stem[1], stem[2], at)
		# ponytail: straw on a ripe head; the young brown if a brighter gold clips under this sun.
		var head := Color("#9a7040") if built_ripe else Color("#6a4a28")
		_ball(at + Vector3(0, height + 0.08, 0), 0.11, head, Vector3(0.85, 2.1, 0.85))

func _meadowbell() -> void:
	# ponytail: three bells and a leaf pad; a flower mesh if the beds get authored plants.
	# ponytail: cream petals clip to white under this sun; raise if the bells go dull.
	var petal := Color("#7a6a52")
	var heart := Color("#c4923a")
	_stem(0.46, 0.034, Color("#3f8f45"))
	_blossom(Vector3(0, 0.52, 0), petal, heart)
	_stem(0.38, 0.028, Color("#3a7a3c"), Vector3(0.36, 0, 0.1))
	_blossom(Vector3(0.36, 0.44, 0.1), Color("#6e5e48"), Color("#b08030"))
	_stem(0.34, 0.026, Color("#2f6a34"), Vector3(-0.34, 0, 0.14))
	_blossom(Vector3(-0.34, 0.4, 0.14), Color("#746656"), heart)
	_ball(Vector3(0, 0.05, 0), 0.16, Color("#2f6a32"), Vector3(1.8, 0.35, 1.8))

func _blossom(at: Vector3, petal: Color, heart: Color) -> void:
	_ball(at, 0.1, heart)
	for i in 5:
		var angle := TAU * float(i) / 5.0
		_ball(at + Vector3(cos(angle) * 0.13, 0.03, sin(angle) * 0.13), 0.07, petal)

func _paint(mesh: Mesh, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

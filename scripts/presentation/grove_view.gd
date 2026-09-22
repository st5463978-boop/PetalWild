extends Node3D

const Kit = preload("res://scripts/presentation/prop_kit.gd")
const JellyScript = preload("res://scripts/presentation/jelly_actor.gd")
const PersonScript = preload("res://scripts/presentation/person_actor.gd")

const CELL := 1.2

var sim_state: Dictionary = {}
var director = null
var software := false
var plots_root: Node3D
var actors_root: Node3D
var props_root: Node3D
var homes_root: Node3D
var ring: MeshInstance3D
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var rain: CPUParticles3D
var motes: CPUParticles3D
var stall: Node3D
var awning: Node3D
var bounds := {}
var prop_sig := ""
var people_sig := ""
var jellies := {}
var people := {}
var plot_nodes := {}
var built := false


func bind(game) -> void:
	director = game


func build(state: Dictionary) -> void:
	sim_state = state
	if built:
		sync(state)
		return
	built = true
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	software = adapter == "" or adapter.contains("llvmpipe") or adapter.contains("soft") or adapter.contains("swift")
	print("PetalWild renderer ", RenderingServer.get_video_adapter_name(), " software=", software)
	_environment()
	_ground(state)
	_dress(state)
	plots_root = Node3D.new()
	add_child(plots_root)
	props_root = Node3D.new()
	add_child(props_root)
	homes_root = Node3D.new()
	add_child(homes_root)
	actors_root = Node3D.new()
	add_child(actors_root)
	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	ring.mesh = torus
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color("F2E2A2")
	rmat.emission_enabled = true
	rmat.emission = Color("E7C56A")
	rmat.emission_energy_multiplier = 0.4
	ring.material_override = rmat
	ring.visible = false
	add_child(ring)
	_stall()
	_shed()
	sync(state)


func sync(state: Dictionary) -> void:
	sim_state = state
	_plots(state)
	_props(state)
	_actors(state)
	_atmosphere(state)
	if stall != null:
		var open := bool(state.get("stall_open", false))
		if awning != null:
			awning.position.y = 1.55 if open else 1.15
			awning.rotation.x = -0.15 if open else 0.55


func plot_world(x: int, y: int) -> Vector3:
	var width := int(sim_state.get("width", 16))
	var height := int(sim_state.get("height", 12))
	return Vector3((float(x) - float(width) * 0.5 + 0.5) * CELL, 0.0, (float(y) - float(height) * 0.5 + 0.5) * CELL)


func world_to_plot(point: Vector3) -> Vector2i:
	if sim_state.is_empty():
		return Vector2i(-1, -1)
	var width := int(sim_state["width"])
	var height := int(sim_state["height"])
	var origin := plot_world(0, 0) - Vector3(CELL, 0, CELL) * 0.5
	var x := int(floor((point.x - origin.x) / CELL))
	var y := int(floor((point.z - origin.z) / CELL))
	if x < 0 or y < 0 or x >= width or y >= height:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func hover(cell: Vector2i) -> void:
	if cell.x < 0:
		ring.visible = false
		return
	ring.visible = true
	var pos := plot_world(cell.x, cell.y)
	ring.position = Vector3(pos.x, 0.16, pos.z)


func anchor_for(person_id: String, tag: String) -> Vector3:
	var person: Dictionary = sim_state.get("people", {}).get(person_id, {})
	var pad := int(person.get("home_pad", 0))
	match tag:
		"stall":
			return _stall_point() + Vector3(0.4, 0, 0.2)
		"home":
			return _pad_point(pad)
		"pond":
			return Vector3(bounds.get("min_x", -8.0) - 3.2, 0, 0.4)
		_:
			return plot_world(8, 10)


func _environment() -> void:
	var world := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.008
	env.fog_aerial_perspective = 0.35
	env.fog_light_color = Color(0.95, 0.84, 0.68)
	if not software:
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_bloom = 0.12
	world.environment = env
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = not software
	sun.directional_shadow_max_distance = 42.0
	sun.light_angular_distance = 1.2
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-28, 140, 0)
	add_child(fill)
	rain = _particles(Color(0.75, 0.82, 0.9), 500 if not software else 160, Vector3(0, -10, 0))
	rain.position = Vector3(0, 8, 0)
	rain.visibility_aabb = AABB(Vector3(-20, -8, -16), Vector3(40, 16, 32))
	add_child(rain)
	motes = _particles(Color(1.0, 0.86, 0.45), 40, Vector3(0, 0.15, 0))
	motes.position = Vector3(0, 1.2, 0)
	add_child(motes)


func _particles(color: Color, amount: int, gravity: Vector3) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 2.4
	particles.explosiveness = 0.0
	particles.direction = Vector3(0, -1, 0)
	particles.spread = 18.0
	particles.gravity = gravity
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	particles.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particles.mesh.surface_set_material(0, mat)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(12, 0.4, 9)
	particles.emitting = false
	return particles


func _ground(state: Dictionary) -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(90, 90)
	plane.mesh = mesh
	var mat := StandardMaterial3D.new()
	var grass_tex := load("res://assets/third_party/polyhaven/leafy_grass/leafy_grass_diff_1k.jpg")
	if grass_tex != null:
		mat.albedo_texture = grass_tex
		mat.uv1_scale = Vector3(28, 28, 1)
	mat.albedo_color = Color(0.78, 0.86, 0.62)
	mat.roughness = 0.92
	plane.material_override = mat
	add_child(plane)
	_bounds(state)


func _bounds(state: Dictionary) -> void:
	var width := int(state["width"])
	var height := int(state["height"])
	var a := plot_world(0, 0)
	var b := plot_world(width - 1, height - 1)
	bounds = {
		"min_x": minf(a.x, b.x) - CELL * 0.5,
		"max_x": maxf(a.x, b.x) + CELL * 0.5,
		"min_z": minf(a.z, b.z) - CELL * 0.5,
		"max_z": maxf(a.z, b.z) + CELL * 0.5,
	}


func _dress(state: Dictionary) -> void:
	_bounds(state)
	var hedge_n := 46 if software else 64
	_hedge(hedge_n)
	_rooms()
	_bed_flowers()
	var tree_files := ["tree_oak.fbx", "tree_default.fbx", "tree_detailed.fbx", "tree_tall.fbx", "tree_fat.fbx"]
	var tree_n := 16 if software else 22
	for i in tree_n:
		var angle := float(i) / float(tree_n) * TAU + 0.2
		var radius := 16.5 + float(i % 3) * 1.4
		var point := Vector3(cos(angle) * radius, 0, sin(angle) * radius * 0.82)
		var tree := Kit.spawn(tree_files[i % tree_files.size()], randf_range(4.2, 6.4))
		if tree == null:
			continue
		tree.position = point
		tree.rotation.y = randf() * TAU
		add_child(tree)
	_scenic_water()
	var flower_files := ["flower_redA.fbx", "flower_yellowA.fbx", "flower_purpleA.fbx", "flower_redC.fbx", "flower_yellowC.fbx"]
	var flower_n := 84 if software else 140
	for i in flower_n:
		var edge := 0.15 + float(i % 7) * 0.35
		var side := i % 4
		var point := Vector3.ZERO
		match side:
			0:
				point = Vector3(lerpf(bounds.min_x, bounds.max_x, float(i % 17) / 16.0), 0, bounds.min_z + edge)
			1:
				point = Vector3(lerpf(bounds.min_x, bounds.max_x, float(i % 17) / 16.0), 0, bounds.max_z - edge)
			2:
				point = Vector3(bounds.min_x + edge, 0, lerpf(bounds.min_z, bounds.max_z, float(i % 13) / 12.0))
			_:
				point = Vector3(bounds.max_x - edge, 0, lerpf(bounds.min_z, bounds.max_z, float(i % 13) / 12.0))
		if absf(point.x) < 1.8 and point.z > bounds.max_z - 1.2:
			continue
		var flower := Kit.spawn(flower_files[i % flower_files.size()], randf_range(0.28, 0.48))
		if flower == null:
			continue
		flower.position = point
		flower.rotation.y = randf() * TAU
		add_child(flower)
	_tufts(state)
	for i in 4:
		var rock := Kit.spawn("stone_largeB.fbx" if i % 2 == 0 else "stone_largeA.fbx", randf_range(0.55, 0.9))
		if rock == null:
			continue
		rock.position = Vector3(bounds.min_x - 2.2 - float(i) * 0.4, 0, -1.5 + float(i) * 0.9)
		add_child(rock)


func _hedge(count: int) -> void:
	var min_x: float = bounds.min_x - 0.7
	var max_x: float = bounds.max_x + 0.7
	var min_z: float = bounds.min_z - 0.7
	var max_z: float = bounds.max_z + 0.7
	var perimeter := (max_x - min_x) * 2.0 + (max_z - min_z) * 2.0
	for i in count:
		var dist := perimeter * float(i) / float(count)
		var point := _perimeter_point(dist, min_x, max_x, min_z, max_z)
		if absf(point.x) < 1.7 and point.z > max_z - 0.4:
			continue
		var bush := Kit.spawn("plant_bushLarge.fbx", randf_range(1.25, 1.55))
		if bush == null:
			continue
		bush.position = point
		bush.rotation.y = randf() * TAU
		add_child(bush)


func _rooms() -> void:
	var min_x: float = bounds.min_x + 0.6
	var max_x: float = bounds.max_x - 0.6
	var min_z: float = bounds.min_z + 0.6
	var max_z: float = bounds.max_z - 0.6
	var mid_x: float = (min_x + max_x) * 0.5
	var mid_z: float = (min_z + max_z) * 0.5
	var crossing := Vector3(mid_x, 0, mid_z)
	_hedge_line(Vector3(mid_x, 0, min_z), Vector3(mid_x, 0, max_z), crossing, 1.8)
	_hedge_line(Vector3(min_x, 0, mid_z), Vector3(max_x, 0, mid_z), crossing, 1.8)


func _hedge_line(from: Vector3, to: Vector3, gap_at: Vector3, gap: float) -> void:
	var span: float = from.distance_to(to)
	var steps: int = maxi(int(span / 0.85), 2)
	for i in steps + 1:
		var point: Vector3 = from.lerp(to, float(i) / float(steps))
		if point.distance_to(gap_at) < gap:
			continue
		var bush = Kit.spawn("plant_bushLarge.fbx", randf_range(1.45, 1.85))
		if bush == null:
			continue
		bush.position = point
		bush.rotation.y = randf() * TAU
		add_child(bush)


func _bed_flowers() -> void:
	var min_x: float = bounds.min_x + 1.1
	var max_x: float = bounds.max_x - 1.1
	var min_z: float = bounds.min_z + 1.1
	var max_z: float = bounds.max_z - 1.1
	var mid_x: float = (min_x + max_x) * 0.5
	var mid_z: float = (min_z + max_z) * 0.5
	var beds: Array[Vector4] = [
		Vector4(min_x, mid_x - 0.8, min_z, mid_z - 0.8),
		Vector4(mid_x + 0.8, max_x, min_z, mid_z - 0.8),
		Vector4(min_x, mid_x - 0.8, mid_z + 0.8, max_z),
		Vector4(mid_x + 0.8, max_x, mid_z + 0.8, max_z),
	]
	var files := ["flower_redA.fbx", "flower_yellowA.fbx", "flower_purpleA.fbx", "flower_redC.fbx", "flower_yellowC.fbx"]
	var each := 5 if software else 9
	var n := 0
	for bed in beds:
		for i in each:
			var point := Vector3(randf_range(bed.x, bed.y), 0, randf_range(bed.z, bed.w))
			var flower = Kit.spawn(files[n % files.size()], randf_range(0.32, 0.55))
			n += 1
			if flower == null:
				continue
			flower.position = point
			flower.rotation.y = randf() * TAU
			add_child(flower)


func _perimeter_point(dist: float, min_x: float, max_x: float, min_z: float, max_z: float) -> Vector3:
	var width := max_x - min_x
	var depth := max_z - min_z
	if dist < width:
		return Vector3(min_x + dist, 0, min_z)
	dist -= width
	if dist < depth:
		return Vector3(max_x, 0, min_z + dist)
	dist -= depth
	if dist < width:
		return Vector3(max_x - dist, 0, max_z)
	dist -= width
	return Vector3(min_x, 0, max_z - dist)


func _scenic_water() -> void:
	var water := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(7.5, 5.2)
	water.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	water.material_override = mat
	water.position = Vector3(bounds.min_x - 4.4, 0.05, -0.2)
	add_child(water)
	var bridge := Kit.spawn("bridge_wood.fbx", 0.7)
	if bridge != null:
		bridge.position = water.position + Vector3(0, 0.05, 0)
		bridge.rotation.y = PI * 0.5
		add_child(bridge)
	var reeds := 8 if software else 14
	for i in reeds:
		var reed := Kit.spawn("grass_leafsLarge.fbx", randf_range(0.7, 1.1))
		if reed == null:
			continue
		var side := -1.0 if i % 2 == 0 else 1.0
		reed.position = water.position + Vector3(side * randf_range(2.2, 3.4), 0, randf_range(-2.0, 2.0))
		add_child(reed)


func _tufts(state: Dictionary) -> void:
	var source := Kit.mesh("grass.fbx")
	if source == null:
		return
	var count := 350 if software else 900
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = source
	multi.instance_count = count
	var base_h := maxf(source.get_aabb().size.y, 0.001)
	var placed := 0
	var width := int(state["width"])
	var height := int(state["height"])
	for y in height:
		for x in width:
			if placed >= count:
				break
			var plot: Dictionary = state["plots"][y * width + x]
			if String(plot.get("g", "")) != "grass":
				continue
			for _n in 2:
				if placed >= count:
					break
				var jitter := Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
				var point := plot_world(x, y) + jitter
				var scale := randf_range(0.28, 0.48) / base_h
				var basis := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(scale, scale, scale))
				multi.set_instance_transform(placed, Transform3D(basis, point))
				placed += 1
	var guard := 0
	while placed < count and guard < count * 3:
		guard += 1
		var point := Vector3(randf_range(-24, 24), 0, randf_range(-18, 18))
		var cell := world_to_plot(point)
		if cell.x >= 0:
			continue
		var scale := randf_range(0.35, 0.6) / base_h
		var basis := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(scale, scale, scale))
		multi.set_instance_transform(placed, Transform3D(basis, point))
		placed += 1
	multi.instance_count = placed
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	add_child(instance)


func _plots(state: Dictionary) -> void:
	var width := int(state["width"])
	var height := int(state["height"])
	for y in height:
		for x in width:
			var key := "%d,%d" % [x, y]
			var plot: Dictionary = state["plots"][y * width + x]
			var stage := _stage(float(plot.get("growth", 0.0)), String(plot.get("plant", "")))
			var sig := "%s|%s|%d" % [plot.get("g", ""), plot.get("plant", ""), stage]
			if plot_nodes.has(key) and String(plot_nodes[key].get_meta("sig")) == sig:
				continue
			if plot_nodes.has(key):
				plot_nodes[key].queue_free()
			var node := _make_plot(plot, stage)
			node.position = plot_world(x, y)
			node.set_meta("sig", sig)
			plots_root.add_child(node)
			plot_nodes[key] = node


func _stage(growth: float, plant: String) -> int:
	if plant == "":
		return 0
	if growth < 0.25:
		return 1
	if growth < 0.55:
		return 2
	if growth < 0.85:
		return 3
	return 4


func _make_plot(plot: Dictionary, stage: int) -> Node3D:
	var node := Node3D.new()
	var ground := String(plot.get("g", "grass"))
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CELL * 0.94, 0.08, CELL * 0.94)
	box.mesh = mesh
	box.position.y = 0.04
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	match ground:
		"soil":
			mat.albedo_color = Color("6B442C")
			var dirt := load("res://assets/third_party/polyhaven/flower_scattered_dirt/flower_scattered_dirt_diff_1k.jpg")
			if dirt != null:
				mat.albedo_texture = dirt
				mat.uv1_scale = Vector3(0.35, 0.35, 1)
		"path":
			mat.albedo_color = Color("C2B39A")
		"pond":
			mat.albedo_color = Color("1E6A66")
		_:
			mat.albedo_color = Color("7FA85A")
	box.material_override = mat
	node.add_child(box)
	if ground == "pond":
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(CELL * 0.86, CELL * 0.86)
		water.mesh = plane
		water.position.y = 0.09
		var wmat := ShaderMaterial.new()
		wmat.shader = load("res://shaders/water.gdshader")
		water.material_override = wmat
		node.add_child(water)
	var plant := String(plot.get("plant", ""))
	if plant != "" and stage > 0:
		node.add_child(_plant_visual(plant, stage))
	return node


func _plant_visual(plant: String, stage: int) -> Node3D:
	var root := Node3D.new()
	var colors: Dictionary = PetalContent.plants.get(plant, {}).get("colors", {})
	var stem_c := Color(String(colors.get("stem", "#3E7A32")))
	var leaf_c := Color(String(colors.get("leaf", "#7CB342")))
	var bloom_c := Color(String(colors.get("bloom", "#F2C14E")))
	var height := 0.12 + float(stage) * 0.12
	var stem := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.02
	capsule.height = height
	stem.mesh = capsule
	stem.position.y = 0.08 + height * 0.5
	var smat := StandardMaterial3D.new()
	smat.albedo_color = stem_c
	stem.material_override = smat
	root.add_child(stem)
	if stage >= 2:
		for side in [-1.0, 1.0]:
			var leaf := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.16, 0.1)
			leaf.mesh = quad
			leaf.position = Vector3(side * 0.08, 0.16 + float(stage) * 0.04, 0)
			leaf.rotation = Vector3(-0.4, 0, side * 0.6)
			var lmat := StandardMaterial3D.new()
			lmat.albedo_color = leaf_c
			lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			leaf.material_override = lmat
			root.add_child(leaf)
	if stage >= 4:
		if plant == "petal_corn":
			var ear := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.08, 0.22, 0.08)
			ear.mesh = box
			ear.position = Vector3(0.06, height, 0)
			var emat := StandardMaterial3D.new()
			emat.albedo_color = bloom_c
			ear.material_override = emat
			root.add_child(ear)
		else:
			for i in 6:
				var petal := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = 0.045
				sphere.height = 0.08
				petal.mesh = sphere
				var a := float(i) / 6.0 * TAU
				petal.position = Vector3(cos(a) * 0.07, 0.1 + height, sin(a) * 0.07)
				var pmat := StandardMaterial3D.new()
				pmat.albedo_color = bloom_c
				if plant == "nightbloom":
					pmat.emission_enabled = true
					pmat.emission = bloom_c
					pmat.emission_energy_multiplier = 0.6
				petal.material_override = pmat
				root.add_child(petal)
	return root


func _props(state: Dictionary) -> void:
	var sig := JSON.stringify(state.get("props", []))
	if sig == prop_sig:
		return
	prop_sig = sig
	for child in props_root.get_children():
		child.queue_free()
	for prop in state.get("props", []):
		var node := _prop_visual(String(prop.get("id", "")))
		if node == null:
			continue
		var pos := plot_world(int(prop.get("x", 0)), int(prop.get("y", 0)))
		node.position = pos
		props_root.add_child(node)


func _prop_visual(id: String) -> Node3D:
	var root := Node3D.new()
	if id == "bench":
		var seat := _box(Vector3(0.7, 0.06, 0.28), Color("8A6244"), Vector3(0, 0.32, 0))
		root.add_child(seat)
		root.add_child(_box(Vector3(0.08, 0.32, 0.08), Color("6A4A32"), Vector3(-0.28, 0.16, 0.1)))
		root.add_child(_box(Vector3(0.08, 0.32, 0.08), Color("6A4A32"), Vector3(0.28, 0.16, 0.1)))
		return root
	var lamp := _box(Vector3(0.06, 0.7, 0.06), Color("3E342C"), Vector3(0, 0.35, 0))
	root.add_child(lamp)
	var glow_color := Color("F6D27A") if id != "lantern" else Color("C9B6FF")
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	bulb.mesh = sphere
	bulb.position.y = 0.74
	var mat := StandardMaterial3D.new()
	mat.albedo_color = glow_color
	mat.emission_enabled = true
	mat.emission = glow_color
	mat.emission_energy_multiplier = 1.4
	bulb.material_override = mat
	root.add_child(bulb)
	if not software:
		var light := OmniLight3D.new()
		light.light_color = glow_color
		light.omni_range = 3.2
		light.light_energy = 0.8
		light.position.y = 0.74
		light.shadow_enabled = false
		root.add_child(light)
	return root


func _stall() -> void:
	stall = Node3D.new()
	stall.position = _stall_point()
	add_child(stall)
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("kind", "stall")
	area.set_meta("id", "petal_stall")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.8, 1.4)
	shape.shape = box
	shape.position.y = 0.9
	area.add_child(shape)
	stall.add_child(area)
	for x in [-0.8, 0.8]:
		stall.add_child(_box(Vector3(0.08, 1.5, 0.08), Color("6B4A32"), Vector3(x, 0.75, 0.45)))
		stall.add_child(_box(Vector3(0.08, 1.5, 0.08), Color("6B4A32"), Vector3(x, 0.75, -0.45)))
	stall.add_child(_box(Vector3(1.9, 0.12, 0.7), Color("A67C52"), Vector3(0, 0.78, 0.15)))
	stall.add_child(_box(Vector3(0.28, 0.22, 0.28), Color("8A5A32"), Vector3(-0.45, 0.92, 0.12)))
	stall.add_child(_box(Vector3(0.22, 0.16, 0.22), Color("C4A46A"), Vector3(0.35, 0.88, 0.18)))
	awning = Node3D.new()
	awning.position = Vector3(0, 1.55, 0)
	stall.add_child(awning)
	var left := _striped_roof(Vector3(-0.58, 0.16, 0), 0.28)
	var right := _striped_roof(Vector3(0.58, 0.16, 0), -0.28)
	awning.add_child(left)
	awning.add_child(right)
	var sign := Label3D.new()
	sign.text = "Petal Stall"
	sign.font_size = 72
	sign.pixel_size = 0.004
	sign.modulate = Color("3A2430")
	sign.outline_size = 12
	sign.outline_modulate = Color("FFF6E8")
	sign.position = Vector3(0, 1.28, -0.62)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	stall.add_child(sign)
	var gate := Label3D.new()
	gate.text = "Garden Grove"
	gate.font_size = 64
	gate.pixel_size = 0.005
	gate.modulate = Color("243428")
	gate.outline_modulate = Color("F6F0DE")
	gate.outline_size = 10
	gate.position = Vector3(0, 1.8, bounds.max_z + 0.2)
	gate.rotation.y = PI
	add_child(gate)


func _striped_roof(at: Vector3, roll: float) -> MeshInstance3D:
	var panel := _box(Vector3(1.2, 0.05, 1.25), Color("F4EFE4"), at)
	panel.rotation.z = roll
	var mat := panel.material_override as StandardMaterial3D
	mat.albedo_texture = _stripes()
	return panel


func _stall_point() -> Vector3:
	return Vector3(0, 0, float(bounds.get("max_z", 7.0)) + 2.1)


func _shed() -> void:
	var shed := Node3D.new()
	shed.position = Vector3(float(bounds.get("min_x", -8.0)) - 1.2, 0, float(bounds.get("min_z", -6.0)) + 1.4)
	add_child(shed)
	shed.add_child(_box(Vector3(1.8, 1.5, 1.5), Color("F7F1E4"), Vector3(0, 0.75, 0)))
	shed.add_child(_box(Vector3(2.1, 0.12, 1.8), Color("A33B32"), Vector3(0, 1.58, 0)))
	shed.add_child(_box(Vector3(0.42, 0.7, 0.06), Color("6E8CA8"), Vector3(0, 0.7, -0.76)))
	var door := _box(Vector3(0.4, 0.9, 0.06), Color("C9856A"), Vector3(0.45, 0.45, -0.76))
	shed.add_child(door)


func _pad_point(index: int) -> Vector3:
	var base := _stall_point()
	return base + Vector3(2.4 + float(index) * 1.8, 0, 0.3)


func _actors(state: Dictionary) -> void:
	var sig := ""
	for id in state.get("people", {}).keys():
		if bool(state["people"][id].get("present", false)):
			sig += id
	if sig != people_sig:
		people_sig = sig
		for child in homes_root.get_children():
			child.queue_free()
		for id in state["people"].keys():
			var present := bool(state["people"][id].get("present", false))
			if present and not people.has(id):
				var actor = PersonScript.new()
				actor.setup(id, PetalContent.residents[id], director)
				actors_root.add_child(actor)
				var pad := int(state["people"][id].get("home_pad", 0))
				var spot: Vector3 = _stall_point() + Vector3(0.55, 0, 0.35) if id == "cara" else _pad_point(pad)
				actor.global_position = spot
				people[id] = actor
				var home := _shed_small()
				home.position = _pad_point(pad) + Vector3(0, 0, 0.8)
				homes_root.add_child(home)
			elif not present and people.has(id):
				people[id].queue_free()
				people.erase(id)
	var shown := 0
	var limit := 4 if software else 8
	for id in PetalContent.species.keys():
		var rec: Dictionary = state["species"][id]
		var want := bool(rec.get("present", false))
		if want and PetalRules.state_index(String(rec.get("state", "unknown"))) < PetalRules.state_index("resident") and shown >= limit:
			want = false
		if want:
			shown += 1
		if want and not jellies.has(id):
			var actor = JellyScript.new()
			actors_root.add_child(actor)
			actor.setup(id, PetalContent.species[id], director)
			if actor.global_position.length() < 0.05:
				var cell: Vector2i = director.random_walkable() if director != null else Vector2i(6, 5)
				var spot: Vector3 = plot_world(cell.x, cell.y)
				spot.y = 0.22
				actor.global_position = spot
				actor.home = spot
			jellies[id] = actor
		elif not want and jellies.has(id):
			jellies[id].queue_free()
			jellies.erase(id)
		elif want and jellies.has(id):
			jellies[id].set_mood(String(rec.get("mood", "calm")))


func _shed_small() -> Node3D:
	var home := Node3D.new()
	home.add_child(_box(Vector3(1.1, 0.9, 0.9), Color("F4EFE4"), Vector3(0, 0.45, 0)))
	home.add_child(_box(Vector3(1.3, 0.1, 1.1), Color("B55248"), Vector3(0, 0.95, 0)))
	return home


func _atmosphere(state: Dictionary) -> void:
	var minute := int(state.get("minute", 480))
	var phase := PetalRules.phase_for(minute)
	var weather := String(state.get("weather", "clear"))
	var hour := float(minute) / 60.0
	var elev := sin((hour - 6.0) / 12.0 * PI)
	sun.rotation_degrees = Vector3(lerpf(18, -55, clampf(elev, 0, 1)) if phase != "night" else 20, -35, 0)
	var warm := Color(1.0, 0.82, 0.58)
	var noon := Color(1.0, 0.96, 0.88)
	var night := Color(0.45, 0.55, 0.85)
	var light := noon
	var energy := 1.15
	if phase == "dawn" or phase == "dusk" or weather == "golden":
		light = warm
		energy = 1.25
	elif phase == "night":
		light = night
		energy = 0.18
	if weather == "rain":
		energy *= 0.62
		light = light.lerp(Color(0.62, 0.68, 0.74), 0.45)
	elif weather == "mist":
		energy *= 0.8
	sun.light_color = light
	sun.light_energy = energy
	fill.light_color = light.lerp(Color(0.7, 0.8, 0.75), 0.5)
	sky_mat.sky_top_color = light.lerp(Color(0.35, 0.55, 0.82), 0.55 if phase != "night" else 0.2)
	sky_mat.sky_horizon_color = light
	sky_mat.ground_horizon_color = Color(0.45, 0.52, 0.32)
	sky_mat.ground_bottom_color = Color(0.18, 0.24, 0.14)
	env.fog_light_color = light
	env.fog_density = 0.02 if weather == "mist" else 0.012 if weather == "rain" else 0.008
	env.ambient_light_energy = 0.35 if phase == "night" else 0.8
	env.tonemap_exposure = 0.72 if phase == "night" else 1.05
	if weather == "golden" or phase == "dusk":
		sun.light_color = Color(1.0, 0.58, 0.28)
		sun.light_energy = 1.65
		sun.rotation_degrees = Vector3(-8, -52, 0)
		fill.light_color = Color(0.55, 0.42, 0.62)
		fill.light_energy = 0.22
		sky_mat.sky_top_color = Color(0.32, 0.42, 0.72)
		sky_mat.sky_horizon_color = Color(1.0, 0.62, 0.32)
		sky_mat.ground_horizon_color = Color(0.62, 0.38, 0.22)
		env.fog_light_color = Color(1.0, 0.72, 0.42)
		env.fog_density = 0.016
		env.ambient_light_energy = 0.42
		env.tonemap_exposure = 1.08
	rain.emitting = weather == "rain"
	motes.emitting = phase == "night" or weather == "golden"
	PetalAudio.set_weather(weather, phase)


func _stripes() -> Texture2D:
	var image := Image.create(64, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 64:
			var band := int(x / 8) % 2
			image.set_pixel(x, y, Color("F7F1E6") if band == 0 else Color("2C5C86"))
	return ImageTexture.create_from_image(image)


func _box(size: Vector3, color: Color, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	node.material_override = mat
	return node

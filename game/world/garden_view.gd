extends Node3D

const MeshKit = preload("res://game/world/mesh_kit.gd")
const TerrainField = preload("res://game/world/terrain_field.gd")
const Cc0Dressing = preload("res://game/world/cc0_dressing.gd")
const FoliageShader = preload("res://game/shaders/foliage.gdshader")
const WaterShader = preload("res://game/shaders/water.gdshader")

var field = TerrainField.new()
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var environment: Environment
var highlight: MeshInstance3D
var rain: CPUParticles3D
var fireflies: CPUParticles3D
var soil_mesh: MultiMeshInstance3D
var water_mesh: MultiMeshInstance3D
var plant_meshes: Dictionary = {}
var foliage_mat: ShaderMaterial
var lantern: OmniLight3D
var dressing


func build() -> void:
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = FoliageShader
	dressing = Cc0Dressing.new()
	dressing.prepare(field)
	_environment()
	_terrain()
	_water()
	_hedges_and_trees()
	_flowers_and_grass()
	_rocks()
	_beds_and_fence()
	_shop()
	_bridge_and_benches()
	_gate()
	_plot_instances()
	_particles()


func sync_plots(plots: Array, plants: Dictionary) -> void:
	var soils: Array[Transform3D] = []
	var soil_colors: Array[Color] = []
	var waters: Array[Transform3D] = []
	var grouped: Dictionary = {}
	for plant_id in plants.keys():
		grouped[str(plant_id)] = []
	for plot in plots:
		var center := field.cell_center(int(plot.x), int(plot.z))
		var soil := str(plot.soil)
		if soil == "water":
			waters.append(Transform3D(Basis.IDENTITY, center + Vector3(0, -0.02, 0)))
			continue
		if soil == "loam" or soil == "compost":
			soils.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.02, 1, 1.02)), center + Vector3(0, -0.02, 0)))
			soil_colors.append(Color(0.34, 0.2, 0.1) if soil == "loam" else Color(0.28, 0.22, 0.12))
		var plant_id := str(plot.plant_id)
		if plant_id == "":
			continue
		var growth := clampf(float(plot.growth), 0.08, 1.0)
		var basis := Basis.IDENTITY.scaled(Vector3(growth, maxf(0.15, growth), growth))
		grouped[plant_id].append(Transform3D(basis, center))
	_write_transforms(soil_mesh, soils, soil_colors)
	_write_transforms(water_mesh, waters, [])
	for plant_id in plant_meshes.keys():
		_write_transforms(plant_meshes[plant_id], grouped.get(plant_id, []), [])


func set_highlight(cell: Vector2i, valid: bool) -> void:
	highlight.visible = valid
	if not valid:
		return
	var center := field.cell_center(cell.x, cell.y)
	highlight.position = center + Vector3(0, 0.08, 0)


func apply_atmosphere(hour: float, weather: String, season: String) -> void:
	var night := 0.0
	if hour >= 19.0:
		night = smoothstep(19.0, 21.0, hour)
	elif hour < 6.0:
		night = smoothstep(6.0, 4.2, hour)
	var dusk := smoothstep(16.0, 18.6, hour) * (1.0 - night)
	var dawn := smoothstep(5.0, 7.2, hour) * (1.0 - smoothstep(8.5, 10.0, hour)) if hour < 12.0 else 0.0
	var warm := clampf(dusk * 0.4 + dawn * 0.32, 0.0, 0.48)
	var sun_color := Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.78, 0.52), warm)
	if season == "autumn":
		sun_color = sun_color.lerp(Color(1.0, 0.62, 0.28), 0.35)
	elif season == "winter":
		sun_color = sun_color.lerp(Color(0.78, 0.84, 0.92), 0.35)
	sun.light_color = sun_color
	sun.light_energy = lerpf(1.02, 0.16, night)
	if weather == "rain":
		sun.light_energy *= 0.5
	elif weather == "mist":
		sun.light_energy *= 0.72
	sun.rotation_degrees = Vector3(lerpf(-52.0, -16.0, warm * 0.7 + night), -36.0, 0.0)
	fill.light_energy = lerpf(0.42, 0.08, night)
	var horizon := Color(0.78, 0.86, 0.78).lerp(Color(0.98, 0.62, 0.38), warm)
	horizon = horizon.lerp(Color(0.1, 0.12, 0.22), night)
	sky_mat.sky_top_color = Color(0.32, 0.56, 0.82).lerp(Color(0.08, 0.1, 0.2), night)
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon.lerp(Color(0.3, 0.36, 0.22), 0.4)
	environment.ambient_light_energy = lerpf(0.82, 0.2, night)
	environment.fog_density = 0.0026
	environment.fog_light_color = horizon
	if weather == "mist":
		environment.fog_density = 0.02
	elif weather == "rain":
		environment.fog_density = 0.012
		environment.fog_light_color = Color(0.62, 0.66, 0.64)
	rain.emitting = weather == "rain"
	fireflies.emitting = night > 0.45 and weather != "rain"
	lantern.light_energy = lerpf(0.4, 1.6, night)
	if foliage_mat:
		var leaf_shift := 0.0
		if season == "autumn":
			leaf_shift = 0.45
		elif season == "winter":
			leaf_shift = -0.15
		foliage_mat.set_shader_parameter("leaf_a", Color(0.13, 0.36, 0.13).lerp(Color(0.45, 0.28, 0.08), maxf(leaf_shift, 0.0)))
		foliage_mat.set_shader_parameter("leaf_b", Color(0.48, 0.68, 0.24).lerp(Color(0.72, 0.48, 0.16), maxf(leaf_shift, 0.0)))


func _environment() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 46.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_color = Color(0.68, 0.82, 0.62)
	add_child(fill)
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.56, 0.82)
	sky_mat.sky_horizon_color = Color(0.95, 0.78, 0.58)
	sky_mat.ground_bottom_color = Color(0.12, 0.16, 0.1)
	sky_mat.ground_horizon_color = Color(0.55, 0.58, 0.4)
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.82
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.0026
	environment.fog_aerial_perspective = 0.35
	var method := RenderingServer.get_current_rendering_method()
	if method != "gl_compatibility":
		environment.glow_enabled = true
		environment.glow_intensity = 0.35
		environment.glow_bloom = 0.12
	world.environment = environment
	add_child(world)


func _terrain() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	var step := TerrainField.SIZE / float(n)
	var origin := -TerrainField.SIZE * 0.5
	for z in n + 1:
		for x in n + 1:
			var wx := origin + float(x) * step
			var wz := origin + float(z) * step
			var h := field.height(wx, wz)
			tool.set_color(field.tint(wx, wz, h))
			tool.add_vertex(Vector3(wx, h, wz))
	for z in n:
		for x in n:
			var i := z * (n + 1) + x
			tool.add_index(i)
			tool.add_index(i + n + 1)
			tool.add_index(i + 1)
			tool.add_index(i + 1)
			tool.add_index(i + n + 1)
			tool.add_index(i + n + 2)
	tool.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = tool.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mesh_instance.material_override = mat
	add_child(mesh_instance)


func _water() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(5.4, -0.08, -7.2)
	var rings := 10
	var segs := 18
	for y in rings + 1:
		for x in segs + 1:
			var u := float(x) / float(segs)
			var v := float(y) / float(rings)
			var angle := u * TAU
			var radius := v * 6.2
			var px := cos(angle) * radius * 1.25
			var pz := sin(angle) * radius
			tool.add_vertex(center + Vector3(px, 0, pz))
	for y in rings:
		for x in segs:
			var i := y * (segs + 1) + x
			tool.add_index(i)
			tool.add_index(i + 1)
			tool.add_index(i + segs + 1)
			tool.add_index(i + 1)
			tool.add_index(i + segs + 2)
			tool.add_index(i + segs + 1)
	tool.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = tool.commit()
	var mat := ShaderMaterial.new()
	mat.shader = WaterShader
	mesh_instance.material_override = mat
	add_child(mesh_instance)


func _hedges_and_trees() -> void:
	var block := BoxMesh.new()
	block.size = Vector3(1.85, 2.25, 1.15)
	var hedges := _multi(block, foliage_mat)
	var center := Vector3(1.0, 0, 2.0)
	var a := 20.2
	var b := 16.0
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in 78:
		var t := float(i) / 78.0 * TAU
		if absf(angle_difference(t, 0.15)) < 0.2:
			continue
		var pos := Vector3(cos(t) * a, 0, sin(t) * b) + center
		pos.y = field.height(pos.x, pos.z) + 1.12
		var tangent := atan2(cos(t) * b, -sin(t) * a)
		var h_scale := 0.9 + 0.18 * absf(sin(t * 4.0))
		var basis := Basis(Vector3.UP, tangent).scaled(Vector3(1.05, h_scale, 0.95))
		transforms.append(Transform3D(basis, pos))
		colors.append(Color(0.78, 0.98, 0.72).lerp(Color(0.95, 1.0, 0.78), absf(sin(t * 3.0))))
	_hedge_run(transforms, colors, Vector3(-12.2, 0, -0.55), Vector3(2.6, 0, -0.55), 9)
	_hedge_run(transforms, colors, Vector3(9.6, 0, -1.4), Vector3(9.6, 0, 5.2), 6)
	_write_transforms(hedges, transforms, colors)
	var canopy_mesh := MeshKit.canopy()
	var trunks := _multi(MeshKit.trunk(), _std(Color(0.34, 0.22, 0.13), 0.9))
	var canopies := _multi(canopy_mesh, foliage_mat)
	var trunk_xf: Array[Transform3D] = []
	var canopy_xf: Array[Transform3D] = []
	var canopy_colors: Array[Color] = []
	for i in 26:
		var t := float(i) / 26.0 * TAU + 0.3
		var pos := Vector3(cos(t) * (a + 4.2), 0, sin(t) * (b + 3.4)) + center
		pos.y = field.height(pos.x, pos.z)
		var scale := 0.85 + 0.4 * absf(sin(t * 3.0))
		trunk_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(scale, scale, scale)), pos))
		var crown := pos + Vector3(0, 2.35 * scale, 0)
		canopy_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale * 1.45), crown))
		canopy_colors.append(Color(0.8, 1.0, 0.72).lerp(Color(0.95, 1.0, 0.8), absf(cos(t * 2.0))))
		var side := Vector3(cos(t * 2.0), 0.15, sin(t * 2.0)) * 0.7 * scale
		canopy_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale * 1.05), crown + side))
		canopy_colors.append(Color(0.7, 0.92, 0.62))
		canopy_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale * 0.85), crown - side + Vector3(0, 0.35, 0)))
		canopy_colors.append(Color(0.88, 0.98, 0.7))
	var inner := [
		Vector3(-13.5, 0, -3.5), Vector3(-15.0, 0, 7.0), Vector3(9.5, 0, -1.5),
		Vector3(-6.0, 0, -6.5), Vector3(8.0, 0, 9.5), Vector3(-11.0, 0, 12.5),
		Vector3(-12.4, 0, 3.2), Vector3(11.2, 0, 7.4),
	]
	for pos in inner:
		var placed: Vector3 = pos
		placed.y = field.height(placed.x, placed.z)
		trunk_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.1, 1.25, 1.1)), placed))
		var inner_crown := placed + Vector3(0, 2.7, 0)
		canopy_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.7, 1.35, 1.7)), inner_crown))
		canopy_colors.append(Color(0.78, 0.98, 0.7))
		canopy_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.15, 1.05, 1.15)), inner_crown + Vector3(0.7, 0.2, 0.2)))
		canopy_colors.append(Color(0.9, 1.0, 0.78))
	_write_transforms(trunks, trunk_xf, [])
	_write_transforms(canopies, canopy_xf, canopy_colors)


func _flowers_and_grass() -> void:
	dressing.scatter(self)
	var tufts := _multi(MeshKit.grass_tuft(), _std(Color(0.22, 0.48, 0.16), 0.9))
	var grass_xf: Array[Transform3D] = []
	for i in 180:
		var pos := _scatter(i + 90, 18.5)
		if pos == Vector3.INF:
			continue
		if field.path_distance(pos.x, pos.z) < 0.75:
			continue
		if Vector2(pos.x - 5.4, pos.z + 7.2).length() < 4.6:
			continue
		pos.y = field.height(pos.x, pos.z)
		var scale := 0.42 + _unit(i * 5) * 0.35
		grass_xf.append(Transform3D(Basis(Vector3.UP, _unit(i) * TAU).scaled(Vector3(scale, scale * 0.7, scale)), pos))
	_write_transforms(tufts, grass_xf, [])


func _rocks() -> void:
	var mesh := MeshKit.rock()
	for i in 14:
		var angle := float(i) / 14.0 * TAU
		var pos := Vector3(5.4 + cos(angle) * 5.4, 0, -7.2 + sin(angle) * 4.4)
		pos.y = field.height(pos.x, pos.z) + 0.12
		_solid(mesh, pos, Vector3(0.5 + _unit(i) * 0.6, 0.35, 0.5), Color(0.45, 0.42, 0.38), 0.85)


func _beds_and_fence() -> void:
	var min_x := TerrainField.PLOT_ORIGIN_X - 0.2
	var max_x := TerrainField.PLOT_ORIGIN_X + float(TerrainField.PLOT_W) * TerrainField.CELL + 0.2
	var min_z := TerrainField.PLOT_ORIGIN_Z - 0.2
	var max_z := TerrainField.PLOT_ORIGIN_Z + float(TerrainField.PLOT_D) * TerrainField.CELL + 0.2
	_board(Vector3((min_x + max_x) * 0.5, 0.16, min_z), Vector3(max_x - min_x, 0.12, 0.12))
	_board(Vector3((min_x + max_x) * 0.5, 0.16, max_z), Vector3(max_x - min_x, 0.12, 0.12))
	_board(Vector3(min_x, 0.16, (min_z + max_z) * 0.5), Vector3(0.12, 0.12, max_z - min_z))
	_board(Vector3(max_x, 0.16, (min_z + max_z) * 0.5), Vector3(0.12, 0.12, max_z - min_z))
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 0.55, 0.12)
	var posts := _multi(post, _std(Color(0.4, 0.26, 0.14), 0.8))
	var transforms: Array[Transform3D] = []
	var count_x := 16
	var count_z := 12
	for i in count_x:
		var x := lerpf(min_x, max_x, float(i) / float(count_x - 1))
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.32, min_z)))
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.32, max_z)))
	for i in count_z:
		var z := lerpf(min_z, max_z, float(i) / float(count_z - 1))
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(min_x, 0.32, z)))
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(max_x, 0.32, z)))
	_write_transforms(posts, transforms, [])


func _shop() -> void:
	var origin := Vector3(13.4, 0.08, 1.5)
	var stones := [
		Color(0.58, 0.52, 0.45), Color(0.7, 0.64, 0.55), Color(0.48, 0.44, 0.39), Color(0.76, 0.69, 0.58),
	]
	for ix in 6:
		for iz in 5:
			var px := -2.15 + float(ix) * 0.86
			var pz := -1.55 + float(iz) * 0.78
			var stone: Color = stones[(ix * 3 + iz) % stones.size()]
			_box(origin + Vector3(px, -0.015, pz), Vector3(0.76, 0.055, 0.68), stone, 0.86)
	_box(origin + Vector3(0, 0.78, -1.42), Vector3(3.5, 1.5, 0.16), Color(0.9, 0.82, 0.66), 0.72)
	_box(origin + Vector3(0, 1.52, -1.42), Vector3(3.7, 0.12, 0.22), Color(0.34, 0.2, 0.11), 0.62)
	_box(origin + Vector3(-1.72, 0.78, -1.42), Vector3(0.12, 1.55, 0.2), Color(0.34, 0.2, 0.11), 0.62)
	_box(origin + Vector3(1.72, 0.78, -1.42), Vector3(0.12, 1.55, 0.2), Color(0.34, 0.2, 0.11), 0.62)
	_box(origin + Vector3(0, 0.58, 0.15), Vector3(2.7, 0.1, 0.95), Color(0.46, 0.28, 0.15), 0.58)
	_box(origin + Vector3(0, 0.32, -0.22), Vector3(2.7, 0.5, 0.12), Color(0.4, 0.24, 0.13), 0.66)
	for i in 7:
		var stripe := Color(0.16, 0.36, 0.7) if i % 2 == 0 else Color(0.96, 0.93, 0.84)
		var along := -1.5 + float(i) * 0.5
		var xf := Transform3D(Basis(Vector3.RIGHT, -0.2), origin + Vector3(along, 1.78, 0.22))
		_box_xf(xf, Vector3(0.48, 0.045, 1.85), stripe, 0.48)
		_box(origin + Vector3(along, 1.48, 1.05), Vector3(0.46, 0.22, 0.035), stripe, 0.5)
	_box(origin + Vector3(-1.75, 0.95, 0.15), Vector3(0.1, 1.7, 0.1), Color(0.24, 0.15, 0.09), 0.58)
	_box(origin + Vector3(1.75, 0.95, 0.15), Vector3(0.1, 1.7, 0.1), Color(0.24, 0.15, 0.09), 0.58)
	_box(origin + Vector3(0, 1.95, -1.28), Vector3(1.7, 0.42, 0.08), Color(0.4, 0.24, 0.12), 0.6)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.26
	barrel.bottom_radius = 0.28
	barrel.height = 0.46
	_solid(barrel, origin + Vector3(-1.95, 0.28, -0.35), Vector3.ONE, Color(0.45, 0.28, 0.16), 0.7)
	var sign := Label3D.new()
	sign.text = "Petal Stall"
	sign.font_size = 48
	sign.modulate = Color(0.98, 0.94, 0.84)
	sign.outline_size = 8
	sign.outline_modulate = Color(0.22, 0.12, 0.08)
	sign.position = origin + Vector3(0, 1.96, -1.18)
	add_child(sign)
	lantern = OmniLight3D.new()
	lantern.position = origin + Vector3(0, 1.7, 0.55)
	lantern.light_color = Color(1.0, 0.72, 0.4)
	lantern.omni_range = 7.5
	lantern.light_energy = 0.7
	add_child(lantern)
	var ground_y := field.height(origin.x, origin.z)
	dressing.place_prop(self, "Sun_Umbrella_1.fbx", Vector3(origin.x + 1.85, ground_y, origin.z + 1.15), 0.6, 0.7)
	dressing.place_prop(self, "Table_1.fbx", Vector3(origin.x + 0.85, ground_y, origin.z + 0.72), 0.15, 0.82)
	dressing.place_prop(self, "Bench_1.fbx", Vector3(origin.x - 0.15, ground_y, origin.z + 1.35), PI, 0.78)
	dressing.place_prop(self, "Planter_1_Terracotta.fbx", Vector3(origin.x - 1.45, ground_y, origin.z - 0.15), 0.2, 1.15)
	dressing.place_prop(self, "Planter_1_Terracotta.fbx", Vector3(origin.x + 1.35, ground_y, origin.z - 0.55), -0.4, 1.05)


func _bridge_and_benches() -> void:
	for i in 5:
		var t := float(i) / 4.0
		var pos := Vector3(lerpf(2.4, 6.8, t), 0.18, lerpf(-4.2, -6.4, t))
		_box(pos, Vector3(0.7, 0.06, 0.42), Color(0.48, 0.32, 0.18), 0.7)
	_garden_bench(Vector3(3.2, 0, 3.6), 0.6)
	_garden_bench(Vector3(-2.6, 0, -1.0), 1.4)
	_garden_bench(Vector3(7.6, 0, -3.4), -0.4)


func _gate() -> void:
	var pos := Vector3(21.2, 0, 2.4)
	pos.y = field.height(pos.x, pos.z)
	_box(pos + Vector3(-0.8, 0.8, 0), Vector3(0.16, 1.6, 0.16), Color(0.32, 0.22, 0.14), 0.7)
	_box(pos + Vector3(0.8, 0.8, 0), Vector3(0.16, 1.6, 0.16), Color(0.32, 0.22, 0.14), 0.7)
	_box(pos + Vector3(0, 1.65, 0), Vector3(1.8, 0.12, 0.12), Color(0.32, 0.22, 0.14), 0.7)
	var sign := Label3D.new()
	sign.text = "Havenbrook"
	sign.font_size = 42
	sign.modulate = Color(0.96, 0.9, 0.75)
	sign.outline_size = 8
	sign.position = pos + Vector3(0, 2.05, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign)


func _plot_instances() -> void:
	var soil := BoxMesh.new()
	soil.size = Vector3(1.05, 0.07, 1.05)
	soil_mesh = _multi(soil, _std(Color(1, 1, 1), 0.95, true))
	var water := BoxMesh.new()
	water.size = Vector3(1.0, 0.1, 1.0)
	water_mesh = _multi(water, _std(Color(0.25, 0.55, 0.62), 0.25))
	for plant_id in ["sunpetal", "petal_corn", "moonvine", "dewberry"]:
		plant_meshes[plant_id] = _multi(MeshKit.flower(), _plant_material(plant_id))
	var plate := BoxMesh.new()
	plate.size = Vector3(1.08, 0.025, 1.08)
	highlight = MeshInstance3D.new()
	highlight.mesh = plate
	var mat := _std(Color(1.0, 0.92, 0.55), 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.86, 0.35, 0.45)
	highlight.material_override = mat
	highlight.visible = false
	add_child(highlight)


func _particles() -> void:
	rain = CPUParticles3D.new()
	rain.amount = 280
	rain.lifetime = 1.3
	rain.position = Vector3(2, 14, 2)
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(16, 0.4, 12)
	rain.direction = Vector3(0.05, -1, 0)
	rain.gravity = Vector3(0, -8, 0)
	rain.initial_velocity_min = 7.0
	rain.initial_velocity_max = 11.0
	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.08
	rain.mesh = drop
	rain.emitting = false
	add_child(rain)
	fireflies = CPUParticles3D.new()
	fireflies.amount = 40
	fireflies.lifetime = 4.0
	fireflies.position = Vector3(1, 1.4, 2)
	fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fireflies.emission_box_extents = Vector3(14, 1.2, 12)
	fireflies.direction = Vector3(0, 1, 0)
	fireflies.gravity = Vector3.ZERO
	fireflies.initial_velocity_min = 0.1
	fireflies.initial_velocity_max = 0.4
	var spark := SphereMesh.new()
	spark.radius = 0.04
	spark.height = 0.08
	fireflies.mesh = spark
	fireflies.color = Color(1.0, 0.86, 0.45)
	fireflies.emitting = false
	add_child(fireflies)


func _plant_material(plant_id: String) -> StandardMaterial3D:
	var colors := {
		"sunpetal": Color(0.95, 0.72, 0.22),
		"petal_corn": Color(0.78, 0.68, 0.28),
		"moonvine": Color(0.62, 0.5, 0.9),
		"dewberry": Color(0.78, 0.28, 0.48),
	}
	return _std(colors.get(plant_id, Color(0.4, 0.7, 0.3)), 0.62)


func _scatter(index: int, reach: float) -> Vector3:
	var x := (_unit(index) * 2.0 - 1.0) * reach
	var z := (_unit(index + 17) * 2.0 - 1.0) * reach * 0.82
	var center := Vector2(1.0, 2.0)
	var ellipse := pow((x - center.x) / 19.0, 2.0) + pow((z - center.y) / 15.0, 2.0)
	if ellipse > 0.92:
		return Vector3.INF
	return Vector3(x, 0, z)


func _unit(index: int) -> float:
	return absf(fmod(sin(float(index) * 12.9898) * 43758.5453, 1.0))


func _board(pos: Vector3, size: Vector3) -> void:
	_box(pos, size, Color(0.4, 0.26, 0.14), 0.78)


func _garden_bench(pos: Vector3, yaw: float) -> void:
	pos.y = field.height(pos.x, pos.z)
	dressing.place_prop(self, "Bench_1.fbx", pos, yaw, 0.9)


func _hedge_run(transforms: Array[Transform3D], colors: Array[Color], start: Vector3, end: Vector3, count: int) -> void:
	for i in count:
		var t := float(i) / float(count - 1)
		var pos := start.lerp(end, t)
		if field.path_distance(pos.x, pos.z) < 1.35:
			continue
		pos.y = field.height(pos.x, pos.z) + 0.84
		var basis := Basis(Vector3.UP, 0.15).scaled(Vector3(1.0, 0.72, 0.85))
		transforms.append(Transform3D(basis, pos))
		colors.append(Color(0.74, 0.95, 0.68))


func _box_xf(xf: Transform3D, size: Vector3, color: Color, roughness: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = xf
	node.material_override = _std(color, roughness)
	add_child(node)


func _box(pos: Vector3, size: Vector3, color: Color, roughness: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_solid(mesh, pos, Vector3.ONE, color, roughness)


func _solid(mesh: Mesh, pos: Vector3, scale: Vector3, color: Color, roughness: float) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.scale = scale
	node.material_override = _std(color, roughness)
	add_child(node)


func _std(color: Color, roughness: float, vertex_color := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.vertex_color_use_as_albedo = vertex_color
	return mat


func _multi(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	node.multimesh = multi
	node.material_override = material
	add_child(node)
	return node


func _write_transforms(node: MultiMeshInstance3D, transforms: Array, colors: Array) -> void:
	var multi := node.multimesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		if i < colors.size():
			multi.set_instance_color(i, colors[i])
		else:
			multi.set_instance_color(i, Color.WHITE)

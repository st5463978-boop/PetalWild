extends RefCounted

const PlantShader = preload("res://game/shaders/plant_card.gdshader")

var field
var plant_mat: ShaderMaterial
var prop_mat: StandardMaterial3D
var _meshes: Dictionary = {}


func prepare(terrain) -> void:
	field = terrain
	var atlas: Texture2D = load("res://game/art/cc0_garden/textures/Plants_Atlas.png") as Texture2D
	plant_mat = ShaderMaterial.new()
	plant_mat.shader = PlantShader
	plant_mat.set_shader_parameter("albedo_tex", atlas)
	var props: Texture2D = load("res://game/art/cc0_garden/textures/Props_Basecolor.png") as Texture2D
	prop_mat = StandardMaterial3D.new()
	prop_mat.albedo_texture = props
	prop_mat.albedo_color = Color.WHITE
	prop_mat.roughness = 0.66
	prop_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func scatter(parent: Node3D) -> void:
	_plant_rect(parent, "Poppy_Single_Red.fbx", -7.2, 8.2, 12.7, 13.55, 0.7, 1.55)
	_plant_rect(parent, "Gerbera_1_Red.fbx", -6.8, 7.6, 13.5, 14.35, 0.75, 1.65)
	_plant_rect(parent, "Larkspur_1_Purple.fbx", -6.2, 7.2, 14.2, 15.05, 0.85, 1.45)
	_plant_rect(parent, "Poppy_Single_Red.fbx", -6.4, 6.8, -2.15, -1.25, 0.68, 1.6)
	_plant_rect(parent, "Gerbera_1_Red.fbx", -5.6, 6.0, -1.35, -0.7, 0.72, 1.55)
	_plant_rect(parent, "Cornflowers_Big_Cluster_Blue.fbx", -14.8, -9.6, 1.4, 9.0, 1.25, 1.2)
	_plant_rect(parent, "Cosmea_Cluster_Small_1.fbx", -14.2, -10.2, 2.2, 8.6, 1.1, 1.05)
	_plant_rect(parent, "Flowering_Garlic_1.fbx", 8.6, 9.35, 1.2, 10.4, 0.8, 1.35)
	_plant_rect(parent, "Giant_Sunflower_big_1.fbx", 14.2, 15.0, -8.0, -3.4, 1.4, 0.82)
	_pond_bank(parent, "Larkspur_1_Purple.fbx", 12, 8.4, 1.25)
	_pond_bank(parent, "Cosmea_Cluster_Small_1.fbx", 8, 9.2, 1.0)
	_lawn(parent, "Grass_Simple_small.fbx", 78, 1.05, 11)
	_lawn(parent, "Wild_Grass_Red_small.fbx", 36, 1.12, 29)


func place_prop(parent: Node3D, file_name: String, pos: Vector3, yaw: float, prop_scale: float) -> void:
	var packed: PackedScene = load("res://game/art/cc0_garden/meshes/%s" % file_name) as PackedScene
	if packed == null:
		return
	var node: Node3D = packed.instantiate() as Node3D
	node.position = pos
	node.rotation.y = yaw
	node.scale = Vector3.ONE * prop_scale
	_paint_props(node)
	parent.add_child(node)


func _plant_rect(parent: Node3D, file_name: String, x0: float, x1: float, z0: float, z1: float, step: float, prop_scale: float) -> void:
	var mesh := _mesh(file_name)
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	var x := x0
	var column := 0
	while x <= x1:
		var z := z0
		var row := 0
		while z <= z1:
			var jitter_x := (_unit(column * 19 + row * 3) - 0.5) * step * 0.28
			var jitter_z := (_unit(column * 5 + row * 11) - 0.5) * step * 0.28
			var px := x + jitter_x
			var pz := z + jitter_z
			if not _blocked(px, pz, 0.85, 4.3, 2.05):
				var placed := Vector3(px, field.height(px, pz), pz)
				var yaw := _unit(column * 13 + row) * TAU
				var size := prop_scale * (0.9 + _unit(column + row * 7) * 0.22)
				transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), placed))
			z += step
			row += 1
		x += step
		column += 1
	_commit(parent, mesh, transforms)


func _pond_bank(parent: Node3D, file_name: String, count: int, radius: float, prop_scale: float) -> void:
	var mesh := _mesh(file_name)
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	for i in count:
		var angle := lerpf(-0.15, PI + 0.15, float(i) / float(count - 1))
		var px := 5.4 + cos(angle) * radius
		var pz := -7.2 + sin(angle) * radius * 0.78
		if _blocked(px, pz, 0.7, 3.6, 2.2):
			continue
		var placed := Vector3(px, field.height(px, pz), pz)
		var yaw := angle + PI
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * prop_scale), placed))
	_commit(parent, mesh, transforms)


func _lawn(parent: Node3D, file_name: String, count: int, prop_scale: float, salt: int) -> void:
	var mesh := _mesh(file_name)
	if mesh == null:
		return
	var transforms: Array[Transform3D] = []
	var i := 0
	var guard := 0
	while transforms.size() < count and guard < count * 8:
		guard += 1
		var px := (_unit(salt + guard * 3) * 2.0 - 1.0) * 18.5
		var pz := (_unit(salt + guard * 5) * 2.0 - 1.0) * 15.0
		if _blocked(px, pz, 0.7, 4.7, 1.7):
			continue
		var placed := Vector3(px, field.height(px, pz), pz)
		var yaw := _unit(guard + i) * TAU
		var size := prop_scale * (0.85 + _unit(guard * 2) * 0.4)
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), placed))
		i += 1
	_commit(parent, mesh, transforms)


func _commit(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var node := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	node.multimesh = multi
	node.material_override = plant_mat
	parent.add_child(node)


func _mesh(file_name: String) -> Mesh:
	if _meshes.has(file_name):
		return _meshes[file_name]
	var packed: PackedScene = load("res://game/art/cc0_garden/meshes/%s" % file_name) as PackedScene
	if packed == null:
		_meshes[file_name] = null
		return null
	var root: Node = packed.instantiate()
	var found: Mesh = _find_mesh(root)
	_meshes[file_name] = found
	root.free()
	return found


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh:
			return mesh_node.mesh
	for child in node.get_children():
		var found: Mesh = _find_mesh(child)
		if found:
			return found
	return null


func _paint_props(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = prop_mat
	for child in node.get_children():
		_paint_props(child)


func _blocked(x: float, z: float, path_clear: float, pond_clear: float, stall_clear: float) -> bool:
	var ellipse := pow((x - 1.0) / 19.6, 2.0) + pow((z - 2.0) / 15.4, 2.0)
	if ellipse > 0.9:
		return true
	if field.in_plots(x, z):
		return true
	if field.path_distance(x, z) < path_clear:
		return true
	if Vector2(x - 5.4, z + 7.2).length() < pond_clear:
		return true
	if Vector2(x - 13.4, z - 1.5).length() < stall_clear:
		return true
	return false


func _unit(index: int) -> float:
	return absf(fmod(sin(float(index) * 12.9898) * 43758.5453, 1.0))

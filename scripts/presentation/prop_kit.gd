extends RefCounted

const ROOT := "res://assets/third_party/kenney/nature-kit/Models/FBX format/"

static func spawn(file_name: String, target_height: float) -> Node3D:
	var packed := _scene(file_name)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	var mesh_node := _find_mesh(node)
	if mesh_node != null:
		var height := mesh_node.get_aabb().size.y
		if height > 0.001:
			var scale := target_height / height
			node.scale = Vector3.ONE * scale
	return node


static func mesh(file_name: String) -> Mesh:
	var packed := _scene(file_name)
	if packed == null:
		return null
	var node := packed.instantiate()
	var mesh_node := _find_mesh(node)
	var found: Mesh = null
	if mesh_node != null:
		found = mesh_node.mesh
	node.free()
	return found


static func _scene(file_name: String) -> PackedScene:
	var path := ROOT + file_name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null

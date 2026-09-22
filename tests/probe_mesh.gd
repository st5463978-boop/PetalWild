extends SceneTree

func _init() -> void:
	var path := "res://assets/third_party/kenney/nature-kit/Models/FBX format/tree_oak.fbx"
	var packed = load(path)
	print("loaded ", packed)
	if packed == null:
		quit(1)
	var node = packed.instantiate()
	_walk(node, 0)
	quit(0)

func _walk(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		print(pad, node.name, " aabb ", mesh_node.get_aabb())
	else:
		print(pad, node.name, " ", node.get_class())
	for child in node.get_children():
		_walk(child, depth + 1)

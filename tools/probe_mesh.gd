extends SceneTree

func _init() -> void:
	var paths := [
		"res://third_party/incoming/assetquest-stylized-garden-demo/FBX/Poppy_Single_Red.fbx",
		"res://third_party/incoming/assetquest-stylized-garden-demo/FBX/Bench_1.fbx",
		"res://third_party/incoming/assetquest-stylized-garden-demo/FBX/Cornflowers_Big_Cluster_Blue.fbx",
	]
	for path in paths:
		var packed = load(path)
		print("LOAD ", path, " ", packed)
		if packed is PackedScene:
			var node := (packed as PackedScene).instantiate()
			var box := _bounds(node, Transform3D.IDENTITY)
			print("BOUNDS ", box)
			node.free()
	quit()

func _bounds(node: Node, xform: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh:
			var local := xform * (node as Node3D).transform
			var part: AABB = local * mesh.get_aabb()
			box = part
			first = false
	for child in node.get_children():
		var next := xform
		if node is Node3D:
			next = xform * (node as Node3D).transform
		var child_box := _bounds(child, next)
		if child_box.size != Vector3.ZERO:
			if first:
				box = child_box
				first = false
			else:
				box = box.merge(child_box)
	return box

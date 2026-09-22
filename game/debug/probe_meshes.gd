extends SceneTree

func _init() -> void:
	var dir := DirAccess.open("res://game/art/cc0_garden/meshes")
	if dir == null:
		push_error("no mesh dir")
		quit(1)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".fbx"):
			var path := "res://game/art/cc0_garden/meshes/%s" % name
			var packed = load(path)
			if packed == null:
				print("FAIL ", path)
			else:
				var node: Node = packed.instantiate()
				_dump(name, node, 0)
				node.free()
		name = dir.get_next()
	quit(0)


func _dump(label: String, node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mesh := mesh_node.mesh
		var aabb := mesh.get_aabb() if mesh else AABB()
		var mat_count := mesh.get_surface_count() if mesh else 0
		print("%s%s mesh aabb=%s surfaces=%d" % [pad, label if depth == 0 else node.name, aabb, mat_count])
		if mesh:
			for i in mat_count:
				var mat := mesh_node.get_active_material(i)
				var extra := ""
				if mat is StandardMaterial3D:
					var std := mat as StandardMaterial3D
					var tex := std.albedo_texture
					extra = " albedo=%s tex=%s transp=%s" % [std.albedo_color, tex.resource_path if tex else "none", std.transparency]
				elif mat:
					extra = " mat=%s" % mat.get_class()
				print("%s  surface %d%s" % [pad, i, extra])
	elif depth <= 2:
		var xf := ""
		if node is Node3D:
			var n3 := node as Node3D
			xf = " pos=%s" % n3.position
		print("%s%s %s%s" % [pad, label if depth == 0 else node.name, node.get_class(), xf])
	for child in node.get_children():
		_dump(label, child, depth + 1)

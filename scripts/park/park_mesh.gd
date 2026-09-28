class_name ParkMesh
extends RefCounted


static func pillow(size: Vector3, segs: int = 8) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := segs
	var slices := segs * 2
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for y in rings + 1:
		var v := float(y) / float(rings)
		var phi := v * PI
		var cy := cos(phi)
		var sy := sin(phi)
		for x in slices + 1:
			var u := float(x) / float(slices)
			var theta := u * TAU
			var sx := cos(theta) * sy
			var sz := sin(theta) * sy
			var sphere := Vector3(sx, cy, sz)
			var cube := sphere
			var ax := absf(cube.x)
			var ay := absf(cube.y)
			var az := absf(cube.z)
			var m := maxf(ax, maxf(ay, az))
			if m > 0.0001:
				cube /= m
			var p := cube.lerp(sphere, 0.34)
			p.x *= size.x * 0.5
			p.y *= size.y * 0.5
			p.z *= size.z * 0.5
			verts.append(p)
			uvs.append(Vector2(u, v))
	for y in rings:
		for x in slices:
			var i := y * (slices + 1) + x
			_tri(tool, verts, uvs, i, i + slices + 1, i + 1)
			_tri(tool, verts, uvs, i + 1, i + slices + 1, i + slices + 2)
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func lumpy_sphere(radius: float, lumps: float, segs: int = 10) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := segs
	var slices := segs * 2
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for y in rings + 1:
		var v := float(y) / float(rings)
		var phi := v * PI
		var cy := cos(phi)
		var sy := sin(phi)
		for x in slices + 1:
			var u := float(x) / float(slices)
			var theta := u * TAU
			var n := 1.0 + lumps * 0.18 * sin(theta * 3.0 + cy * 4.0) * cos(phi * 2.0)
			var p := Vector3(cos(theta) * sy, cy, sin(theta) * sy) * radius * n
			verts.append(p)
			uvs.append(Vector2(u, v))
	for y in rings:
		for x in slices:
			var i := y * (slices + 1) + x
			_tri(tool, verts, uvs, i, i + slices + 1, i + 1)
			_tri(tool, verts, uvs, i + 1, i + slices + 1, i + slices + 2)
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func grass_blade() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blade_card(tool, 0.0)
	_blade_card(tool, PI * 0.5)
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func wedge_roof(width: float, height: float, depth: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var hd := depth * 0.5
	var ridge := Vector3(0.0, height, 0.0)
	var a := Vector3(-hw, 0.0, -hd)
	var b := Vector3(hw, 0.0, -hd)
	var c := Vector3(hw, 0.0, hd)
	var d := Vector3(-hw, 0.0, hd)
	_face3(tool, a, ridge, b, Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1))
	_face3(tool, b, ridge, c, Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1))
	_face3(tool, c, ridge, d, Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1))
	_face3(tool, d, ridge, a, Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1))
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func gable_roof(width: float, height: float, depth: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var hd := depth * 0.5
	var r0 := Vector3(0.0, height, -hd)
	var r1 := Vector3(0.0, height, hd)
	var a := Vector3(-hw, 0.0, -hd)
	var b := Vector3(hw, 0.0, -hd)
	var c := Vector3(hw, 0.0, hd)
	var d := Vector3(-hw, 0.0, hd)
	_face3(tool, a, r0, b, Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1))
	_face3(tool, d, c, r1, Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0))
	_quad(tool, a, r0, r1, d)
	_quad(tool, b, c, r1, r0)
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func _blade_card(tool: SurfaceTool, yaw: float) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	var w := 0.09
	var h := 0.42
	var bend := 0.08
	var p0 := Vector3(-w * c, 0.0, -w * s)
	var p1 := Vector3(w * c, 0.0, w * s)
	var p2 := Vector3(w * c + (-s) * bend, h, w * s + c * bend)
	var p3 := Vector3(-w * c + (-s) * bend, h, -w * s + c * bend)
	tool.set_uv(Vector2(0, 1))
	tool.set_color(Color(1, 1, 1, 0.0))
	tool.add_vertex(p0)
	tool.set_uv(Vector2(1, 1))
	tool.set_color(Color(1, 1, 1, 0.0))
	tool.add_vertex(p1)
	tool.set_uv(Vector2(1, 0))
	tool.set_color(Color(1, 1, 1, 1.0))
	tool.add_vertex(p2)
	tool.set_uv(Vector2(0, 1))
	tool.set_color(Color(1, 1, 1, 0.0))
	tool.add_vertex(p0)
	tool.set_uv(Vector2(1, 0))
	tool.set_color(Color(1, 1, 1, 1.0))
	tool.add_vertex(p2)
	tool.set_uv(Vector2(0, 0))
	tool.set_color(Color(1, 1, 1, 1.0))
	tool.add_vertex(p3)


static func _tri(tool: SurfaceTool, verts: Array[Vector3], uvs: Array[Vector2], a: int, b: int, c: int) -> void:
	tool.set_uv(uvs[a])
	tool.add_vertex(verts[a])
	tool.set_uv(uvs[b])
	tool.add_vertex(verts[b])
	tool.set_uv(uvs[c])
	tool.add_vertex(verts[c])


static func _face3(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	tool.set_uv(ua)
	tool.add_vertex(a)
	tool.set_uv(ub)
	tool.add_vertex(b)
	tool.set_uv(uc)
	tool.add_vertex(c)


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tool.set_uv(Vector2(0, 1))
	tool.add_vertex(a)
	tool.set_uv(Vector2(0, 0))
	tool.add_vertex(b)
	tool.set_uv(Vector2(1, 0))
	tool.add_vertex(c)
	tool.set_uv(Vector2(0, 1))
	tool.add_vertex(a)
	tool.set_uv(Vector2(1, 0))
	tool.add_vertex(c)
	tool.set_uv(Vector2(1, 1))
	tool.add_vertex(d)

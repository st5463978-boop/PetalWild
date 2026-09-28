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


static func oct_roof(radius: float, height: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(0.0, height, 0.0)
	var n := 8
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var p0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var u0 := float(i) / float(n)
		var u1 := float(i + 1) / float(n)
		_face3(tool, p0, apex, p1, Vector2(u0, 1.0), Vector2((u0 + u1) * 0.5, 0.0), Vector2(u1, 1.0))
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func leaf_cross(width: float, height: float, drape: bool) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_leaf_card(tool, width, height, 0.0, drape)
	_leaf_card(tool, width, height, PI * 0.5, drape)
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func lily_pad(radius: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 5
	var segs := 22
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for ring in rings + 1:
		var t := float(ring) / float(rings)
		for seg in segs + 1:
			var u := float(seg) / float(segs)
			var theta := u * TAU
			var notch := smoothstep(0.15, 0.0, absf(angle_delta(theta, 0.15)))
			var r := radius * t * lerpf(1.0, 0.08, notch * smoothstep(0.25, 1.0, t))
			var curl := t * t * 0.045 + sin(theta * 2.0) * t * 0.02
			verts.append(Vector3(cos(theta) * r, curl, sin(theta) * r))
			uvs.append(Vector2(u, t))
	for ring in rings:
		for seg in segs:
			var i := ring * (segs + 1) + seg
			_tri(tool, verts, uvs, i, i + segs + 1, i + 1)
			_tri(tool, verts, uvs, i + 1, i + segs + 1, i + segs + 2)
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func water_lily() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var petals := 8
	for i in petals:
		var a := TAU * float(i) / float(petals)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.045
		var root := dir * 0.03 + Vector3(0, 0.02, 0)
		var tip := dir * 0.16 + Vector3(0, 0.07, 0)
		var mid := dir * 0.1 + Vector3(0, 0.055, 0)
		_face3(tool, root - side, tip, root + side, Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1))
		_face3(tool, root - side, mid + Vector3(0, 0.02, 0), tip, Vector2(0, 1), Vector2(0.3, 0.4), Vector2(0.5, 0))
	var center := 6
	for i in center:
		var a0 := TAU * float(i) / float(center)
		var a1 := TAU * float(i + 1) / float(center)
		var p0 := Vector3(cos(a0) * 0.035, 0.045, sin(a0) * 0.035)
		var p1 := Vector3(cos(a1) * 0.035, 0.045, sin(a1) * 0.035)
		_face3(tool, Vector3(0, 0.05, 0), p1, p0, Vector2(0.5, 0.5), Vector2(1, 1), Vector2(0, 1))
	tool.generate_normals()
	tool.generate_tangents()
	return tool.commit()


static func angle_delta(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU) - PI
	return absf(d)


static func _leaf_card(tool: SurfaceTool, width: float, height: float, yaw: float, drape: bool) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	var hw := width * 0.5
	var p0 := Vector3(-hw * c, 0.0, -hw * s)
	var p1 := Vector3(hw * c, 0.0, hw * s)
	var p2 := Vector3(hw * c, height, hw * s)
	var p3 := Vector3(-hw * c, height, -hw * s)
	var tip0 := 0.05 if drape else 0.0
	var tip1 := 1.0 if drape else 1.0
	if drape:
		tip0 = 1.0
		tip1 = 0.05
	_leaf_vert(tool, p0, Vector2(0, 1), tip0)
	_leaf_vert(tool, p1, Vector2(1, 1), tip0)
	_leaf_vert(tool, p2, Vector2(1, 0), tip1)
	_leaf_vert(tool, p0, Vector2(0, 1), tip0)
	_leaf_vert(tool, p2, Vector2(1, 0), tip1)
	_leaf_vert(tool, p3, Vector2(0, 0), tip1)


static func _leaf_vert(tool: SurfaceTool, p: Vector3, uv: Vector2, tip: float) -> void:
	tool.set_uv(uv)
	tool.set_color(Color(1, 1, 1, tip))
	tool.add_vertex(p)


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

extends RefCounted

static func jelly(shape: String) -> ArrayMesh:
	return _sphere(0.42, 14, 18, shape)


static func shrub() -> ArrayMesh:
	return _sphere(0.72, 10, 12, "shrub")


static func rock() -> ArrayMesh:
	return _sphere(0.45, 8, 10, "rock")


static func canopy() -> ArrayMesh:
	return _sphere(1.15, 10, 12, "canopy")


static func flower() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_prism(tool, Vector3(0, 0.18, 0), 0.025, 0.36, Color(0.25, 0.45, 0.18))
	for i in 5:
		var angle := float(i) / 5.0 * TAU
		var dir := Vector3(cos(angle), 0.15, sin(angle))
		_add_prism(tool, Vector3(0, 0.36, 0) + dir * 0.05, 0.06, 0.16, Color(0.95, 0.72, 0.55))
	tool.generate_normals()
	return tool.commit()


static func grass_tuft() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(tool, 0.0)
	_quad(tool, PI * 0.5)
	tool.generate_normals()
	return tool.commit()


static func tree() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_prism(tool, Vector3(0, 0.7, 0), 0.16, 1.4, Color(0.38, 0.24, 0.14))
	tool.generate_normals()
	var trunk: ArrayMesh = tool.commit()
	var head := canopy()
	var combo := ArrayMesh.new()
	# Keep trunk and canopy as separate meshes at the call site.
	return trunk if false else head


static func trunk() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_prism(tool, Vector3(0, 0.85, 0), 0.18, 1.7, Color(0.36, 0.22, 0.12))
	tool.generate_normals()
	return tool.commit()


static func _sphere(radius: float, rings: int, segs: int, shape: String) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in rings + 1:
		var v := float(y) / float(rings)
		var phi := v * PI
		var ny := cos(phi)
		var sin_phi := sin(phi)
		for x in segs + 1:
			var u := float(x) / float(segs)
			var theta := u * TAU
			var r := _radius(shape, ny, theta, radius)
			tool.set_uv(Vector2(u, v))
			tool.add_vertex(Vector3(sin_phi * cos(theta) * r, ny * r, sin_phi * sin(theta) * r))
	for y in rings:
		for x in segs:
			var i := y * (segs + 1) + x
			tool.add_index(i)
			tool.add_index(i + segs + 1)
			tool.add_index(i + 1)
			tool.add_index(i + 1)
			tool.add_index(i + segs + 1)
			tool.add_index(i + segs + 2)
	tool.generate_normals()
	return tool.commit()


static func _radius(shape: String, ny: float, theta: float, radius: float) -> float:
	match shape:
		"pear":
			var belly := 1.05 - smoothstep(-0.15, 0.9, ny) * 0.62
			return radius * belly * (1.0 + 0.04 * sin(theta * 3.0))
		"stacked":
			var stack := 0.72 + 0.28 * absf(sin(ny * PI * 2.4))
			return radius * stack
		"droplet":
			var drop := 0.55 + (1.0 - smoothstep(-1.0, 0.8, ny)) * 0.7
			return radius * drop
		"long":
			return radius * (0.62 + 0.08 * sin(theta * 2.0))
		"flat":
			return radius * (1.15 + 0.08 * sin(theta * 4.0))
		"crown":
			var bumps := 1.0 + 0.16 * maxf(0.0, sin(theta * 5.0) * sin(ny * 3.0))
			return radius * bumps * (0.85 + 0.2 * (1.0 - ny))
		"multi":
			var lobes := 0.78 + 0.28 * absf(cos(theta * 3.0))
			return radius * lobes
		"botanical":
			var ridges := 1.0 + 0.1 * sin(theta * 6.0) * maxf(ny, 0.0)
			return radius * ridges
		"shrub":
			return radius * (0.85 + 0.18 * sin(theta * 5.0) * cos(ny * 4.0))
		"canopy":
			return radius * (0.9 + 0.14 * sin(theta * 3.0 + ny * 2.0))
		"rock":
			return radius * (0.75 + 0.28 * absf(sin(theta * 4.0 + ny * 6.0)))
		_:
			return radius


static func _quad(tool: SurfaceTool, yaw: float) -> void:
	var right := Vector3(cos(yaw), 0, sin(yaw)) * 0.045
	var a := -right
	var b := right
	var c := right + Vector3(0, 0.34, 0)
	var d := -right + Vector3(0, 0.34, 0)
	var color := Color(0.3, 0.55, 0.2)
	for vertex in [a, b, c, a, c, d]:
		tool.set_color(color)
		tool.add_vertex(vertex)


static func _add_prism(tool: SurfaceTool, center: Vector3, radius: float, height: float, color: Color) -> void:
	var segs := 8
	var bottom := center.y - height * 0.5
	var top := center.y + height * 0.5
	for i in segs:
		var a0 := float(i) / float(segs) * TAU
		var a1 := float(i + 1) / float(segs) * TAU
		var p0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var verts: Array[Vector3] = [
			Vector3(p0.x, bottom, p0.z) + Vector3(center.x, 0, center.z),
			Vector3(p1.x, bottom, p1.z) + Vector3(center.x, 0, center.z),
			Vector3(p1.x, top, p1.z) + Vector3(center.x, 0, center.z),
			Vector3(p0.x, bottom, p0.z) + Vector3(center.x, 0, center.z),
			Vector3(p1.x, top, p1.z) + Vector3(center.x, 0, center.z),
			Vector3(p0.x, top, p0.z) + Vector3(center.x, 0, center.z),
		]
		for vertex in verts:
			tool.set_color(color)
			tool.add_vertex(vertex)

class_name GardenDressing
extends RefCounted

var _rng := RandomNumberGenerator.new()

func build(parent: Node3D) -> void:
	_rng.seed = 14017
	_terrain(parent)
	_water(parent)
	_plots(parent)
	_paths(parent)
	_hedge(parent)
	_hedge_clumps(parent)
	_hedge_leaves(parent)
	_hedge_fringe(parent)
	_hedge_coat(parent)
	_hedge_bulges(parent)
	_hedge_volume(parent)
	_scatter_grass(parent)
	_room_cover(parent)
	_flowers(parent)
	_flower_rows(parent)
	_shrubs(parent)
	_trees(parent)
	_willow(parent)
	_groundcover(parent)
	_lawn_tufts(parent)
	_lawn_meadow(parent)
	_room_clumps(parent)
	_room_carpet(parent)
	_room_beds(parent)
	_stones(parent)
	_cc0_props(parent)

func _terrain(parent: Node3D) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 24.0
	var step := 0.55
	var count := int(half * 2.0 / step)
	for iz in count:
		for ix in count:
			var x0 := -half + float(ix) * step
			var z0 := -half + float(iz) * step
			_quad(tool, x0, z0, step)
	tool.generate_normals()
	var mesh := tool.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	node.material_override = material
	node.name = "Terrain"
	parent.add_child(node)

func _quad(tool: SurfaceTool, x0: float, z0: float, step: float) -> void:
	var x1 := x0 + step
	var z1 := z0 + step
	_vert(tool, x0, z0)
	_vert(tool, x1, z0)
	_vert(tool, x1, z1)
	_vert(tool, x0, z0)
	_vert(tool, x1, z1)
	_vert(tool, x0, z1)

func _vert(tool: SurfaceTool, x: float, z: float) -> void:
	var y := GardenLayout.height_at(x, z)
	tool.set_color(GardenLayout.terrain_color(x, z, y))
	tool.set_uv(Vector2(x, z))
	tool.add_vertex(Vector3(x, y, z))

func _water(parent: Node3D) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var segments := 28
	for ring in rings:
		for seg in segments:
			var r0 := GardenLayout.POND_RADIUS * float(ring) / float(rings)
			var r1 := GardenLayout.POND_RADIUS * float(ring + 1) / float(rings)
			var a0 := TAU * float(seg) / float(segments)
			var a1 := TAU * float(seg + 1) / float(segments)
			_water_vert(tool, r0, a0)
			_water_vert(tool, r1, a0)
			_water_vert(tool, r1, a1)
			_water_vert(tool, r0, a0)
			_water_vert(tool, r1, a1)
			_water_vert(tool, r0, a1)
	var mesh := tool.commit()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	node.material_override = material
	node.name = "Pond"
	parent.add_child(node)

func _water_vert(tool: SurfaceTool, radius: float, angle: float) -> void:
	var center := GardenLayout.POND_CENTER
	var x := center.x + cos(angle) * radius
	var z := center.z + sin(angle) * radius
	tool.set_uv(Vector2(x, z))
	tool.add_vertex(Vector3(x, -0.08, z))

func _plots(parent: Node3D) -> void:
	for px in 2:
		for pz in 2:
			var rect := GardenLayout.plot_rect(px, pz)
			_frame(parent, rect)

func _frame(parent: Node3D, rect: Rect2) -> void:
	var y := 0.08
	var thick := 0.08
	var h := 0.14
	_box(parent, Vector3(rect.position.x + rect.size.x * 0.5, y, rect.position.y - thick * 0.5), Vector3(rect.size.x + thick, h, thick), Color("#8a6244"))
	_box(parent, Vector3(rect.position.x + rect.size.x * 0.5, y, rect.position.y + rect.size.y + thick * 0.5), Vector3(rect.size.x + thick, h, thick), Color("#8a6244"))
	_box(parent, Vector3(rect.position.x - thick * 0.5, y, rect.position.y + rect.size.y * 0.5), Vector3(thick, h, rect.size.y), Color("#7b563c"))
	_box(parent, Vector3(rect.position.x + rect.size.x + thick * 0.5, y, rect.position.y + rect.size.y * 0.5), Vector3(thick, h, rect.size.y), Color("#7b563c"))

func _paths(parent: Node3D) -> void:
	var strips: Array = [
		[Vector3(-4.55, 0, 5.2), Vector3(-4.55, 0, 3.5)],
		[Vector3(-6.6, 0, 3.5), Vector3(-1.4, 0, 3.5)],
		[Vector3(-2.35, 0, 3.5), Vector3(-2.35, 0, -6.35)],
		[Vector3(-7.4, 0, -6.35), Vector3(0.6, 0, -6.35)],
		[Vector3(2.6, 0, -2.5), Vector3(6.4, 0, -2.5)],
	]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip in strips:
		_ribbon(tool, strip[0], strip[1], 0.92)
	tool.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	node.material_override = _standard(Color("#cbb89a"), 0.9)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.name = "Paths"
	parent.add_child(node)

func _ribbon(tool: SurfaceTool, a: Vector3, b: Vector3, width: float) -> void:
	var dir := b - a
	dir.y = 0.0
	var length := dir.length()
	if length < 0.01:
		return
	dir /= length
	var side := Vector3(-dir.z, 0, dir.x) * width * 0.5
	var y := 0.03
	var a_left := Vector3(a.x, y, a.z) + side
	var a_right := Vector3(a.x, y, a.z) - side
	var b_left := Vector3(b.x, y, b.z) + side
	var b_right := Vector3(b.x, y, b.z) - side
	for point in [a_left, b_left, b_right, a_left, b_right, a_right]:
		tool.set_color(Color("#cbb89a"))
		tool.add_vertex(point)

func _hedge(parent: Node3D) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge := Rect2(-13.6, -9.9, 26.4, 17.8)
	var south_gate: Array[Vector3] = [Vector3(0.0, -9.9, 2.9)]
	_hedge_wall(tool, Vector3(edge.position.x, 0, edge.position.y), Vector3(edge.size.x, 0, 0), south_gate, 1.22)
	_hedge_wall(tool, Vector3(edge.end.x, 0, edge.position.y), Vector3(0, 0, edge.size.y), [], 1.22)
	_hedge_wall(tool, Vector3(edge.end.x, 0, edge.end.y), Vector3(-edge.size.x, 0, 0), [], 1.22)
	_hedge_wall(tool, Vector3(edge.position.x, 0, edge.end.y), Vector3(0, 0, -edge.size.y), [], 1.22)
	# Lower walls around the four beds, with gaps where the paths already run.
	var room_south: Array[Vector3] = [Vector3(-2.35, -6.55, 1.2)]
	var room_north: Array[Vector3] = [Vector3(-4.55, 3.2, 1.25), Vector3(-2.35, 3.2, 1.05)]
	var room_east: Array[Vector3] = [Vector3(3.85, -2.5, 1.2)]
	_hedge_wall(tool, Vector3(-8.55, 0, -6.55), Vector3(12.4, 0, 0), room_south, 0.78)
	_hedge_wall(tool, Vector3(3.85, 0, -6.55), Vector3(0, 0, 9.75), room_east, 0.78)
	_hedge_wall(tool, Vector3(3.85, 0, 3.2), Vector3(-12.4, 0, 0), room_north, 0.78)
	_hedge_wall(tool, Vector3(-8.55, 0, 3.2), Vector3(0, 0, -9.75), [], 0.78)
	tool.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	node.material_override = _hedge_material()
	node.name = "Hedge"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)

func _hedge_wall(tool: SurfaceTool, origin: Vector3, along: Vector3, openings: Array, scale: float) -> void:
	_hedge_run(tool, origin, along, openings, scale, 0.0, 0.2)
	_hedge_run(tool, origin, along, openings, scale * 0.74, -0.78, 2.1)
	_hedge_run(tool, origin, along, openings, scale * 0.66, 0.7, 4.0)


func _hedge_run(tool: SurfaceTool, origin: Vector3, along: Vector3, openings: Array, scale: float, offset_side: float, phase: float) -> void:
	var length := along.length()
	if length < 0.2:
		return
	var dir := along / length
	var side := Vector3(-dir.z, 0.0, dir.x)
	var profile: Array[Vector2] = [
		Vector2(-0.50, 0.02),
		Vector2(-0.48, 0.46),
		Vector2(-0.40, 0.84),
		Vector2(-0.22, 1.12),
		Vector2(0.0, 1.28),
		Vector2(0.22, 1.12),
		Vector2(0.40, 0.84),
		Vector2(0.48, 0.46),
		Vector2(0.50, 0.02),
	]
	var count := maxi(int(length / 0.34), 2)
	var previous: Array[Vector3] = []
	var previous_open := false
	for i in count + 1:
		var center := origin + dir * (float(i) / float(count) * length) + side * offset_side
		var open := false
		for hole in openings:
			var gate := hole as Vector3
			if Vector2(center.x - gate.x, center.z - gate.y).length() < gate.z:
				open = true
				break
		var ring: Array[Vector3] = []
		var lift := sin(center.x * 0.85 + center.z * 0.7 + phase) * 0.36 * scale
		var bulge := 1.0 + sin(center.x * 2.6 + center.z * 1.9 + phase) * 0.22
		var chop := 0.52 + 0.7 * absf(sin(center.x * 0.85 + center.z * 0.6 + phase))
		var lean := sin(center.x * 2.2 + phase) * 0.22 * scale
		var knot := absf(sin(center.x * 0.48 + center.z * 0.36))
		var waist := 0.22 + 0.78 * knot
		var width := (0.62 + scale * 0.22) * bulge * lerpf(0.28, 1.0, waist)
		if _hedge_gap(center):
			open = true
		for point in profile:
			var height := point.y
			if height > 0.72:
				height = 0.72 + (height - 0.72) * 0.22
			if height > 0.12:
				height *= chop * lerpf(0.45, 1.0, knot)
			ring.append(center + side * (point.x * width + lean * height) + Vector3(0, height * scale + lift, 0))
		if i > 0 and not open and not previous_open:
			_hedge_bridge(tool, previous, ring)
		previous = ring
		previous_open = open

func _hedge_gap(at: Vector3) -> bool:
	return absf(sin(at.x * 0.48 + at.z * 0.36)) < 0.28

func _hedge_bridge(tool: SurfaceTool, a: Array[Vector3], b: Array[Vector3]) -> void:
	for i in a.size() - 1:
		_hedge_tri(tool, a[i], b[i], b[i + 1])
		_hedge_tri(tool, a[i], b[i + 1], a[i + 1])

func _hedge_tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.set_uv(Vector2(0, 1))
	tool.add_vertex(a)
	tool.set_uv(Vector2(1, 1))
	tool.add_vertex(b)
	tool.set_uv(Vector2(0.5, 0))
	tool.add_vertex(c)

func _hedge_leaves(parent: Node3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.64, 0.48)
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var runs: Array = [
		[Vector3(-13.6, 0, -9.9), Vector3(26.4, 0, 0), 1.22, [Vector3(0.0, -9.9, 2.9)]],
		[Vector3(12.8, 0, -9.9), Vector3(0, 0, 17.8), 1.22, []],
		[Vector3(12.8, 0, 7.9), Vector3(-26.4, 0, 0), 1.22, []],
		[Vector3(-13.6, 0, 7.9), Vector3(0, 0, -17.8), 1.22, []],
		[Vector3(-8.55, 0, -6.55), Vector3(12.4, 0, 0), 0.78, [Vector3(-2.35, -6.55, 1.2)]],
		[Vector3(3.85, 0, -6.55), Vector3(0, 0, 9.75), 0.78, [Vector3(3.85, -2.5, 1.2)]],
		[Vector3(3.85, 0, 3.2), Vector3(-12.4, 0, 0), 0.78, [Vector3(-4.55, 3.2, 1.25), Vector3(-2.35, 3.2, 1.05)]],
		[Vector3(-8.55, 0, 3.2), Vector3(0, 0, -9.75), 0.78, []],
	]
	var shell: Array[Vector2] = [
		Vector2(-0.55, 0.14),
		Vector2(-0.5, 0.36),
		Vector2(-0.4, 0.62),
		Vector2(-0.26, 0.88),
		Vector2(-0.12, 1.1),
		Vector2(0.0, 1.26),
		Vector2(0.12, 1.1),
		Vector2(0.26, 0.88),
		Vector2(0.4, 0.62),
		Vector2(0.5, 0.36),
		Vector2(0.55, 0.14),
	]
	for run in runs:
		var origin: Vector3 = run[0]
		var along: Vector3 = run[1]
		var scale: float = run[2]
		var holes: Array = run[3]
		var length := along.length()
		var dir := along / length
		var side := Vector3(-dir.z, 0.0, dir.x)
		var steps := int(length / 0.28)
		var width := 0.62 + scale * 0.22
		for i in steps:
			var center := origin + dir * ((float(i) + 0.5) / float(steps) * length)
			var blocked := false
			for hole in holes:
				var gate := hole as Vector3
				if Vector2(center.x - gate.x, center.z - gate.y).length() < gate.z + 0.2:
					blocked = true
					break
			if blocked:
				continue
			if _hedge_gap(center):
				continue
			var lift := sin(center.x * 0.85 + center.z * 0.7) * 0.42 * scale
			for point in shell:
				var flank := point.x
				if absf(flank) < 0.04:
					flank = 0.16 if _rng.randf() > 0.5 else -0.16
				var outward := side * signf(flank)
				var crown := absf(point.x) < 0.04
				var poke := _rng.randf_range(0.05, 0.2)
				var at := center + side * (point.x * width) + outward * poke
				at.y = point.y * scale + lift + _rng.randf_range(-0.03, 0.07)
				var normal := (outward * (0.28 if crown else 0.82) + Vector3.UP * (0.95 if crown else 0.4)).normalized()
				var x_axis := dir.cross(normal).normalized()
				var y_axis := normal.cross(x_axis).normalized()
				var basis := Basis(x_axis, y_axis, normal).rotated(normal, _rng.randf_range(-0.8, 0.8))
				var scale_leaf := _rng.randf_range(0.75, 1.4)
				basis = basis.scaled(Vector3.ONE * scale_leaf)
				var tint := Color("#1f5528").lerp(Color("#c6d96a"), _rng.randf() * 0.55)
				points.append(Transform3D(basis, at))
				colors.append(tint)
				var crossed := basis.rotated(normal, 1.15).scaled(Vector3(0.82, 0.82, 0.82))
				points.append(Transform3D(crossed, at + outward * 0.04))
				colors.append(tint.darkened(0.08))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/leaf_card.gdshader")
	material.set_shader_parameter("tex", load("res://assets/third_party/kenney/foliage-pack/PNG/Default size/Leaves/foliagePack_leaves_003.png"))
	material.set_shader_parameter("tint", Color("#3d7a34"))
	_multimesh(parent, quad, points, colors, material, "HedgeLeaves", false)

func _room_cover(parent: Node3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.48, 0.3)
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	while points.size() < 1500 and tries < 6000:
		tries += 1
		var x := _rng.randf_range(-8.2, 3.5)
		var z := _rng.randf_range(-6.2, 2.9)
		if GardenLayout.in_plots(x, z, 0.05) or GardenLayout.on_path(x, z):
			continue
		if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS:
			continue
		var y := GardenLayout.height_at(x, z) + 0.025
		var basis := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
		basis = basis.rotated(Vector3.UP, _rng.randf() * TAU)
		basis = basis.rotated(basis.x, _rng.randf_range(-0.55, 0.55))
		basis = basis.scaled(Vector3.ONE * _rng.randf_range(0.55, 1.2))
		points.append(Transform3D(basis, Vector3(x, y, z)))
		colors.append(Color("#6a8f3a").lerp(Color("#c4a15a"), _rng.randf() * 0.35))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/leaf_card.gdshader")
	material.set_shader_parameter("tex", load("res://assets/third_party/kenney/foliage-pack/PNG/Default size/Leaves/foliagePack_leaves_007.png"))
	material.set_shader_parameter("tint", Color("#5c7a32"))
	_multimesh(parent, quad, points, colors, material, "RoomCover", false)

func _hedge_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/hedge.gdshader")
	return material

func _hedge_clumps(parent: Node3D) -> void:
	var mesh := _hedge_tuft()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var segments: Array[Dictionary] = [
		{"a": Vector3(-13.6, 0, -9.9), "b": Vector3(12.8, 0, -9.9), "h": 1.15, "gate": Vector2(0.0, -9.9), "gate_r": 3.1},
		{"a": Vector3(12.8, 0, -9.9), "b": Vector3(12.8, 0, 7.9), "h": 1.15},
		{"a": Vector3(12.8, 0, 7.9), "b": Vector3(-13.6, 0, 7.9), "h": 1.15},
		{"a": Vector3(-13.6, 0, 7.9), "b": Vector3(-13.6, 0, -9.9), "h": 1.15},
		{"a": Vector3(-8.55, 0, -6.55), "b": Vector3(3.85, 0, -6.55), "h": 0.72, "gate": Vector2(-2.35, -6.55), "gate_r": 1.35},
		{"a": Vector3(3.85, 0, -6.55), "b": Vector3(3.85, 0, 3.2), "h": 0.72, "gate": Vector2(3.85, -2.5), "gate_r": 1.35},
		{"a": Vector3(3.85, 0, 3.2), "b": Vector3(-8.55, 0, 3.2), "h": 0.72, "gate": Vector2(-3.4, 3.2), "gate_r": 2.4},
		{"a": Vector3(-8.55, 0, 3.2), "b": Vector3(-8.55, 0, -6.55), "h": 0.72},
	]
	for seg in segments:
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		var height: float = seg["h"]
		var span := a.distance_to(b)
		var count := maxi(int(span / 0.46), 1)
		var dir := (b - a) / span if span > 0.2 else Vector3.FORWARD
		var side := Vector3(-dir.z, 0.0, dir.x)
		for i in count:
			var center := a.lerp(b, float(i) / float(count))
			if seg.has("gate"):
				var gate: Vector2 = seg["gate"]
				if Vector2(center.x, center.z).distance_to(gate) < float(seg["gate_r"]):
					continue
			if _hedge_gap(center):
				continue
			var scale := _rng.randf_range(1.15, 1.9)
			var at := center + side * _rng.randf_range(-0.32, 0.32)
			at.y = height * _rng.randf_range(1.05, 1.45)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.35, 0.2), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25))).scaled(Vector3.ONE * scale)
			points.append(Transform3D(basis, at))
			colors.append(Color("#1e5a2c").lerp(Color("#d2e06a"), _rng.randf()))
			customs.append(Color(_rng.randf(), 0.0, 0.0, 1.0))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "HedgeClumps", true, customs)

func _hedge_tuft() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fans: Array[Vector4] = [
		Vector4(0.2, -0.55, 0.18, 0.5),
		Vector4(1.15, 0.2, 0.14, 0.36),
		Vector4(2.05, -0.3, 0.2, 0.54),
		Vector4(2.9, 0.4, 0.13, 0.34),
		Vector4(4.1, -0.12, 0.17, 0.46),
		Vector4(5.2, 0.48, 0.12, 0.3),
	]
	for fan in fans:
		_tuft_leaf(tool, fan.x, fan.y, fan.z, fan.w)
	tool.generate_normals()
	return tool.commit()

func _tuft_leaf(tool: SurfaceTool, yaw: float, pitch: float, width: float, height: float) -> void:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var a := basis * Vector3(-width, 0.02, 0.0)
	var b := basis * Vector3(width, 0.02, 0.0)
	var rib := basis * Vector3(0.0, height * 0.48, width * 0.25)
	var tip := basis * Vector3(0.0, height, 0.0)
	var n := (b - a).cross(tip - a)
	if n.length() < 0.0001:
		n = Vector3.UP
	n = n.normalized()
	_leaf_tri(tool, a, b, rib, n, Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0.45))
	_leaf_tri(tool, a, rib, tip, n, Vector2(0, 1), Vector2(0.5, 0.45), Vector2(0.5, 0))
	_leaf_tri(tool, b, tip, rib, n, Vector2(1, 1), Vector2(0.5, 0), Vector2(0.5, 0.45))
	var back := -n
	_leaf_tri(tool, b, a, rib, back, Vector2(1, 1), Vector2(0, 1), Vector2(0.5, 0.45))
	_leaf_tri(tool, rib, a, tip, back, Vector2(0.5, 0.45), Vector2(0, 1), Vector2(0.5, 0))
	_leaf_tri(tool, rib, tip, b, back, Vector2(0.5, 0.45), Vector2(0.5, 0), Vector2(1, 1))

func _hedge_fringe(parent: Node3D) -> void:
	var mesh := _hedge_leaf_card()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var segments: Array[Dictionary] = [
		{"a": Vector3(-13.6, 0, -9.9), "b": Vector3(12.8, 0, -9.9), "h": 1.45, "gate": Vector2(0.0, -9.9), "gate_r": 3.1},
		{"a": Vector3(12.8, 0, -9.9), "b": Vector3(12.8, 0, 7.9), "h": 1.45},
		{"a": Vector3(12.8, 0, 7.9), "b": Vector3(-13.6, 0, 7.9), "h": 1.45},
		{"a": Vector3(-13.6, 0, 7.9), "b": Vector3(-13.6, 0, -9.9), "h": 1.45},
		{"a": Vector3(-8.55, 0, -6.55), "b": Vector3(3.85, 0, -6.55), "h": 0.95, "gate": Vector2(-2.35, -6.55), "gate_r": 1.35},
		{"a": Vector3(3.85, 0, -6.55), "b": Vector3(3.85, 0, 3.2), "h": 0.95, "gate": Vector2(3.85, -2.5), "gate_r": 1.35},
		{"a": Vector3(3.85, 0, 3.2), "b": Vector3(-8.55, 0, 3.2), "h": 0.95, "gate": Vector2(-3.4, 3.2), "gate_r": 2.4},
		{"a": Vector3(-8.55, 0, 3.2), "b": Vector3(-8.55, 0, -6.55), "h": 0.95},
	]
	for seg in segments:
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		var height: float = seg["h"]
		var span := a.distance_to(b)
		var count := maxi(int(span / 0.26), 1)
		var dir := (b - a) / span if span > 0.2 else Vector3.FORWARD
		var side := Vector3(-dir.z, 0.0, dir.x)
		for i in count:
			var center := a.lerp(b, float(i) / float(count))
			if seg.has("gate"):
				var gate: Vector2 = seg["gate"]
				if Vector2(center.x, center.z).distance_to(gate) < float(seg["gate_r"]):
					continue
			if _hedge_gap(center):
				continue
			for face in 2:
				var sign := -1.0 if face == 0 else 1.0
				var at := center + side * sign * _rng.randf_range(0.02, 0.38)
				at.y = height * _rng.randf_range(0.08, 1.18)
				var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.6, 0.5), _rng.randf() * TAU, _rng.randf_range(-0.45, 0.45)))
				var scale := _rng.randf_range(1.35, 2.35)
				points.append(Transform3D(basis.scaled(Vector3(scale, scale * _rng.randf_range(0.9, 1.6), scale)), at))
				colors.append(Color("#1c5c2c").lerp(Color("#d5e07a"), _rng.randf() * 0.85))
				customs.append(Color(_rng.randf(), 0.0, 0.0, 1.0))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "HedgeFringe", true, customs)

func _hedge_coat(parent: Node3D) -> void:
	var mesh := _hedge_leaf_card()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var balls: Array[Transform3D] = []
	var ball_colors: Array[Color] = []
	var runs: Array = [
		[Vector3(-13.6, 0, -9.9), Vector3(26.4, 0, 0), 1.22, [Vector3(0.0, -9.9, 3.2)]],
		[Vector3(12.8, 0, -9.9), Vector3(0, 0, 17.8), 1.22, []],
		[Vector3(12.8, 0, 7.9), Vector3(-26.4, 0, 0), 1.22, []],
		[Vector3(-13.6, 0, 7.9), Vector3(0, 0, -17.8), 1.22, []],
		[Vector3(-8.55, 0, -6.55), Vector3(12.4, 0, 0), 0.78, [Vector3(-2.35, -6.55, 1.45)]],
		[Vector3(3.85, 0, -6.55), Vector3(0, 0, 9.75), 0.78, [Vector3(3.85, -2.5, 1.45)]],
		[Vector3(3.85, 0, 3.2), Vector3(-12.4, 0, 0), 0.78, [Vector3(-4.55, 3.2, 1.4), Vector3(-2.35, 3.2, 1.2)]],
		[Vector3(-8.55, 0, 3.2), Vector3(0, 0, -9.75), 0.78, []],
	]
	for run in runs:
		var origin: Vector3 = run[0]
		var along: Vector3 = run[1]
		var scale: float = run[2]
		var holes: Array = run[3]
		var length := along.length()
		var dir := along / length
		var side := Vector3(-dir.z, 0.0, dir.x)
		var steps := int(length / 0.42)
		for i in steps:
			var center := origin + dir * ((float(i) + 0.5) / float(steps) * length)
			var blocked := false
			for hole in holes:
				var gate := hole as Vector3
				if Vector2(center.x - gate.x, center.z - gate.y).length() < gate.z:
					blocked = true
					break
			if blocked:
				continue
			if _hedge_gap(center):
				continue
			for n in 2:
				var side_sign := -1.0 if n == 0 else 1.0
				for layer in 3:
					var outward := side * side_sign
					var at := center + outward * _rng.randf_range(0.28, 0.85)
					at.y = (0.22 + float(layer) * 0.42) * scale + _rng.randf_range(-0.04, 0.1)
					var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.35, 0.7), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4)))
					var size := _rng.randf_range(1.6, 2.8) * (1.2 if layer == 2 else 1.0)
					points.append(Transform3D(basis.scaled(Vector3(size, size * _rng.randf_range(0.9, 1.45), size)), at))
					var lift := float(layer) / 2.0
					colors.append(Color("#16321c").lerp(Color("#7aaa44"), lift * 0.55 + _rng.randf() * 0.35))
					customs.append(Color(_rng.randf(), 0.0, 0.0, 1.0))
					if layer < 2:
						var ball_at := center + outward * _rng.randf_range(0.15, 0.55)
						ball_at.y = at.y * 0.92
						var ball_scale := _rng.randf_range(0.7, 1.25)
						balls.append(Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3(ball_scale, ball_scale * _rng.randf_range(0.75, 1.15), ball_scale)), ball_at))
						ball_colors.append(Color("#102616").lerp(Color("#3f7a32"), _rng.randf() * 0.7))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "HedgeCoat", false, customs)
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.28
	ball_mesh.height = 0.4
	ball_mesh.radial_segments = 7
	ball_mesh.rings = 4
	_multimesh(parent, ball_mesh, balls, ball_colors, _foliage_material(), "HedgePuffs", false)

func _hedge_bulges(parent: Node3D) -> void:
	var mesh := _hedge_tuft()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 14036
	var segments: Array[Dictionary] = [
		{"a": Vector3(-13.6, 0, -9.9), "b": Vector3(12.8, 0, -9.9), "h": 1.15, "gate": Vector2(0.0, -9.9), "gate_r": 3.1},
		{"a": Vector3(12.8, 0, -9.9), "b": Vector3(12.8, 0, 7.9), "h": 1.15},
		{"a": Vector3(12.8, 0, 7.9), "b": Vector3(-13.6, 0, 7.9), "h": 1.15},
		{"a": Vector3(-13.6, 0, 7.9), "b": Vector3(-13.6, 0, -9.9), "h": 1.15},
		{"a": Vector3(-8.55, 0, -6.55), "b": Vector3(3.85, 0, -6.55), "h": 0.72, "gate": Vector2(-2.35, -6.55), "gate_r": 1.35},
		{"a": Vector3(3.85, 0, -6.55), "b": Vector3(3.85, 0, 3.2), "h": 0.72, "gate": Vector2(3.85, -2.5), "gate_r": 1.35},
		{"a": Vector3(3.85, 0, 3.2), "b": Vector3(-8.55, 0, 3.2), "h": 0.72, "gate": Vector2(-3.4, 3.2), "gate_r": 2.4},
		{"a": Vector3(-8.55, 0, 3.2), "b": Vector3(-8.55, 0, -6.55), "h": 0.72},
	]
	for seg in segments:
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		var height: float = seg["h"]
		var span := a.distance_to(b)
		if span < 0.2:
			continue
		var dir := (b - a) / span
		var side := Vector3(-dir.z, 0.0, dir.x)
		var count := maxi(int(span / 1.7), 1)
		for i in count:
			if rng.randf() > 0.62:
				continue
			var center := a.lerp(b, (float(i) + 0.5) / float(count))
			if seg.has("gate"):
				var gate: Vector2 = seg["gate"]
				if Vector2(center.x, center.z).distance_to(gate) < float(seg["gate_r"]) + 0.4:
					continue
			if _hedge_gap(center):
				continue
			for n in 8:
				var sign := -1.0 if n < 4 else 1.0
				var at := center + side * sign * rng.randf_range(0.25, 1.15) + dir * rng.randf_range(-0.45, 0.45)
				at.y = height * rng.randf_range(0.2, 1.45)
				var basis := Basis.from_euler(Vector3(rng.randf_range(-0.7, 0.45), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
				var scale := rng.randf_range(1.8, 3.4)
				points.append(Transform3D(basis.scaled(Vector3(scale, scale * rng.randf_range(0.75, 1.45), scale)), at))
				colors.append(Color("#174d28").lerp(Color("#e2ee86"), rng.randf()))
				customs.append(Color(rng.randf(), 0.0, 0.0, 1.0))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "HedgeBulges", false, customs)

func _hedge_volume(parent: Node3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.32)
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 14091
	var segments: Array[Dictionary] = [
		{"a": Vector3(-13.6, 0, -9.9), "b": Vector3(12.8, 0, -9.9), "h": 1.22, "gate": Vector2(0.0, -9.9), "gate_r": 3.1},
		{"a": Vector3(12.8, 0, -9.9), "b": Vector3(12.8, 0, 7.9), "h": 1.22},
		{"a": Vector3(12.8, 0, 7.9), "b": Vector3(-13.6, 0, 7.9), "h": 1.22},
		{"a": Vector3(-13.6, 0, 7.9), "b": Vector3(-13.6, 0, -9.9), "h": 1.22},
		{"a": Vector3(-8.55, 0, -6.55), "b": Vector3(3.85, 0, -6.55), "h": 0.78, "gate": Vector2(-2.35, -6.55), "gate_r": 1.35},
		{"a": Vector3(3.85, 0, -6.55), "b": Vector3(3.85, 0, 3.2), "h": 0.78, "gate": Vector2(3.85, -2.5), "gate_r": 1.35},
		{"a": Vector3(3.85, 0, 3.2), "b": Vector3(-8.55, 0, 3.2), "h": 0.78, "gate": Vector2(-3.4, 3.2), "gate_r": 2.4},
		{"a": Vector3(-8.55, 0, 3.2), "b": Vector3(-8.55, 0, -6.55), "h": 0.78},
	]
	for seg in segments:
		var a: Vector3 = seg["a"]
		var b: Vector3 = seg["b"]
		var height: float = seg["h"]
		var span := a.distance_to(b)
		if span < 0.2:
			continue
		var dir := (b - a) / span
		var side := Vector3(-dir.z, 0.0, dir.x)
		var steps := int(span / 0.34)
		for i in steps:
			var center := a.lerp(b, (float(i) + 0.5) / float(steps))
			if _hedge_gap(center):
				continue
			if seg.has("gate"):
				var gate: Vector2 = seg["gate"]
				if Vector2(center.x, center.z).distance_to(gate) < float(seg["gate_r"]):
					continue
			var knot := absf(sin(center.x * 0.48 + center.z * 0.36))
			for n in 2:
				var sign := -1.0 if n == 0 else 1.0
				var outward := side * sign
				for layer in 3:
					var at := center + outward * rng.randf_range(0.35, 0.55 + knot * 0.9)
					at += dir * rng.randf_range(-0.12, 0.12)
					at.y = (0.18 + float(layer) * 0.42) * height * lerpf(0.7, 1.15, knot)
					var normal := (outward * 0.85 + Vector3.UP * 0.25).normalized()
					var x_axis := dir.cross(normal).normalized()
					var y_axis := normal.cross(x_axis).normalized()
					var basis := Basis(x_axis, y_axis, normal)
					basis = basis.rotated(normal, rng.randf_range(-0.8, 0.8))
					var size := rng.randf_range(0.8, 1.45)
					points.append(Transform3D(basis.scaled(Vector3(size, size * rng.randf_range(0.8, 1.3), 1.0)), at))
					colors.append(Color("#1d5228").lerp(Color("#c5dc62"), knot * 0.45 + rng.randf() * 0.35))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/leaf_card.gdshader")
	material.set_shader_parameter("tex", load("res://assets/third_party/kenney/foliage-pack/PNG/Default size/Leaves/foliagePack_leaves_003.png"))
	material.set_shader_parameter("tint", Color("#3a7a32"))
	_multimesh(parent, quad, points, colors, material, "HedgeVolume", false)

func _hedge_leaf_card() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_leaf_plane_sized(tool, 0.0, 0.16, 0.5)
	_leaf_plane_sized(tool, 0.85, 0.12, 0.38)
	tool.generate_normals()
	return tool.commit()

func _leaf_card() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_leaf_plane(tool, 0.0)
	_leaf_plane(tool, 1.05)
	_leaf_plane(tool, 2.1)
	tool.generate_normals()
	return tool.commit()

func _leaf_plane(tool: SurfaceTool, yaw: float) -> void:
	_leaf_plane_sized(tool, yaw, 0.07, 0.22)

func _leaf_plane_sized(tool: SurfaceTool, yaw: float, width: float, height: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var a := basis * Vector3(-width, 0.0, 0.0)
	var b := basis * Vector3(width, 0.0, 0.0)
	var c := basis * Vector3(width * 0.28, height, 0.0)
	var d := basis * Vector3(-width * 0.28, height, 0.0)
	var normal := basis * Vector3(0, 0, 1)
	_leaf_tri(tool, a, b, c, normal, Vector2(0, 1), Vector2(1, 1), Vector2(0.65, 0))
	_leaf_tri(tool, a, c, d, normal, Vector2(0, 1), Vector2(0.65, 0), Vector2(0.35, 0))

func _leaf_tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	tool.set_normal(normal)
	tool.set_uv(ua)
	tool.add_vertex(a)
	tool.set_normal(normal)
	tool.set_uv(ub)
	tool.add_vertex(b)
	tool.set_normal(normal)
	tool.set_uv(uc)
	tool.add_vertex(c)

func _scatter_grass(parent: Node3D) -> void:
	var mesh := _blade()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var tries := 0
	while points.size() < 3600 and tries < 12000:
		tries += 1
		var x := _rng.randf_range(-18.0, 18.0)
		var z := _rng.randf_range(-16.0, 14.0)
		if GardenLayout.in_plots(x, z, 0.05):
			continue
		if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS - 0.2:
			continue
		if GardenLayout.on_path(x, z):
			continue
		var y := GardenLayout.height_at(x, z)
		if y < -0.12:
			continue
		var scale := _rng.randf_range(0.55, 1.35)
		var basis := Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3(scale, scale * _rng.randf_range(0.8, 1.5), scale))
		points.append(Transform3D(basis, Vector3(x, y, z)))
		var tint := Color("#6fa344").lerp(Color("#d5e07a"), _rng.randf() * 0.65)
		if _rng.randf() > 0.82:
			tint = Color("#3e7a34")
		colors.append(tint)
		customs.append(Color(_rng.randf(), 0.2, 0, 1))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "Grass", false, customs)

func _flowers(parent: Node3D) -> void:
	var mesh := _flower()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var regions := [
		{"at": Vector2(-10.5, -2.0), "radius": 2.4, "color": Color("#f08aa4")},
		{"at": Vector2(-9.0, 2.2), "radius": 1.6, "color": Color("#f4e3b0")},
		{"at": Vector2(3.2, -7.2), "radius": 2.2, "color": Color("#f0a04a")},
		{"at": Vector2(1.2, -7.6), "radius": 1.5, "color": Color("#e7e2f4")},
		{"at": Vector2(6.2, 1.5), "radius": 1.8, "color": Color("#c9a0e8")},
		{"at": Vector2(5.4, -5.4), "radius": 1.4, "color": Color("#f2d36b")},
		{"at": Vector2(-4.0, -7.8), "radius": 1.8, "color": Color("#ef7f72")},
		{"at": Vector2(10.2, 3.4), "radius": 1.6, "color": Color("#f7f0d8")},
		{"at": Vector2(-8.05, -2.2), "radius": 0.75, "color": Color("#f4b4c4")},
		{"at": Vector2(-4.6, -6.15), "radius": 0.7, "color": Color("#f7e7a8")},
		{"at": Vector2(3.15, -3.4), "radius": 0.75, "color": Color("#f0a06a")},
		{"at": Vector2(-5.2, 2.7), "radius": 0.7, "color": Color("#efe6ff")},
	]
	for region in regions:
		var center: Vector2 = region["at"]
		var palette: Color = region["color"]
		for i in 70:
			var angle := _rng.randf() * TAU
			var dist := sqrt(_rng.randf()) * float(region["radius"])
			var x := center.x + cos(angle) * dist
			var z := center.y + sin(angle) * dist
			if GardenLayout.in_plots(x, z, 0.0):
				continue
			if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS:
				continue
			var y := GardenLayout.height_at(x, z)
			var scale := _rng.randf_range(1.4, 2.6)
			var basis := Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3.ONE * scale)
			points.append(Transform3D(basis, Vector3(x, y + 0.02, z)))
			colors.append(palette.lerp(Color("#fff8ea"), _rng.randf() * 0.35))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "Flowers", false)

func _flower_rows(parent: Node3D) -> void:
	var mesh := _row_bloom()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var bands: Array[Dictionary] = [
		{"rect": Rect2(-11.6, -7.7, 23.2, 0.85), "color": Color("#e56b8a")},
		{"rect": Rect2(-11.6, -6.95, 23.2, 0.42), "color": Color("#f2d36b")},
		{"rect": Rect2(-12.5, -6.2, 1.15, 10.6), "color": Color("#f08aa4")},
		{"rect": Rect2(4.15, -7.4, 0.7, 4.6), "color": Color("#e39a52")},
		{"rect": Rect2(4.15, -1.6, 0.7, 4.2), "color": Color("#c9a0e8")},
		{"rect": Rect2(-12.2, 5.9, 5.6, 1.15), "color": Color("#f7f0d8")},
		{"rect": Rect2(-2.6, 5.9, 13.6, 1.15), "color": Color("#ef7f72")},
	]
	for band in bands:
		var rect: Rect2 = band["rect"]
		var palette: Color = band["color"]
		var cols := maxi(int(rect.size.x / 0.42), 1)
		var rows := maxi(int(rect.size.y / 0.42), 1)
		for iz in rows:
			for ix in cols:
				var x := rect.position.x + (float(ix) + 0.5) * rect.size.x / float(cols)
				var z := rect.position.y + (float(iz) + 0.5) * rect.size.y / float(rows)
				x += _rng.randf_range(-0.06, 0.06)
				z += _rng.randf_range(-0.06, 0.06)
				if GardenLayout.in_plots(x, z, 0.2):
					continue
				if GardenLayout.on_path(x, z):
					continue
				if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.4:
					continue
				var y := GardenLayout.height_at(x, z)
				var scale := _rng.randf_range(1.7, 2.5)
				var basis := Basis.from_euler(Vector3(0, _rng.randf() * TAU, _rng.randf_range(-0.08, 0.08))).scaled(Vector3(scale, scale, scale))
				points.append(Transform3D(basis, Vector3(x, y, z)))
				colors.append(palette.lerp(Color("#fff6ea"), _rng.randf() * 0.18))
	_multimesh(parent, mesh, points, colors, _bloom_material(), "FlowerRows", false)

func _row_bloom() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_h := 0.62
	var stem_w := 0.025
	var stem := [
		Vector3(-stem_w, 0.0, 0.0),
		Vector3(stem_w, 0.0, 0.0),
		Vector3(stem_w, stem_h, 0.0),
		Vector3(-stem_w, 0.0, 0.0),
		Vector3(stem_w, stem_h, 0.0),
		Vector3(-stem_w, stem_h, 0.0),
	]
	for point in stem:
		tool.set_color(Color("#d7e7b0"))
		tool.add_vertex(point)
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var tip := Vector3(cos(angle) * 0.2, stem_h + 0.05, sin(angle) * 0.2)
		var left := Vector3(cos(angle - 0.45) * 0.08, stem_h, sin(angle - 0.45) * 0.08)
		var right := Vector3(cos(angle + 0.45) * 0.08, stem_h, sin(angle + 0.45) * 0.08)
		var heart := Vector3(0.0, stem_h + 0.02, 0.0)
		for point in [heart, left, tip, heart, tip, right]:
			tool.set_color(Color.WHITE)
			tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()

func _bloom_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.62
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _shrubs(parent: Node3D) -> void:
	var spots: Array[Vector2] = [
		Vector2(-11.2, -3.4),
		Vector2(-10.2, 3.6),
		Vector2(4.6, -8.2),
		Vector2(7.4, 2.6),
		Vector2(9.6, -6.2),
		Vector2(-2.6, -8.6),
	]
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.42
	cone.height = 0.7
	cone.radial_segments = 7
	for spot in spots:
		if GardenLayout.in_plots(spot.x, spot.y, 0.3):
			continue
		var y := GardenLayout.height_at(spot.x, spot.y)
		var node := MeshInstance3D.new()
		node.mesh = cone
		node.material_override = _standard(Color("#2f6d34"), 0.8)
		node.position = Vector3(spot.x, y + 0.32, spot.y)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)

func _trees(parent: Node3D) -> void:
	# Backdrop and side frame only. The south approach stays open for the garden camera.
	var spots: Array[Vector2] = [
		Vector2(-17.4, -11.2),
		Vector2(-18.6, -3.4),
		Vector2(-17.2, 4.2),
		Vector2(-16.0, 11.2),
		Vector2(16.6, -10.6),
		Vector2(18.0, -2.2),
		Vector2(17.2, 5.0),
		Vector2(15.4, 11.4),
		Vector2(-9.5, 13.0),
		Vector2(-2.2, 13.6),
		Vector2(5.2, 13.1),
		Vector2(11.4, 12.2),
		Vector2(-14.8, -14.4),
		Vector2(13.8, -14.2),
	]
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.08
	trunk_mesh.bottom_radius = 0.15
	trunk_mesh.height = 1.7
	trunk_mesh.radial_segments = 7
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.015
	cone_mesh.bottom_radius = 1.05
	cone_mesh.height = 1.5
	cone_mesh.radial_segments = 8
	var index := 0
	for spot in spots:
		var y := GardenLayout.height_at(spot.x, spot.y)
		var height := 1.7 + float(index % 4) * 0.32
		var trunk := MeshInstance3D.new()
		trunk.mesh = trunk_mesh
		trunk.material_override = _standard(Color("#6a4530").lerp(Color("#8a5a3c"), float(index % 3) / 3.0), 0.9)
		trunk.position = Vector3(spot.x, y + height * 0.45, spot.y)
		trunk.scale = Vector3(1, height / 1.7, 1)
		trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(trunk)
		for layer in 3:
			var cone := MeshInstance3D.new()
			cone.mesh = cone_mesh
			var leaf := Color("#1f5a2c").lerp(Color("#9bc45a"), 0.18 + float(layer) * 0.22)
			cone.material_override = _standard(leaf, 0.8)
			var scale := 1.05 - float(layer) * 0.22
			cone.position = Vector3(spot.x, y + height * 0.62 + float(layer) * 0.62, spot.y)
			cone.scale = Vector3(scale, 0.78, scale)
			cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			parent.add_child(cone)
		index += 1

func _willow(parent: Node3D) -> void:
	var root := Vector3(5.55, 0.0, -4.35)
	var y := GardenLayout.height_at(root.x, root.z)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.1
	trunk.bottom_radius = 0.22
	trunk.height = 2.3
	trunk.radial_segments = 8
	var trunk_node := MeshInstance3D.new()
	trunk_node.mesh = trunk
	trunk_node.material_override = _standard(Color("#5c4030"), 0.86)
	trunk_node.position = root + Vector3(0, y + 1.15, 0)
	parent.add_child(trunk_node)
	var strand := CapsuleMesh.new()
	strand.radius = 0.035
	strand.height = 1.5
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in 72:
		var angle := TAU * float(i) / 72.0
		var hang := 1.15 + _rng.randf_range(0.0, 0.7)
		var radial := 0.7 + _rng.randf() * 0.55
		var at := root + Vector3(cos(angle) * radial, y + 2.15 - hang * 0.45, sin(angle) * radial)
		var basis := Basis.from_euler(Vector3(0.9, angle, 0)).scaled(Vector3(1, hang, 1))
		points.append(Transform3D(basis, at))
		colors.append(Color("#3f8a3c").lerp(Color("#d5e48a"), _rng.randf() * 0.4))
	_multimesh(parent, strand, points, colors, _foliage_material(), "Willow", true)

func _groundcover(parent: Node3D) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 4
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in 900:
		var x := _rng.randf_range(-16.0, 16.0)
		var z := _rng.randf_range(-14.0, 12.0)
		if GardenLayout.in_plots(x, z, 0.0) or GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS:
			continue
		var y := GardenLayout.height_at(x, z)
		var scale := _rng.randf_range(0.4, 1.1)
		points.append(Transform3D(Basis().scaled(Vector3(scale, scale * 0.45, scale)), Vector3(x, y + 0.02, z)))
		colors.append(Color("#2f6a30").lerp(Color("#8aaa44"), _rng.randf()))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "GroundCover", false)

func _lawn_tufts(parent: Node3D) -> void:
	var mesh := _leaf_card()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var tries := 0
	while points.size() < 640 and tries < 4000:
		tries += 1
		var x := _rng.randf_range(-12.2, 12.2)
		var z := _rng.randf_range(-9.2, 7.2)
		if GardenLayout.in_plots(x, z, 0.35):
			continue
		if GardenLayout.on_path(x, z):
			continue
		if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.35:
			continue
		var y := GardenLayout.height_at(x, z)
		if y < -0.05:
			continue
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.15, 0.2), _rng.randf() * TAU, 0.0))
		var scale := _rng.randf_range(1.7, 3.2)
		points.append(Transform3D(basis.scaled(Vector3(scale, scale * _rng.randf_range(0.85, 1.5), scale)), Vector3(x, y, z)))
		colors.append(Color("#2a6b34").lerp(Color("#d7e48a"), _rng.randf() * 0.7))
		customs.append(Color(_rng.randf(), 0.0, 0.0, 1.0))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "LawnTufts", false, customs)

func _lawn_meadow(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 14133
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var blooms: Array[Transform3D] = []
	var bloom_colors: Array[Color] = []
	var palette: Array[Color] = [Color("#e56b8a"), Color("#f2d36b"), Color("#f7f0d8"), Color("#c9a0e8"), Color("#ef7f72")]
	var tries := 0
	while points.size() < 2200 and tries < 8000:
		tries += 1
		var x := rng.randf_range(-11.6, 11.4)
		var z := rng.randf_range(-6.2, 5.5)
		if x > -8.3 and x < 3.6 and z > -6.3 and z < 2.95:
			continue
		if GardenLayout.in_plots(x, z, 0.2) or GardenLayout.on_path(x, z):
			continue
		if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.45:
			continue
		var y := GardenLayout.height_at(x, z)
		if y < -0.08:
			continue
		var basis := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0))
		var scale := rng.randf_range(0.75, 1.5)
		points.append(Transform3D(basis.scaled(Vector3(scale, scale * rng.randf_range(0.85, 1.55), scale)), Vector3(x, y, z)))
		colors.append(Color("#3a7a34").lerp(Color("#d5e48a"), rng.randf() * 0.55))
		customs.append(Color(rng.randf(), 0.15, 0.0, 1.0))
		if blooms.size() < 480 and rng.randf() > 0.8:
			var tint: Color = palette[rng.randi_range(0, palette.size() - 1)]
			var bscale := rng.randf_range(0.65, 1.15)
			blooms.append(Transform3D(basis.scaled(Vector3.ONE * bscale), Vector3(x, y, z)))
			bloom_colors.append(tint)
	_multimesh(parent, _blade(), points, colors, _foliage_material(), "LawnMeadow", false, customs)
	_multimesh(parent, _row_bloom(), blooms, bloom_colors, _bloom_material(), "LawnBlooms", false)

func _room_clumps(parent: Node3D) -> void:
	var mesh := _leaf_card()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var patches: Array[Vector2] = [
		Vector2(-6.4, -3.6),
		Vector2(-6.8, 1.5),
		Vector2(1.6, 1.2),
		Vector2(2.1, -4.4),
		Vector2(-1.0, 2.2),
		Vector2(0.6, -5.6),
	]
	for patch in patches:
		for i in 34:
			var x := patch.x + _rng.randf_range(-1.05, 1.05)
			var z := patch.y + _rng.randf_range(-0.85, 0.85)
			if GardenLayout.in_plots(x, z, 0.15) or GardenLayout.on_path(x, z):
				continue
			if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS:
				continue
			var y := GardenLayout.height_at(x, z)
			var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.2, 0.35), _rng.randf() * TAU, _rng.randf_range(-0.2, 0.2)))
			var size := _rng.randf_range(2.2, 3.8)
			points.append(Transform3D(basis.scaled(Vector3(size, size * _rng.randf_range(0.7, 1.35), size)), Vector3(x, y, z)))
			colors.append(Color("#1a4c28").lerp(Color("#8fb85a"), _rng.randf() * 0.65))
			customs.append(Color(_rng.randf(), 0.0, 0.0, 1.0))
	_multimesh(parent, mesh, points, colors, _foliage_material(), "RoomClumps", false, customs)

func _room_carpet(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.36)
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	while points.size() < 2400 and tries < 9000:
		tries += 1
		var x := rng.randf_range(-8.3, 3.6)
		var z := rng.randf_range(-6.3, 3.0)
		if GardenLayout.in_plots(x, z, 0.08) or GardenLayout.on_path(x, z):
			continue
		if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS:
			continue
		var y := GardenLayout.height_at(x, z) + 0.015
		var basis := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
		basis = basis.rotated(Vector3.UP, rng.randf() * TAU)
		basis = basis.rotated(basis.x, rng.randf_range(1.2, 1.5))
		basis = basis.scaled(Vector3.ONE * rng.randf_range(0.75, 1.55))
		points.append(Transform3D(basis, Vector3(x, y, z)))
		colors.append(Color("#3f6b2e").lerp(Color("#d2df78"), rng.randf() * 0.75))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/leaf_card.gdshader")
	material.set_shader_parameter("tex", load("res://assets/third_party/kenney/foliage-pack/PNG/Default size/Leaves/foliagePack_leaves_007.png"))
	material.set_shader_parameter("tint", Color("#6d8f3a"))
	_multimesh(parent, quad, points, colors, material, "RoomCarpet", false)

func _room_beds(parent: Node3D) -> void:
	var mesh := _row_bloom()
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	var beds: Array[Dictionary] = [
		{"rect": Rect2(-7.15, -1.9, 4.35, 0.95), "color": Color("#e56b8a")},
		{"rect": Rect2(-1.55, -1.9, 4.15, 0.95), "color": Color("#f4e2a8")},
		{"rect": Rect2(-7.15, 2.7, 4.2, 0.7), "color": Color("#f7f0d8")},
		{"rect": Rect2(-1.5, 2.7, 3.6, 0.7), "color": Color("#ef7f4a")},
		{"rect": Rect2(-8.15, -5.7, 1.55, 2.15), "color": Color("#e56b8a")},
		{"rect": Rect2(-8.15, 0.35, 1.45, 1.85), "color": Color("#f2d36b")},
		{"rect": Rect2(1.85, -5.55, 1.45, 1.55), "color": Color("#f08aa4")},
		{"rect": Rect2(1.7, 0.55, 1.55, 1.45), "color": Color("#c9a0e8")},
		{"rect": Rect2(-5.9, -5.85, 2.4, 0.7), "color": Color("#ef7f72")},
	]
	for bed in beds:
		var rect: Rect2 = bed["rect"]
		var palette: Color = bed["color"]
		var cols := maxi(int(rect.size.x / 0.28), 1)
		var rows := maxi(int(rect.size.y / 0.28), 1)
		for iz in rows:
			for ix in cols:
				var x := rect.position.x + (float(ix) + 0.5) * rect.size.x / float(cols)
				var z := rect.position.y + (float(iz) + 0.5) * rect.size.y / float(rows)
				x += _rng.randf_range(-0.04, 0.04)
				z += _rng.randf_range(-0.04, 0.04)
				if GardenLayout.in_plots(x, z, 0.18) or GardenLayout.on_path(x, z):
					continue
				if GardenLayout.pond_distance(x, z) < GardenLayout.POND_RADIUS + 0.3:
					continue
				var y := GardenLayout.height_at(x, z)
				var scale := _rng.randf_range(1.6, 2.3)
				var basis := Basis.from_euler(Vector3(0, _rng.randf() * TAU, _rng.randf_range(-0.06, 0.06))).scaled(Vector3(scale, scale, scale))
				points.append(Transform3D(basis, Vector3(x, y, z)))
				colors.append(palette.lerp(Color("#fff6ea"), _rng.randf() * 0.2))
	_multimesh(parent, mesh, points, colors, _bloom_material(), "RoomBeds", false)

func _stones(parent: Node3D) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.22
	mesh.radial_segments = 6
	mesh.rings = 4
	var points: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in 48:
		var x := _rng.randf_range(-12.0, 10.0)
		var z := _rng.randf_range(-8.0, 6.0)
		if not GardenLayout.on_path(x, z) and _rng.randf() > 0.35:
			continue
		if GardenLayout.in_plots(x, z, 0.2):
			continue
		var y := maxf(GardenLayout.height_at(x, z), 0.02)
		var scale := Vector3(_rng.randf_range(0.4, 1.1), _rng.randf_range(0.25, 0.55), _rng.randf_range(0.4, 0.9))
		points.append(Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(scale), Vector3(x, y, z)))
		colors.append(Color("#b7aa98").lerp(Color("#8d8274"), _rng.randf()))
	_multimesh(parent, mesh, points, colors, _standard(Color.WHITE, 0.9), "Stones", false)

func _blade() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := 0.46
	var width := 0.07
	_blade_tri(tool, Vector3(-width, 0, 0), Vector3(width, 0, 0), Vector3(0, height, 0))
	_blade_tri(tool, Vector3(0, 0, -width), Vector3(0, 0, width), Vector3(0, height * 0.86, 0))
	tool.generate_normals()
	return tool.commit()

func _blade_tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.set_uv(Vector2(0, 1))
	tool.add_vertex(a)
	tool.set_uv(Vector2(1, 1))
	tool.add_vertex(b)
	tool.set_uv(Vector2(0.5, 0))
	tool.add_vertex(c)

func _flower() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var tip := Vector3(cos(angle) * 0.16, 0.08, sin(angle) * 0.16)
		var left := Vector3(cos(angle - 0.4) * 0.07, 0.02, sin(angle - 0.4) * 0.07)
		var right := Vector3(cos(angle + 0.4) * 0.07, 0.02, sin(angle + 0.4) * 0.07)
		tool.set_uv(Vector2(0.5, 0.2))
		tool.add_vertex(Vector3(0, 0.03, 0))
		tool.set_uv(Vector2(0, 1))
		tool.add_vertex(left)
		tool.set_uv(Vector2(1, 1))
		tool.add_vertex(tip)
		tool.set_uv(Vector2(0.5, 0.2))
		tool.add_vertex(Vector3(0, 0.03, 0))
		tool.set_uv(Vector2(0, 1))
		tool.add_vertex(tip)
		tool.set_uv(Vector2(1, 1))
		tool.add_vertex(right)
	tool.generate_normals()
	return tool.commit()

func _multimesh(parent: Node3D, mesh: Mesh, points: Array[Transform3D], colors: Array[Color], material: Material, node_name: String, shadows: bool, customs: Array[Color] = []) -> void:
	if points.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = not customs.is_empty()
	multi.mesh = mesh
	multi.instance_count = points.size()
	for i in points.size():
		multi.set_instance_transform(i, points[i])
		multi.set_instance_color(i, colors[i])
		if not customs.is_empty():
			multi.set_instance_custom_data(i, customs[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = material
	node.name = node_name
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

func _foliage_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/foliage.gdshader")
	return material

func _bark_material() -> StandardMaterial3D:
	return _standard(Color.WHITE, 0.9)

func _standard(color: Color, rough: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.vertex_color_use_as_albedo = true
	return material

const _PACK := "res://third_party/incoming/assetquest-stylized-garden-demo/"

func _cc0_props(parent: Node3D) -> void:
	var plants := _cutout_material(
		load(_PACK + "Textures/Plants_Atlas_1_Basecolor.png"),
		load(_PACK + "Textures/Plants_Atlas_1_Opacity.png")
	)
	var prop_tex: Texture2D = load(_PACK + "Textures/Props_Basecolor.png")
	var props := _flat_material(Color.WHITE, 0.66)
	props.albedo_texture = prop_tex
	var layout := [
		["FBX/Poppy_Single_Red.fbx", Vector3(-10.4, 0, -2.4), 1.15, 0.4],
		["FBX/Poppy_Single_Red.fbx", Vector3(-9.5, 0, -1.2), 0.95, 2.1],
		["FBX/Cornflowers_Big_Cluster_Blue.fbx", Vector3(-10.8, 0, 2.8), 1.05, 1.2],
		["FBX/Larkspur_1_Purple.fbx", Vector3(3.6, 0, -7.6), 1.1, 0.6],
		["FBX/Gerbera_1_Red.fbx", Vector3(6.6, 0, 1.8), 1.0, 2.4],
		["FBX/Giant_Sunflower_big_1.fbx", Vector3(6.8, 0, -5.6), 1.05, 0.8],
		["FBX/Flowering_Garlic_1.fbx", Vector3(-3.6, 0, -8.4), 1.0, 1.7],
		["FBX/Cosmea_Cluster_Small_1.fbx", Vector3(1.6, 0, -8.0), 1.15, 0.3],
		["FBX/Grass_Simple_small.fbx", Vector3(-2.2, 0, -8.8), 1.3, 0.5],
		["FBX/Wild_Grass_Red_small.fbx", Vector3(2.4, 0, 2.2), 1.2, 1.4],
		["FBX/Bench_1.fbx", Vector3(-1.4, 0, 3.6), 1.0, 0.2],
		["FBX/Planter_1_Terracotta.fbx", Vector3(-5.4, 0, 4.4), 1.0, 1.1],
		["FBX/Table_1.fbx", Vector3(-2.55, 0, 6.15), 0.78, 0.35],
		["FBX/Sun_Umbrella_1.fbx", Vector3(-2.7, 0, 6.35), 0.46, 0.5],
		["FBX/Poppy_Single_Red.fbx", Vector3(-11.2, 0, -3.1), 0.85, 1.4],
		["FBX/Poppy_Single_Red.fbx", Vector3(-9.2, 0, -3.3), 1.05, 2.6],
		["FBX/Cornflowers_Big_Cluster_Blue.fbx", Vector3(-11.6, 0, 1.6), 0.9, 0.7],
		["FBX/Cornflowers_Big_Cluster_Blue.fbx", Vector3(-9.6, 0, 3.8), 0.8, 2.2],
		["FBX/Larkspur_1_Purple.fbx", Vector3(4.8, 0, -8.2), 0.9, 1.5],
		["FBX/Larkspur_1_Purple.fbx", Vector3(2.4, 0, -8.6), 0.85, 0.4],
		["FBX/Gerbera_1_Red.fbx", Vector3(7.8, 0, 0.6), 0.9, 1.1],
		["FBX/Cosmea_Cluster_Small_1.fbx", Vector3(0.4, 0, -8.4), 1.0, 2.0],
		["FBX/Cosmea_Cluster_Small_1.fbx", Vector3(2.6, 0, -7.4), 0.85, 0.9],
		["FBX/Flowering_Garlic_1.fbx", Vector3(-5.2, 0, -8.6), 0.9, 1.3],
		["FBX/Grass_Simple_small.fbx", Vector3(-6.8, 0, 4.4), 1.25, 0.6],
		["FBX/Grass_Simple_small.fbx", Vector3(4.2, 0, 4.6), 1.1, 1.8],
		["FBX/Wild_Grass_Red_small.fbx", Vector3(11.0, 0, 1.4), 1.15, 0.3],
		["FBX/Wild_Grass_Red_small.fbx", Vector3(-12.2, 0, -6.4), 1.2, 2.4],
		["FBX/Poppy_Single_Red.fbx", Vector3(-6.4, 0, -7.25), 1.0, 0.3],
		["FBX/Cosmea_Cluster_Small_1.fbx", Vector3(-0.4, 0, -7.35), 1.05, 1.1],
		["FBX/Larkspur_1_Purple.fbx", Vector3(2.15, 0, -7.15), 1.0, 0.7],
		["FBX/Cornflowers_Big_Cluster_Blue.fbx", Vector3(4.7, 0, -0.6), 1.0, 0.9],
		["FBX/Grass_Simple_small.fbx", Vector3(-9.15, 0, -0.8), 1.25, 0.4],
		["FBX/Wild_Grass_Red_small.fbx", Vector3(-9.05, 0, 1.7), 1.15, 1.4],
	]
	for item in layout:
		var file := str(item[0])
		var at: Vector3 = item[1]
		var packed := load(_PACK + file) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate()
		var y := GardenLayout.height_at(at.x, at.z)
		node.position = Vector3(at.x, y, at.z)
		node.rotation.y = float(item[3])
		node.scale = Vector3.ONE * float(item[2])
		if file.find("Bench") != -1 or file.find("Planter") != -1 or file.find("Table") != -1 or file.find("Umbrella") != -1:
			_paint_imported(node, props)
		else:
			_paint_imported(node, plants)
		parent.add_child(node)

func _flat_material(color: Color, rough: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	return material

func _cutout_material(albedo: Texture2D, opacity: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/cutout.gdshader")
	material.set_shader_parameter("albedo_tex", albedo)
	material.set_shader_parameter("opacity_tex", opacity)
	return material

func _paint_imported(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		mesh_node.material_override = material
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_paint_imported(child, material)

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _standard(color, 0.78)
	node.position = at
	parent.add_child(node)

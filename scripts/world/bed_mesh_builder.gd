class_name BedMeshBuilder
extends RefCounted

const LIP_H := 0.11
const SOIL_H := 0.09
const DOME := 0.02
const CORNER := 0.18
const ROLL := 0.06
const MARGIN := 0.12
const SEG := 16
const ROLL_SEG := 6
const GRID := 0.05

static func build(size: Vector2) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := size.x * 0.5 + MARGIN
	var hd := size.y * 0.5 + MARGIN
	var inner_w := hw - ROLL
	var inner_d := hd - ROLL
	_roll(tool, hw, hd, inner_w, inner_d)
	_ring(tool, inner_w, inner_d, inner_w - 0.02, inner_d - 0.02, LIP_H, SOIL_H, Color(0.7, 0.85, 0, 1))
	_soil_cap(tool, inner_w - 0.02, inner_d - 0.02, SOIL_H)
	tool.generate_normals()
	return tool.commit()

static func _roll(tool: SurfaceTool, ow: float, od: float, iw: float, id: float) -> void:
	var rings: Array[PackedVector2Array] = []
	var ys: Array[float] = []
	var cols: Array[Color] = []
	for s in ROLL_SEG + 1:
		var t := float(s) / float(ROLL_SEG)
		var ang := t * 0.5 * PI
		var w := lerpf(ow, iw, sin(ang))
		var d := lerpf(od, id, sin(ang))
		var y := LIP_H * (1.0 - cos(ang))
		rings.append(_rounded(w, d))
		ys.append(y)
		var ao := lerpf(0.55, 1.0, t)
		cols.append(Color(ao, 1, 0, 1))
	for s in rings.size() - 1:
		_bridge(tool, rings[s], ys[s], cols[s], rings[s + 1], ys[s + 1], cols[s + 1])

static func _ring(tool: SurfaceTool, ow: float, od: float, iw: float, id: float, y0: float, y1: float, color: Color) -> void:
	_bridge(tool, _rounded(ow, od), y0, color, _rounded(iw, id), y1, color)

static func _bridge(tool: SurfaceTool, a: PackedVector2Array, ya: float, ca: Color, b: PackedVector2Array, yb: float, cb: Color) -> void:
	for i in a.size():
		var j := (i + 1) % a.size()
		_tri(tool, Vector3(a[i].x, ya, a[i].y), Vector3(a[j].x, ya, a[j].y), Vector3(b[j].x, yb, b[j].y), ca)
		_tri(tool, Vector3(a[i].x, ya, a[i].y), Vector3(b[j].x, yb, b[j].y), Vector3(b[i].x, yb, b[i].y), cb)

static func _soil_cap(tool: SurfaceTool, w: float, d: float, y: float) -> void:
	var gx := maxi(int((w * 2.0) / GRID), 8)
	var gz := maxi(int((d * 2.0) / GRID), 8)
	for iz in gz:
		for ix in gx:
			var u0 := float(ix) / float(gx)
			var v0 := float(iz) / float(gz)
			var u1 := float(ix + 1) / float(gx)
			var v1 := float(iz + 1) / float(gz)
			var p0 := _grid_pt(u0, v0, w, d, y)
			var p1 := _grid_pt(u1, v0, w, d, y)
			var p2 := _grid_pt(u1, v1, w, d, y)
			var p3 := _grid_pt(u0, v1, w, d, y)
			_tri(tool, p0, p1, p2, Color(1, 0, 0, 1))
			_tri(tool, p0, p2, p3, Color(1, 0, 0, 1))

static func _grid_pt(u: float, v: float, w: float, d: float, y: float) -> Vector3:
	var x := (u - 0.5) * 2.0 * w
	var z := (v - 0.5) * 2.0 * d
	var r := 1.0 - clampf((x * x) / (w * w) + (z * z) / (d * d), 0.0, 1.0)
	return Vector3(x, y + DOME * r, z)

static func _rounded(hw: float, hd: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := minf(CORNER, minf(hw, hd) * 0.9)
	var corners: Array[Vector3] = [
		Vector3(hw - r, hd - r, 0.0),
		Vector3(-hw + r, hd - r, 0.5 * PI),
		Vector3(-hw + r, -hd + r, PI),
		Vector3(hw - r, -hd + r, 1.5 * PI),
	]
	for c in corners:
		for s in SEG:
			var a := c.z + (0.5 * PI) * float(s) / float(SEG)
			pts.append(Vector2(c.x + cos(a) * r, c.y + sin(a) * r))
	return pts

static func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.set_uv(Vector2(a.x, a.z))
	tool.add_vertex(a)
	tool.set_color(color)
	tool.set_uv(Vector2(b.x, b.z))
	tool.add_vertex(b)
	tool.set_color(color)
	tool.set_uv(Vector2(c.x, c.z))
	tool.add_vertex(c)

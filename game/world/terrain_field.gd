extends RefCounted

const SIZE := 56.0
const PLOT_ORIGIN_X := -8.05
const PLOT_ORIGIN_Z := 0.55
const CELL := 1.15
const PLOT_W := 14
const PLOT_D := 10


func height(x: float, z: float) -> float:
	if in_plots(x, z):
		return 0.05
	var nx := x / SIZE
	var nz := z / SIZE
	var radial := sqrt(nx * nx * 0.7 + nz * nz * 0.85)
	var bowl := smoothstep(0.18, 0.46, radial)
	var h := bowl * 2.6
	h += sin(x * 0.31) * cos(z * 0.27) * 0.14 * bowl
	var pond := Vector2(x - 5.4, z + 7.2)
	var pond_r := sqrt(pond.x * pond.x * 0.62 + pond.y * pond.y)
	if pond_r < 6.4:
		h = lerpf(h, -0.78, smoothstep(6.4, 1.1, pond_r))
	if path_distance(x, z) < 1.45:
		h = lerpf(h, 0.045, 0.9)
	if Vector2(x - 13.5, z - 1.6).length() < 3.4:
		h = lerpf(h, 0.07, 0.92)
	return h


func in_plots(x: float, z: float) -> bool:
	var max_x := PLOT_ORIGIN_X + float(PLOT_W) * CELL
	var max_z := PLOT_ORIGIN_Z + float(PLOT_D) * CELL
	return x >= PLOT_ORIGIN_X - 0.35 and x <= max_x + 0.35 and z >= PLOT_ORIGIN_Z - 0.35 and z <= max_z + 0.35


func path_distance(x: float, z: float) -> float:
	var points: Array[Vector2] = [
		Vector2(13.2, 1.5),
		Vector2(7.5, 2.2),
		Vector2(2.0, 5.4),
		Vector2(-1.2, 9.2),
		Vector2(1.5, 1.0),
		Vector2(4.6, -4.8),
	]
	var point := Vector2(x, z)
	var best := 999.0
	for i in points.size() - 1:
		best = minf(best, _segment_distance(point, points[i], points[i + 1]))
	return best


func tint(x: float, z: float, h: float) -> Color:
	var n := _hash(x, z)
	if h < -0.18:
		return Color(0.04, 0.13, 0.12).lerp(Color(0.08, 0.2, 0.16), n)
	if path_distance(x, z) < 1.2:
		return Color(0.52, 0.44, 0.31).lerp(Color(0.7, 0.6, 0.44), n)
	if in_plots(x, z):
		return Color(0.29, 0.18, 0.1).lerp(Color(0.36, 0.24, 0.13), n)
	var grass := Color(0.24, 0.5, 0.16).lerp(Color(0.58, 0.74, 0.22), n)
	if h > 1.15:
		grass = grass.lerp(Color(0.28, 0.4, 0.2), 0.45)
	return grass


func cell_center(x: int, z: int) -> Vector3:
	return Vector3(
		PLOT_ORIGIN_X + (float(x) + 0.5) * CELL,
		0.12,
		PLOT_ORIGIN_Z + (float(z) + 0.5) * CELL
	)


func cell_from_world(point: Vector3) -> Vector2i:
	var x := int(floor((point.x - PLOT_ORIGIN_X) / CELL))
	var z := int(floor((point.z - PLOT_ORIGIN_Z) / CELL))
	return Vector2i(x, z)


func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _hash(x: float, z: float) -> float:
	return absf(fmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0))

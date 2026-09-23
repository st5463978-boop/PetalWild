class_name GardenLayout
extends RefCounted

const CELL_W := 0.92
const CELL_D := 0.86
const COLS := 5
const ROWS := 4
const BED_W := 10
const BED_H := 8
const BASE_POND_CELLS := 22
const POND_CENTER := Vector3(8.0, 0.0, -2.5)
const POND_RADIUS := 3.25
const STALL := Vector3(-4.55, 0.0, 5.15)
const SHED := Vector3(-11.15, 0.0, 3.55)
const TEA := Vector3(2.6, 0.0, -7.5)
const HUT := Vector3(-5.6, 0.0, -7.9)
const FOUNDRY := Vector3(-1.4, 0.0, -8.3)
const HALL := Vector3(0.55, 0.0, -9.7)
const GATE := Vector3(0.0, 0.0, -11.2)

static func plot_origin(ix: int, iz: int) -> Vector2:
	var px := 0 if ix < COLS else 1
	var pz := 0 if iz < ROWS else 1
	if px == 0 and pz == 0:
		return Vector2(-7.4, -5.4)
	if px == 1 and pz == 0:
		return Vector2(-1.9, -5.4)
	if px == 0 and pz == 1:
		return Vector2(-7.4, -0.85)
	return Vector2(-1.9, -0.85)

static func plot_rect(px: int, pz: int) -> Rect2:
	var origin := plot_origin(px * COLS, pz * ROWS)
	return Rect2(origin.x, origin.y, COLS * CELL_W, ROWS * CELL_D)

static func cell_center(ix: int, iz: int) -> Vector3:
	var origin := plot_origin(ix, iz)
	var local_x := ix % COLS
	var local_z := iz % ROWS
	var x := origin.x + (float(local_x) + 0.5) * CELL_W
	var z := origin.y + (float(local_z) + 0.5) * CELL_D
	return Vector3(x, 0.045, z)

static func world_to_cell(point: Vector3) -> Vector2i:
	for ix in BED_W:
		for iz in BED_H:
			var center := cell_center(ix, iz)
			if absf(point.x - center.x) <= CELL_W * 0.5 and absf(point.z - center.z) <= CELL_D * 0.5:
				return Vector2i(ix, iz)
	return Vector2i(-1, -1)

static func in_plots(x: float, z: float, pad: float = 0.15) -> bool:
	var point := Vector2(x, z)
	for px in 2:
		for pz in 2:
			if plot_rect(px, pz).grow(pad).has_point(point):
				return true
	return false

static func pond_distance(x: float, z: float) -> float:
	return Vector2(x - POND_CENTER.x, z - POND_CENTER.z).length()

static func on_path(x: float, z: float) -> bool:
	return _path_band(x, z, 0.46)

static func on_track(x: float, z: float) -> bool:
	# ponytail: the north-south center stays a track; widen it if feet leave the stones.
	return _path_band(x, z, 0.22)

static func _path_band(x: float, z: float, ns_half: float) -> bool:
	if absf(x + 2.35) < ns_half and z > -6.5 and z < 3.7:
		return true
	if absf(z - 3.5) < 0.46 and x > -7.2 and x < -1.0:
		return true
	if absf(z + 2.5) < 0.42 and x > 2.4 and x < 6.8:
		return true
	if absf(z + 6.35) < 0.5 and x > -8.2 and x < 1.2:
		return true
	if absf(x + 4.55) < 0.42 and z > 3.3 and z < 5.5:
		return true
	return false

static func height_at(x: float, z: float) -> float:
	var height := 0.0
	var radius := Vector2(x, z).length()
	if radius > 15.0:
		var rise := smoothstep(15.0, 27.0, radius)
		height += rise * 2.15
		height += sin(x * 0.16) * cos(z * 0.13) * 0.55 * rise
	var pond := pond_distance(x, z)
	if pond < POND_RADIUS + 1.7:
		var bowl := smoothstep(POND_RADIUS + 1.55, POND_RADIUS * 0.55, pond)
		height -= bowl * 0.46
	return height

static func inside_hedge(x: float, z: float) -> bool:
	return x > -13.4 and x < 12.6 and z > -9.6 and z < 7.8

static func terrain_color(x: float, z: float, y: float) -> Color:
	var pond := pond_distance(x, z)
	if pond < POND_RADIUS * 0.92 and y < -0.05:
		return Color("#1e5c56")
	if pond < POND_RADIUS + 1.15:
		return Color("#6e8b49")
	if on_track(x, z):
		# ponytail: pale path dirt clips to white under this sun; raise if the path goes muddy.
		return Color("#6a5e4c")
	if in_plots(x, z, 0.0):
		var furrow := sin(x * 7.5) * 0.5 + 0.5
		return Color("#8d5a3a").lerp(Color("#c4895c"), furrow)
	var n := sin(x * 0.33) * cos(z * 0.27)
	var meadow := Color("#3d6428").lerp(Color("#6a9440"), clampf(n * 0.5 + 0.5, 0.0, 1.0))
	if sin(x * 0.85 + z * 0.4) > 0.62:
		meadow = meadow.lerp(Color("#3c7634"), 0.4)
	if y > 0.8:
		meadow = meadow.lerp(Color("#8aa85a"), 0.35)
	return meadow

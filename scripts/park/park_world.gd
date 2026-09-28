class_name ParkWorld
extends RefCounted

const Kit = preload("res://scripts/presentation/prop_kit.gd")
const AQ := "res://third_party/incoming/assetquest-stylized-garden-demo/"
const TOWN := "res://assets/third_party/kenney/fantasy-town/Models/FBX format/"
const TOWN_S := 1.55
const CELL := 1.0
const I0 := -12
const I1 := 12

var mats: ParkMaterials
var rng := RandomNumberGenerator.new()
var parent: Node3D
var lanterns: Array[OmniLight3D] = []
var _town_cache: Dictionary = {}


func build(root: Node3D, materials: ParkMaterials) -> void:
	parent = root
	mats = materials
	rng.seed = 280928
	_ground()
	_tiles()
	_pond()
	_hedge()
	_grass()
	_flowers()
	_veg()
	_trees()
	_willow()
	_lilies_reeds()
	_bridge()
	_gazebo()
	_greenhouse()
	_stall()
	_playground()
	_benches_lamps()
	_railings()
	_city()
	_clock_tower()
	_fruit()
	_spawns()
	_probe()


func height_at(x: float, z: float) -> float:
	var p := pond_amount(x, z)
	if p > 0.0:
		return lerpf(0.02, -0.46, p)
	return 0.0


func pond_amount(x: float, z: float) -> float:
	var u := x / 5.4
	var v := (z + 0.12) / 3.58
	var d := u * u + v * v
	var bx := (x - 2.2) / 2.2
	var bz := (z - 1.38) / 1.72
	var bite := bx * bx + bz * bz
	if bite < 1.0:
		d += (1.0 - bite) * 0.64
	return clampf(1.0 - d, 0.0, 1.0)


func _kind(ix: int, iz: int) -> String:
	var x := (float(ix) + 0.5) * CELL
	var z := (float(iz) + 0.5) * CELL
	var r := Vector2(x, z).length()
	if pond_amount(x, z) > 0.08:
		return "pond"
	if r > 13.0:
		return "void"
	if r > 10.15:
		return "cobble"
	if r > 9.2 and r <= 10.15:
		return "hedge"
	if Vector2(x - 6.15, z + 5.75).length() < 2.05:
		return "plaza"
	if x > 5.15 and x < 8.55 and z > 5.35 and z < 8.55:
		return "play"
	if x > 7.6 and x < 10.2 and z > -1.2 and z < 3.4 and r < 10.5:
		return "plaza"
	if r > 3.9 and r < 5.35:
		return "gravel"
	if (absf(x) < 0.55 and absf(z) > 5.05 and r < 9.2) or (absf(z) < 0.55 and absf(x) > 5.05 and r < 9.2):
		return "flag"
	if (ix == 4 or iz == 4 or ix == -5 or iz == -5) and r > 5.2 and r < 9.2:
		return "flag"
	var plot := _plot_kind(ix, iz)
	if plot != "":
		return plot
	return "lawn"


func _plot_kind(ix: int, iz: int) -> String:
	# Discrete square beds, not whole wedges, so lawn still reads.
	var plots: Array = [
		[-8, -6, 3, 5, "veg"],
		[-8, -6, -6, -4, "flower"],
		[-3, -1, 6, 8, "flower"],
		[2, 4, 6, 8, "veg"],
		[5, 7, 2, 4, "flower"],
		[5, 7, -7, -5, "veg"],
		[-3, -1, -8, -6, "flower"],
		[1, 3, -8, -6, "veg"],
		[-8, -6, 6, 7, "veg"],
		[-5, -3, 6, 8, "flower"],
	]
	for plot in plots:
		if ix >= int(plot[0]) and ix <= int(plot[1]) and iz >= int(plot[2]) and iz <= int(plot[3]):
			return str(plot[4])
	return ""


func _ground() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 24.0
	var step := 0.7
	var n := int(half * 2.0 / step)
	for iz in n:
		for ix in n:
			var x0 := -half + float(ix) * step
			var z0 := -half + float(iz) * step
			if pond_amount(x0 + step * 0.5, z0 + step * 0.5) > 0.12:
				continue
			_ground_quad(tool, x0, z0, step)
	tool.generate_normals()
	tool.generate_tangents()
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	node.material_override = mats.lawn
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.name = "ParkLawn"
	parent.add_child(node)


func _ground_quad(tool: SurfaceTool, x0: float, z0: float, step: float) -> void:
	var x1 := x0 + step
	var z1 := z0 + step
	tool.set_uv(Vector2(x0, z0))
	tool.set_color(Color.WHITE)
	tool.add_vertex(Vector3(x0, -0.02, z0))
	tool.set_uv(Vector2(x1, z0))
	tool.add_vertex(Vector3(x1, -0.02, z0))
	tool.set_uv(Vector2(x1, z1))
	tool.add_vertex(Vector3(x1, -0.02, z1))
	tool.set_uv(Vector2(x0, z0))
	tool.add_vertex(Vector3(x0, -0.02, z0))
	tool.set_uv(Vector2(x1, z1))
	tool.add_vertex(Vector3(x1, -0.02, z1))
	tool.set_uv(Vector2(x0, z1))
	tool.add_vertex(Vector3(x0, -0.02, z1))


func _tiles() -> void:
	var lawn_xf: Array[Transform3D] = []
	var lawn_col: Array[Color] = []
	var soil_xf: Array[Transform3D] = []
	var soil_col: Array[Color] = []
	var grav_xf: Array[Transform3D] = []
	var grav_col: Array[Color] = []
	var cob_xf: Array[Transform3D] = []
	var cob_col: Array[Color] = []
	var flag_xf: Array[Transform3D] = []
	var flag_col: Array[Color] = []
	var play_xf: Array[Transform3D] = []
	var play_col: Array[Color] = []
	var plaza_xf: Array[Transform3D] = []
	var plaza_col: Array[Color] = []
	var edge_xf: Array[Transform3D] = []
	var edge_col: Array[Color] = []
	var corner_xf: Array[Transform3D] = []
	var corner_col: Array[Color] = []
	var pillow := ParkMesh.pillow(Vector3(0.96, 0.07, 0.96), 6)
	var bed := ParkMesh.pillow(Vector3(0.9, 0.14, 0.9), 6)
	var cob := ParkMesh.pillow(Vector3(0.98, 0.06, 0.98), 6)
	var edge := ParkMesh.pillow(Vector3(0.28, 0.28, 0.96), 6)
	var corner := ParkMesh.pillow(Vector3(0.36, 0.32, 0.36), 5)
	for iz in range(I0, I1):
		for ix in range(I0, I1):
			var kind := _kind(ix, iz)
			if kind == "pond" or kind == "void" or kind == "hedge":
				continue
			var x := (float(ix) + 0.5) * CELL
			var z := (float(iz) + 0.5) * CELL
			var y := height_at(x, z)
			var yaw := rng.randf_range(-0.04, 0.04)
			var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
			var at := Vector3(x, y + 0.03, z)
			match kind:
				"veg", "flower":
					soil_xf.append(Transform3D(basis, at + Vector3(0, 0.05, 0)))
					soil_col.append(Color(0.92, 0.88, 0.82).lerp(Color(1, 1, 1), rng.randf() * 0.2))
					_edge_ring(edge_xf, edge_col, corner_xf, corner_col, x, y, z)
				"gravel":
					grav_xf.append(Transform3D(basis, at))
					grav_col.append(Color(1, 0.96, 0.9))
				"cobble":
					cob_xf.append(Transform3D(basis, at - Vector3(0, 0.01, 0)))
					cob_col.append(Color(0.95, 0.92, 0.86).lerp(Color(1, 1, 1), rng.randf() * 0.15))
				"flag", "plaza":
					if kind == "plaza":
						plaza_xf.append(Transform3D(basis, at))
						plaza_col.append(Color(1, 0.97, 0.9))
					else:
						flag_xf.append(Transform3D(basis, at))
						flag_col.append(Color(0.98, 0.94, 0.86))
				"play":
					play_xf.append(Transform3D(basis, at + Vector3(0, 0.02, 0)))
					play_col.append(Color(1, 0.95, 0.8))
				_:
					lawn_xf.append(Transform3D(basis, at))
					lawn_col.append(Color(0.95, 1.0, 0.88).lerp(Color(1, 1, 1), rng.randf() * 0.2))
	_multi(pillow, lawn_xf, lawn_col, mats.lawn, "LawnTiles")
	_multi(bed, soil_xf, soil_col, mats.soil, "SoilTiles")
	_multi(pillow, grav_xf, grav_col, mats.gravel, "GravelTiles")
	_multi(cob, cob_xf, cob_col, mats.cobble, "CobbleTiles")
	_multi(pillow, flag_xf, flag_col, mats.flag, "FlagTiles")
	_multi(pillow, plaza_xf, plaza_col, mats.flag, "PlazaTiles")
	_multi(bed, play_xf, play_col, mats.sand, "PlayTiles")
	_multi(edge, edge_xf, edge_col, mats.rock, "BedEdging")
	_multi(corner, corner_xf, corner_col, mats.rock, "BedCorners")


func _edge_ring(xforms: Array[Transform3D], colors: Array[Color], corners: Array[Transform3D], corner_colors: Array[Color], x: float, y: float, z: float) -> void:
	var specs: Array = [
		[Vector3(x, y + 0.08, z - 0.42), 0.0],
		[Vector3(x, y + 0.08, z + 0.42), 0.0],
		[Vector3(x - 0.42, y + 0.08, z), PI * 0.5],
		[Vector3(x + 0.42, y + 0.08, z), PI * 0.5],
	]
	for spec in specs:
		var at: Vector3 = spec[0]
		var yaw := float(spec[1])
		xforms.append(Transform3D(Basis.from_euler(Vector3(0, yaw, 0)), at))
		colors.append(Color(0.78, 0.74, 0.66))
	var stones: Array[Vector3] = [
		Vector3(x - 0.46, y + 0.12, z - 0.46),
		Vector3(x + 0.46, y + 0.12, z - 0.46),
		Vector3(x - 0.46, y + 0.12, z + 0.46),
		Vector3(x + 0.46, y + 0.12, z + 0.46),
	]
	for stone in stones:
		var spin := Basis.from_euler(Vector3(0, rng.randf_range(0, 0.4), 0))
		corners.append(Transform3D(spin, stone))
		corner_colors.append(Color(0.82, 0.78, 0.7))


func _pond() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_fill_pond(tool, 0.0)
	tool.generate_normals()
	tool.generate_tangents()
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	node.material_override = mats.bed
	node.name = "PondBed"
	parent.add_child(node)
	_water_plane()
	var rock_mesh := ParkMesh.lumpy_sphere(0.28, 1.4, 8)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in 72:
		var a := TAU * float(i) / 72.0 + rng.randf_range(-0.04, 0.04)
		var rr := 4.55 + rng.randf_range(-0.25, 0.45) + 0.35 * sin(a * 2.0)
		var x := cos(a) * rr * 1.18
		var z := sin(a) * rr * 0.78
		if pond_amount(x, z) > 0.55:
			continue
		var y := height_at(x, z)
		var s := rng.randf_range(0.55, 1.15)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), a, rng.randf_range(-0.2, 0.2)))
		b = b.scaled(Vector3(s, s * rng.randf_range(0.45, 0.7), s))
		xf.append(Transform3D(b, Vector3(x, y + 0.04, z)))
		cols.append(Color(0.85, 0.82, 0.76).lerp(Color(1, 1, 1), rng.randf() * 0.2))
	_multi(rock_mesh, xf, cols, mats.rock, "PondRim")


func _fill_pond(tool: SurfaceTool, y_lift: float) -> void:
	var rings := 16
	var segs := 36
	for ring in rings:
		for seg in segs:
			var t0 := float(ring) / float(rings)
			var t1 := float(ring + 1) / float(rings)
			var a0 := TAU * float(seg) / float(segs)
			var a1 := TAU * float(seg + 1) / float(segs)
			_pond_vert(tool, t0, a0, y_lift)
			_pond_vert(tool, t1, a0, y_lift)
			_pond_vert(tool, t1, a1, y_lift)
			_pond_vert(tool, t0, a0, y_lift)
			_pond_vert(tool, t1, a1, y_lift)
			_pond_vert(tool, t0, a1, y_lift)


func _pond_vert(tool: SurfaceTool, t: float, angle: float, y_lift: float = 0.0) -> void:
	var rx := 5.35 * t
	var rz := 3.55 * t
	var x := cos(angle) * rx
	var z := sin(angle) * rz - 0.12 * t
	# kidney bite
	var bite := clampf(1.0 - (((x - 2.1) / 2.3) * ((x - 2.1) / 2.3) + ((z - 1.3) / 1.8) * ((z - 1.3) / 1.8)), 0.0, 1.0)
	x -= bite * 0.55 * t
	z -= bite * 0.35 * t
	var y := lerpf(0.0, -0.5, 1.0 - t * t) + y_lift
	tool.set_uv(Vector2(x * 0.18, z * 0.18))
	tool.add_vertex(Vector3(x, y, z))


func _water_plane() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 16
	var segs := 40
	for ring in rings:
		for seg in segs:
			var t0 := float(ring) / float(rings) * 0.94
			var t1 := float(ring + 1) / float(rings) * 0.94
			var a0 := TAU * float(seg) / float(segs)
			var a1 := TAU * float(seg + 1) / float(segs)
			_water_vert(tool, t0, a0)
			_water_vert(tool, t1, a0)
			_water_vert(tool, t1, a1)
			_water_vert(tool, t0, a0)
			_water_vert(tool, t1, a1)
			_water_vert(tool, t0, a1)
	tool.generate_normals()
	tool.generate_tangents()
	var node := MeshInstance3D.new()
	node.mesh = tool.commit()
	node.material_override = mats.water
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.name = "PondSurface"
	parent.add_child(node)


func _water_vert(tool: SurfaceTool, t: float, angle: float) -> void:
	var rx := 5.35 * t
	var rz := 3.55 * t
	var x := cos(angle) * rx
	var z := sin(angle) * rz - 0.12 * t
	var bite := clampf(1.0 - (((x - 2.1) / 2.3) * ((x - 2.1) / 2.3) + ((z - 1.3) / 1.8) * ((z - 1.3) / 1.8)), 0.0, 1.0)
	x -= bite * 0.55 * t
	z -= bite * 0.35 * t
	tool.set_uv(Vector2(x * 0.2, z * 0.2))
	tool.add_vertex(Vector3(x, 0.02, z))


func _hedge() -> void:
	var card := ParkMesh.leaf_cross(0.72, 0.82, false)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	var count := 96
	for i in count:
		var a := TAU * float(i) / float(count)
		var r := 9.55 + 0.12 * sin(a * 5.0)
		var x := cos(a) * r
		var z := sin(a) * r
		for layer in 2:
			var s := rng.randf_range(0.9, 1.25)
			var y := 0.28 + float(layer) * 0.48
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.18), a + rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.2)))
			b = b.scaled(Vector3(s, s * rng.randf_range(0.75, 1.05), s))
			xf.append(Transform3D(b, Vector3(x + rng.randf_range(-0.08, 0.08), y, z)))
			cols.append(Color(0.86, 0.98, 0.78).lerp(Color(1.0, 1.0, 0.88), rng.randf()))
			custom.append(Color(rng.randf(), 0, 0, 1))
	for i in 40:
		var a := TAU * float(i) / 40.0 + 0.08
		var r := 8.5
		var x := cos(a) * r
		var z := sin(a) * r
		if pond_amount(x, z) > 0.01:
			continue
		var s := rng.randf_range(0.55, 0.85)
		var b := Basis.from_euler(Vector3(0.05, a, 0.0)).scaled(Vector3(s, s * 0.7, s))
		xf.append(Transform3D(b, Vector3(x, 0.32, z)))
		cols.append(Color(0.8, 0.96, 0.72))
		custom.append(Color(rng.randf(), 0, 0, 1))
	_multi(card, xf, cols, mats.leaf, "Hedge", custom)


func _grass() -> void:
	var blade := ParkMesh.grass_blade()
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	var tries := 0
	while xf.size() < 780 and tries < 5000:
		tries += 1
		var x := rng.randf_range(-11.0, 11.0)
		var z := rng.randf_range(-11.0, 11.0)
		var k := _kind(int(floor(x)), int(floor(z)))
		if k == "pond" or k == "cobble" or k == "play" or k == "void":
			continue
		if pond_amount(x, z) > 0.02:
			continue
		var y := height_at(x, z)
		var s := rng.randf_range(0.7, 1.15)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.2), rng.randf() * TAU, 0.0))
		xf.append(Transform3D(b.scaled(Vector3(s, s * rng.randf_range(0.85, 1.4), s)), Vector3(x, y, z)))
		cols.append(Color("447826").lerp(Color("82a834"), rng.randf()))
		custom.append(Color(rng.randf(), 0, 0, 1))
	_multi(blade, xf, cols, mats.foliage, "GrassClumps", custom)


func _flowers() -> void:
	var files: Array[String] = [
		"FBX/Poppy_Single_Red.fbx",
		"FBX/Gerbera_1_Red.fbx",
		"FBX/Larkspur_1_Purple.fbx",
		"FBX/Cornflowers_Big_Cluster_Blue.fbx",
		"FBX/Cosmea_Cluster_Small_1.fbx",
		"FBX/Giant_Sunflower_big_1.fbx",
		"FBX/Flowering_Garlic_1.fbx",
	]
	var plants := mats.blooms
	var spots: Array[Vector3] = []
	for iz in range(I0, I1):
		for ix in range(I0, I1):
			if _kind(ix, iz) != "flower":
				continue
			var x := (float(ix) + 0.5) * CELL + rng.randf_range(-0.18, 0.18)
			var z := (float(iz) + 0.5) * CELL + rng.randf_range(-0.18, 0.18)
			spots.append(Vector3(x, height_at(x, z), z))
	# extra border blooms
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(5.4, 8.2)
		var x := cos(a) * r
		var z := sin(a) * r
		var k := _kind(int(floor(x)), int(floor(z)))
		if k == "pond" or k == "cobble" or k == "play":
			continue
		spots.append(Vector3(x, height_at(x, z), z))
	var n := 0
	for spot in spots:
		var file := files[n % files.size()]
		_aq(file, spot, rng.randf_range(1.15, 1.75), rng.randf() * TAU, plants)
		n += 1
	# Kenney flowers as extra colour
	var kenney: Array[String] = ["flower_redA.fbx", "flower_yellowA.fbx", "flower_purpleA.fbx"]
	for i in 24:
		var a := rng.randf() * TAU
		var r := rng.randf_range(5.6, 8.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if pond_amount(x, z) > 0.05:
			continue
		_kit(kenney[i % 3], rng.randf_range(0.55, 0.9), Vector3(x, height_at(x, z), z), rng.randf() * TAU)


func _veg() -> void:
	var crops: Array[String] = [
		"crops_leafsStageB.fbx",
		"crops_leafsStageA.fbx",
		"crop_carrot.fbx",
		"crop_pumpkin.fbx",
		"crop_turnip.fbx",
	]
	for iz in range(I0, I1):
		for ix in range(I0, I1):
			if _kind(ix, iz) != "veg":
				continue
			var x := (float(ix) + 0.5) * CELL
			var z := (float(iz) + 0.5) * CELL
			_kit(crops[abs(ix + iz) % crops.size()], rng.randf_range(0.28, 0.55), Vector3(x, 0.08, z), rng.randf() * TAU)


func _trees() -> void:
	var card := ParkMesh.leaf_cross(0.9, 1.05, false)
	var spots: Array = [
		[Vector2(-7.4, -6.8), 3.6],
		[Vector2(-8.2, 2.6), 3.3],
		[Vector2(7.6, -7.4), 3.8],
		[Vector2(-6.2, 7.1), 3.1],
		[Vector2(3.4, 8.6), 3.4],
		[Vector2(-10.8, -3.2), 4.0],
		[Vector2(10.6, -4.2), 3.7],
		[Vector2(-11.2, 6.4), 3.2],
		[Vector2(11.0, 5.8), 3.4],
		[Vector2(-2.2, -9.4), 2.6],
		[Vector2(2.6, -9.6), 2.7],
		[Vector2(-4.8, -10.6), 2.8],
		[Vector2(5.2, -11.0), 2.8],
		[Vector2(8.8, -10.4), 4.0],
		[Vector2(-8.6, -10.8), 4.2],
	]
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	for spot in spots:
		var p: Vector2 = spot[0]
		_leaf_crown(Vector3(p.x, 0.0, p.y), float(spot[1]), card, xf, cols, custom, 28)
	for i2 in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.2, 10.2)
		var x := cos(a) * r
		var z := sin(a) * r
		if pond_amount(x, z) > 0.02:
			continue
		_leaf_crown(Vector3(x, 0.0, z), rng.randf_range(0.85, 1.25), card, xf, cols, custom, 8)
	_multi(card, xf, cols, mats.leaf, "TreeCrowns", custom)


func _leaf_crown(at: Vector3, height: float, card: Mesh, xf: Array[Transform3D], cols: Array[Color], custom: Array[Color], count: int) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.07 * clampf(height / 3.0, 0.45, 1.1)
	trunk.bottom_radius = 0.13 * clampf(height / 3.0, 0.5, 1.2)
	trunk.height = height * 0.42
	trunk.radial_segments = 7
	_add_mesh(trunk, mats.bark, at + Vector3(0, trunk.height * 0.5, 0), "Trunk")
	var crown := height * 0.38
	for i in count:
		var yaw := rng.randf() * TAU
		var elev := rng.randf_range(-0.15, 1.0)
		var rad := rng.randf_range(0.05, crown)
		var pos := at + Vector3(cos(yaw) * rad, height * 0.48 + elev * crown * 0.7, sin(yaw) * rad)
		var s := rng.randf_range(0.7, 1.3) * clampf(height / 3.2, 0.45, 1.25)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.45, 0.45), yaw, rng.randf_range(-0.6, 0.6)))
		b = b.scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
		xf.append(Transform3D(b, pos))
		cols.append(Color(0.84, 0.97, 0.74).lerp(Color(1.0, 1.0, 0.86), rng.randf()))
		custom.append(Color(rng.randf(), 0, 0, 1))


func _willow() -> void:
	var root := Vector3(2.75, 0.0, 2.7)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.09
	trunk.bottom_radius = 0.2
	trunk.height = 2.5
	trunk.radial_segments = 8
	_add_mesh(trunk, mats.bark, root + Vector3(0, 1.25, 0), "WillowTrunk")
	var toward := Vector3(-0.55, 0.0, -0.72).normalized()
	var clump := ParkMesh.leaf_cross(0.7, 1.0, true)
	var strand := ParkMesh.leaf_cross(0.32, 1.0, true)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	var sxf: Array[Transform3D] = []
	var scols: Array[Color] = []
	var scustom: Array[Color] = []
	for b in 5:
		var side := float(b) - 2.0
		var branch_end := root + Vector3(-0.05, 2.45, 0.05) + toward * (0.55 + absf(side) * 0.08) + Vector3(side * 0.28, -0.15, side * 0.05)
		var limb := CylinderMesh.new()
		limb.top_radius = 0.03
		limb.bottom_radius = 0.055
		limb.height = root.distance_to(branch_end) * 0.55
		limb.radial_segments = 5
		var mid := root.lerp(branch_end, 0.55) + Vector3(0, 0.35, 0)
		var node := _add_mesh(limb, mats.bark, mid, "WillowBranch")
		node.look_at(branch_end, Vector3.UP)
		node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		for i in 16:
			var hang := rng.randf_range(0.55, 1.85)
			var slip := rng.randf_range(-0.35, 0.35)
			var tip := branch_end + toward * hang * 0.55 + Vector3(slip, -hang, slip * 0.2)
			var attach := branch_end + Vector3(slip * 0.3, 0.0, slip * 0.1)
			_hang_card(attach, tip, xf, cols, custom, rng.randf_range(0.65, 1.15))
		for i in 8:
			var hang := rng.randf_range(0.7, 1.6)
			var slip := rng.randf_range(-0.25, 0.25)
			var tip := branch_end + toward * hang * 0.4 + Vector3(slip, -hang * 0.95, 0.0)
			_hang_card(branch_end, tip, sxf, scols, scustom, rng.randf_range(0.7, 1.2))
	_multi(clump, xf, cols, mats.leaf, "WillowCurtain", custom)
	_multi(strand, sxf, scols, mats.strand, "WillowStrands", scustom)


func _hang_card(attach: Vector3, tip: Vector3, xf: Array[Transform3D], cols: Array[Color], custom: Array[Color], width: float) -> void:
	var span := attach - tip
	if span.length() < 0.05:
		return
	var y_axis := span.normalized()
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length() < 0.2:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis).scaled(Vector3(width, span.length(), width))
	xf.append(Transform3D(basis, tip))
	cols.append(Color(0.9, 1.0, 0.82).lerp(Color(1.0, 1.0, 0.9), rng.randf()))
	custom.append(Color(rng.randf(), 0, 0, 1))


func _lilies_reeds() -> void:
	var pad := ParkMesh.lily_pad(0.36)
	var bloom := ParkMesh.water_lily()
	var center := SphereMesh.new()
	center.radius = 0.028
	center.height = 0.04
	center.radial_segments = 8
	center.rings = 4
	var pxf: Array[Transform3D] = []
	var pc: Array[Color] = []
	var bxf: Array[Transform3D] = []
	var bc: Array[Color] = []
	var cxf: Array[Transform3D] = []
	var cc: Array[Color] = []
	for i in 16:
		var x := rng.randf_range(-1.6, 2.2)
		var z := rng.randf_range(0.15, 3.05)
		if pond_amount(x, z) < 0.2:
			continue
		var y := 0.035
		var s := rng.randf_range(0.75, 1.45)
		var curl := rng.randf_range(-0.12, 0.18)
		var yaw := rng.randf() * TAU
		var basis := Basis.from_euler(Vector3(curl, yaw, curl * 0.4)).scaled(Vector3(s, 1.0, s))
		pxf.append(Transform3D(basis, Vector3(x, y, z)))
		pc.append(Color(0.82, 1.0, 0.78).lerp(Color(1, 1, 0.9), rng.randf()))
		if i % 2 == 0:
			var flower := Basis.from_euler(Vector3(curl, yaw, 0)).scaled(Vector3(1.7, 1.7, 1.7))
			bxf.append(Transform3D(flower, Vector3(x, y + 0.02, z)))
			bc.append(Color(1, 0.96, 0.94))
			cxf.append(Transform3D(Basis.IDENTITY, Vector3(x, y + 0.07, z)))
			cc.append(Color("f2d27a"))
	_multi(pad, pxf, pc, mats.lily, "LilyPads")
	_multi(bloom, bxf, bc, mats.petal, "LilyBlooms")
	_multi(center, cxf, cc, mats.solid(Color("f2d27a"), 0.4), "LilyCenters")
	var blade := ParkMesh.leaf_cross(0.14, 1.15, false)
	var head := CylinderMesh.new()
	head.top_radius = 0.03
	head.bottom_radius = 0.048
	head.height = 0.22
	head.radial_segments = 6
	var sxf: Array[Transform3D] = []
	var sc: Array[Color] = []
	var scustom: Array[Color] = []
	var hxf: Array[Transform3D] = []
	var hc: Array[Color] = []
	for i in 22:
		var x := rng.randf_range(-2.7, -0.45)
		var z := rng.randf_range(1.9, 3.85)
		if pond_amount(x, z) > 0.55:
			continue
		var h := rng.randf_range(0.75, 1.4)
		var lean := Basis.from_euler(Vector3(rng.randf_range(-0.18, 0.1), rng.randf() * TAU, 0)).scaled(Vector3(1, h, 1))
		sxf.append(Transform3D(lean, Vector3(x, 0.0, z)))
		sc.append(Color("6f9a42").lerp(Color("c6d56a"), rng.randf()))
		scustom.append(Color(rng.randf(), 0, 0, 1))
		if i % 2 == 0:
			hxf.append(Transform3D(Basis.IDENTITY, Vector3(x, 1.08 * h, z)))
			hc.append(Color("6a4a28").lerp(Color("a07848"), rng.randf()))
	_multi(blade, sxf, sc, mats.foliage, "Reeds", scustom)
	_multi(head, hxf, hc, mats.solid(Color("7a5530"), 0.62), "Cattails")


func _bridge() -> void:
	# Four Kenney narrow decks, ~1 m each, arched over the south-west pinch.
	var origin := Vector3(-3.25, 0.04, -0.05)
	var dir := Vector3(0.70, 0.0, 0.71).normalized()
	var yaw := atan2(-dir.z, dir.x)
	var piece := 1.04 * 1.15
	for i in 4:
		var t := float(i) - 1.5
		var p := origin + dir * t * piece
		p.y += cos(t / 1.7) * 0.16
		_kit("bridge_woodNarrow.glb", 0.0, p, yaw, 1.15, mats.wood)


func _gazebo() -> void:
	var origin := Vector3(6.2, 0.0, -5.75)
	var floor := CylinderMesh.new()
	floor.top_radius = 1.55
	floor.bottom_radius = 1.62
	floor.height = 0.14
	floor.radial_segments = 8
	_add_mesh(floor, mats.wood, origin + Vector3(0, 0.07, 0), "GazeboFloor")
	for i in 8:
		var a := TAU * float(i) / 8.0 + PI / 8.0
		var at := origin + Vector3(cos(a) * 1.32, 0.12, sin(a) * 1.32)
		_town_xform("pillar-wood.fbx", at, a, Vector3(1.45, 2.2, 1.45))
	var roof := ParkMesh.oct_roof(1.85, 0.72)
	_add_mesh(roof, mats.tinted_wood(Color("6e5340")), origin + Vector3(0, 2.15, 0), "GazeboRoof")
	var roof2 := ParkMesh.oct_roof(1.05, 0.48)
	_add_mesh(roof2, mats.tinted_wood(Color("5c4634")), origin + Vector3(0, 2.72, 0), "GazeboRoof2")
	var cap := SphereMesh.new()
	cap.radius = 0.1
	cap.height = 0.16
	_add_mesh(cap, mats.tinted_wood(Color("6c543e")), origin + Vector3(0, 3.22, 0), "GazeboFinial")
	var rail := ParkMesh.pillow(Vector3(0.9, 0.08, 0.08), 5)
	for i in 8:
		var a0 := TAU * float(i) / 8.0 + PI / 8.0
		var a1 := TAU * float(i + 1) / 8.0 + PI / 8.0
		var mid := (a0 + a1) * 0.5
		var at := origin + Vector3(cos(mid) * 1.28, 0.72, sin(mid) * 1.28)
		var node := MeshInstance3D.new()
		node.mesh = rail
		node.material_override = mats.wood
		node.position = at
		node.rotation.y = -mid + PI * 0.5
		parent.add_child(node)


func _greenhouse() -> void:
	var origin := Vector3(8.35, 0.0, -8.15)
	var base := ParkMesh.pillow(Vector3(2.6, 0.18, 2.1), 6)
	_add_mesh(base, mats.wood, origin + Vector3(0, 0.09, 0), "GhBase")
	var frame := ParkMesh.pillow(Vector3(0.1, 1.7, 0.1), 4)
	var corners: Array[Vector3] = [
		Vector3(-1.15, 0.95, -0.9), Vector3(1.15, 0.95, -0.9),
		Vector3(-1.15, 0.95, 0.9), Vector3(1.15, 0.95, 0.9),
	]
	for c in corners:
		_add_mesh(frame, mats.tinted_wood(Color("9f7f63")), origin + c, "GhPost")
	var pane := BoxMesh.new()
	pane.size = Vector3(2.2, 1.55, 0.04)
	var glass_n := MeshInstance3D.new()
	glass_n.mesh = pane
	glass_n.material_override = mats.glass
	glass_n.position = origin + Vector3(0, 0.95, -0.92)
	parent.add_child(glass_n)
	var glass_s := glass_n.duplicate() as MeshInstance3D
	glass_s.position = origin + Vector3(0, 0.95, 0.92)
	parent.add_child(glass_s)
	var pane2 := BoxMesh.new()
	pane2.size = Vector3(0.04, 1.55, 1.7)
	var glass_e := MeshInstance3D.new()
	glass_e.mesh = pane2
	glass_e.material_override = mats.glass
	glass_e.position = origin + Vector3(1.18, 0.95, 0)
	parent.add_child(glass_e)
	var glass_w := glass_e.duplicate() as MeshInstance3D
	glass_w.position = origin + Vector3(-1.18, 0.95, 0)
	parent.add_child(glass_w)
	var roof := ParkMesh.gable_roof(2.7, 0.85, 2.2)
	_add_mesh(roof, mats.glass, origin + Vector3(0, 1.78, 0), "GhRoof")
	var ridge := ParkMesh.pillow(Vector3(0.12, 0.08, 2.2), 4)
	_add_mesh(ridge, mats.wood, origin + Vector3(0, 2.55, 0), "GhRidge")
	_kit("pot_large.fbx", 0.35, origin + Vector3(-0.45, 0.18, 0.1), 0.2)
	_aq("FBX/Planter_1_Terracotta.fbx", origin + Vector3(0.5, 0.18, 0.15), 0.7, 0.4, mats.wood)


func _stall() -> void:
	var origin := Vector3(9.55, 0.0, 1.35)
	var post := CylinderMesh.new()
	post.top_radius = 0.07
	post.bottom_radius = 0.08
	post.height = 2.15
	post.radial_segments = 8
	for p in [Vector3(-0.85, 1.1, -0.55), Vector3(0.85, 1.1, -0.55), Vector3(-0.85, 1.1, 0.55), Vector3(0.85, 1.1, 0.55)]:
		_add_mesh(post, mats.wood, origin + p, "StallPost")
	var counter := ParkMesh.pillow(Vector3(2.05, 0.12, 0.85), 6)
	_add_mesh(counter, mats.tinted_wood(Color("b68d73")), origin + Vector3(0, 0.92, 0.05), "StallCounter")
	var awning := ParkMesh.pillow(Vector3(2.45, 0.1, 1.55), 5)
	var awn := MeshInstance3D.new()
	awn.mesh = awning
	awn.material_override = mats.awning
	awn.position = origin + Vector3(0, 2.08, 0)
	awn.rotation_degrees = Vector3(-16, 0, 0)
	parent.add_child(awn)
	var cloth := PlaneMesh.new()
	cloth.size = Vector2(2.5, 1.6)
	var cloth_n := MeshInstance3D.new()
	cloth_n.mesh = cloth
	cloth_n.material_override = mats.awning
	cloth_n.position = origin + Vector3(0, 2.15, 0.05)
	cloth_n.rotation_degrees = Vector3(-18, 0, 0)
	parent.add_child(cloth_n)
	_kit("log_stack.fbx", 0.35, origin + Vector3(-0.45, 0.18, 0.15), 0.3)
	_kit("pot_large.fbx", 0.32, origin + Vector3(0.55, 0.18, 0.2), 0.8)
	# fruit pile
	var fruit := SphereMesh.new()
	fruit.radius = 0.07
	fruit.height = 0.14
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in 10:
		xf.append(Transform3D(Basis.IDENTITY, origin + Vector3(rng.randf_range(-0.25, 0.35), 1.04, rng.randf_range(-0.15, 0.2))))
		cols.append(Color("d23732") if i % 2 == 0 else Color("e67828"))
	_multi(fruit, xf, cols, mats.solid(Color("d23732"), 0.35), "StallFruit")


func _playground() -> void:
	var origin := Vector3(6.85, 0.0, 6.95)
	# sandbox rim
	var rim := ParkMesh.pillow(Vector3(2.6, 0.22, 0.22), 5)
	_add_mesh(rim, mats.wood, origin + Vector3(0, 0.12, -1.15), "SandRim")
	_add_mesh(rim, mats.wood, origin + Vector3(0, 0.12, 1.15), "SandRim")
	var rim2 := ParkMesh.pillow(Vector3(0.22, 0.22, 2.5), 5)
	_add_mesh(rim2, mats.wood, origin + Vector3(-1.2, 0.12, 0), "SandRim")
	_add_mesh(rim2, mats.wood, origin + Vector3(1.2, 0.12, 0), "SandRim")
	# slide
	var slide := ParkMesh.pillow(Vector3(0.55, 0.08, 1.8), 5)
	var s := MeshInstance3D.new()
	s.mesh = slide
	s.material_override = mats.solid(Color("7a4ac8"), 0.45)
	s.position = origin + Vector3(1.55, 0.55, 0.15)
	s.rotation_degrees = Vector3(-32, 18, 0)
	parent.add_child(s)
	var stair := ParkMesh.pillow(Vector3(0.45, 0.9, 0.45), 5)
	_add_mesh(stair, mats.solid(Color("6a3eb0"), 0.5), origin + Vector3(2.05, 0.5, -0.55), "SlideTower")
	# seesaw
	var plank := ParkMesh.pillow(Vector3(1.8, 0.08, 0.28), 5)
	_add_mesh(plank, mats.solid(Color("3d7ec9"), 0.5), origin + Vector3(-0.15, 0.38, 1.55), "Seesaw")
	var pivot := SphereMesh.new()
	pivot.radius = 0.12
	pivot.height = 0.2
	_add_mesh(pivot, mats.wood, origin + Vector3(-0.15, 0.22, 1.55), "SeesawPivot")


func _benches_lamps() -> void:
	var benches: Array[Vector3] = [
		Vector3(-6.4, 0, 2.8),
		Vector3(-1.2, 0, 6.4),
		Vector3(3.6, 0, 5.9),
		Vector3(7.4, 0, -2.6),
		Vector3(-7.1, 0, -3.4),
		Vector3(1.6, 0, -7.6),
		Vector3(10.8, 0, -1.2),
		Vector3(-10.2, 0, 1.5),
	]
	var wood := mats.tinted_wood(Color("6c543e"))
	var i := 0
	for at in benches:
		_aq("FBX/Bench_1.fbx", at, 1.0, float(i) * 0.7 + 0.4, wood)
		i += 1
	var lamps: Array[Vector3] = [
		Vector3(-5.6, 0, 4.15),
		Vector3(5.15, 0, 4.35),
		Vector3(-4.9, 0, -4.4),
		Vector3(4.7, 0, -4.55),
		Vector3(0.2, 0, 7.6),
		Vector3(8.4, 0, 0.2),
		Vector3(-8.2, 0, 0.15),
		Vector3(2.4, 0, -8.4),
	]
	for at in lamps:
		_lamp(at)


func _lamp(at: Vector3) -> void:
	var post := CylinderMesh.new()
	post.top_radius = 0.045
	post.bottom_radius = 0.07
	post.height = 2.55
	post.radial_segments = 8
	_add_mesh(post, mats.metal, at + Vector3(0, 1.28, 0), "LampPost")
	var base := CylinderMesh.new()
	base.top_radius = 0.14
	base.bottom_radius = 0.16
	base.height = 0.12
	_add_mesh(base, mats.metal, at + Vector3(0, 0.06, 0), "LampBase")
	var cage := SphereMesh.new()
	cage.radius = 0.16
	cage.height = 0.28
	cage.radial_segments = 8
	cage.rings = 4
	var glass_n := MeshInstance3D.new()
	glass_n.mesh = cage
	glass_n.material_override = mats.lantern_glass
	glass_n.position = at + Vector3(0, 2.55, 0)
	parent.add_child(glass_n)
	var light := OmniLight3D.new()
	light.light_color = Color("e7984c")
	light.light_energy = 0.85
	light.omni_range = 4.2
	light.shadow_enabled = false
	light.position = at + Vector3(0, 2.55, 0)
	light.add_to_group("park_lantern")
	parent.add_child(light)
	lanterns.append(light)


func _railings() -> void:
	# Iron railing along the east path for the pond-edge camera.
	var post := ParkMesh.pillow(Vector3(0.06, 0.85, 0.06), 4)
	var bar := ParkMesh.pillow(Vector3(0.9, 0.04, 0.04), 4)
	for i in 9:
		var z := -1.6 + float(i) * 0.85
		var x := 7.15
		_add_mesh(post, mats.metal, Vector3(x, 0.42, z), "RailPost")
		if i < 8:
			_add_mesh(bar, mats.metal, Vector3(x, 0.62, z + 0.42), "RailBar")


func _city() -> void:
	# South-facing terrace. A gap holds the clock tower.
	var specs: Array = [
		[-11.2, 3, 2],
		[-6.2, 2, 3],
		[-2.6, 2, 2],
		[8.6, 3, 2],
		[13.6, 2, 3],
	]
	for spec in specs:
		_kit_house(Vector3(float(spec[0]), 0.0, -12.45), Vector3.RIGHT, Vector3(0, 0, -1), int(spec[1]), 2, int(spec[2]), true)
	var z := 5.6
	for i in 4:
		var stories := 2 if i % 2 == 0 else 3
		_kit_house(Vector3(-12.85, 0.0, z), Vector3(0, 0, -1), Vector3(-1, 0, 0), 2, 2, stories, true)
		z -= 2.0 * TOWN_S + 0.45
	z = -5.4
	for i in 4:
		var stories2 := 3 if i % 2 == 0 else 2
		_kit_house(Vector3(12.85, 0.0, z), Vector3(0, 0, 1), Vector3(1, 0, 0), 2, 2, stories2, true)
		z += 2.0 * TOWN_S + 0.45


func _kit_house(corner: Vector3, right: Vector3, inward: Vector3, bays_w: int, bays_d: int, stories: int, chimney: bool) -> void:
	var step := TOWN_S
	for story in stories:
		var y := float(story) * step
		for i in bays_w:
			var along := (float(i) + 0.5) * step
			var front := corner + right * along + Vector3(0, y, 0)
			var file := "wall-window-shutters.fbx"
			if story == 0 and i == bays_w / 2:
				file = "wall-door.fbx"
			elif (i + story) % 3 == 0:
				file = "wall-window-glass.fbx"
			_town_face(file, front, _yaw_out(-inward), TOWN_S)
			if story == stories - 1:
				_town_face("overhang.fbx", front + Vector3(0, step * 0.62, 0), _yaw_out(-inward), TOWN_S)
			var back := corner + right * along + inward * (float(bays_d) * step) + Vector3(0, y, 0)
			_town_face("wall.fbx", back, _yaw_out(inward), TOWN_S)
		for j in bays_d:
			var deep := (float(j) + 0.5) * step
			var left := corner + inward * deep + Vector3(0, y, 0)
			var side_file := "wall-window-small.fbx" if (j + story) % 2 == 0 else "wall.fbx"
			_town_face(side_file, left, _yaw_out(-right), TOWN_S)
			var right_at := corner + right * (float(bays_w) * step) + inward * deep + Vector3(0, y, 0)
			_town_face("wall.fbx", right_at, _yaw_out(right), TOWN_S)
	var center := corner + right * (float(bays_w) * step * 0.5) + inward * (float(bays_d) * step * 0.5)
	center.y = float(stories) * step
	var yaw := _yaw_out(right)
	_town_xform("roof-gable.fbx", center, yaw, Vector3(float(bays_w) * step, 1.45, float(bays_d) * step))
	if chimney:
		_town_xform("chimney.fbx", center + right * 0.35 + Vector3(0, 0.15, 0), yaw, Vector3(1.2, 1.35, 1.2))


func _clock_tower() -> void:
	var corner := Vector3(4.55, 0.0, -12.45)
	var step := TOWN_S
	var stories := 6
	for story in stories:
		var y := float(story) * step
		for i in 2:
			for face_i in 4:
				var file := "wall-window-shutters.fbx" if story % 2 == 0 else "wall.fbx"
				if story == stories - 1:
					file = "wall.fbx"
				var along := (float(i) + 0.5) * step
				var face_at := Vector3.ZERO
				var outward := Vector3.FORWARD
				match face_i:
					0:
						face_at = corner + Vector3(along, y, 0.0)
						outward = Vector3(0, 0, 1)
					1:
						face_at = corner + Vector3(along, y, -2.0 * step)
						outward = Vector3(0, 0, -1)
					2:
						face_at = corner + Vector3(0.0, y, -along)
						outward = Vector3(-1, 0, 0)
					_:
						face_at = corner + Vector3(2.0 * step, y, -along)
						outward = Vector3(1, 0, 0)
				_town_face(file, face_at, _yaw_out(outward), TOWN_S)
	var top := corner + Vector3(step, float(stories) * step, -step)
	_town_xform("roof-point.fbx", top, 0.0, Vector3(step * 2.35, 4.4, step * 2.35))
	var face := CylinderMesh.new()
	face.top_radius = 0.62
	face.bottom_radius = 0.62
	face.height = 0.06
	face.radial_segments = 16
	var clock_mat := StandardMaterial3D.new()
	clock_mat.albedo_color = Color("f2e8d2")
	if ResourceLoader.exists("res://assets/park/generated/clock_face.png"):
		clock_mat.albedo_texture = load("res://assets/park/generated/clock_face.png")
	clock_mat.roughness = 0.45
	var disc := MeshInstance3D.new()
	disc.mesh = face
	disc.material_override = clock_mat
	disc.position = corner + Vector3(step, 5.2 * step, 0.18)
	disc.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(disc)


func _yaw_out(outward: Vector3) -> float:
	return atan2(-outward.z, outward.x)


func _town_face(file_name: String, face_bottom: Vector3, yaw: float, scale: float) -> void:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
	var origin := face_bottom - basis * Vector3(0.5, 0.0, 0.0)
	_town_place(file_name, Transform3D(basis, origin))


func _town_xform(file_name: String, origin: Vector3, yaw: float, scale: Vector3) -> void:
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	_town_place(file_name, Transform3D(basis, origin))


func _town_place(file_name: String, xform: Transform3D) -> void:
	var packed: PackedScene = _town_cache.get(file_name)
	if packed == null:
		var path := TOWN + file_name
		if not ResourceLoader.exists(path):
			return
		packed = load(path) as PackedScene
		if packed == null:
			return
		_town_cache[file_name] = packed
	var node := packed.instantiate() as Node3D
	if node == null:
		return
	node.transform = xform
	_town_finish(node)
	parent.add_child(node)


func _town_finish(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var source := mesh_node.get_active_material(0)
		if source is StandardMaterial3D:
			var painted := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
			painted.roughness = 0.62
			mesh_node.material_override = painted
	for child in node.get_children():
		_town_finish(child)


func _fruit() -> void:
	var apple := SphereMesh.new()
	apple.radius = 0.07
	apple.height = 0.14
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i in 16:
		var a := TAU * float(i) / 16.0
		xf.append(Transform3D(Basis.IDENTITY, Vector3(-7.4 + cos(a) * 0.7, 2.1 + rng.randf() * 0.6, -6.8 + sin(a) * 0.7)))
		cols.append(Color("a52b21"))
	_multi(apple, xf, cols, mats.solid(Color("a52b21"), 0.35), "Apples")
	var orange_xf: Array[Transform3D] = []
	var orange_c: Array[Color] = []
	for i in 14:
		var a := TAU * float(i) / 14.0
		orange_xf.append(Transform3D(Basis.IDENTITY, Vector3(7.6 + cos(a) * 0.65, 2.3 + rng.randf() * 0.5, -7.4 + sin(a) * 0.65)))
		orange_c.append(Color("e67828"))
	_multi(apple, orange_xf, orange_c, mats.solid(Color("e67828"), 0.4), "Oranges")


func _spawns() -> void:
	var jelly: Array[Vector3] = [
		Vector3(-6.8, 0.05, 1.8),
		Vector3(-5.4, 0.05, -3.1),
		Vector3(4.6, 0.05, 3.4),
		Vector3(6.1, 0.05, 0.6),
		Vector3(-2.2, 0.05, 5.8),
		Vector3(2.8, 0.05, -6.4),
		Vector3(5.4, 0.05, 7.2),
		Vector3(-7.6, 0.05, 6.2),
	]
	var veg: Array[Vector3] = [
		Vector3(-3.4, 0.05, 3.2),
		Vector3(8.6, 0.05, 2.4),
		Vector3(-4.8, 0.05, -6.2),
		Vector3(1.6, 0.05, 7.4),
	]
	for at in jelly:
		_marker(at, "jelly_spawn", Color("00a592"))
	for at in veg:
		_marker(at, "veg_spawn", Color("e67828"))
	_marker(Vector3(-1.6, -0.12, 1.1), "duck_spawn", Color("c39042"))
	_marker(Vector3(3.4, 0.2, 1.8), "pond_edge_hook", Color("24a4c6"))


func _marker(at: Vector3, group: String, color: Color) -> void:
	var node := Marker3D.new()
	node.position = at + Vector3(0, 0.2, 0)
	node.name = group + str(parent.get_child_count())
	node.add_to_group(group)
	parent.add_child(node)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.12
	ring.outer_radius = 0.18
	ring.rings = 8
	ring.ring_segments = 10
	var mesh_n := MeshInstance3D.new()
	mesh_n.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	mesh_n.material_override = mat
	mesh_n.position = at + Vector3(0, 0.04, 0)
	mesh_n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_n.add_to_group("park_marker_visual")
	parent.add_child(mesh_n)
	var label := Label3D.new()
	label.text = group.replace("_", " ")
	label.font_size = 14
	label.modulate = Color(1, 1, 1, 0.7)
	label.position = at + Vector3(0, 0.28, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 4
	label.add_to_group("park_debug_label")
	parent.add_child(label)


func _probe() -> void:
	var probe := ReflectionProbe.new()
	probe.size = Vector3(18, 6, 14)
	probe.origin_offset = Vector3(0, 1.2, 0)
	probe.position = Vector3(0, 1.0, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	probe.box_projection = true
	probe.interior = false
	parent.add_child(probe)


func _cutout() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/cutout.gdshader")
	if ResourceLoader.exists(AQ + "Textures/Plants_Atlas_1_Basecolor.png"):
		material.set_shader_parameter("albedo_tex", load(AQ + "Textures/Plants_Atlas_1_Basecolor.png"))
		material.set_shader_parameter("opacity_tex", load(AQ + "Textures/Plants_Atlas_1_Opacity.png"))
	return material


func _kit(file_name: String, height: float, at: Vector3, yaw: float, uniform_scale: float = 1.0, paint: Material = null) -> void:
	var glb := file_name.replace(".fbx", ".glb")
	var path := "res://assets/third_party/kenney/nature-kit/Models/GLTF format/" + glb
	if not ResourceLoader.exists(path):
		path = "res://assets/third_party/kenney/nature-kit/Models/FBX format/" + file_name.replace(".glb", ".fbx")
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	if node == null:
		return
	if height > 0.05:
		var mesh_node := _find_mesh(node)
		if mesh_node != null:
			var h := mesh_node.get_aabb().size.y
			if h > 0.05:
				node.scale = Vector3.ONE * (height / h)
	elif uniform_scale != 1.0:
		node.scale = Vector3.ONE * uniform_scale
	node.position = at
	node.rotation.y = yaw
	if paint != null:
		_paint(node, paint)
	elif glb.begins_with("tree_") or glb.begins_with("plant_"):
		_paint(node, mats.hedge)
	parent.add_child(node)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _aq(file_name: String, at: Vector3, scale: float, yaw: float, material: Material) -> void:
	var path := AQ + file_name
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	if node == null:
		return
	node.position = at
	node.rotation.y = yaw
	node.scale = Vector3.ONE * scale
	_paint(node, material)
	parent.add_child(node)


func _paint(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_paint(child, material)


func _add_mesh(mesh: Mesh, material: Material, at: Vector3, node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.name = node_name
	parent.add_child(node)
	return node


func _multi(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], material: Material, node_name: String, custom: Array = []) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if i < colors.size():
			mm.set_instance_color(i, colors[i])
		if i < custom.size():
			mm.set_instance_custom_data(i, custom[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.name = node_name
	parent.add_child(node)

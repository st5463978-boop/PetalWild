class_name RoadDressing
extends RefCounted

const STONE := Color("#4a4038")
const STRIP := Color("#6a5e4c")
const LAWN := Color("#3f6a32")
const BENCH := [
	[Vector3(0, 0.22, 0), Vector3(0.72, 0.05, 0.28), Color("#8d6244")],
	[Vector3(0, 0.36, -0.12), Vector3(0.72, 0.2, 0.05), Color("#a87852")],
	[Vector3(-0.3, 0.11, 0), Vector3(0.05, 0.22, 0.24), Color("#6b4a32")],
	[Vector3(0.3, 0.11, 0), Vector3(0.05, 0.22, 0.24), Color("#6b4a32")],
]

var pieces: Array = []
var parent: Node3D

func load_data() -> void:
	var text := FileAccess.get_file_as_string("res://data/road_pieces.json")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("road_pieces.json missing")
		pieces = []
		return
	pieces = parsed.get("pieces", [])

func build(host: Node3D) -> void:
	parent = host
	load_data()
	for entry in pieces:
		_spawn(entry)
	sync(false)

func sync(show: bool) -> void:
	if parent == null:
		return
	for node in parent.get_tree().get_nodes_in_group("parish_road"):
		var body := node as Node3D
		if body:
			body.visible = show

func expected(group: String) -> int:
	var n := 0
	for entry in pieces:
		if str(entry.get("group", "")) == group:
			n = maxi(n, int(entry.get("expected", 1)))
	return n

func page_for(group: String) -> String:
	for entry in pieces:
		if str(entry.get("group", "")) == group:
			return str(entry.get("page", ""))
	return ""

func line(group: String) -> String:
	if count(group) != expected(group) or expected(group) <= 0:
		return ""
	return page_for(group)

func count(group: String) -> int:
	if parent == null:
		return 0
	var want: Array = []
	for entry in pieces:
		if str(entry.get("group", "")) == group:
			want.append(entry)
	if want.is_empty():
		return 0
	var n := 0
	for node in parent.get_tree().get_nodes_in_group(group):
		var body := node as Node3D
		if body == null or not body.visible:
			continue
		if not _matches(body, want):
			return -1
		n += 1
	return n

func all_hidden() -> bool:
	var seen := {}
	for entry in pieces:
		var g := str(entry.get("group", ""))
		if seen.get(g, false):
			continue
		seen[g] = true
		if count(g) != 0:
			return false
	return true

func all_shown() -> bool:
	var seen := {}
	for entry in pieces:
		var g := str(entry.get("group", ""))
		if seen.get(g, false):
			continue
		seen[g] = true
		if count(g) != expected(g):
			return false
	return true

func page_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	var seen := {}
	for entry in pieces:
		var text := str(entry.get("page", ""))
		if text == "" or seen.get(text, false):
			continue
		var g := str(entry.get("group", ""))
		if line(g) == "":
			continue
		seen[text] = true
		out.append(text)
	return out

func card_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	var seen := {}
	for entry in pieces:
		if not bool(entry.get("card", false)):
			continue
		var text := str(entry.get("page", ""))
		if text == "" or seen.get(text, false):
			continue
		if line(str(entry.get("group", ""))) == "":
			continue
		seen[text] = true
		out.append(text)
	return out

func _matches(body: Node3D, want: Array) -> bool:
	var pos := body.global_position
	var hit: Dictionary = {}
	for entry in want:
		var at: Array = entry.get("pos", [0, 0, 0])
		if at.size() < 3:
			continue
		if absf(pos.x - float(at[0])) <= 0.25 and absf(pos.z - float(at[2])) <= 0.25:
			hit = entry
			break
	if hit.is_empty():
		return false
	if GardenLayout.in_plots(pos.x, pos.z) and str(hit.get("id", "")) != "inside_path":
		if pos.z > -10.5:
			return false
	var kind := str(hit.get("kind", ""))
	if kind == "bell":
		var bell := body as PlantView
		return bell != null and bell.plant_id == "meadowbell" and bell.scale.y >= 0.35 and bell.scale.y <= 0.65
	if kind == "bench":
		var planks := 0
		for child in body.get_children():
			if child is MeshInstance3D:
				planks += 1
		return planks >= 4
	if kind == "lawn":
		var lawn := body as MeshInstance3D
		if lawn == null or not (lawn.mesh is CylinderMesh):
			return false
		return _albedo(lawn, LAWN)
	var mesh := body as MeshInstance3D
	if mesh == null or not (mesh.mesh is BoxMesh):
		return false
	if kind == "stone":
		return _albedo(mesh, STONE)
	return _albedo(mesh, STRIP)

func _albedo(mesh: MeshInstance3D, color: Color) -> bool:
	var mat := mesh.material_override as StandardMaterial3D
	return mat != null and mat.albedo_color.is_equal_approx(color)

func _spawn(entry: Dictionary) -> void:
	var kind := str(entry.get("kind", "strip"))
	var at: Array = entry.get("pos", [0.0, 0.0, 0.0])
	var pos := Vector3(float(at[0]), float(at[1]), float(at[2]))
	var node: Node3D
	if kind == "bell":
		var bell := PlantView.new()
		bell.position = pos
		parent.add_child(bell)
		bell.show_plant("meadowbell", 0.4, 0.8, 0.5)
		node = bell
	elif kind == "bench":
		node = Node3D.new()
		node.position = pos
		var rot = entry.get("rot_y", 0.0)
		if typeof(rot) == TYPE_FLOAT:
			node.rotation.y = float(rot)
		parent.add_child(node)
		for part in BENCH:
			var plank := BoxMesh.new()
			plank.size = part[1]
			var bit := _box(plank, part[2], 0.84)
			bit.position = part[0]
			node.add_child(bit)
	elif kind == "lawn":
		var disc := CylinderMesh.new()
		disc.top_radius = float(entry.get("radius", 0.85))
		disc.bottom_radius = disc.top_radius
		disc.height = 0.04
		disc.radial_segments = 16
		var lawn := MeshInstance3D.new()
		lawn.mesh = disc
		lawn.material_override = _mat(LAWN, 0.96)
		lawn.position = pos
		lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(lawn)
		node = lawn
	else:
		var box := BoxMesh.new()
		var size: Array = entry.get("size", [0.46, 0.07, 0.32] if kind == "stone" else [1.2, 0.03, 1.05])
		box.size = Vector3(float(size[0]), float(size[1]), float(size[2]))
		var mesh := MeshInstance3D.new()
		mesh.mesh = box
		var color := STONE if kind == "stone" else STRIP
		if entry.has("albedo"):
			color = Color(str(entry.get("albedo")))
		mesh.material_override = _mat(color, 0.92 if kind == "stone" else 0.96)
		mesh.position = pos
		mesh.rotation.y = float(entry.get("rot_y", 0.0))
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh)
		node = mesh
	node.visible = false
	node.add_to_group("parish_road")
	node.add_to_group(str(entry.get("group", "parish_road")))

func _box(mesh: Mesh, color: Color, rough: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color, rough)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat

class_name GrokTown
extends Node3D

## The square beyond the hedge. Layout, door steps, and the planted court
## come from data/town.json. Meshes are stand-ins, the same way the parish is built.

const DATA := "res://data/town.json"

var spec: Dictionary = {}
var records: Dictionary = {}
var civic_ids: PackedStringArray = PackedStringArray()
var piece_total := 0
var planter_total := 0
var gate_yaw_deg := 0.0
var gate_faces := ""
var bounds := Rect2(-12, -12, 24, 24)
var _built := false


func setup() -> void:
	if _built:
		return
	_built = true
	_load()
	position = _vec3(spec.get("origin", [0, 0, -34]), Vector3(0, 0, -34))
	_ground()
	_gate()
	_hall()
	_stalls()
	_civics()
	_court()
	_measure_bounds()


func _ready() -> void:
	setup()


func focus_point() -> Vector3:
	return global_position + _vec3(spec.get("square", [0, 0, 0]), Vector3.ZERO)


func piece_count() -> int:
	return piece_total


func record(id: String) -> Dictionary:
	var found: Variant = records.get(id, {})
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return found


func step_fits(id: String) -> bool:
	var row := record(id)
	if row.is_empty() or not row.has("door_w"):
		return false
	var door_w := float(row["door_w"])
	var step_w := float(row["step_w"])
	var extra := _max_extra()
	return step_w + 0.001 >= door_w and step_w <= door_w + extra + 0.001


func step_width(id: String) -> float:
	return float(record(id).get("step_w", 0.0))


func old_step_width(id: String) -> float:
	return float(record(id).get("old_step_w", 0.0))


func door_color(id: String) -> Color:
	var raw := str(record(id).get("door_color", "#000000"))
	return Color(raw)


func stall_gap() -> float:
	return float(record("market_row").get("gap", -1.0))


func marker_uv(world: Vector3) -> Vector2:
	var local := world - global_position
	var uv := Vector2(
		inverse_lerp(bounds.position.x, bounds.end.x, local.x),
		inverse_lerp(bounds.position.y, bounds.end.y, local.z)
	)
	return uv.clamp(Vector2.ZERO, Vector2.ONE)


func card_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("%s faces the hedge road." % str(record("parish_gate").get("name", "Parish Gate")))
	lines.append("Town Hall keeps %d planters by the door." % planter_total)
	lines.append("Market Row sits against the hall gable.")
	for id in civic_ids:
		var fit := "steps meet the door" if step_fits(id) else "steps are wide"
		lines.append("%s · %s" % [str(record(id).get("name", id)), fit])
	lines.append("%d beds, flowers and path tiles in the court." % piece_total)
	return lines


func spot_uvs() -> Array:
	var spots: Array = []
	for id_v in records.keys():
		var id := str(id_v)
		var row := record(id)
		if not row.has("at"):
			continue
		var at := _as_vec3(row.get("at", null), Vector3.ZERO)
		var uv := Vector2(
			inverse_lerp(bounds.position.x, bounds.end.x, at.x),
			inverse_lerp(bounds.position.y, bounds.end.y, at.z)
		)
		spots.append({"id": id, "uv": uv, "name": str(row.get("name", id))})
	return spots


func _load() -> void:
	var text := FileAccess.get_file_as_string(DATA)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Missing %s" % DATA)
		spec = {}
		return
	spec = parsed


func _ground() -> void:
	_box(self, Vector3(0, -0.06, -1.0), Vector3(28, 0.08, 26), Color("#3d6a3c"), "Lawn")


func _gate() -> void:
	var row: Dictionary = spec.get("gate", {})
	var at := _vec3(row.get("at", [0, 0, 9]), Vector3(0, 0, 9))
	gate_yaw_deg = float(row.get("yaw_deg", 0.0))
	gate_faces = str(row.get("faces", ""))
	var root := Node3D.new()
	root.name = "ParishGate"
	root.position = at
	root.rotation_degrees = Vector3(0, gate_yaw_deg, 0)
	add_child(root)
	_box(root, Vector3(-1.35, 1.15, 0), Vector3(0.42, 2.3, 0.42), Color("#4a4038"), "PostL")
	_box(root, Vector3(1.35, 1.15, 0), Vector3(0.42, 2.3, 0.42), Color("#4a4038"), "PostR")
	_box(root, Vector3(0, 2.2, 0), Vector3(3.2, 0.28, 0.5), Color("#3a342c"), "Lintel")
	_sign(root, str(row.get("name", "Parish Gate")), Vector3(0, 2.7, 0))
	records["parish_gate"] = {"name": str(row.get("name", "Parish Gate")), "at": at, "yaw_deg": gate_yaw_deg, "faces": gate_faces}


func _hall() -> void:
	var row: Dictionary = spec.get("hall", {})
	var at := _vec3(row.get("at", Vector3.ZERO), Vector3.ZERO)
	var body := _vec3(row.get("body", [4, 2, 3]), Vector3(4, 2, 3))
	var root := _shell(str(row.get("id", "town_hall")), str(row.get("name", "Town Hall")), at, body, row.get("door", {}))
	var door: Dictionary = row.get("door", {})
	var door_w := float(door.get("w", 1.0))
	var planter_n := int(row.get("planters", 0))
	for i in planter_n:
		var side := -1.0 if i == 0 else 1.0
		_box(root, Vector3(side * (door_w * 0.5 + 0.45), 0.28, body.z * 0.5 + 0.35), Vector3(0.42, 0.36, 0.42), Color("#8d4b32"), "Planter%d" % i)
		_box(root, Vector3(side * (door_w * 0.5 + 0.45), 0.58, body.z * 0.5 + 0.35), Vector3(0.28, 0.32, 0.28), Color("#3f8a45"), "PlanterLeaf%d" % i)
		planter_total += 1
	records["town_hall"] = {
		"name": str(row.get("name", "Town Hall")),
		"at": at,
		"body": body,
		"gable": str(row.get("gable", "-x")),
		"planters": planter_total,
	}


func _stalls() -> void:
	var row: Dictionary = spec.get("stalls", {})
	var hall: Dictionary = record("town_hall")
	var hall_at := _as_vec3(hall.get("at", null), Vector3.ZERO)
	var body := _as_vec3(hall.get("body", null), Vector3(4, 2, 3))
	var depth := float(row.get("depth", 1.2))
	var width := float(row.get("width", 1.3))
	var count := int(row.get("count", 1))
	var face_x := hall_at.x - body.x * 0.5
	var center_x := face_x - depth * 0.5
	var root := Node3D.new()
	root.name = "MarketRow"
	add_child(root)
	for i in count:
		var z := hall_at.z + (float(i) - float(count - 1) * 0.5) * (width + 0.12)
		var stall := _box(root, Vector3(center_x, 0.85, z), Vector3(depth, 1.5, width), Color("#c4653d"), "Stall%d" % i)
		_box(stall, Vector3(0, 0.82, 0), Vector3(depth + 0.18, 0.08, width + 0.12), Color("#f3e2b0"), "Awning")
	var gap := absf((center_x + depth * 0.5) - face_x)
	records["market_row"] = {
		"name": str(row.get("name", "Market Row")),
		"at": Vector3(center_x, 0, hall_at.z),
		"gap": gap,
		"count": count,
	}


func _civics() -> void:
	var civic: Variant = spec.get("civic", [])
	if typeof(civic) != TYPE_ARRAY:
		return
	for item_v in civic:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		var id := str(item.get("id", "building"))
		var at := _vec3(item.get("at", Vector3.ZERO), Vector3.ZERO)
		var body := _vec3(item.get("body", [3, 2, 2.5]), Vector3(3, 2, 2.5))
		var door: Dictionary = item.get("door", {})
		var root := _shell(id, str(item.get("name", id)), at, body, door)
		var door_w := float(door.get("w", 1.0))
		var step_w := door_w + _margin() * 2.0
		var tread := float(spec.get("step_fit", {}).get("tread", 0.7))
		var rise := float(spec.get("step_fit", {}).get("rise", 0.14))
		_box(root, Vector3(0, rise * 0.5, body.z * 0.5 + tread * 0.5), Vector3(step_w, rise, tread), Color("#8a8178"), "Steps")
		civic_ids.append(id)
		records[id] = {
			"name": str(item.get("name", id)),
			"at": at,
			"body": body,
			"door_w": door_w,
			"step_w": step_w,
			"old_step_w": float(item.get("old_step_w", 0.0)),
			"door_color": str(door.get("color", "#5c4034")),
		}


func _court() -> void:
	var court: Variant = spec.get("court", {})
	if typeof(court) != TYPE_DICTIONARY:
		return
	var body: Dictionary = court
	for kind_v in body.keys():
		var kind := str(kind_v)
		var row_v: Variant = body[kind]
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var count := int(row.get("count", 0))
		var cols := maxi(int(row.get("cols", 1)), 1)
		var origin := _vec3(row.get("origin", Vector3.ZERO), Vector3.ZERO)
		var step := _vec3(row.get("step", Vector3.ONE), Vector3.ONE)
		var size := _vec3(row.get("size", Vector3(0.4, 0.2, 0.4)), Vector3(0.4, 0.2, 0.4))
		var color := Color(str(row.get("color", "#88aa66")))
		var alt := Color(str(row.get("alt", row.get("color", "#88aa66"))))
		for i in count:
			var col := i % cols
			var line := int(i / cols)
			var at := origin + Vector3(step.x * float(col), step.y, step.z * float(line))
			var tint := color if i % 2 == 0 else alt
			var piece := _box(self, at, size, tint, "%s%d" % [kind, i])
			piece.add_to_group("grok_town_piece")
			piece_total += 1


func _shell(id: String, building_name: String, at: Vector3, body: Vector3, door_v: Variant) -> Node3D:
	var root := Node3D.new()
	root.name = id
	root.position = at
	add_child(root)
	_box(root, Vector3(0, body.y * 0.5, 0), body, Color("#c4a574"), "Body")
	_box(root, Vector3(0, body.y + 0.18, 0), Vector3(body.x + 0.3, 0.16, body.z + 0.3), Color("#6b3a32"), "Roof")
	var door: Dictionary = door_v if typeof(door_v) == TYPE_DICTIONARY else {}
	var door_w := float(door.get("w", 1.0))
	var door_h := float(door.get("h", 2.0))
	var door_color := Color(str(door.get("color", "#5c4034")))
	_box(root, Vector3(0, door_h * 0.5, body.z * 0.5 + 0.04), Vector3(door_w, door_h, 0.08), door_color, "Door")
	_sign(root, building_name, Vector3(0, body.y + 0.55, body.z * 0.5))
	return root


func _measure_bounds() -> void:
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	var first := true
	for id_v in records.keys():
		var at: Vector3 = record(str(id_v)).get("at", Vector3.ZERO)
		if first:
			min_x = at.x
			max_x = at.x
			min_z = at.z
			max_z = at.z
			first = false
			continue
		min_x = minf(min_x, at.x)
		max_x = maxf(max_x, at.x)
		min_z = minf(min_z, at.z)
		max_z = maxf(max_z, at.z)
	bounds = Rect2(min_x - 3.0, min_z - 3.0, (max_x - min_x) + 6.0, (max_z - min_z) + 6.0)


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color, node_name: String) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.94
	mesh_node.material_override = mat
	mesh_node.position = at
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_node)
	return mesh_node


func _sign(parent: Node3D, text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 42
	label.pixel_size = 0.0045
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("f7f1e6")
	label.outline_modulate = Color("1c2418")
	label.outline_size = 6
	parent.add_child(label)


func _margin() -> float:
	return float(spec.get("step_fit", {}).get("side_margin", 0.12))


func _max_extra() -> float:
	return float(spec.get("step_fit", {}).get("max_extra", 0.35))


func _as_vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	return fallback


func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_ARRAY:
		return fallback
	var row: Array = value
	if row.size() < 3:
		return fallback
	return Vector3(float(row[0]), float(row[1]), float(row[2]))

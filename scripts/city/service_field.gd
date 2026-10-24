class_name ServiceField
extends RefCounted

## Coarse bed grid. Each stamp paints one catalog channel with linear radius falloff.
## Contribution is strength * (1 - distance / radius), and 0 past the rim.

var width := 10
var height := 8
var charged_day := 0
var weights: Dictionary = {}
var catalog: Dictionary = {}
var stamps: Dictionary = {}
var bias_for: Callable = Callable()

var _cells: Dictionary = {}


func _init() -> void:
	width = GardenLayout.BED_W
	height = GardenLayout.BED_H
	_load_catalog()


func setup(columns: int, rows: int) -> void:
	width = maxi(columns, 1)
	height = maxi(rows, 1)
	charged_day = 0
	stamps.clear()
	_cells.clear()
	_load_catalog()


func stamp(service_id: String, cell: Vector2i, radius: float, strength: float) -> void:
	if service_id == "":
		return
	stamps[service_id] = {
		"x": cell.x,
		"z": cell.y,
		"radius": maxf(radius, 0.0),
		"strength": maxf(strength, 0.0),
	}
	_rebuild()


func clear_service(service_id: String) -> void:
	if not stamps.has(service_id):
		return
	stamps.erase(service_id)
	_rebuild()


func sample(cell: Vector2i, channel: String) -> float:
	if channel == "quality":
		return quality_at(cell)
	if not _inside(cell):
		return 0.0
	return clampf(_channel_at(cell, channel) + _bias(cell, channel), 0.0, 1.0)


func quality_at(cell: Vector2i) -> float:
	if not _inside(cell):
		return 0.0
	var total := 0.0
	for key_v in weights.keys():
		var channel := str(key_v)
		if channel == "quality":
			continue
		total += float(weights[channel]) * sample(cell, channel)
	return total


func _bias(cell: Vector2i, channel: String) -> float:
	if not bias_for.is_valid():
		return 0.0
	return float(bias_for.call(cell, channel))


func quality_mean() -> float:
	if width <= 0 or height <= 0:
		return 0.0
	var total := 0.0
	var count := 0
	for x in width:
		for z in height:
			total += quality_at(Vector2i(x, z))
			count += 1
	if count <= 0:
		return 0.0
	return total / float(count)


func channel_max(channel: String) -> float:
	var best := 0.0
	for x in width:
		for z in height:
			best = maxf(best, sample(Vector2i(x, z), channel))
	return best


func upkeep_total() -> int:
	var due := 0
	for key_v in stamps.keys():
		due += _upkeep_for(str(key_v))
	return due


func charge_daily(day: int) -> int:
	if day <= charged_day:
		return 0
	charged_day = day
	var due := upkeep_total()
	if due <= 0:
		return 0
	var economy := autoload("Economy")
	if economy == null or not economy.has_method("deduct"):
		return 0
	return int(economy.call("deduct", due))


func to_state() -> Dictionary:
	var rows: Array = []
	var ids: Array = stamps.keys()
	ids.sort()
	for key_v in ids:
		var service_id := str(key_v)
		var body: Dictionary = stamps[service_id]
		rows.append({
			"id": service_id,
			"x": int(body.get("x", 0)),
			"z": int(body.get("z", 0)),
			"radius": float(body.get("radius", 0.0)),
			"strength": float(body.get("strength", 0.0)),
		})
	return {"services": rows, "charged_day": charged_day}


func apply_state(data: Variant) -> void:
	stamps.clear()
	_cells.clear()
	charged_day = 0
	if typeof(data) != TYPE_DICTIONARY:
		return
	var body: Dictionary = data
	charged_day = int(body.get("charged_day", 0))
	var rows: Variant = body.get("services", [])
	if typeof(rows) != TYPE_ARRAY:
		return
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		stamp(
			str(row.get("id", "")),
			Vector2i(int(row.get("x", 0)), int(row.get("z", 0))),
			float(row.get("radius", 0.0)),
			float(row.get("strength", 0.0))
		)


func _channel_at(cell: Vector2i, channel: String) -> float:
	var row: Variant = _cells.get(_key(cell), {})
	if typeof(row) != TYPE_DICTIONARY:
		return 0.0
	return float((row as Dictionary).get(channel, 0.0))


func _rebuild() -> void:
	_cells.clear()
	for key_v in stamps.keys():
		var service_id := str(key_v)
		var body: Dictionary = stamps[service_id]
		var channel := _channel_for(service_id)
		if channel == "":
			continue
		var origin := Vector2i(int(body.get("x", 0)), int(body.get("z", 0)))
		var radius := float(body.get("radius", 0.0))
		var strength := float(body.get("strength", 0.0))
		var reach := int(ceil(radius))
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				var cell := origin + Vector2i(dx, dz)
				if not _inside(cell):
					continue
				var dist := origin.distance_to(cell)
				var add := _falloff(dist, radius, strength)
				if add <= 0.0:
					continue
				_paint(cell, channel, add)


func _paint(cell: Vector2i, channel: String, amount: float) -> void:
	var key := _key(cell)
	var row: Dictionary = {}
	var existing: Variant = _cells.get(key, {})
	if typeof(existing) == TYPE_DICTIONARY:
		row = (existing as Dictionary).duplicate()
	row[channel] = minf(1.0, float(row.get(channel, 0.0)) + amount)
	_cells[key] = row


func _falloff(dist: float, radius: float, strength: float) -> float:
	if dist > radius:
		return 0.0
	if radius <= 0.0:
		if dist <= 0.0:
			return strength
		return 0.0
	return strength * (1.0 - dist / radius)


static func autoload(node_name: String) -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		if tree.root != null:
			return tree.root.get_node_or_null(node_name)
	return null


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _catalog_id(service_id: String) -> String:
	var cut := service_id.find("#")
	if cut == -1:
		return service_id
	return service_id.substr(0, cut)


func _channel_for(service_id: String) -> String:
	var row: Dictionary = catalog.get(_catalog_id(service_id), {})
	return str(row.get("channel", ""))


func _upkeep_for(service_id: String) -> int:
	var row: Dictionary = catalog.get(_catalog_id(service_id), {})
	return maxi(int(row.get("upkeep", 0)), 0)


func _load_catalog() -> void:
	weights = {}
	catalog = {}
	var text := FileAccess.get_file_as_string("res://data/services.json")
	if text == "":
		push_error("Missing data file res://data/services.json")
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in res://data/services.json")
		return
	var root: Dictionary = parsed
	var weight_body: Variant = root.get("quality_weights", {})
	if typeof(weight_body) == TYPE_DICTIONARY:
		weights = weight_body
	var rows: Variant = root.get("services", [])
	if typeof(rows) != TYPE_ARRAY:
		return
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var service_id := str(row.get("id", ""))
		if service_id == "":
			continue
		catalog[service_id] = row

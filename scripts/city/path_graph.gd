class_name PathGraph
extends RefCounted

## AStar3D over catalog walks, road stones, and placed paths.
## Hourly footfall feeds market demand. Open-stall footfall sells stock for Bram.
## Tuning lives in data/paths.json. A CausalLog, when bound, records the reason.

var seed := 4242
var hour_footfall := 0
var footfall_total := 0
var census_for: Callable = Callable()

var log: CausalLog
var soil: RefCounted
var ecology: Node
var rng := RandomNumberGenerator.new()

var step := 1.5
var connect_radius := 2.4
var anchors: Array = []
var runs: Array = []
var trips: Array = []
var walk: Dictionary = {}
var walk_weather: Array = []
var stall: Dictionary = {}
var _plant_order: Array[String] = []
var _prices: Dictionary = {}
var _names: Dictionary = {}

var _astar := AStar3D.new()
var _anchor_ids: Dictionary = {}
var _point_ids: Array[int] = []
var _extras: Dictionary = {}
var _next_id := 1
var _edge_footfall: Dictionary = {}
var _placed: Array = []
var _roads: Array = []
var _stones: Array[Vector3] = []
var _seen_hour := -1
var _sold_hour := -1
var _open_hour := 0.0


func _init() -> void:
	rng.seed = seed
	_load()


func setup(causal: CausalLog, beds: RefCounted, parish: Node) -> void:
	log = causal
	soil = beds
	ecology = parish
	_load()
	rebuild()


func reseed(next_seed: int) -> void:
	seed = next_seed
	rng.seed = seed


func rebuild() -> void:
	_astar = AStar3D.new()
	_anchor_ids.clear()
	_point_ids.clear()
	_extras.clear()
	_next_id = 1
	_add_anchors()
	_add_runs()
	_add_segments(_placed)
	_add_segments(_roads)
	_add_stone_points()
	_snap_extras()


func point_count() -> int:
	return _astar.get_point_count()


func has_anchor(anchor_id: String) -> bool:
	return _anchor_ids.has(anchor_id)


func footfall_signal() -> float:
	return float(hour_footfall)


func path_between(from_id: String, to_id: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not _anchor_ids.has(from_id) or not _anchor_ids.has(to_id):
		return out
	var from_point := int(_anchor_ids[from_id])
	var to_point := int(_anchor_ids[to_id])
	if from_point == to_point:
		out.append(_astar.get_point_position(from_point))
		return out
	var ids := _astar.get_id_path(from_point, to_point)
	for pid in ids:
		out.append(_astar.get_point_position(int(pid)))
	return out


func reaches(from_at: Vector3, anchor_id: String) -> bool:
	if not _anchor_ids.has(anchor_id) or _point_ids.is_empty():
		return false
	var from_point := _nearest(from_at)
	var to_point := int(_anchor_ids[anchor_id])
	if not _close_enough(from_point, from_at):
		return false
	if from_point == to_point:
		return true
	return _astar.get_id_path(from_point, to_point).size() >= 2


func reaches_point(from_at: Vector3, to_at: Vector3) -> bool:
	if _point_ids.is_empty():
		return false
	var from_point := _nearest(from_at)
	var to_point := _nearest(to_at)
	if not _close_enough(from_point, from_at) or not _close_enough(to_point, to_at):
		return false
	if from_point == to_point:
		return from_at.distance_to(to_at) <= connect_radius
	return _astar.get_id_path(from_point, to_point).size() >= 2


func edge_digest() -> String:
	var keys: Array = _edge_footfall.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key in keys:
		parts.append("%s=%d" % [str(key), int(_edge_footfall[key])])
	return "|".join(parts)


func add_stones(points: Array) -> void:
	for item in points:
		if item is Vector3:
			_stones.append(item)
		else:
			var at := _vec(item)
			if at != Vector3.ZERO or _looks_like_origin(item):
				_stones.append(at)
	rebuild()


func add_placed(path_id: String, from_at: Vector3, to_at: Vector3) -> void:
	_placed.append({
		"kind": "placed",
		"id": path_id,
		"from": [from_at.x, from_at.y, from_at.z],
		"to": [to_at.x, to_at.y, to_at.z],
	})
	rebuild()


func ingest_scene(root: Node) -> void:
	_stones.clear()
	_roads.clear()
	if root == null:
		rebuild()
		return
	var index := 0
	for child in root.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or not _on_road(mesh_node):
			continue
		var box := mesh_node.mesh as BoxMesh
		if box == null:
			continue
		var span := maxf(box.size.x, box.size.z)
		if span >= 0.7:
			var ends := _segment_ends(mesh_node)
			if ends.size() == 2:
				_roads.append({
					"kind": "placed",
					"id": "road-%d" % index,
					"from": [ends[0].x, ends[0].y, ends[0].z],
					"to": [ends[1].x, ends[1].y, ends[1].z],
				})
				index += 1
		else:
			_stones.append(_to_world(mesh_node, Vector3.ZERO))
	rebuild()


func tick() -> void:
	var key := _hour_key()
	if key < 0 or key == _seen_hour:
		return
	_seen_hour = key
	hour_footfall = 0
	var census := _census()
	_open_hour = float(census.get("hour", 0.0))
	if not _weather_ok(str(census.get("weather", ""))):
		return
	var plan := _plan(census)
	for trip_id in plan:
		hour_footfall += _walk(str(trip_id))
	footfall_total += hour_footfall
	if hour_footfall <= 0:
		return
	var why := "Footfall +%d because residents %d, creatures %d, ripe beds %d walked toward the stall" % [
		hour_footfall,
		int(census.get("residents", 0)),
		int(census.get("creatures", 0)),
		int(census.get("ripe", 0)),
	]
	_write_log("footfall", "market", why)


func settle_stall() -> int:
	if _seen_hour < 0 or _sold_hour == _seen_hour:
		return 0
	_sold_hour = _seen_hour
	if not _stall_open(_open_hour):
		return 0
	var need := int(stall.get("footfall_per_sale", 1))
	if need <= 0:
		need = 1
	var sales := mini(maxi(int(stall.get("max_sales", 1)), 0), int(floor(float(hour_footfall) / float(need))))
	if sales <= 0:
		return 0
	var economy := ServiceField.autoload("Economy")
	if economy == null or not economy.has_method("count"):
		return 0
	var left := sales
	var coins := 0
	var parts := PackedStringArray()
	for plant_id in _plant_ids():
		if left <= 0:
			break
		var have := int(economy.call("count", plant_id))
		var moved := mini(have, left)
		if moved <= 0:
			continue
		if not bool(economy.call("take", plant_id, moved)):
			continue
		var price := _price(plant_id) * moved
		economy.call("earn", price)
		coins += price
		left -= moved
		parts.append("%d %s" % [moved, plant_id])
	if parts.is_empty():
		return 0
	var why := "%s's stall sold %s for %d because footfall %d crossed the path" % [
		_keeper_name(),
		", ".join(parts),
		coins,
		hour_footfall,
	]
	_write_log("stall_sale", str(stall.get("keeper", "bram")), why)
	return coins


func to_state() -> Array:
	var rows: Array = []
	for item in _placed:
		if typeof(item) == TYPE_DICTIONARY:
			rows.append((item as Dictionary).duplicate(true))
	var keys: Array = _edge_footfall.keys()
	keys.sort()
	for key in keys:
		var count := int(_edge_footfall[key])
		if count <= 0:
			continue
		rows.append({"kind": "footfall", "edge": str(key), "count": count})
	if _seen_hour >= 0 or hour_footfall > 0 or footfall_total > 0 or _sold_hour >= 0:
		rows.append({
			"kind": "meta",
			"seen_hour": _seen_hour,
			"sold_hour": _sold_hour,
			"hour_footfall": hour_footfall,
			"total": footfall_total,
			"seed": seed,
			"rng_state": str(rng.state),
			"open_hour": _open_hour,
		})
	return rows


func apply_state(data: Variant) -> void:
	_placed.clear()
	_roads.clear()
	_stones.clear()
	_edge_footfall.clear()
	hour_footfall = 0
	footfall_total = 0
	_seen_hour = -1
	_sold_hour = -1
	_open_hour = 0.0
	var meta: Dictionary = {}
	for item in _rows_from(data):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var kind := str(row.get("kind", ""))
		if kind == "footfall":
			var edge := str(row.get("edge", ""))
			if edge != "":
				_edge_footfall[edge] = maxi(int(row.get("count", 0)), 0)
		elif kind == "meta":
			meta = row
		elif kind == "placed" or row.has("from"):
			_placed.append(row.duplicate(true))
	if meta.has("seed"):
		reseed(int(meta.get("seed", seed)))
	var saved_rng := str(meta.get("rng_state", ""))
	if saved_rng != "":
		rng.state = int(saved_rng)
	if meta.has("seen_hour"):
		_seen_hour = int(meta.get("seen_hour", -1))
	if meta.has("sold_hour"):
		_sold_hour = int(meta.get("sold_hour", -1))
	hour_footfall = int(meta.get("hour_footfall", 0))
	footfall_total = int(meta.get("total", 0))
	_open_hour = float(meta.get("open_hour", 0.0))
	if footfall_total <= 0:
		footfall_total = _sum_edges()
	rebuild()


func _write_log(kind: String, target: String, why: String) -> void:
	if log == null:
		return
	log.add({
		"kind": kind,
		"target": target,
		"cause": why,
		"summary": why,
	}, _now_min())


func _plan(census: Dictionary) -> Array:
	var chosen: Array = []
	var cap := maxi(int(walk.get("cap", 8)), 0)
	if _stall_open(_open_hour):
		_add_kind(chosen, "keeper", maxi(int(walk.get("keeper", 0)), 0))
	_add_kind(chosen, "resident", maxi(int(census.get("residents", 0)), 0) * maxi(int(walk.get("resident_each", 1)), 0))
	_add_kind(chosen, "creature", maxi(int(census.get("creatures", 0)), 0) * maxi(int(walk.get("creature_each", 1)), 0))
	_add_kind(chosen, "visitor", maxi(int(census.get("ripe", 0)), 0) * maxi(int(walk.get("ripe_each", 1)), 0))
	var jitter := int(walk.get("jitter", 1))
	if jitter > 1:
		var extra := rng.randi() % jitter
		while extra > 0:
			var trip_id := _pick("")
			if trip_id != "":
				chosen.append(trip_id)
			extra -= 1
	if cap >= 0 and chosen.size() > cap:
		chosen = chosen.slice(0, cap)
	return chosen


func _add_kind(chosen: Array, kind: String, count: int) -> void:
	var left := count
	while left > 0:
		var trip_id := _pick(kind)
		if trip_id != "":
			chosen.append(trip_id)
		left -= 1


func _pick(kind: String) -> String:
	var options: Array[String] = []
	for item in trips:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		if kind != "" and str(row.get("kind", "")) != kind:
			continue
		var trip_id := str(row.get("id", ""))
		if trip_id != "":
			options.append(trip_id)
	if options.is_empty():
		return ""
	return options[rng.randi() % options.size()]


func _walk(trip_id: String) -> int:
	var spec := _trip(trip_id)
	if spec.is_empty():
		return 0
	var from_name := str(spec.get("from", ""))
	var to_name := str(spec.get("to", ""))
	if not _anchor_ids.has(from_name) or not _anchor_ids.has(to_name):
		return 0
	var from_point := int(_anchor_ids[from_name])
	var to_point := int(_anchor_ids[to_name])
	if from_point == to_point:
		return 0
	var ids := _astar.get_id_path(from_point, to_point)
	if ids.size() < 2:
		return 0
	var steps_n := 0
	var index := 0
	while index < ids.size() - 1:
		var from_at := _astar.get_point_position(int(ids[index]))
		var to_at := _astar.get_point_position(int(ids[index + 1]))
		var key := _edge_key(from_at, to_at)
		_edge_footfall[key] = int(_edge_footfall.get(key, 0)) + 1
		steps_n += 1
		index += 1
	return steps_n


func _trip(trip_id: String) -> Dictionary:
	for item in trips:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		if str(row.get("id", "")) == trip_id:
			return row
	return {}


func _census() -> Dictionary:
	var body := {
		"residents": _resident_count(),
		"creatures": _creature_count(),
		"ripe": _ripe(),
		"hour": _clock_hour(),
		"weather": _clock_weather(),
	}
	if not census_for.is_valid():
		return body
	var provided: Variant = census_for.call()
	if typeof(provided) != TYPE_DICTIONARY:
		return body
	var over: Dictionary = provided
	for key in over.keys():
		body[str(key)] = over[key]
	return body


func _resident_count() -> int:
	if ecology == null or not is_instance_valid(ecology):
		return 0
	if ecology.has_method("resident_total"):
		return int(ecology.call("resident_total"))
	return 0


func _creature_count() -> int:
	if ecology == null or not is_instance_valid(ecology):
		return 0
	var actors: Variant = ecology.get("actors")
	if typeof(actors) != TYPE_ARRAY:
		return 0
	return (actors as Array).size()


func _ripe() -> int:
	if soil == null or not soil.has_method("all"):
		return 0
	var cells: Variant = soil.call("all")
	if typeof(cells) != TYPE_ARRAY:
		return 0
	var ripe := 0
	for cell in cells:
		if typeof(cell) != TYPE_OBJECT or cell == null:
			continue
		var plot: Object = cell
		if str(plot.get("plant_id")) != "" and float(plot.get("growth")) >= 1.0:
			ripe += 1
	return ripe


func _weather_ok(weather: String) -> bool:
	if walk_weather.is_empty():
		return true
	return walk_weather.has(weather)


func _stall_open(hour_value: float) -> bool:
	return hour_value >= float(stall.get("open_from", 5.0)) and hour_value < float(stall.get("open_until", 19.5))


func _add_anchors() -> void:
	for item in anchors:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var anchor_id := str(row.get("id", ""))
		if anchor_id == "":
			continue
		var point := _add_point(_vec(row.get("at", [])), false)
		_anchor_ids[anchor_id] = point


func _add_runs() -> void:
	for item in runs:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		_span_anchors(str(row.get("from", "")), str(row.get("to", "")))


func _add_segments(rows: Array) -> void:
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var from_at := _vec(row.get("from", []))
		var to_at := _vec(row.get("to", []))
		_span_points(from_at, to_at, true)


func _add_stone_points() -> void:
	for at in _stones:
		_add_point(at, true)


func _span_anchors(from_id: String, to_id: String) -> void:
	if not _anchor_ids.has(from_id) or not _anchor_ids.has(to_id):
		return
	var from_point := int(_anchor_ids[from_id])
	var to_point := int(_anchor_ids[to_id])
	var from_at := _astar.get_point_position(from_point)
	var to_at := _astar.get_point_position(to_point)
	var steps_n := _steps(from_at, to_at)
	var prev := from_point
	var index := 1
	while index < steps_n:
		var at := from_at.lerp(to_at, float(index) / float(steps_n))
		var point := _add_point(at, false)
		_link(prev, point)
		prev = point
		index += 1
	_link(prev, to_point)


func _span_points(from_at: Vector3, to_at: Vector3, extra: bool) -> void:
	var from_point := _add_point(from_at, extra)
	var to_point := _add_point(to_at, extra)
	var steps_n := _steps(from_at, to_at)
	var prev := from_point
	var index := 1
	while index < steps_n:
		var at := from_at.lerp(to_at, float(index) / float(steps_n))
		var point := _add_point(at, extra)
		_link(prev, point)
		prev = point
		index += 1
	_link(prev, to_point)


func _steps(from_at: Vector3, to_at: Vector3) -> int:
	var span := from_at.distance_to(to_at)
	return maxi(int(ceil(span / maxf(step, 0.25))), 1)


func _snap_extras() -> void:
	if connect_radius <= 0.0:
		return
	var extra_ids: Array[int] = []
	for key in _extras.keys():
		extra_ids.append(int(key))
	for point in extra_ids:
		var at := _astar.get_point_position(point)
		var best := -1
		var best_dist := connect_radius
		for other in _point_ids:
			if other == point:
				continue
			var dist := at.distance_to(_astar.get_point_position(other))
			if dist > connect_radius or dist <= 0.001:
				continue
			if _extras.has(other):
				_link(point, other)
			elif dist <= best_dist:
				best_dist = dist
				best = other
		if best >= 0:
			_link(point, best)


func _add_point(at: Vector3, extra: bool) -> int:
	var point := _next_id
	_next_id += 1
	_astar.add_point(point, at)
	_point_ids.append(point)
	if extra:
		_extras[point] = true
	return point


func _link(from_point: int, to_point: int) -> void:
	if from_point == to_point or from_point < 0 or to_point < 0:
		return
	if not _astar.has_point(from_point) or not _astar.has_point(to_point):
		return
	if _astar.are_points_connected(from_point, to_point):
		return
	_astar.connect_points(from_point, to_point)


func _nearest(at: Vector3) -> int:
	var best := -1
	var best_dist := INF
	for point in _point_ids:
		var dist := at.distance_to(_astar.get_point_position(point))
		if dist < best_dist:
			best_dist = dist
			best = point
	return best


func _edge_key(a: Vector3, b: Vector3) -> String:
	var left := a
	var right := b
	if _before(b, a):
		left = b
		right = a
	return "%s|%s" % [_fmt(left), _fmt(right)]


func _fmt(at: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


func _before(a: Vector3, b: Vector3) -> bool:
	var ax := snappedf(a.x, 0.01)
	var bx := snappedf(b.x, 0.01)
	if not is_equal_approx(ax, bx):
		return ax < bx
	var ay := snappedf(a.y, 0.01)
	var by := snappedf(b.y, 0.01)
	if not is_equal_approx(ay, by):
		return ay < by
	return snappedf(a.z, 0.01) < snappedf(b.z, 0.01)


func _segment_ends(mesh_node: MeshInstance3D) -> Array[Vector3]:
	var box := mesh_node.mesh as BoxMesh
	if box == null:
		return []
	var half := Vector3(0, 0, box.size.z * 0.5)
	if box.size.x > box.size.z:
		half = Vector3(box.size.x * 0.5, 0, 0)
	var ends: Array[Vector3] = [_to_world(mesh_node, -half), _to_world(mesh_node, half)]
	return ends


func _to_world(node: Node3D, local_at: Vector3) -> Vector3:
	if node.is_inside_tree():
		return node.to_global(local_at)
	return node.transform * local_at


func _close_enough(point: int, at: Vector3) -> bool:
	if point < 0:
		return false
	return at.distance_to(_astar.get_point_position(point)) <= connect_radius + 0.05


func _on_road(node: Node) -> bool:
	for group in node.get_groups():
		if str(group).begins_with("parish_road"):
			return true
	return false


func _plant_ids() -> Array[String]:
	return _plant_order


func _price(plant_id: String) -> int:
	var bonus := int(stall.get("price_bonus", 0))
	var base := int(_prices.get(plant_id, 1))
	return maxi(base + bonus, 0)


func _keeper_name() -> String:
	var keeper := str(stall.get("keeper", "bram"))
	var person_name := str(_names.get(keeper, ""))
	if person_name != "":
		return person_name
	return keeper.capitalize()


func _rows_from(data: Variant) -> Array:
	if typeof(data) == TYPE_ARRAY:
		return data
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var body: Dictionary = data
	var raw: Variant = body.get("paths", [])
	if typeof(raw) == TYPE_ARRAY:
		return raw
	return []


func _sum_edges() -> int:
	var total := 0
	for key in _edge_footfall.keys():
		total += int(_edge_footfall[key])
	return total


func _looks_like_origin(item: Variant) -> bool:
	return typeof(item) == TYPE_ARRAY and (item as Array).size() >= 3


func _vec(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if typeof(value) != TYPE_ARRAY:
		return Vector3.ZERO
	var row: Array = value
	if row.size() < 3:
		return Vector3.ZERO
	return Vector3(float(row[0]), float(row[1]), float(row[2]))


func _hour_key() -> int:
	var clock := ServiceField.autoload("Clock")
	if clock == null:
		return -1
	return int(clock.get("day")) * 24 + int(floor(float(clock.call("hour"))))


func _clock_hour() -> float:
	var clock := ServiceField.autoload("Clock")
	if clock == null or not clock.has_method("hour"):
		return 0.0
	return float(clock.call("hour"))


func _clock_weather() -> String:
	var clock := ServiceField.autoload("Clock")
	if clock == null:
		return "clear"
	return str(clock.get("weather"))


func _now_min() -> float:
	var clock := ServiceField.autoload("Clock")
	if clock != null and clock.has_method("absolute_minutes"):
		return float(clock.call("absolute_minutes"))
	return 0.0


func _load() -> void:
	anchors = []
	runs = []
	trips = []
	walk = {}
	walk_weather = []
	stall = {}
	step = 1.5
	connect_radius = 2.4
	var text := FileAccess.get_file_as_string("res://data/paths.json")
	if text == "":
		push_error("Missing data file res://data/paths.json")
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in res://data/paths.json")
		return
	var root: Dictionary = parsed
	step = maxf(float(root.get("step", step)), 0.25)
	connect_radius = maxf(float(root.get("connect_radius", connect_radius)), 0.0)
	var anchor_rows: Variant = root.get("anchors", [])
	if typeof(anchor_rows) == TYPE_ARRAY:
		anchors = anchor_rows
	var run_rows: Variant = root.get("runs", [])
	if typeof(run_rows) == TYPE_ARRAY:
		runs = run_rows
	var trip_rows: Variant = root.get("trips", [])
	if typeof(trip_rows) == TYPE_ARRAY:
		trips = trip_rows
	var walk_body: Variant = root.get("walk", {})
	if typeof(walk_body) == TYPE_DICTIONARY:
		walk = walk_body
	var weather_rows: Variant = root.get("walk_weather", [])
	if typeof(weather_rows) == TYPE_ARRAY:
		walk_weather = weather_rows
	var stall_body: Variant = root.get("stall", {})
	if typeof(stall_body) == TYPE_DICTIONARY:
		stall = stall_body
	_load_trade()


func _load_trade() -> void:
	_plant_order.clear()
	_prices.clear()
	_names.clear()
	var plants: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/plants.json"))
	if typeof(plants) == TYPE_ARRAY:
		for item in plants:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = item
			var plant_id := str(row.get("id", ""))
			if plant_id == "":
				continue
			_plant_order.append(plant_id)
			_prices[plant_id] = int(row.get("sell_price", 1))
	var people: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/people.json"))
	if typeof(people) != TYPE_ARRAY:
		return
	for item in people:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var person_id := str(row.get("id", ""))
		if person_id == "":
			continue
		_names[person_id] = str(row.get("name", person_id))

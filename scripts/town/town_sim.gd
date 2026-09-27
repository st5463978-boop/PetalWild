class_name TownSim
extends RefCounted

# ponytail: one grid and occupancy counts; spawn actors if a distant plot ever needs a body.
var width := 8
var height := 5
var gate := Vector2i(3, 2)
var park_plot := Vector2i(5, 4)
var districts: Dictionary = {}
var buildings: Dictionary = {}
var plots: Array = []
var route: Array = []
var stats: Dictionary = {}
var lane_mode := "fill"
var chose_lane := false

func boot(text: String = "") -> void:
	var raw := text
	if raw == "":
		raw = FileAccess.get_file_as_string("res://data/town.json")
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("town.json missing")
		return
	var data: Dictionary = parsed
	width = int(data.get("width", 8))
	height = int(data.get("height", 5))
	var gate_raw: Variant = data.get("gate", [3, 2])
	var park_raw: Variant = data.get("park_plot", [5, 4])
	gate = _cell(gate_raw)
	park_plot = _cell(park_raw)
	districts.clear()
	for entry in data.get("districts", []):
		var row: Dictionary = entry
		districts[str(row.get("id", ""))] = row.duplicate(true)
	buildings.clear()
	for entry in data.get("buildings", []):
		var row: Dictionary = entry
		buildings[str(row.get("id", ""))] = row.duplicate(true)
	_build_plots()
	lane_mode = "fill"
	chose_lane = false
	stats = _blank_stats()

func tick(ctx: Dictionary) -> void:
	if plots.is_empty():
		boot()
	_open_districts(ctx)
	_occupy(ctx)
	_cover()
	_route()
	_tally(ctx)

func aggregate() -> int:
	return int(stats.get("aggregate", 0))

func occupancy(building_id: String) -> int:
	var occ_raw: Variant = stats.get("occ", {})
	if typeof(occ_raw) != TYPE_DICTIONARY:
		return 0
	var occ: Dictionary = occ_raw as Dictionary
	return int(occ.get(building_id, 0))

func building_open(building_id: String) -> bool:
	var row: Dictionary = buildings.get(building_id, {})
	return bool(row.get("now_open", false))

func open_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id in districts.keys():
		if bool(districts[id].get("now_open", false)):
			ids.append(str(id))
	return ids

func coverage() -> float:
	return float(stats.get("coverage", 0.0))

func lod_counts() -> Dictionary:
	return {
		"0": 0,
		"1": 0,
		"2": 0,
		"3": int(stats.get("near_park", 0)),
		"4": int(stats.get("aggregate", 0)) - int(stats.get("near_park", 0)),
	}

func page_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(str(stats.get("headline", "Hedge Hollow stands alone.")))
	lines.append("Town folk  %s  ·  aggregate %s  ·  no distant bodies" % [str(stats.get("town_pop", 0)), str(stats.get("aggregate", 0))])
	lines.append("Lane houses  %s / %s" % [str(occupancy("lane")), str(int(districts.get("lane", {}).get("houses", 0)))])
	var park_state := "not built"
	if building_open("grove_park"):
		park_state = "open · %s on the lawn" % str(occupancy("grove_park"))
	lines.append("Grove Park  %s" % park_state)
	lines.append("Service cover  %d%%" % int(coverage() * 100.0))
	if route.size() > 1:
		lines.append("Path  gate to park · %s steps · %s riders" % [str(route.size() - 1), str(stats.get("riders", 0))])
	else:
		lines.append("Path  the hedge still closes the way.")
	return lines

func to_dict() -> Dictionary:
	return {
		"lane_mode": lane_mode,
		"chose_lane": chose_lane,
		"stats": stats.duplicate(true),
	}

func from_dict(data: Dictionary) -> void:
	lane_mode = str(data.get("lane_mode", "fill"))
	chose_lane = bool(data.get("chose_lane", false))
	var saved: Variant = data.get("stats", {})
	if typeof(saved) == TYPE_DICTIONARY:
		stats = (saved as Dictionary).duplicate(true)

func _build_plots() -> void:
	plots.clear()
	for y in height:
		for x in width:
			var district := _district_at(x, y)
			var ground := "garden"
			if district == "lane":
				ground = "path" if x % 2 == 1 or Vector2i(x, y) == gate else "house"
			elif district == "park":
				ground = "path" if Vector2i(x, y) == park_plot or x == gate.x else "park"
			plots.append({
				"x": x,
				"y": y,
				"g": ground,
				"district": district,
				"occ": 0,
				"lod": 4 if district != "hollow" else 1,
				"cover": [],
			})

func _district_at(x: int, y: int) -> String:
	for id in districts.keys():
		var row: Dictionary = districts[id]
		if x >= int(row.get("x0", 0)) and x <= int(row.get("x1", 0)) and y >= int(row.get("y0", 0)) and y <= int(row.get("y1", 0)):
			return str(id)
	return ""

func _open_districts(ctx: Dictionary) -> void:
	for id in districts.keys():
		var row: Dictionary = districts[id]
		var need := str(row.get("need", ""))
		var now := bool(row.get("open", false))
		if need == "road":
			now = bool(ctx.get("road", false))
		elif need == "park":
			now = bool(ctx.get("park", false))
		row["now_open"] = now
	for id in buildings.keys():
		var row: Dictionary = buildings[id]
		var need := str(row.get("need", ""))
		var now := bool(row.get("open", false))
		if need == "park":
			now = bool(ctx.get("park", false))
		row["now_open"] = now
	if bool(districts.get("lane", {}).get("now_open", false)) and not chose_lane:
		chose_lane = true
		var fill := str(ctx.get("lane_fill", ""))
		if fill == "fill" or fill == "sparse":
			lane_mode = fill
		else:
			lane_mode = _decide_fill()

func _decide_fill() -> String:
	var options: Array = ["fill", "sparse"]
	if not Engine.has_singleton("PetalDecide"):
		return "fill"
	var svc: Object = Engine.get_singleton("PetalDecide")
	var picked := str(svc.call("choose", "South Lane has empty houses beyond the hedge. Fill them or keep them sparse?", options))
	if options.has(picked):
		return picked
	return "fill"

func _occupy(ctx: Dictionary) -> void:
	for plot in plots:
		plot["occ"] = 0
	var people := int(ctx.get("people", 0))
	var residents := int(ctx.get("residents", 0))
	var passers := int(ctx.get("passers", 0))
	var hour := float(ctx.get("hour", 10.0))
	var weather := str(ctx.get("weather", "clear"))
	var day := hour >= 5.0 and hour < 19.5
	var fair := weather == "clear" or weather == "golden"
	var lane_n := 0
	if bool(districts.get("lane", {}).get("now_open", false)):
		var cap := int(districts.get("lane", {}).get("houses", 6))
		lane_n = mini(cap, 1 + residents + people + int(passers / 2))
		if lane_mode == "sparse":
			lane_n = maxi(1, int(lane_n / 2))
		if not day:
			lane_n = maxi(1, int(ceil(float(lane_n) * 0.5)))
	_pour("house", "lane", lane_n)
	var park_n := 0
	if bool(districts.get("park", {}).get("now_open", false)):
		var cap := int(districts.get("park", {}).get("capacity", 8))
		if day and fair:
			park_n = mini(cap, passers + people)
		elif day:
			park_n = mini(2, people)
	_pour("park", "park", park_n)
	var near := 0
	if bool(ctx.get("near_park", false)):
		near = mini(2, park_n)
		park_n -= near
	stats["lane_occ"] = lane_n
	stats["park_occ"] = park_n + near
	stats["near_park"] = near
	stats["occ"] = {"lane": lane_n, "grove_park": park_n + near}

func _pour(ground: String, district: String, amount: int) -> void:
	var left := amount
	for plot in plots:
		if left <= 0:
			return
		if str(plot.get("g", "")) != ground or str(plot.get("district", "")) != district:
			continue
		plot["occ"] = 1
		left -= 1
	if left <= 0:
		return
	for plot in plots:
		if left <= 0:
			return
		if str(plot.get("district", "")) != district:
			continue
		plot["occ"] = int(plot.get("occ", 0)) + left
		left = 0

func _cover() -> void:
	for plot in plots:
		plot["cover"] = []
	for id in buildings.keys():
		var row: Dictionary = buildings[id]
		if not bool(row.get("now_open", false)):
			continue
		var at := _cell(row.get("plot", [0, 0]))
		var service := str(row.get("service", id))
		for plot in plots:
			if absi(int(plot["x"]) - at.x) + absi(int(plot["y"]) - at.y) > 4:
				continue
			if not bool(districts.get(str(plot["district"]), {}).get("now_open", false)):
				continue
			var cover: Array = []
			var raw: Variant = plot.get("cover", [])
			if typeof(raw) == TYPE_ARRAY:
				cover = raw
			if not cover.has(service):
				cover.append(service)
			plot["cover"] = cover

func _route() -> void:
	var blocked := {}
	for plot in plots:
		var district := str(plot.get("district", ""))
		if not bool(districts.get(district, {}).get("now_open", false)) and district != "park":
			blocked[Vector2i(int(plot["x"]), int(plot["y"]))] = true
		if str(plot.get("g", "")) == "hedge":
			blocked[Vector2i(int(plot["x"]), int(plot["y"]))] = true
	if bool(districts.get("park", {}).get("now_open", false)) or bool(districts.get("lane", {}).get("now_open", false)):
		blocked.erase(park_plot)
		blocked.erase(gate)
	route = PetalPath.astar(Vector2i(gate.x, 0), park_plot, blocked, width, height)

func _tally(ctx: Dictionary) -> void:
	var garden := int(ctx.get("people", 0)) + int(ctx.get("residents", 0))
	var distant := int(stats.get("lane_occ", 0)) + int(stats.get("park_occ", 0))
	var served := 0
	var live := 0
	for plot in plots:
		if not bool(districts.get(str(plot["district"]), {}).get("now_open", false)):
			continue
		live += 1
		var cover_raw: Variant = plot.get("cover", [])
		if typeof(cover_raw) == TYPE_ARRAY and (cover_raw as Array).size() > 0:
			served += 1
		var district := str(plot.get("district", ""))
		plot["lod"] = 1 if district == "hollow" else (3 if int(plot.get("occ", 0)) > 0 and bool(ctx.get("near_park", false)) and district == "park" else 4)
	var jobs := 0
	for id in buildings.keys():
		var row: Dictionary = buildings[id]
		if bool(row.get("now_open", false)):
			jobs += int(row.get("jobs", 0))
	var cover := float(served) / maxf(float(live), 1.0)
	var riders := 0
	if route.size() > 1 and bool(districts.get("lane", {}).get("now_open", false)):
		riders = int(ctx.get("passers", 0))
	var headline := "Hedge Hollow stands alone."
	if bool(districts.get("park", {}).get("now_open", false)):
		headline = "Grove Park is a public lawn. The lane holds houses. Nobody walks them in hero detail."
	elif bool(districts.get("lane", {}).get("now_open", false)):
		headline = "South Lane holds houses beyond the hedge. They tick as counts."
	stats["garden_pop"] = garden
	stats["town_pop"] = garden + distant
	stats["aggregate"] = distant
	stats["jobs"] = jobs
	stats["coverage"] = cover
	stats["riders"] = riders
	stats["headline"] = headline
	stats["bodies"] = 0

func _blank_stats() -> Dictionary:
	return {
		"garden_pop": 0,
		"town_pop": 0,
		"aggregate": 0,
		"jobs": 0,
		"coverage": 0.0,
		"riders": 0,
		"headline": "Hedge Hollow stands alone.",
		"bodies": 0,
		"lane_occ": 0,
		"park_occ": 0,
		"near_park": 0,
		"occ": {},
	}

func _cell(raw: Variant) -> Vector2i:
	if typeof(raw) != TYPE_ARRAY:
		return Vector2i.ZERO
	var pair: Array = raw
	if pair.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(pair[0]), int(pair[1]))

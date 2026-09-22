class_name WorldState
extends RefCounted

static func fresh(catalogs: Dictionary) -> Dictionary:
	var opening: Dictionary = catalogs["opening"]
	var width := int(opening["width"])
	var height := int(opening["height"])
	var rows: Array = opening["rows"]
	var plots: Array = []
	for y in height:
		var row := String(rows[y])
		for x in width:
			var code := row[x]
			var ground := "grass"
			match code:
				"p":
					ground = "path"
				"s":
					ground = "soil"
				"w":
					ground = "pond"
				"f":
					ground = "flowerbed"
				_:
					ground = "grass"
			plots.append({
				"g": ground,
				"m": 0.08 if ground != "path" else 0.02,
				"f": 0.31,
				"plant": "",
				"growth": 0.0,
			})
	for starter in opening.get("starters", []):
		var x := int(starter["x"])
		var y := int(starter["y"])
		var plot: Dictionary = plots[y * width + x]
		if String(plot["g"]) == "soil":
			plot["plant"] = String(starter["plant"])
			plot["growth"] = float(starter["growth"])
			plot["m"] = 0.36
	var species := {}
	for id in catalogs["species"].keys():
		species[id] = {
			"state": "unknown",
			"visits": 0,
			"relationship": 0.0,
			"mood": "calm",
			"harassment": 0,
			"present": false,
			"dwell": 0.0,
			"fed": 0,
			"variant": false,
			"pos": [],
			"days_resident": 0,
			"counted_day": -1,
			"announced": {},
		}
	var people := {}
	for id in catalogs["residents"].keys():
		var def: Dictionary = catalogs["residents"][id]
		people[id] = {
			"present": bool(def.get("starts_present", false)),
			"trust": 0,
			"relationship": float(def.get("relationship", 0.0)),
			"needs": {"energy": 0.72, "hunger": 0.64, "social": 0.48, "purpose": 0.55},
			"mood": "content",
			"memories": [],
			"home_pad": int(def.get("home_pad", -1)),
			"complained_day": -1,
		}
	var inventory: Dictionary = opening["inventory"].duplicate(true)
	return {
		"version": 1,
		"day": int(opening.get("day", 1)),
		"minute": int(opening.get("minute", 480)),
		"minute_acc": 0.0,
		"time_scale": 1.0,
		"weather": "clear",
		"weather_acc": 0.0,
		"season": "spring",
		"coins": int(opening.get("coins", 0)),
		"inventory": inventory,
		"selected_seed": "sunpetal_seed",
		"plots": plots,
		"width": width,
		"height": height,
		"species": species,
		"people": people,
		"props": opening.get("props", []).duplicate(true),
		"stall_open": false,
		"harvested": {},
		"sales": 0,
		"theft": 0,
		"mischief_acc": 0.0,
		"flags": {},
		"audit": [],
		"discoveries": [],
		"tutorial": {},
	}


static func plot_at(state: Dictionary, x: int, y: int) -> Dictionary:
	var width := int(state["width"])
	var height := int(state["height"])
	if x < 0 or y < 0 or x >= width or y >= height:
		return {}
	return state["plots"][y * width + x]


static func ensure(state: Dictionary, catalogs: Dictionary) -> Dictionary:
	var blank := fresh(catalogs)
	for key in blank.keys():
		if not state.has(key):
			state[key] = blank[key]
	for id in blank["species"].keys():
		if not state["species"].has(id):
			state["species"][id] = blank["species"][id]
		else:
			for field in blank["species"][id].keys():
				if not state["species"][id].has(field):
					state["species"][id][field] = blank["species"][id][field]
	for id in blank["people"].keys():
		if not state["people"].has(id):
			state["people"][id] = blank["people"][id]
	state["version"] = 1
	return state

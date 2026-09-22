class_name PetalContext
extends RefCounted

static func build(state: Dictionary, _catalogs: Dictionary) -> Dictionary:
	var width := int(state.get("width", 0))
	var height := int(state.get("height", 0))
	var plots: Array = state.get("plots", [])
	var mature := {}
	var ground := {}
	var fert_sum := 0.0
	var moist_sum := 0.0
	var soil_n := 0
	for y in height:
		for x in width:
			var plot: Dictionary = plots[y * width + x]
			var g := String(plot.get("g", "grass"))
			ground[g] = int(ground.get(g, 0)) + 1
			if g == "grass" or g == "soil":
				fert_sum += float(plot.get("f", 0.0))
				moist_sum += float(plot.get("m", 0.0))
				soil_n += 1
			var plant := String(plot.get("plant", ""))
			if plant != "" and float(plot.get("growth", 0.0)) >= 1.0:
				mature[plant] = int(mature.get(plant, 0)) + 1
	var fertility := fert_sum / float(soil_n) if soil_n else 0.0
	var moisture := moist_sum / float(soil_n) if soil_n else 0.0
	var species_states := {}
	var fed := {}
	var residents := 0
	for id in state.get("species", {}).keys():
		var rec: Dictionary = state["species"][id]
		var st := String(rec.get("state", "unknown"))
		species_states[id] = st
		fed[id] = int(rec.get("fed", 0))
		if PetalRules.state_index(st) >= PetalRules.state_index("resident"):
			residents += 1
	var people := {}
	for id in state.get("people", {}).keys():
		people[id] = bool(state["people"][id].get("present", false))
	var props := {}
	for prop in state.get("props", []):
		var pid := String(prop.get("id", ""))
		props[pid] = int(props.get(pid, 0)) + 1
	var mature_n := 0
	for k in mature.keys():
		mature_n += int(mature[k])
	var decor := int(props.get("bench", 0)) + int(props.get("lamp", 0)) + int(props.get("lantern", 0))
	var quality := (
		clampf(float(mature_n) / 8.0, 0.0, 1.0)
		+ clampf(float(residents) / 4.0, 0.0, 1.0)
		+ clampf(float(decor) / 5.0, 0.0, 1.0)
		+ clampf(fertility, 0.0, 1.0)
	) / 4.0
	return {
		"mature": mature,
		"ground": ground,
		"phase": PetalRules.phase_for(int(state.get("minute", 0))),
		"weather": String(state.get("weather", "clear")),
		"season": String(state.get("season", "spring")),
		"fertility": fertility,
		"moisture": moisture,
		"quality": quality,
		"species": species_states,
		"people": people,
		"flags": state.get("flags", {}),
		"harvested": state.get("harvested", {}),
		"fed": fed,
		"props": props,
		"venue": {"petal_stall": bool(state.get("stall_open", false))},
		"residents": residents,
		"sales": int(state.get("sales", 0)),
	}

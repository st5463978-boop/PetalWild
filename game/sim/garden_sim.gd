extends RefCounted

const WIDTH := 14
const DEPTH := 10

var plots: Array = []
var plant_defs: Dictionary = {}


func configure(defs: Dictionary) -> void:
	plant_defs = defs


func setup_new() -> void:
	plots.clear()
	for z in DEPTH:
		for x in WIDTH:
			plots.append({
				"x": x,
				"z": z,
				"soil": "grass",
				"moisture": 0.22,
				"fertility": 0.31,
				"chemistry": "balanced",
				"plant_id": "",
				"growth": 0.0,
			})


func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < WIDTH and z < DEPTH


func plot_at(x: int, z: int) -> Dictionary:
	if not in_bounds(x, z):
		return {}
	return plots[z * WIDTH + x]


func till(x: int, z: int) -> bool:
	var plot: Dictionary = plot_at(x, z)
	if plot.is_empty() or str(plot.soil) == "water":
		return false
	plot.soil = "loam"
	plot.fertility = maxf(float(plot.fertility), 0.34)
	return true


func plant_seed(x: int, z: int, plant_id: String) -> String:
	var plot: Dictionary = plot_at(x, z)
	if plot.is_empty():
		return "That spot is outside the beds."
	if str(plot.plant_id) != "":
		return "Something is already growing there."
	if str(plot.soil) != "loam" and str(plot.soil) != "compost":
		return "Till the bed first."
	if not plant_defs.has(plant_id):
		return "Unknown seed."
	var def: Dictionary = plant_defs[plant_id]
	var soils: Array = def.get("soils", [])
	if not soils.has(str(plot.soil)):
		return "%s will not take in this soil." % def.get("name", plant_id)
	var chem := str(def.get("chemistry", ""))
	if chem != "" and str(plot.chemistry) != chem:
		return "%s needs %s soil." % [def.get("name", plant_id), chem]
	plot.plant_id = plant_id
	plot.growth = 0.04
	return ""


func water(x: int, z: int) -> bool:
	var plot: Dictionary = plot_at(x, z)
	if plot.is_empty() or str(plot.soil) == "water":
		return false
	plot.moisture = minf(1.0, float(plot.moisture) + 0.36)
	return true


func fertilize(x: int, z: int) -> bool:
	var plot: Dictionary = plot_at(x, z)
	if plot.is_empty() or str(plot.soil) == "water":
		return false
	plot.fertility = minf(1.0, float(plot.fertility) + 0.24)
	return true


func tend(x: int, z: int) -> Dictionary:
	var plot: Dictionary = plot_at(x, z)
	if plot.is_empty() or str(plot.plant_id) == "":
		return {"harvested": "", "tended": false}
	if float(plot.growth) >= 0.98:
		var harvested := str(plot.plant_id)
		plot.plant_id = ""
		plot.growth = 0.0
		plot.fertility = maxf(0.12, float(plot.fertility) - 0.06)
		return {"harvested": harvested, "tended": true}
	plot.growth = minf(0.97, float(plot.growth) + 0.05)
	plot.moisture = minf(1.0, float(plot.moisture) + 0.04)
	return {"harvested": "", "tended": true}


func scoop(x: int, z: int) -> bool:
	var plot: Dictionary = plot_at(x, z)
	if plot.is_empty():
		return false
	if str(plot.soil) == "water":
		plot.soil = "loam"
		plot.plant_id = ""
		plot.growth = 0.0
		plot.moisture = 0.4
		return true
	if str(plot.plant_id) != "":
		return false
	plot.soil = "water"
	plot.moisture = 1.0
	plot.plant_id = ""
	plot.growth = 0.0
	return true


func tick(delta: float, weather: String, hour: float, season: String) -> void:
	var raining := weather == "rain"
	for plot in plots:
		if str(plot.soil) == "water":
			plot.moisture = 1.0
			continue
		var evap := 0.006 * delta
		if weather == "clear" and hour > 11.0 and hour < 16.0:
			evap *= 1.3
		if weather == "mist":
			evap *= 0.4
			plot.moisture = minf(1.0, float(plot.moisture) + 0.008 * delta)
		if raining:
			plot.moisture = minf(1.0, float(plot.moisture) + 0.04 * delta)
		else:
			plot.moisture = maxf(0.0, float(plot.moisture) - evap)
		var plant_id := str(plot.plant_id)
		if plant_id == "" or not plant_defs.has(plant_id):
			continue
		var def: Dictionary = plant_defs[plant_id]
		var soils: Array = def.get("soils", ["loam"])
		var rate := float(def.get("rate", 0.015))
		if not soils.has(str(plot.soil)):
			rate *= 0.2
		var chem := str(def.get("chemistry", ""))
		if chem != "" and str(plot.chemistry) != chem:
			rate *= 0.12
		var window := float(def.get("moisture_window", 0.4))
		if absf(float(plot.moisture) - float(def.get("moisture", 0.45))) > window:
			rate *= 0.4
		rate *= lerpf(0.5, 1.35, clampf(float(plot.fertility), 0.0, 1.0))
		var seasons: Array = def.get("seasons", [])
		if not seasons.is_empty() and not seasons.has(season):
			rate *= 0.5
		if bool(def.get("likes_rain", false)) and raining:
			rate *= 1.25
		var wants_night := bool(def.get("night", false))
		var is_night := hour < 6.0 or hour >= 19.0
		if wants_night and is_night:
			rate *= 1.65
		elif wants_night:
			rate *= 0.22
		plot.growth = minf(1.0, float(plot.growth) + rate * delta)
		if float(plot.growth) > 0.55:
			plot.moisture = maxf(0.0, float(plot.moisture) - 0.0025 * delta)
			plot.fertility = maxf(0.08, float(plot.fertility) - 0.0006 * delta)


func count_mature(plant_id: String) -> int:
	var count := 0
	for plot in plots:
		if str(plot.plant_id) == plant_id and float(plot.growth) >= 0.98:
			count += 1
	return count


func count_plant(plant_id: String) -> int:
	var count := 0
	for plot in plots:
		if str(plot.plant_id) == plant_id:
			count += 1
	return count


func count_soil(soil: String) -> int:
	var count := 0
	for plot in plots:
		if str(plot.soil) == soil:
			count += 1
	return count


func count_chemistry(chem: String) -> int:
	var count := 0
	for plot in plots:
		if str(plot.chemistry) == chem:
			count += 1
	return count


func average_moisture() -> float:
	if plots.is_empty():
		return 0.0
	var total := 0.0
	for plot in plots:
		total += float(plot.moisture)
	return total / float(plots.size())


func average_fertility() -> float:
	if plots.is_empty():
		return 0.0
	var total := 0.0
	for plot in plots:
		total += float(plot.fertility)
	return total / float(plots.size())


func apply_chemistry(chem: String, count: int) -> int:
	var changed := 0
	var passes := [["loam", "compost"], ["grass"]]
	for soils in passes:
		for plot in plots:
			if changed >= count:
				return changed
			if str(plot.soil) == "water" or str(plot.chemistry) == chem:
				continue
			if not soils.has(str(plot.soil)):
				continue
			plot.chemistry = chem
			if chem == "compost" and str(plot.soil) != "water":
				plot.soil = "compost"
				plot.fertility = minf(1.0, float(plot.fertility) + 0.12)
			changed += 1
	return changed


func steal_produce(plant_id: String) -> bool:
	for plot in plots:
		if str(plot.plant_id) == plant_id and float(plot.growth) >= 0.98:
			plot.growth = 0.62
			return true
	return false


func to_dict() -> Dictionary:
	return {"width": WIDTH, "depth": DEPTH, "plots": plots.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	var loaded: Array = data.get("plots", [])
	if loaded.size() == WIDTH * DEPTH:
		plots = loaded.duplicate(true)
	else:
		setup_new()

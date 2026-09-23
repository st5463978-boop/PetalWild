class_name SoilField
extends RefCounted

var cells: Dictionary = {}
var seed_rain := 0.0
var seeded := ""

func _init() -> void:
	for ix in GardenLayout.BED_W:
		for iz in GardenLayout.BED_H:
			var cell := SoilCell.new()
			cell.ix = ix
			cell.iz = iz
			cells["%d,%d" % [ix, iz]] = cell

func get_cell(ix: int, iz: int) -> SoilCell:
	return cells.get("%d,%d" % [ix, iz])

func all() -> Array:
	return cells.values()

func tick(game_minutes: float, weather: String) -> Array:
	var hours := game_minutes / 60.0
	var raining := weather == "rain"
	var died: Array = []
	seeded = ""
	for cell in all():
		var soil: SoilCell = cell
		var before := soil.moisture
		if raining:
			soil.moisture = minf(1.0, soil.moisture + hours * 0.95)
		else:
			soil.moisture = maxf(0.04, soil.moisture - hours * 0.22)
		if soil.plant_id == "":
			continue
		var definition: Dictionary = ContentDB.plant(soil.plant_id)
		if definition.is_empty():
			continue
		var grow_hours := maxf(0.2, float(definition.get("grow_hours", 2.0)))
		var need := float(definition.get("water_need", 0.3))
		if soil.moisture < need:
			var dry_hours := hours
			if raining:
				dry_hours = 0.0
			elif before > need:
				dry_hours = clampf((need - soil.moisture) / 0.22, 0.0, hours)
			soil.wilt += dry_hours
			# ponytail: six dry hours clears the bed; a wilt curve if crops should linger.
			soil.growth = maxf(0.04, soil.growth - hours / (grow_hours * 4.0))
			if soil.wilt >= 6.0:
				died.append(soil.plant_id)
				soil.plant_id = ""
				soil.growth = 0.0
				soil.wilt = 0.0
			continue
		soil.wilt = 0.0
		if soil.fertility < float(definition.get("fertility_need", 0.2)):
			continue
		var chem_need := str(definition.get("chem", ""))
		if chem_need != "" and soil.chem != chem_need:
			continue
		soil.growth = minf(1.0, soil.growth + hours / grow_hours)
	if raining:
		seed_rain = minf(0.5, seed_rain + hours)
		# ponytail: one ripe plant seeds one tilled neighbor per half-hour of rain; a scatter if a shower should fill the row.
		if seed_rain >= 0.5:
			seeded = _seed_one()
			if seeded != "":
				seed_rain = 0.0
	else:
		seed_rain = 0.0
	return died

func _seed_one() -> String:
	for iz in GardenLayout.BED_H:
		for ix in GardenLayout.BED_W:
			var parent := get_cell(ix, iz)
			if parent.plant_id == "" or parent.growth < 1.0:
				continue
			var spot := _seed_spot(ix, iz, parent.plant_id)
			if spot == null:
				continue
			spot.plant_id = parent.plant_id
			spot.growth = 0.18
			spot.wilt = 0.0
			spot.moisture = maxf(spot.moisture, 0.74)
			return parent.plant_id
	return ""

func _seed_spot(ix: int, iz: int, plant_id: String) -> SoilCell:
	var best: SoilCell = null
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for off in offsets:
		var nx := ix + off.x
		var nz := iz + off.y
		if nx < 0 or nz < 0 or nx >= GardenLayout.BED_W or nz >= GardenLayout.BED_H:
			continue
		var plot := get_cell(nx, nz)
		if plot == null or plot.plant_id != "" or not plot.tilled:
			continue
		var center := GardenLayout.cell_center(nx, nz)
		if GardenLayout.on_path(center.x, center.z):
			continue
		if GardenLayout.pond_distance(center.x, center.z) < GardenLayout.POND_RADIUS:
			continue
		if not _can_hold(plot, plant_id):
			continue
		if best == null or nx < best.ix or (nx == best.ix and nz < best.iz):
			best = plot
	return best

func _can_hold(plot: SoilCell, plant_id: String) -> bool:
	var definition: Dictionary = ContentDB.plant(plant_id)
	if definition.is_empty():
		return false
	if plot.fertility < float(definition.get("fertility_need", 0.2)):
		return false
	var chem_need := str(definition.get("chem", ""))
	return chem_need == "" or plot.chem == chem_need

func apply_chem(chem: String, count: int) -> int:
	var empties: Array[SoilCell] = []
	for cell in all():
		var soil: SoilCell = cell
		if soil.plant_id == "" and soil.chem != chem:
			empties.append(soil)
	empties.shuffle()
	var applied := 0
	for soil in empties:
		if applied >= count:
			break
		soil.chem = chem
		soil.tilled = true
		soil.fertility = maxf(soil.fertility, 0.46)
		soil.moisture = maxf(soil.moisture, 0.4)
		applied += 1
	return applied

func to_state() -> Array:
	var saved: Array = []
	for cell in all():
		var soil: SoilCell = cell
		if soil.tilled or soil.plant_id != "" or soil.chem != "base" or soil.moisture > 0.45:
			saved.append(soil.to_dict())
	return saved

func apply_state(saved: Array) -> void:
	for ix in GardenLayout.BED_W:
		for iz in GardenLayout.BED_H:
			var soil := get_cell(ix, iz)
			soil.tilled = false
			soil.moisture = 0.28
			soil.fertility = 0.3
			soil.chem = "base"
			soil.plant_id = ""
			soil.growth = 0.0
			soil.wilt = 0.0
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var soil := get_cell(int(entry.get("ix", -1)), int(entry.get("iz", -1)))
		if soil:
			soil.apply_dict(entry)

class_name SoilField
extends RefCounted

var cells: Dictionary = {}

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

func tick(game_minutes: float, weather: String) -> void:
	var hours := game_minutes / 60.0
	var raining := weather == "rain"
	for cell in all():
		var soil: SoilCell = cell
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
		if soil.moisture < float(definition.get("water_need", 0.3)):
			# ponytail: a quarter of the grow rate; a death state if a crop should vanish.
			soil.growth = maxf(0.04, soil.growth - hours / (grow_hours * 4.0))
			continue
		if soil.fertility < float(definition.get("fertility_need", 0.2)):
			continue
		var chem_need := str(definition.get("chem", ""))
		if chem_need != "" and soil.chem != chem_need:
			continue
		soil.growth = minf(1.0, soil.growth + hours / grow_hours)

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
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var soil := get_cell(int(entry.get("ix", -1)), int(entry.get("iz", -1)))
		if soil:
			soil.apply_dict(entry)

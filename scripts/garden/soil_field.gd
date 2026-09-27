class_name SoilField
extends RefCounted

var cells: Dictionary = {}
var seed_rain := 0.0
var seeded := ""
var sown_at := Vector3.ZERO
var _mark_sown := false
var eco := EcologyRules.new()

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
	# ponytail: mist and a golden afternoon hold the water already there; a clear hour still dries it.
	var holding := weather == "mist" or weather == "golden"
	var died: Array = []
	seeded = ""
	for cell in all():
		var soil: SoilCell = cell
		var before := soil.moisture
		if raining:
			soil.moisture = minf(1.0, soil.moisture + hours * 0.95)
		elif not holding:
			soil.moisture = maxf(0.04, soil.moisture - hours * 0.22)
		if soil.plant_id == "":
			# ponytail: a clear hour returns a little feed; rain, mist, and golden leave a bare bed.
			if soil.tilled and weather == "clear" and soil.fertility < 0.42:
				soil.fertility = minf(0.42, soil.fertility + hours * 0.04)
			continue
		var definition: Dictionary = ContentDB.plant(soil.plant_id)
		if definition.is_empty():
			continue
		var grow_hours := maxf(0.2, float(definition.get("grow_hours", 2.0)))
		var need := float(definition.get("water_need", 0.3))
		if soil.moisture < need:
			if weather == "mist":
				continue
			var dry_hours := hours
			if raining:
				dry_hours = 0.0
			elif before > need:
				dry_hours = clampf((need - soil.moisture) / 0.22, 0.0, hours)
			soil.wilt += dry_hours
			# ponytail: six dry hours clears the bed; a wilt curve if crops should linger.
			soil.growth = maxf(0.04, soil.growth - hours / (grow_hours * 4.0))
			var feed_line := float(definition.get("fertility_need", 0.2))
			var waiting := soil.plant_id == "mosspear" and soil.growth < 1.0 and soil.fertility < feed_line
			if soil.wilt >= 6.0 and not waiting:
				died.append(soil.plant_id)
				soil.plant_id = ""
				soil.growth = 0.0
				soil.wilt = 0.0
				soil.taken = false
				soil.eaten_by = ""
			continue
		soil.wilt = 0.0
		if soil.fertility < float(definition.get("fertility_need", 0.2)):
			continue
		var chem_need := str(definition.get("chem", ""))
		if chem_need != "" and soil.chem != chem_need:
			continue
		# ponytail: a bed can wait for a later day; moisture and feed still move.
		if soil.grow_from_day > Clock.day:
			continue
		var rate := eco.growth_factor(definition, neighbor_ids(soil), count_plant(soil.plant_id))
		soil.growth = minf(1.0, soil.growth + hours / grow_hours * rate)
		if soil.growth >= 1.0:
			soil.taken = false
			soil.eaten_by = ""
		# ponytail: a living crop tires the bed; a slower season if he should come less often.
		soil.fertility = maxf(0.04, soil.fertility - hours * 0.03)
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

func inherit_into(plot: SoilCell) -> bool:
	if plot == null or plot.plant_id == "":
		return false
	var parent: SoilCell = null
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for off in offsets:
		var neighbor := get_cell(plot.ix + off.x, plot.iz + off.y)
		if neighbor == null or neighbor.plant_id != plot.plant_id or neighbor.growth < 1.0:
			continue
		parent = neighbor
		break
	if parent == null:
		return false
	PlantGenetics.apply_cell(plot, PlantGenetics.mix(PlantGenetics.from_cell(parent), PlantGenetics.from_cell(_mate(parent)), plot.ix * 10 + plot.iz))
	return true

func seed_from(plant_id: String) -> String:
	# ponytail: the bell ring reuses the rain neighbor; a scatter if one chime should fill the row.
	_mark_sown = true
	var sown := _seed_one(plant_id)
	_mark_sown = false
	return sown

func _seed_one(only: String = "") -> String:
	for iz in GardenLayout.BED_H:
		for ix in GardenLayout.BED_W:
			var parent := get_cell(ix, iz)
			if parent.plant_id == "" or parent.growth < 1.0:
				continue
			if only != "" and parent.plant_id != only:
				continue
			var spot := _seed_spot(ix, iz, parent.plant_id)
			if spot == null:
				continue
			spot.plant_id = parent.plant_id
			spot.growth = 0.18
			spot.wilt = 0.0
			spot.taken = false
			spot.eaten_by = ""
			spot.moisture = maxf(spot.moisture, 0.74)
			var mate := _mate(parent)
			PlantGenetics.apply_cell(spot, PlantGenetics.mix(PlantGenetics.from_cell(parent), PlantGenetics.from_cell(mate), parent.ix * 10 + parent.iz))
			if _mark_sown:
				sown_at = GardenLayout.cell_center(spot.ix, spot.iz)
			return parent.plant_id
	return ""

func _mate(parent: SoilCell) -> SoilCell:
	for cell in all():
		var other: SoilCell = cell
		if other == parent:
			continue
		if other.plant_id != parent.plant_id or other.growth < 1.0:
			continue
		return other
	return parent

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
	# ponytail: mosspear seeds at the fallow cap; ripening still uses fertility_need.
	var need := float(definition.get("seed_fertility", definition.get("fertility_need", 0.2)))
	if plot.fertility < need:
		return false
	var chem_need := str(definition.get("chem", ""))
	return chem_need == "" or plot.chem == chem_need

func neighbor_ids(plot: SoilCell) -> Array:
	var ids: Array = []
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for off in offsets:
		var other := get_cell(plot.ix + off.x, plot.iz + off.y)
		if other == null or other.plant_id == "":
			continue
		ids.append(other.plant_id)
	return ids

func count_plant(plant_id: String) -> int:
	var total := 0
	for cell in all():
		var soil: SoilCell = cell
		if soil.plant_id == plant_id:
			total += 1
	return total

func beds() -> Array:
	var rows: Array = []
	for cell in all():
		var soil: SoilCell = cell
		if soil.plant_id == "":
			continue
		rows.append({"plant_id": soil.plant_id, "ix": soil.ix, "iz": soil.iz})
	return rows

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
			soil.eaten_by = ""
			soil.hue = 0.5
			soil.stature = 1.0
			soil.crop_yield = 1.0
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var soil := get_cell(int(entry.get("ix", -1)), int(entry.get("iz", -1)))
		if soil:
			soil.apply_dict(entry)

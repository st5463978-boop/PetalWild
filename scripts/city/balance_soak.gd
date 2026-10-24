extends RefCounted

## Headless month used by tests/live/test_balance_soak.gd.
## Lives in the project so SoilField can see the ContentDB autoload.


func run(host: Node) -> Dictionary:
	var clock := host.get_node("Clock")
	var economy := host.get_node("Economy")
	clock.call("reset_new")
	clock.set("running", false)
	economy.call("reset_new")
	var soil := SoilField.new()
	var field := ServiceField.new()
	field.setup(10, 8)
	field.stamp("well", Vector2i(1, 1), 3.0, 1.0)
	field.stamp("hive", Vector2i(2, 1), 4.0, 1.0)
	var causal := CausalLog.new()
	var districts := GardenDistricts.new()
	districts.setup(field, causal)
	field.bias_for = Callable(districts, "service_bias")
	var kept := [Vector2i(1, 1), Vector2i(1, 2)]
	var neglected := [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]
	for cell_v in kept:
		var cell: Vector2i = cell_v
		_plant(soil, cell, false)
		districts.paint_cell("north_beds", cell, "North Beds")
	for cell_v in neglected:
		var cell: Vector2i = cell_v
		_plant(soil, cell, true)
		districts.paint_cell("north_beds", cell, "North Beds")
	districts.paint_cell("lane_edge", Vector2i(6, 6), "Lane Edge")
	districts.set_policy("north_beds", "organic_only", true)
	districts.set_policy("north_beds", "pollinator_haven", true)
	districts.set_policy("north_beds", "night_lanterns", true)
	districts.set_policy("lane_edge", "market_day", true)
	var paths := PathGraph.new()
	paths.setup(causal, soil, null)
	paths.reseed(4242)
	var box := {"residents": 2, "harvests": 0, "harvest_day": -1}
	paths.census_for = func() -> Dictionary:
		return {
			"residents": mini(int(box["residents"]), 3),
			"creatures": 2,
			"ripe": mini(_ripe(soil), 2),
			"hour": float(clock.call("hour")),
			"weather": str(clock.get("weather")),
		}
	var demand := CityDemand.new()
	demand.setup(field, causal, soil, null, paths)
	demand.reseed(4242)
	demand.districts = districts
	demand.signals_for = func() -> Dictionary:
		return {
			"resident_total": int(box["residents"]),
			"free_beds": _free(soil),
			"quality_mean": field.quality_mean(),
			"coins": int(economy.get("coins")),
			"stall_stock": _stock(economy),
			"footfall": paths.footfall_signal(),
		}
	var food := FoodWeb.new()
	food.reseed(4242)
	food.log = causal
	food.food_scale = Callable(districts, "food_scale")
	food.counts["grapling"] = 4
	food.counts["gushorn"] = 2
	var blight := Blight.new()
	blight.soil = soil
	blight.services = field
	blight.log = causal
	blight.pest_scale = Callable(districts, "pest_scale")
	var bloom := [100, 0]
	var hive := [100, 0]
	var market := [100, 0]
	var coins := {"start": int(economy.get("coins")), "min": int(economy.get("coins")), "max": int(economy.get("coins")), "end": 0}
	var pests := {"min": 99, "max": 0, "sum": 0.0, "n": 0}
	var residents := [100, 0]
	var web := [100, 0]
	var arrivals: Array = []
	var focus := districts.centroid("north_beds")
	for step in 30 * 24:
		clock.call("set_from_absolute", float(step) * 60.0)
		soil.tick(60.0, str(clock.get("weather")))
		_tend(host, soil, economy, kept, neglected, box)
		districts.refresh(focus, step)
		paths.tick()
		paths.settle_stall()
		field.charge_daily(int(clock.get("day")))
		districts.charge_daily(int(clock.get("day")))
		var catalog: Variant = host.get_node("ContentDB").get("species")
		var species: Dictionary = catalog if typeof(catalog) == TYPE_DICTIONARY else {}
		food.hour(species)
		blight.hour(_world(soil, field, clock), PackedStringArray())
		demand.tick()
		if int(floor(float(clock.call("hour")))) == 6:
			var before := int(box["residents"])
			box["residents"] = demand.settle(before)
			if int(box["residents"]) != before:
				arrivals.append("d%d:%d" % [int(clock.get("day")), int(box["residents"])])
		_note(bloom, demand.bloom)
		_note(hive, demand.hive)
		_note(market, demand.market)
		var purse := int(economy.get("coins"))
		coins["min"] = mini(int(coins["min"]), purse)
		coins["max"] = maxi(int(coins["max"]), purse)
		var moths := blight.moths.size()
		pests["min"] = mini(int(pests["min"]), moths)
		pests["max"] = maxi(int(pests["max"]), moths)
		pests["sum"] = float(pests["sum"]) + float(moths)
		pests["n"] = int(pests["n"]) + 1
		var web_n := int(food.counts.get("grapling", 0)) + int(food.counts.get("gushorn", 0))
		_note(residents, int(box["residents"]))
		_note(web, web_n)
	coins["end"] = int(economy.get("coins"))
	coins["flow"] = int(coins["end"]) - int(coins["start"])
	var samples := maxi(int(pests["n"]), 1)
	return {
		"days": 30,
		"bloom": [int(bloom[0]), int(bloom[1])],
		"hive": [int(hive[0]), int(hive[1])],
		"market": [int(market[0]), int(market[1])],
		"coins": coins,
		"pests": {"min": int(pests["min"]), "max": int(pests["max"]), "mean": float(pests["sum"]) / float(samples)},
		"population": {"residents": [int(residents[0]), int(residents[1])], "residents_end": int(box["residents"]), "settled": arrivals, "web": [int(web[0]), int(web[1])]},
	}


func _plant(soil: SoilField, cell: Vector2i, neglected: bool) -> void:
	var plot := soil.get_cell(cell.x, cell.y)
	plot.plant_id = "meadowbell"
	plot.tilled = true
	plot.fertility = 0.55
	plot.moisture = 0.7 if not neglected else 0.5
	plot.growth = 0.35 if not neglected else 0.04
	plot.wilt = 0.0
	plot.grow_from_day = 1 if not neglected else 9999


func _tend(host: Node, soil: SoilField, economy: Node, kept: Array, neglected: Array, box: Dictionary) -> void:
	var day := int(host.get_node("Clock").get("day"))
	if int(box["harvest_day"]) != day:
		box["harvest_day"] = day
		box["harvests"] = 0
	for cell_v in kept:
		var cell: Vector2i = cell_v
		var plot := soil.get_cell(cell.x, cell.y)
		if plot.plant_id == "":
			_plant(soil, cell, false)
		plot.moisture = maxf(plot.moisture, 0.82)
		plot.fertility = maxf(plot.fertility, 0.4)
		if plot.growth >= 1.0 and int(box["harvests"]) < 2 and int(economy.call("count", "meadowbell")) < 3:
			economy.call("add", "meadowbell", 1)
			plot.growth = 0.32
			plot.taken = true
			box["harvests"] = int(box["harvests"]) + 1
	for cell_v in neglected:
		var cell: Vector2i = cell_v
		var plot := soil.get_cell(cell.x, cell.y)
		if plot.plant_id == "":
			_plant(soil, cell, true)


func _world(soil: SoilField, field: ServiceField, clock: Node) -> Dictionary:
	var mature := {}
	var moisture := 0.0
	var count := 0
	for cell_v in soil.all():
		var plot: SoilCell = cell_v
		count += 1
		moisture += plot.moisture
		if plot.plant_id != "" and plot.growth >= 1.0:
			mature[plot.plant_id] = int(mature.get(plot.plant_id, 0)) + 1
	var mature_total := 0
	for value in mature.values():
		mature_total += int(value)
	var quality := clampf(float(mature_total) / 10.0, 0.0, 1.0) * 0.75
	quality += clampf(moisture / maxf(float(count), 1.0), 0.0, 1.0) * 0.25
	return {
		"garden_quality": quality,
		"mature": mature,
		"service_field": field,
		"weather": str(clock.get("weather")),
		"hour": float(clock.call("hour")),
		"species_state": {},
		"structures": {},
	}


func _free(soil: SoilField) -> int:
	var free := 0
	for cell_v in soil.all():
		var plot: SoilCell = cell_v
		if plot.plant_id == "":
			free += 1
	return free


func _ripe(soil: SoilField) -> int:
	var ripe := 0
	for cell_v in soil.all():
		var plot: SoilCell = cell_v
		if plot.plant_id != "" and plot.growth >= 1.0:
			ripe += 1
	return ripe


func _stock(economy: Node) -> int:
	var total := 0
	for plant_id in ["meadowbell", "peach", "reed", "bramble", "mosspear", "nightlantern"]:
		total += int(economy.call("count", plant_id))
	return total


func _note(span: Array, value: int) -> void:
	span[0] = mini(int(span[0]), value)
	span[1] = maxi(int(span[1]), value)

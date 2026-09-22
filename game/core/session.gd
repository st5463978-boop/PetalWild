extends Node

signal notice(text: String)
signal changed

const SAVE_VERSION := 1
const SECONDS_PER_DAY := 180.0

const ContentDB = preload("res://game/core/content_db.gd")
const GardenSim = preload("res://game/sim/garden_sim.gd")
const EcologySim = preload("res://game/sim/ecology_sim.gd")
const TownSim = preload("res://game/sim/town_sim.gd")
const TrustSim = preload("res://game/sim/trust_sim.gd")

var content
var garden
var ecology
var town
var trust

var day := 1
var hour := 17.6
var season := "spring"
var weather := "clear"
var weather_time := 0.0
var speed := 1.5
var paused := true
var playing := false
var petals := 28
var sales := 0
var thefts := 0
var theft_timer := 18.0
var inventory: Dictionary = {}
var people: Dictionary = {}
var relationships: Dictionary = {}
var log_lines: Array = []
var tool := "till"
var selected_seed := "sunpetal"
var speech: Dictionary = {}
var master_volume := 0.75
var ui_scale := 1.0
var reduce_motion := false
var ecology_timer := 0.0


func _ready() -> void:
	content = ContentDB.new()
	content.load_all()
	garden = GardenSim.new()
	ecology = EcologySim.new()
	town = TownSim.new()
	trust = TrustSim.new()
	_load_settings()
	new_game()


func new_game() -> void:
	day = 1
	hour = 17.6
	season = "spring"
	weather = "clear"
	weather_time = 0.0
	speed = 1.5
	paused = true
	playing = false
	petals = 28
	sales = 0
	thefts = 0
	theft_timer = 18.0
	tool = "till"
	selected_seed = "sunpetal"
	inventory = {
		"seed_sunpetal": 6,
		"seed_petal_corn": 4,
		"fert_pack": 4,
		"home_kit": 1,
	}
	relationships = {
		"quin_hearth|lumen_barrow": -0.2,
		"quin_hearth|neeve_allium": 0.4,
		"lumen_barrow|neeve_allium": 0.15,
		"player|quin_hearth": 0.25,
		"player|lumen_barrow": 0.2,
		"player|neeve_allium": 0.2,
	}
	log_lines = ["The hedge gate is shut. The beds are still grass."]
	speech = {}
	garden.configure(content.plants)
	garden.setup_new()
	ecology.setup(content.species)
	town.setup(content.districts, content.venues)
	trust.setup(content.agents)
	people.clear()
	for entry in content.residents:
		var spec: Dictionary = entry
		var home: Dictionary = spec.get("home", {})
		people[str(spec.id)] = {
			"id": spec.id,
			"unlocked": false,
			"energy": 0.82,
			"social": 0.55,
			"purpose": 0.7,
			"mood": "waiting",
			"x": float(home.get("x", 0.0)),
			"z": float(home.get("z", 0.0)),
			"tx": float(home.get("x", 0.0)),
			"tz": float(home.get("z", 0.0)),
			"line": "",
		}
	_refresh_derived()
	changed.emit()


func begin_playing() -> void:
	playing = true
	paused = false
	_say("The garden is yours. Till a bed before you trust a seed to it.")
	changed.emit()


func advance(delta: float) -> void:
	if not playing or paused:
		return
	var sim_delta := delta * speed
	hour += sim_delta / SECONDS_PER_DAY * 24.0
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		_roll_season()
		_say("Day %d begins." % day)
	_tick_weather(sim_delta)
	garden.tick(sim_delta, weather, hour, season)
	_tick_people(sim_delta)
	_tick_theft(sim_delta)
	ecology_timer += sim_delta
	if ecology_timer >= 0.45:
		var events: Array = ecology.evaluate(_ecology_context(), ecology_timer)
		ecology_timer = 0.0
		for event in events:
			_on_ecology_event(event)
	for id in speech.keys():
		speech[id] = maxf(0.0, float(speech[id]) - delta)
	_refresh_derived()
	changed.emit()


func use_tool(x: int, z: int) -> String:
	if not playing:
		return ""
	var message := ""
	match tool:
		"till":
			message = "Soil turned." if garden.till(x, z) else "That ground will not turn."
		"seed":
			message = _plant(x, z)
		"water":
			message = "Watered." if garden.water(x, z) else "Nothing there to drink."
		"fert":
			if int(inventory.get("fert_pack", 0)) <= 0:
				message = "No fertility packs."
			elif garden.fertilize(x, z):
				inventory["fert_pack"] = int(inventory["fert_pack"]) - 1
				message = "Fertilised."
			else:
				message = "Can't fertilise that."
		"tend":
			message = _tend(x, z)
		"scoop":
			message = "Pool changed." if garden.scoop(x, z) else "Scoop an empty bed, or fill a pool back in."
		"home":
			message = _home()
	if message != "":
		_say(message)
	changed.emit()
	return message


func buy(item_id: String) -> String:
	var item := _item(item_id)
	if item.is_empty():
		return "Not in the stall."
	if not unlock_ok(item.get("unlock", {"type": "always"})):
		return "Quin hasn't learned that yet."
	var price := int(item.get("price", 1))
	if petals < price:
		return "Not enough petals."
	petals -= price
	var gives := str(item.get("gives", item_id))
	inventory[gives] = int(inventory.get(gives, 0)) + int(item.get("qty", 1))
	sales += 1
	_shift_relationship("player|quin_hearth", 0.03)
	var message := "Bought %s." % item.get("name", item_id)
	_say(message)
	changed.emit()
	return message


func sell_produce(plant_id: String) -> String:
	var key := "produce_%s" % plant_id
	if int(inventory.get(key, 0)) <= 0:
		return "No %s to sell." % content.plant_name(plant_id)
	inventory[key] = int(inventory[key]) - 1
	var price := int(content.plants.get(plant_id, {}).get("sell", 1))
	petals += price
	sales += 1
	var message := "Sold %s for %d petals." % [content.plant_name(plant_id), price]
	_say(message)
	changed.emit()
	return message


func unlock_ok(unlock: Dictionary) -> bool:
	match str(unlock.get("type", "always")):
		"always":
			return true
		"species_at_least":
			var rec: Dictionary = ecology.records.get(str(unlock.get("id", "")), {})
			return ecology.rank(str(rec.get("state", "UNKNOWN"))) >= ecology.rank(str(unlock.get("state", "VISITOR")))
		"sales_at_least":
			return sales >= int(unlock.get("count", 1))
		"sightings_at_least":
			return ecology.sighting_count() >= int(unlock.get("count", 1))
		"resident_unlocked":
			return bool(people.get(str(unlock.get("id", "")), {}).get("unlocked", false))
		"residents":
			return unlocked_people() >= int(unlock.get("count", 1))
		_:
			return false


func quality() -> float:
	var score := 48.0
	for plant_id in content.plants.keys():
		score += float(garden.count_mature(str(plant_id))) * 2.0
		score += float(garden.count_plant(str(plant_id))) * 0.4
	score += float(garden.count_soil("water")) * 0.7
	score += float(ecology.resident_count()) * 5.0
	score += float(unlocked_people()) * 2.0
	return score


func phase_name() -> String:
	if hour < 5.0 or hour >= 19.5:
		return "Night"
	if hour < 8.0:
		return "Dawn"
	if hour < 16.5:
		return "Day"
	return "Dusk"


func is_night() -> bool:
	return hour < 6.0 or hour >= 19.0


func unlocked_people() -> int:
	var count := 0
	for id in people.keys():
		if bool(people[id].unlocked):
			count += 1
	return count


func save_slot(slot: int) -> bool:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(to_save(), "\t"))
	_say("Saved slot %d." % slot)
	return true


func load_slot(slot: int) -> bool:
	var file := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		_say("Slot %d is empty." % slot)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_say("That save could not be read.")
		return false
	var data: Dictionary = parsed
	var version := int(data.get("version", 0))
	if version <= 0 or version > SAVE_VERSION:
		_say("Save version %d is not supported." % version)
		return false
	_apply_save(data)
	playing = true
	paused = false
	_say("Garden restored.")
	changed.emit()
	return true


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func to_save() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"day": day,
		"hour": hour,
		"season": season,
		"weather": weather,
		"weather_time": weather_time,
		"speed": speed,
		"petals": petals,
		"sales": sales,
		"thefts": thefts,
		"inventory": inventory.duplicate(true),
		"people": people.duplicate(true),
		"relationships": relationships.duplicate(true),
		"log": log_lines.duplicate(),
		"tool": tool,
		"selected_seed": selected_seed,
		"garden": garden.to_dict(),
		"ecology": ecology.to_dict(),
		"town": town.to_dict(),
		"trust": trust.to_dict(),
	}


func save_settings() -> void:
	var file := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"master_volume": master_volume,
		"ui_scale": ui_scale,
		"reduce_motion": reduce_motion,
	}))


func force_hour(value: float) -> void:
	hour = fmod(value, 24.0)
	if hour < 0.0:
		hour += 24.0


func force_weather(value: String) -> void:
	weather = value


func grow_all() -> void:
	for plot in garden.plots:
		if str(plot.plant_id) != "":
			plot.growth = 1.0


func _apply_save(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	hour = float(data.get("hour", 8.0))
	season = str(data.get("season", "spring"))
	weather = str(data.get("weather", "clear"))
	weather_time = float(data.get("weather_time", 0.0))
	speed = float(data.get("speed", 1.5))
	petals = int(data.get("petals", 0))
	sales = int(data.get("sales", 0))
	thefts = int(data.get("thefts", 0))
	inventory = data.get("inventory", {})
	people = data.get("people", {})
	relationships = data.get("relationships", {})
	log_lines = data.get("log", [])
	tool = str(data.get("tool", "till"))
	selected_seed = str(data.get("selected_seed", "sunpetal"))
	garden.configure(content.plants)
	garden.from_dict(data.get("garden", {}))
	ecology.setup(content.species)
	ecology.from_dict(data.get("ecology", {}))
	town.setup(content.districts, content.venues)
	town.from_dict(data.get("town", {}))
	trust.setup(content.agents)
	trust.from_dict(data.get("trust", {}))
	_refresh_derived()


func _ecology_context() -> Dictionary:
	var mature := {}
	var states := {}
	for plant_id in content.plants.keys():
		mature[str(plant_id)] = garden.count_mature(str(plant_id))
	for id in ecology.records.keys():
		states[str(id)] = str(ecology.records[id].state)
	return {
		"mature": mature,
		"states": states,
		"water_cells": garden.count_soil("water"),
		"fertility": garden.average_fertility(),
		"chemistry": {
			"pollinated": garden.count_chemistry("pollinated"),
			"compost": garden.count_chemistry("compost"),
		},
		"quality": quality(),
		"weather": weather,
		"night": is_night(),
		"season": season,
		"garden": garden,
	}


func _refresh_derived() -> void:
	for id in people.keys():
		var spec := _resident(id)
		var person: Dictionary = people[id]
		if bool(person.unlocked):
			continue
		if spec.is_empty():
			continue
		if unlock_ok(spec.get("unlock", {"type": "always"})):
			person.unlocked = true
			person.mood = "arrived"
			var lines: Dictionary = spec.get("lines", {})
			person.line = str(lines.get("arrive", ""))
			speech[id] = 6.0
			_say(str(person.line))
	town.tick({
		"resident_creatures": ecology.resident_count(),
		"veg_people": unlocked_people(),
		"quality": quality(),
		"thefts": thefts,
		"people": people,
	})


func _tick_people(delta: float) -> void:
	var phase := _schedule_phase()
	for id in people.keys():
		var person: Dictionary = people[id]
		if not bool(person.unlocked):
			continue
		var spec := _resident(id)
		var spot: Dictionary = spec.get(phase, spec.get("home", {}))
		person.tx = float(spot.get("x", person.x))
		person.tz = float(spot.get("z", person.z))
		var dx := float(person.tx) - float(person.x)
		var dz := float(person.tz) - float(person.z)
		var dist := sqrt(dx * dx + dz * dz)
		if dist > 0.05:
			var step := minf(dist, 1.4 * delta)
			person.x = float(person.x) + dx / dist * step
			person.z = float(person.z) + dz / dist * step
			person.mood = "walking"
		else:
			person.mood = phase
			if phase == "home":
				person.energy = minf(1.0, float(person.energy) + 0.04 * delta)
			elif phase == "work":
				person.purpose = minf(1.0, float(person.purpose) + 0.04 * delta)
			else:
				person.social = minf(1.0, float(person.social) + 0.04 * delta)
		person.energy = maxf(0.0, float(person.energy) - 0.008 * delta)
		person.social = maxf(0.0, float(person.social) - 0.006 * delta)
		person.purpose = maxf(0.0, float(person.purpose) - 0.005 * delta)


func _tick_theft(delta: float) -> void:
	theft_timer -= delta
	if theft_timer > 0.0:
		return
	theft_timer = 36.0
	var blob: Dictionary = ecology.records.get("blob", {})
	if ecology.rank(str(blob.get("state", "UNKNOWN"))) < ecology.rank("VISITOR"):
		return
	if not garden.steal_produce("petal_corn"):
		return
	thefts += 1
	ecology.adjust_bond("blob", -0.04, "playful")
	_shift_relationship("player|quin_hearth", -0.06)
	_shift_relationship("quin_hearth|lumen_barrow", -0.04)
	var quin: Dictionary = people.get("quin_hearth", {})
	if bool(quin.get("unlocked", false)):
		var lines: Dictionary = _resident("quin_hearth").get("lines", {})
		quin.line = str(lines.get("theft", "The corn walked off."))
		speech["quin_hearth"] = 5.0
		_say(str(quin.line))
		var lumen: Dictionary = people.get("lumen_barrow", {})
		if bool(lumen.get("unlocked", false)):
			var lumen_lines: Dictionary = _resident("lumen_barrow").get("lines", {})
			lumen.line = str(lumen_lines.get("theft", ""))
			speech["lumen_barrow"] = 5.0


func _tick_weather(delta: float) -> void:
	weather_time += delta
	var limit := 70.0 if weather == "clear" else 28.0
	if weather_time < limit:
		return
	weather_time = 0.0
	var roll := randf()
	var next := "clear"
	if roll > 0.72:
		next = "rain"
	elif roll > 0.5:
		next = "mist"
	if next != weather:
		weather = next
		_say("The weather turns to %s." % weather)


func _plant(x: int, z: int) -> String:
	var key := "seed_%s" % selected_seed
	if int(inventory.get(key, 0)) <= 0:
		return "The pouch has no %s." % content.plant_name(selected_seed)
	var error: String = garden.plant_seed(x, z, selected_seed)
	if error != "":
		return error
	inventory[key] = int(inventory[key]) - 1
	return "Planted %s." % content.plant_name(selected_seed)


func _tend(x: int, z: int) -> String:
	var result: Dictionary = garden.tend(x, z)
	var harvested := str(result.get("harvested", ""))
	if harvested != "":
		var key := "produce_%s" % harvested
		inventory[key] = int(inventory.get(key, 0)) + 1
		petals += 2
		return "Harvested %s." % content.plant_name(harvested)
	if bool(result.get("tended", false)):
		return "Tended."
	return "Nothing to tend."


func _home() -> String:
	if int(inventory.get("home_kit", 0)) <= 0:
		return "No home kit."
	var id: String = ecology.best_settler()
	if id == "":
		return "Nobody is ready to settle."
	var before := str(ecology.records[id].state)
	if not ecology.grant_home(id):
		return "They will not take a house yet."
	inventory["home_kit"] = int(inventory["home_kit"]) - 1
	_on_ecology_event({
		"type": "state",
		"id": id,
		"name": ecology.defs[id].get("name", id),
		"from": before,
		"to": ecology.records[id].state,
	})
	return ""


func _on_ecology_event(event: Dictionary) -> void:
	var name := str(event.get("name", "A creature"))
	var to_state := str(event.get("to", ""))
	_say("%s is now %s." % [name, to_state.to_lower().replace("_", " ")])


func _schedule_phase() -> String:
	if hour >= 6.0 and hour < 9.0:
		return "home"
	if hour >= 9.0 and hour < 17.0:
		return "work"
	if hour >= 17.0 and hour < 21.0:
		return "social"
	return "home"


func _roll_season() -> void:
	var names := ["spring", "summer", "autumn", "winter"]
	season = names[int((day - 1) / 3) % 4]


func _shift_relationship(key: String, amount: float) -> void:
	relationships[key] = clampf(float(relationships.get(key, 0.0)) + amount, -1.0, 1.0)


func _resident(id: String) -> Dictionary:
	for entry in content.residents:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func _item(id: String) -> Dictionary:
	for entry in content.items:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func _say(text: String) -> void:
	if text == "":
		return
	log_lines.append(text)
	if log_lines.size() > 30:
		log_lines.pop_front()
	notice.emit(text)


func _slot_path(slot: int) -> String:
	return "user://saves/slot%d.json" % slot


func _load_settings() -> void:
	var file := FileAccess.open("user://settings.json", FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	master_volume = float(parsed.get("master_volume", master_volume))
	ui_scale = float(parsed.get("ui_scale", ui_scale))
	reduce_motion = bool(parsed.get("reduce_motion", reduce_motion))

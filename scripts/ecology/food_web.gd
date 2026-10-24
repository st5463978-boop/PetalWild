class_name FoodWeb
extends RefCounted

## Predator and prey counts. Predation stops at the surplus floor so a prey is never wiped out.
## Rates, the floor, and the seed span live in data/ecology.json.

var counts: Dictionary = {}
var banks: Dictionary = {}
var eaten: Dictionary = {}
var seed := 4242
var hour_index := 0
var tuning: Dictionary = {}
var log: CausalLog


func _init() -> void:
	_load()


func reseed(next_seed: int) -> void:
	seed = next_seed


func sync_minimums(actors: Dictionary) -> void:
	for key_v in actors.keys():
		var id := str(key_v)
		var have := int(actors[key_v])
		if int(counts.get(id, 0)) < have:
			counts[id] = have


func hour(catalog: Dictionary) -> Dictionary:
	var step := hour_index
	hour_index += 1
	var ids := _ids(catalog)
	var prey_of := _prey_of(catalog, ids)
	for id in ids:
		var definition := _def(catalog, id)
		if _diet(definition).size() > 0:
			continue
		if not prey_of.has(id):
			continue
		if int(counts.get(id, 0)) <= 0 and not bool(tuning.get("grow_from_zero", false)):
			continue
		_grow(id, _cap(definition), step)
	var losses := {}
	for id in ids:
		var definition := _def(catalog, id)
		var diet := _diet(definition)
		if diet.is_empty() or int(counts.get(id, 0)) <= 0:
			continue
		var ate := _predate(id, definition, diet, catalog, step, losses)
		if ate > 0:
			banks["starve:" + id] = 0
			_grow(id, _cap(definition), step)
		else:
			_starve(id, definition, step)
	return losses


func to_state() -> Dictionary:
	return {
		"seed": seed,
		"hour_index": hour_index,
		"counts": counts.duplicate(),
		"banks": banks.duplicate(),
		"eaten": eaten.duplicate(),
	}


func apply_state(data: Variant) -> void:
	counts.clear()
	banks.clear()
	eaten.clear()
	hour_index = 0
	if typeof(data) != TYPE_DICTIONARY:
		return
	var body: Dictionary = data
	if body.has("seed"):
		seed = int(body.get("seed", seed))
	hour_index = int(body.get("hour_index", 0))
	_copy_ints(body.get("counts", {}), counts)
	_copy_ints(body.get("banks", {}), banks)
	_copy_ints(body.get("eaten", {}), eaten)


func _predate(predator: String, definition: Dictionary, diet: Array, catalog: Dictionary, step: int, losses: Dictionary) -> int:
	var floor_n := int(tuning.get("floor", 1))
	var surplus_min := int(tuning.get("surplus_min", 2))
	var ate := 0
	for bite_v in diet:
		if typeof(bite_v) != TYPE_DICTIONARY:
			continue
		var bite: Dictionary = bite_v
		var prey := str(bite.get("species", ""))
		if prey == "" or prey == predator:
			continue
		var have := int(counts.get(prey, 0))
		var spare := have - floor_n - surplus_min
		if spare <= 0:
			continue
		var rate := float(bite.get("rate", 0.0))
		var whole := int(floor(rate))
		var key := "bite:" + predator + ">" + prey
		var bank := int(banks.get(key, 0))
		bank += int(round((rate - float(whole)) * 100.0))
		if bank >= 100:
			whole += 1
			bank -= 100
		banks[key] = bank
		var eat := mini(maxi(whole, 0), spare)
		if eat < spare and _phase(predator, prey, step) == 1:
			eat += 1
		if eat <= 0:
			continue
		counts[prey] = have - eat
		ate += eat
		losses[prey] = int(losses.get(prey, 0)) + eat
		var pair := predator + ">" + prey
		eaten[pair] = int(eaten.get(pair, 0)) + eat
		var prey_name := str(_def(catalog, prey).get("name", prey))
		var pred_name := str(definition.get("name", predator))
		var why := "%s ate %d %s because %d %s sat above the surplus of %d." % [pred_name, eat, prey_name, have, prey_name, surplus_min]
		_write_log(prey, why)
	return ate


func _grow(id: String, cap: int, step: int) -> void:
	var every := maxi(int(tuning.get("grow_every", 4)), 1)
	var key := "grow:" + id
	var bank := int(banks.get(key, 0)) + 1
	if _phase(id, "grow", step) == 1:
		bank += 1
	while bank >= every and int(counts.get(id, 0)) < cap:
		bank -= every
		counts[id] = int(counts.get(id, 0)) + 1
	banks[key] = bank


func _starve(id: String, definition: Dictionary, step: int) -> void:
	if int(counts.get(id, 0)) <= 0:
		return
	var every := maxi(int(tuning.get("starve_every", 6)), 1)
	var key := "starve:" + id
	var bank := int(banks.get(key, 0)) + 1
	if _phase(id, "starve", step) == 1:
		bank += 1
	if bank >= every:
		bank -= every
		counts[id] = int(counts.get(id, 0)) - 1
		var display := str(definition.get("name", id))
		_write_log(id, "%s thinned to %d because prey stayed at the surplus floor." % [display, int(counts.get(id, 0))])
	banks[key] = bank


func _phase(species_id: String, kind: String, step: int) -> int:
	var span := maxi(int(tuning.get("seed_span", 5)), 1)
	if span <= 1:
		return 0
	# species_id and kind keep the call sites distinct if a later span wants them.
	var mixed := absi(seed) + step + absi(species_id.length() + kind.length())
	if mixed % span == 0:
		return 1
	return 0


func _prey_of(catalog: Dictionary, ids: Array[String]) -> Dictionary:
	var found := {}
	for id in ids:
		for bite_v in _diet(_def(catalog, id)):
			if typeof(bite_v) != TYPE_DICTIONARY:
				continue
			var bite: Dictionary = bite_v
			var prey := str(bite.get("species", ""))
			if prey != "":
				found[prey] = true
	return found


func _ids(catalog: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key_v in catalog.keys():
		ids.append(str(key_v))
	ids.sort()
	return ids


func _def(catalog: Dictionary, id: String) -> Dictionary:
	var body: Variant = catalog.get(id, {})
	if typeof(body) != TYPE_DICTIONARY:
		return {}
	return body


func _diet(definition: Dictionary) -> Array:
	var body: Variant = definition.get("diet", [])
	if typeof(body) != TYPE_ARRAY:
		return []
	return body


func _cap(definition: Dictionary) -> int:
	if definition.has("web_cap"):
		return maxi(int(definition.get("web_cap", 1)), 1)
	return maxi(int(tuning.get("default_cap", 8)), 1)


func _copy_ints(body: Variant, into: Dictionary) -> void:
	if typeof(body) != TYPE_DICTIONARY:
		return
	var source: Dictionary = body
	for key_v in source.keys():
		into[str(key_v)] = int(source[key_v])


func _write_log(target: String, why: String) -> void:
	if log == null:
		return
	log.add({
		"kind": "food_web",
		"target": target,
		"cause": why,
		"summary": why,
	}, float(hour_index))


func _load() -> void:
	tuning = {}
	var text := FileAccess.get_file_as_string("res://data/ecology.json")
	if text == "":
		push_error("Missing data file res://data/ecology.json")
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in res://data/ecology.json")
		return
	var root: Dictionary = parsed
	var body: Variant = root.get("food_web", {})
	if typeof(body) == TYPE_DICTIONARY:
		tuning = body

class_name EcologyRules
extends RefCounted

const RANKS := {
	"unknown": 0,
	"rumoured": 1,
	"sighted": 2,
	"curious": 3,
	"visitor": 4,
	"repeat": 5,
	"settler": 6,
	"resident": 7,
	"bonded": 8,
	"breeding": 9,
}

func rank_of(state: String) -> int:
	return int(RANKS.get(state, 0))

func requirement_met(req: Dictionary, world: Dictionary) -> bool:
	var kind := str(req.get("type", ""))
	match kind:
		"mature_plant":
			var mature: Dictionary = world.get("mature", {})
			return int(mature.get(str(req.get("plant", "")), 0)) >= int(req.get("min", 1))
		"pond_cells":
			return int(world.get("pond_cells", 0)) >= int(req.get("min", 1))
		"moisture":
			return float(world.get("moisture", 0.0)) >= float(req.get("min", 0.0))
		"fertility":
			return float(world.get("fertility", 0.0)) >= float(req.get("min", 0.0))
		"chem_cells":
			var chem: Dictionary = world.get("chem", {})
			return int(chem.get(str(req.get("chem", "")), 0)) >= int(req.get("min", 1))
		"weather_in":
			return str(world.get("weather", "")) in req.get("weather", [])
		"hour_between":
			var hour := float(world.get("hour", 0.0))
			return hour >= float(req.get("from", 0.0)) and hour <= float(req.get("to", 24.0))
		"species_state":
			var states: Dictionary = world.get("species_state", {})
			var have := str(states.get(str(req.get("species", "")), "unknown"))
			return rank_of(have) >= rank_of(str(req.get("state", "visitor")))
		"resident_count":
			var counts: Dictionary = world.get("resident_count", {})
			return int(counts.get(str(req.get("species", "")), 0)) >= int(req.get("min", 2))
		"structure":
			var structures: Dictionary = world.get("structures", {})
			return int(structures.get(str(req.get("id", "")), 0)) >= int(req.get("min", 1))
		"garden_quality":
			return float(world.get("garden_quality", 0.0)) >= float(req.get("min", 1.0))
		_:
			return false

func all_met(species: Dictionary, world: Dictionary) -> bool:
	for req in species.get("requirements", []):
		if not requirement_met(req, world):
			return false
	return true

func unmet(species: Dictionary, world: Dictionary) -> PackedStringArray:
	var labels := PackedStringArray()
	for req in species.get("requirements", []):
		if not requirement_met(req, world):
			labels.append(str(req.get("label", "Condition")))
	return labels

func met_labels(species: Dictionary, world: Dictionary) -> PackedStringArray:
	var labels := PackedStringArray()
	for req in species.get("requirements", []):
		if requirement_met(req, world):
			labels.append(str(req.get("label", "Condition")))
	return labels

func romance_met(species: Dictionary, world: Dictionary) -> bool:
	var romance: Dictionary = species.get("romance", {})
	if romance.is_empty():
		return false
	return requirement_met(romance, world)

func romance_label(species: Dictionary) -> String:
	var romance: Dictionary = species.get("romance", {})
	if romance.is_empty():
		return ""
	return str(romance.get("label", "Romance"))

func food_of(species: Dictionary) -> String:
	return str(species.get("food", ""))

func habitat_of(entry: Dictionary) -> String:
	return str(entry.get("habitat", ""))

func growth_factor(plant: Dictionary, neighbor_ids: Array, same_count: int) -> float:
	var rate := 1.0
	var likes := str(plant.get("likes", ""))
	if likes != "" and neighbor_ids.has(likes):
		rate += 0.28
	var crowd := int(plant.get("crowd", 99))
	if same_count >= crowd:
		rate *= 0.7
	return rate

func likes_label(plant: Dictionary, neighbor_ids: Array) -> String:
	var likes := str(plant.get("likes", ""))
	if likes == "" or not neighbor_ids.has(likes):
		return ""
	return str(plant.get("likes_label", "A neighbour is helping."))

func crowded(plant: Dictionary, same_count: int) -> bool:
	return same_count >= int(plant.get("crowd", 99))

func adjacent(a: Dictionary, b: Dictionary) -> bool:
	return absi(int(a.get("ix", 0)) - int(b.get("ix", 0))) + absi(int(a.get("iz", 0)) - int(b.get("iz", 0))) == 1

func garden_line(beds: Array, plants: Dictionary) -> String:
	var counts := {}
	for bed in beds:
		var crop_id := str(bed.get("plant_id", ""))
		if crop_id == "":
			continue
		counts[crop_id] = int(counts.get(crop_id, 0)) + 1
	for bed in beds:
		var bed_id := str(bed.get("plant_id", ""))
		var crop_def: Dictionary = plants.get(bed_id, {})
		var likes := str(crop_def.get("likes", ""))
		if likes == "":
			continue
		for other in beds:
			if str(other.get("plant_id", "")) != likes:
				continue
			if not adjacent(bed, other):
				continue
			var here := habitat_of(crop_def)
			var liked_def: Dictionary = plants.get(likes, {})
			var there := habitat_of(liked_def)
			if here == "" or there == "":
				return "Neighbouring beds are helping each other."
			return "The %s leans on the %s." % [here, there]
	for stand_id in counts.keys():
		var stand_def: Dictionary = plants.get(str(stand_id), {})
		if not crowded(stand_def, int(counts[stand_id])):
			continue
		var stand := habitat_of(stand_def)
		if stand == "":
			return "A stand is crowded."
		return "The %s is crowded." % stand
	return ""

func restless_line(species: Dictionary, counts: Dictionary, plants: Dictionary) -> String:
	var habitat := habitat_of(species)
	if habitat == "":
		return ""
	var own := 0
	var other := 0
	var other_name := ""
	for crop in counts.keys():
		var crop_def: Dictionary = plants.get(str(crop), {})
		var n := int(counts[crop])
		if habitat_of(crop_def) == habitat:
			own += n
		elif n > other:
			other = n
			other_name = habitat_of(crop_def)
	if other >= 5 and other >= own * 3 and other_name != "":
		return "The %s is crowding the %s." % [other_name, habitat]
	return ""

func need_line(species: Dictionary, hunger: float, world: Dictionary, plants: Dictionary) -> String:
	if hunger < 0.28:
		var food_id := food_of(species)
		var food: Dictionary = plants.get(food_id, {})
		var food_name := str(food.get("name", food_id))
		if food_name == "":
			return "Hungry."
		return "Hungry  ·  wants %s" % food_name
	var counts: Dictionary = world.get("plant_counts", {})
	return restless_line(species, counts, plants)

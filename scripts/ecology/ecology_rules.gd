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

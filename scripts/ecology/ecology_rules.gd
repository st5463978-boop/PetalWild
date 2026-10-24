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

const TIER_RANK := {
	"closed": 0,
	"visit": 1,
	"resident": 2,
	"romance": 3,
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
		"service":
			return _service_met(req, world)
		_:
			return false

func _service_met(req: Dictionary, world: Dictionary) -> bool:
	var field: Variant = world.get("service_field", null)
	if not (field is ServiceField):
		return false
	var grid: ServiceField = field
	var channel := str(req.get("channel", ""))
	var minimum := float(req.get("min", 0.0))
	if req.has("x") and req.has("z"):
		return grid.sample(Vector2i(int(req.get("x", 0)), int(req.get("z", 0))), channel) >= minimum
	return grid.channel_max(channel) >= minimum


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


func tier_rank(tier: String) -> int:
	return int(TIER_RANK.get(tier, 0))


func gate_defined(species: Dictionary, tier: String) -> bool:
	var key := "%s_req" % tier
	if species.has(key):
		return _gate_list(species[key]).size() > 0
	if tier == "visit":
		return _gate_list(species.get("requirements", [])).size() > 0
	if tier == "romance":
		return _gate_list(species.get("romance", {})).size() > 0
	return false


func gate_reqs(species: Dictionary, tier: String) -> Array:
	var key := "%s_req" % tier
	if species.has(key):
		return _gate_list(species[key])
	if tier == "visit":
		return _gate_list(species.get("requirements", []))
	if tier == "romance":
		return _gate_list(species.get("romance", {}))
	return []


func gate_met(species: Dictionary, world: Dictionary, tier: String) -> bool:
	if not gate_defined(species, tier):
		return false
	for req_v in gate_reqs(species, tier):
		if typeof(req_v) != TYPE_DICTIONARY:
			return false
		var req: Dictionary = req_v
		if not requirement_met(req, world):
			return false
	return true


func highest_tier(species: Dictionary, world: Dictionary) -> String:
	if not gate_met(species, world, "visit"):
		return "closed"
	if gate_defined(species, "resident"):
		if not gate_met(species, world, "resident"):
			return "visit"
		if gate_defined(species, "romance") and gate_met(species, world, "romance"):
			return "romance"
		return "resident"
	if gate_defined(species, "romance") and gate_met(species, world, "romance"):
		return "romance"
	return "visit"


func gate_summary(species: Dictionary, world: Dictionary, tier: String) -> String:
	var focus := tier
	if focus == "closed" or not gate_defined(species, focus):
		focus = "visit"
	var bits := PackedStringArray()
	for req_v in gate_reqs(species, focus):
		if typeof(req_v) != TYPE_DICTIONARY:
			continue
		var req: Dictionary = req_v
		var label := str(req.get("label", "Condition"))
		if requirement_met(req, world):
			bits.append("met " + label)
		else:
			bits.append("unmet " + label)
	if bits.is_empty():
		return "no requirements are set"
	return ", ".join(bits)


func _gate_list(body: Variant) -> Array:
	if typeof(body) == TYPE_ARRAY:
		return body
	if typeof(body) == TYPE_DICTIONARY and not (body as Dictionary).is_empty():
		return [body]
	return []

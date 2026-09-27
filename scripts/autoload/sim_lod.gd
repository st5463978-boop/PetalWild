extends Node

var tiers := {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
var district_stats := {
	"id": "hedge_hollow",
	"name": "Hedge Hollow",
	"phase": "A",
	"veg_people": 0,
	"creature_residents": 0,
	"employed": 1,
	"garden_quality": 0.0,
	"coins": 0,
}

var vale_lod := {}

func classify(distance: float, held: bool, inspected: bool) -> int:
	if held or inspected:
		return 0
	if distance < 7.5:
		return 1
	if distance < 16.0:
		return 2
	if distance < 36.0:
		return 3
	return 4

func recount(actors: Array) -> void:
	tiers = {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var key := str(int(actor.tier))
		tiers[key] = int(tiers.get(key, 0)) + 1

func note_population(people: int, residents: int, quality: float, coins: int) -> void:
	district_stats["veg_people"] = people
	district_stats["creature_residents"] = residents
	district_stats["garden_quality"] = quality
	district_stats["coins"] = coins
	district_stats["employed"] = 1 if people > 0 else 0

func note_aggregate(n: int) -> void:
	note_town(0, n)

func note_town(individuals: int, distant: int) -> void:
	# ponytail: L3 is named folk in view; L4 is the rest of the settlement.
	tiers["3"] = int(tiers.get("3", 0)) + individuals
	tiers["4"] = distant

func note_vale(data: Dictionary) -> void:
	vale_lod = data

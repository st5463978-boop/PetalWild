extends Node

var tiers := {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
var district_rows: Array = []
var stride_2 := 2
var stride_3 := 4
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

func _ready() -> void:
	_load_lod()


func stride_for(tier: int) -> int:
	if tier <= 1:
		return 1
	if tier == 2:
		return maxi(stride_2, 1)
	if tier == 3:
		return maxi(stride_3, 1)
	return 0


func note_districts(rows: Array) -> void:
	district_rows = rows.duplicate(true)


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

func _load_lod() -> void:
	var text := FileAccess.get_file_as_string("res://data/policies.json")
	if text == "":
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var lod: Variant = (parsed as Dictionary).get("lod", {})
	if typeof(lod) != TYPE_DICTIONARY:
		return
	var body: Dictionary = lod
	stride_2 = int(body.get("stride_2", stride_2))
	stride_3 = int(body.get("stride_3", stride_3))


func note_population(people: int, residents: int, quality: float, coins: int) -> void:
	district_stats["veg_people"] = people
	district_stats["creature_residents"] = residents
	district_stats["garden_quality"] = quality
	district_stats["coins"] = coins
	district_stats["employed"] = 1 if people > 0 else 0

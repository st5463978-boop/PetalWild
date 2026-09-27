extends SceneTree

func _initialize() -> void:
	var rules = load("res://scripts/ecology/ecology_rules.gd").new()
	var species = JSON.parse_string(FileAccess.get_file_as_string("res://data/species.json"))
	var bell := {}
	var bulrush := {}
	for entry in species:
		if str(entry.get("id", "")) == "bellhelp":
			bell = entry
		if str(entry.get("id", "")) == "bulrush":
			bulrush = entry
	var world := {
		"mature": {"meadowbell": 3, "reed": 0},
		"pond_cells": 22,
		"moisture": 0.2,
		"fertility": 0.2,
		"chem": {},
		"weather": "clear",
		"hour": 10.0,
		"species_state": {},
		"resident_count": {},
		"structures": {},
		"garden_quality": 0.1,
	}
	if not rules.all_met(bell, world):
		push_error("bellhelp should be ready")
		quit(1)
		return
	world["mature"]["meadowbell"] = 2
	if rules.all_met(bell, world):
		push_error("bellhelp should wait for a third meadowbell")
		quit(1)
		return
	world["mature"]["reed"] = 3
	world["pond_cells"] = 26
	if not rules.all_met(bulrush, world):
		push_error("bulrush should be ready with pond and reeds")
		quit(1)
		return
	if rules.rank_of("resident") <= rules.rank_of("visitor"):
		push_error("state ranks are inverted")
		quit(1)
		return
	var plants := {}
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/plants.json"))
	for entry in catalog:
		plants[str(entry.get("id", ""))] = entry
	var meadow: Dictionary = plants["meadowbell"]
	if rules.growth_factor(meadow, ["reed"], 1) <= 1.0:
		push_error("a reed neighbour should hurry a meadowbell")
		quit(1)
		return
	if rules.growth_factor(meadow, [], 5) >= 1.0:
		push_error("five meadowbells should crowd")
		quit(1)
		return
	var beds: Array = [
		{"plant_id": "meadowbell", "ix": 1, "iz": 1},
		{"plant_id": "reed", "ix": 1, "iz": 2},
	]
	if rules.garden_line(beds, plants) != "The meadow leans on the bank.":
		push_error("the parish should name a reed beside a meadowbell")
		quit(1)
		return
	var packed: Array = []
	for i in 5:
		packed.append({"plant_id": "meadowbell", "ix": i, "iz": 0})
	if rules.garden_line(packed, plants) != "The meadow is crowded.":
		push_error("the parish should name a crowded meadow")
		quit(1)
		return
	if rules.garden_line([], plants) != "":
		push_error("an empty garden should stay quiet")
		quit(1)
		return
	var hungry: String = rules.need_line(bell, 0.2, {"plant_counts": {}}, plants)
	if hungry.find("Hungry") == -1 or hungry.find("Meadowbell") == -1:
		push_error("a hungry bellhelp should ask for meadowbells")
		quit(1)
		return
	print("PETAL_RULES_OK")
	quit(0)

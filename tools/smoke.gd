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
	print("PETAL_RULES_OK")
	quit(0)

extends SceneTree

func _init() -> void:
	var catalogs := {
		"plants": _json("res://data/plants.json"),
		"species": _json("res://data/species.json"),
		"residents": _json("res://data/residents.json"),
		"items": _json("res://data/items.json"),
		"opening": _json("res://data/opening.json"),
		"dialogue": _json("res://data/dialogue.json"),
		"venues": _json("res://data/venues.json"),
		"districts": _json("res://data/districts.json"),
	}
	_expect(catalogs["plants"].has("meadowbell"), "meadowbell plant")
	_expect(catalogs["species"].has("bellhelp"), "bellhelp species")
	var state := WorldState.fresh(catalogs)
	_expect(state["plots"].size() == 192, "plot count")
	_expect(int(state["coins"]) == 36, "coins")
	_expect(int(state["inventory"]["sunpetal_seed"]) == 5, "sunpetal seeds")
	_expect(int(state["inventory"]["petal_corn_seed"]) == 4, "corn seeds")
	_expect(bool(state["people"]["cara"]["present"]), "cara present")
	_expect(String(state["species"]["bellhelp"]["state"]) == "unknown", "bellhelp unknown")
	var blocked := {Vector2i(1, 2): true, Vector2i(2, 2): true, Vector2i(3, 2): true}
	var path: Array = PetalPath.astar(Vector2i(0, 2), Vector2i(4, 2), blocked, 5, 5)
	_expect(path.size() > 4, "path detours around a wall")
	_expect(path[0] == Vector2i(0, 2) and path[path.size() - 1] == Vector2i(4, 2), "path ends")
	var packed: Variant = JSON.parse_string(JSON.stringify(state))
	_expect(typeof(packed) == TYPE_DICTIONARY, "save json")
	if typeof(packed) != TYPE_DICTIONARY:
		quit(1)
		return
	var packed_state: Dictionary = packed
	var restored: Dictionary = WorldState.ensure(packed_state, catalogs)
	_expect(String(restored["species"]["bellhelp"]["state"]) == String(state["species"]["bellhelp"]["state"]), "roundtrip state")
	print("SMOKE OK")
	quit(0)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	if typeof(parsed) == TYPE_ARRAY:
		var out := {}
		for entry in parsed:
			if typeof(entry) == TYPE_DICTIONARY and entry.has("id"):
				out[str(entry["id"])] = entry
		return out
	return {}


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("ok  ", label)
		return
	print("FAIL ", label)
	quit(1)

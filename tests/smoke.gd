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
	var state := WorldState.fresh(catalogs)
	_expect(state["plots"].size() == 192, "plot count")
	_expect(int(state["coins"]) == 36, "coins")
	_expect(int(state["inventory"]["sunpetal_seed"]) == 5, "sunpetal seeds")
	_expect(int(state["inventory"]["petal_corn_seed"]) == 4, "corn seeds")
	_expect(bool(state["people"]["cara"]["present"]), "cara present")
	_expect(String(state["species"]["sunburst"]["state"]) == "unknown", "sunburst unknown")
	var blocked := {Vector2i(1, 2): true, Vector2i(2, 2): true, Vector2i(3, 2): true}
	var path: Array = PetalPath.astar(Vector2i(0, 2), Vector2i(4, 2), blocked, 5, 5)
	_expect(path.size() > 4, "path detours around a wall")
	_expect(path[0] == Vector2i(0, 2) and path[path.size() - 1] == Vector2i(4, 2), "path ends")
	for i in 3:
		var plot: Dictionary = state["plots"][i]
		plot["g"] = "soil"
		plot["plant"] = "sunpetal"
		plot["growth"] = 1.0
		plot["m"] = 0.8
		plot["f"] = 0.6
	state["minute"] = 10 * 60
	var ctx := PetalContext.build(state, catalogs)
	_expect(int(ctx["mature"]["sunpetal"]) == 3, "three mature sunpetals")
	var events: Array = PetalSim.tick(state, catalogs, 0.1)
	_expect(String(state["species"]["sunburst"]["state"]) == "visitor", "sunburst visits when sunpetals are open")
	_expect(bool(state["species"]["sunburst"]["present"]), "sunburst body is wanted")
	_expect(String(state["species"]["rendle"]["state"]) == "unknown", "rendle waits for a resident")
	state["inventory"]["sunpetal_bloom"] = 1
	state["harvested"]["sunpetal_bloom"] = 1
	PetalSim.feed(state, catalogs, "sunburst")
	for _i in 40:
		PetalSim.tick(state, catalogs, 1.0)
	_expect(PetalRules.state_index(String(state["species"]["sunburst"]["state"])) >= PetalRules.state_index("resident"), "sunburst settles")
	PetalSim.tick(state, catalogs, 0.2)
	_expect(PetalRules.state_index(String(state["species"]["rendle"]["state"])) >= PetalRules.state_index("visitor"), "rendle follows a resident sunburst")
	for plot in state["plots"]:
		if String(plot["g"]) == "soil" or String(plot["g"]) == "grass":
			plot["f"] = 0.7
	for _j in 5:
		PetalSim.tick(state, catalogs, 0.2)
	_expect(bool(state["flags"].get("nightbloom_unlocked", false)), "nightbloom unlocks from rendle and rich soil")
	var grown := WorldState.fresh(catalogs)
	var bed: Dictionary = grown["plots"][4 * 16 + 4]
	bed["g"] = "soil"
	bed["plant"] = "sunpetal"
	bed["growth"] = 0.0
	bed["m"] = 1.0
	bed["f"] = 1.0
	grown["minute"] = 10 * 60
	grown["weather"] = "clear"
	for _k in 80:
		PetalSim.tick(grown, catalogs, 0.5)
	_expect(float(bed["growth"]) >= 1.0, "a watered sunpetal matures")
	var poor := WorldState.fresh(catalogs)
	poor["coins"] = 1
	var denied: Array = PetalSim.try_buy(poor, catalogs, "sunpetal_seed")
	_expect(String(denied[0]["type"]) == "error", "poor purchase fails")
	_expect(int(poor["coins"]) == 1, "coins unchanged")
	var rich := WorldState.fresh(catalogs)
	var bought: Array = PetalSim.try_buy(rich, catalogs, "sunpetal_seed")
	_expect(String(bought[0]["type"]) == "ok", "purchase works")
	_expect(int(rich["coins"]) == 30, "seed costs 6")
	_expect(int(rich["inventory"]["sunpetal_seed"]) == 6, "seed added")
	var tossed := WorldState.fresh(catalogs)
	tossed["species"]["sunburst"]["present"] = true
	for _n in 3:
		PetalSim.toss(tossed, catalogs, "sunburst", true)
	_expect(int(tossed["species"]["sunburst"]["harassment"]) >= 4, "harassment stacks")
	var trust_state := WorldState.fresh(catalogs)
	trust_state["people"]["oshi"]["present"] = true
	trust_state["people"]["oshi"]["trust"] = 3
	var before := int(trust_state["coins"])
	var proposal: Array = PetalSim.propose(trust_state, catalogs, "oshi", true)
	_expect(String(proposal[0]["type"]) == "proposal", "proposal returns text")
	_expect(int(trust_state["coins"]) == before, "approval spends nothing")
	_expect(trust_state["audit"].size() == 1, "audit row written")
	_expect(bool(trust_state["audit"][0]["external"]) == false, "external flag stays false")
	var packed: Variant = JSON.parse_string(JSON.stringify(state))
	_expect(typeof(packed) == TYPE_DICTIONARY, "save json")
	var restored: Dictionary = WorldState.ensure(packed, catalogs)
	_expect(String(restored["species"]["sunburst"]["state"]) == String(state["species"]["sunburst"]["state"]), "roundtrip state")
	print("SMOKE OK")
	quit(0)


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("ok  ", label)
		return
	print("FAIL ", label)
	quit(1)

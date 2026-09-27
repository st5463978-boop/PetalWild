extends SceneTree

func _init() -> void:
	_catalogs()
	_genetics()
	_ecology()
	_soil()
	_save()
	_decide()
	_campaign()
	_legacy()
	print("PETAL_CONTRACTS_OK")
	quit(0)

func _catalogs() -> void:
	var plants: Array = _array("res://data/plants.json")
	var species: Array = _array("res://data/species.json")
	var people: Array = _array("res://data/people.json")
	var items: Array = _array("res://data/items.json")
	var ids := PackedStringArray()
	for row in plants:
		var plant: Dictionary = row
		_expect(plant.has("id") and plant.has("name") and plant.has("seed") and plant.has("sell_price"), "plant contract " + str(plant.get("id", "?")))
		ids.append(str(plant.get("id", "")))
	_expect(ids.has("meadowbell") and ids.has("peach") and not ids.has("sunpetal"), "live plants, not sunpetal")
	var spec_ids := PackedStringArray()
	for row in species:
		var spec: Dictionary = row
		_expect(spec.has("id") and spec.has("name") and spec.has("requirements"), "species contract " + str(spec.get("id", "?")))
		spec_ids.append(str(spec.get("id", "")))
	_expect(spec_ids.has("bellhelp") and spec_ids.has("bulrush") and not spec_ids.has("sunburst"), "live species, not sunburst")
	var who := PackedStringArray()
	for row in people:
		who.append(str(row.get("id", "")))
	_expect(who.has("lumen") and who.has("bram") and who.has("nessa") and not who.has("cara"), "live people, not Cara")
	var produce := ["meadowbell", "peach", "reed", "bramble", "mosspear", "nightlantern"]
	for id in produce:
		_expect(ids.has(str(id)), "shop produce " + str(id))
	var seed_ok := false
	for row in items:
		if str(row.get("id", "")) == "meadowbell_seed":
			seed_ok = str(row.get("plant", "")) == "meadowbell"
	_expect(seed_ok, "meadowbell seed points at meadowbell")
	var venues: Dictionary = _object("res://data/venues.json")
	_expect(venues.has("petal_stall") and venues.has("grove_park"), "venues include stall and park")
	_expect(not bool(venues.get("grove_park", {}).get("active", true)), "Grove Park stays unbuilt")
	var district: Dictionary = _object("res://data/district.json")
	_expect(str(district.get("id", "")) == "hedge_hollow", "live district is Hedge Hollow")
	var road: Dictionary = _object("res://data/road_pieces.json")
	_expect(road.has("pieces") and (road.get("pieces") as Array).size() > 0, "road pieces data")
	var vale: Dictionary = _object("res://data/regions.json")
	_expect(str(vale.get("home", "")) == "hollow", "vale home is Hedge Hollow")
	var settlements: Array = vale.get("settlements", [])
	_expect(settlements.size() == 5, "five vale parishes")
	var vale_ids := PackedStringArray()
	for row in settlements:
		vale_ids.append(str(row.get("id", "")))
	_expect(vale_ids.has("hollow") and vale_ids.has("reedbank") and vale_ids.has("mossford") and vale_ids.has("lea") and vale_ids.has("thatch"), "vale names")

func _genetics() -> void:
	var child: Dictionary = PlantGenetics.mix({"hue": 0.2, "stature": 0.7, "crop_yield": 0.6}, {"hue": 0.8, "stature": 1.4, "crop_yield": 1.5}, 8)
	_expect(float(child["hue"]) > 0.2 and float(child["hue"]) < 0.8, "mixed hue")
	_expect(PlantGenetics.price(10, 1.5) == 15, "yield price")

func _ecology() -> void:
	var rules := EcologyRules.new()
	var species: Array = _array("res://data/species.json")
	var bell := {}
	for entry in species:
		if str(entry.get("id", "")) == "bellhelp":
			bell = entry
	var world := {
		"mature": {"meadowbell": 3},
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
	_expect(rules.all_met(bell, world), "bellhelp ready at 3 bells")
	world["mature"]["meadowbell"] = 2
	_expect(not rules.all_met(bell, world), "bellhelp waits")
	_expect(rules.rank_of("resident") > rules.rank_of("visitor"), "ranks")

func _soil() -> void:
	var cell := SoilCell.new()
	cell.ix = 1
	cell.iz = 2
	cell.tilled = true
	cell.plant_id = "meadowbell"
	cell.hue = 0.33
	cell.stature = 1.1
	cell.crop_yield = 1.2
	var packed: Dictionary = cell.to_dict()
	var other := SoilCell.new()
	other.apply_dict(packed)
	_expect(other.plant_id == "meadowbell" and absf(other.hue - 0.33) < 0.001 and absf(other.stature - 1.1) < 0.001, "cell traits roundtrip")

func _save() -> void:
	var saver = load("res://scripts/autoload/save_game.gd").new()
	_expect(int(saver.VERSION) == 1, "save version 1")
	var payload := {"name": "Hedge Hollow", "clock": {"day": 2}, "economy": {"coins": 41}}
	_expect(saver.write_slot(8, payload), "write slot 8")
	var loaded: Dictionary = saver.read_slot(8)
	_expect(int(loaded.get("economy", {}).get("coins", 0)) == 41, "reload coins")

func _decide() -> void:
	var decide = load("res://scripts/autoload/petal_decide.gd").new()
	var body: Dictionary = decide.body_for("Settle?", ["settle", "keep visiting"], "visitor")
	_expect(body.has("question") and body.has("context") and body.has("options"), "decide schema keys")
	_expect((body["options"] as Array).size() == 2, "decide options")
	decide.forced = ""
	var pick: String = decide.choose("x", ["wait", "buy"], "stall")
	_expect(pick == "wait", "offline first option")
	_expect(decide.last_tier == "offline", "offline tier")
	decide.forced = "buy"
	_expect(decide.choose("x", ["wait", "buy"]) == "buy", "forced buy")
	decide.forced = ""

func _campaign() -> void:
	_expect(CampaignBoard.needed() == 7, "seven lanes")
	_expect(CampaignBoard.landed() == 7, "all seven lanes landed")
	_expect(not CampaignBoard.complete(), "integration not marked complete until playable")
	_expect(CampaignBoard.debug_line().find("landed") >= 0, "debug names landed lanes")
	_expect(CampaignBoard.waiting_ids().is_empty(), "no waiting lanes")
	var lanes: Dictionary = CampaignBoard.lanes()
	_expect(str(lanes.get("tag", "")) == "petal-campaign-baseline-20260927", "baseline tag")

func _legacy() -> void:
	var text := FileAccess.get_file_as_string("res://scripts/autoload/petal_content.gd")
	_expect(text.find("res://data/plants.json") >= 0, "legacy content still points at live path")
	var plants = JSON.parse_string(FileAccess.get_file_as_string("res://data/plants.json"))
	_expect(typeof(plants) == TYPE_ARRAY, "live plants are an array; Kenney loader wants a dict")

func _array(path: String) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(typeof(parsed) == TYPE_ARRAY, path)
	return parsed

func _object(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(typeof(parsed) == TYPE_DICTIONARY, path)
	return parsed

func _expect(ok: bool, label: String) -> void:
	if ok:
		print("ok  ", label)
		return
	print("FAIL ", label)
	quit(1)

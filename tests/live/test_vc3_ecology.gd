extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")


func _db() -> Node:
	return root.get_node("ContentDB")


func _order() -> Array:
	return _db().get("species_order")


func _catalog() -> Dictionary:
	return _db().get("species")


func _spec(id: String) -> Dictionary:
	return _db().call("species_def", id)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t: PetalAssert = PA.new("vc3_ecology")
	_data(t)
	_gates(t)
	_food(t)
	_blight(t)
	_save(t)
	_tick_wiring(t)
	t.done()


func _data(t: PetalAssert) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ecology.json"))
	t.expect(typeof(parsed) == TYPE_DICTIONARY, "ecology.json is an object")
	if typeof(parsed) == TYPE_DICTIONARY:
		var root: Dictionary = parsed
		var food: Dictionary = root.get("food_web", {})
		var blight: Dictionary = root.get("blight", {})
		t.expect(int(food.get("floor", 0)) == 1, "the food web keeps a population floor")
		t.expect(int(food.get("surplus_min", 0)) == 2, "predation waits for a prey surplus")
		t.expect(str(blight.get("id", "")) == "blight_moth", "blight tuning names the moth")
		t.expect((blight.get("counter_services", []) as Array).has("lantern"), "a lantern counters blight-moths")
		t.expect((blight.get("counter_helpers", []) as Array).has("bram"), "a helper counters blight-moths")
	var saw_service := false
	for id in _order():
		var spec: Dictionary = _spec(id)
		t.expect(spec.has("visit_req") and spec.has("resident_req") and spec.has("romance_req"), "%s has visit, resident, and romance gates" % id)
		for req_v in spec.get("resident_req", []):
			if typeof(req_v) != TYPE_DICTIONARY:
				continue
			var req: Dictionary = req_v
			if str(req.get("type", "")) == "service":
				saw_service = true
	t.expect(saw_service, "a resident gate uses the service requirement")
	var horn: Dictionary = _spec("gushorn")
	var diet: Array = horn.get("diet", [])
	t.expect(diet.size() == 1, "gushorn keeps a diet")
	if diet.size() == 1 and typeof(diet[0]) == TYPE_DICTIONARY:
		var bite: Dictionary = diet[0]
		t.expect(str(bite.get("species", "")) == "grapling", "gushorn eats grapling")
		t.expect(int(bite.get("rate", 0)) == 1, "the diet rate lives on the species")


func _gates(t: PetalAssert) -> void:
	var rules := EcologyRules.new()
	var custom := {
		"name": "Custom",
		"visit_req": [{"type": "service", "channel": "pollination", "min": 0.4, "label": "Pollination"}],
		"resident_req": [{"type": "service", "channel": "light", "min": 0.5, "label": "Lantern light"}],
		"romance_req": [{"type": "resident_count", "species": "custom", "min": 2, "label": "A pair"}],
	}
	var field := ServiceField.new()
	field.setup(10, 8)
	var world := {"service_field": field, "resident_count": {}}
	t.expect(rules.highest_tier(custom, world) == "closed", "a dark garden keeps the custom gate closed")
	field.stamp("hive", Vector2i(4, 3), 4.0, 1.0)
	t.expect(rules.highest_tier(custom, world) == "visit", "pollination opens the visit gate")
	t.expect(rules.gate_met(custom, world, "visit"), "the service requirement is met for visit")
	t.expect(not rules.gate_met(custom, world, "resident"), "light is still below the resident gate")
	field.stamp("lantern", Vector2i(4, 3), 3.0, 1.0)
	t.expect(rules.highest_tier(custom, world) == "resident", "lantern light opens the resident gate")
	world["resident_count"] = {"custom": 2}
	t.expect(rules.highest_tier(custom, world) == "romance", "a pair opens the romance gate")

	var live := ServiceField.new()
	live.setup(10, 8)
	var causal := CausalLog.new()
	var gates := SpeciesGates.new()
	gates.log = causal
	gates.boot(_order())
	var bell: Dictionary = _spec("bellhelp")
	gates.refresh(_order(), _catalog(), _bell_world(live, 0, 0))
	t.expect(str(gates.tiers.get("bellhelp", "")) == "closed", "bellhelp starts closed")
	t.expect(gates.notes.is_empty(), "a closed gate does not journal")
	var visit: Array = gates.refresh(_order(), _catalog(), _bell_world(live, 3, 0))
	t.expect(str(gates.tiers.get("bellhelp", "")) == "visit", "three meadowbells open the visit gate")
	t.expect(visit.size() == 1 and str(visit[0]).find("closed to visit") != -1, "the visit note names both tiers")
	live.stamp("well", Vector2i(4, 3), 3.0, 1.0)
	var still: Array = gates.refresh(_order(), _catalog(), _bell_world(live, 3, 0))
	t.expect(still.is_empty() and str(gates.tiers.get("bellhelp", "")) == "visit", "a well does not satisfy pollination")
	live.stamp("hive", Vector2i(4, 3), 4.0, 1.0)
	var settled: Array = gates.refresh(_order(), _catalog(), _bell_world(live, 3, 0))
	t.expect(str(gates.tiers.get("bellhelp", "")) == "resident", "hive pollination opens the resident gate")
	t.expect(settled.size() == 1 and str(settled[0]).find("Pollination across the beds") != -1, "the resident note names the service")
	t.expect(rules.gate_met(bell, _bell_world(live, 3, 0), "resident"), "bellhelp resident requirements are met")
	var paired: Array = gates.refresh(_order(), _catalog(), _bell_world(live, 3, 2))
	t.expect(str(gates.tiers.get("bellhelp", "")) == "romance", "two residents open the romance gate")
	t.expect(paired.size() == 1 and str(paired[0]).find("to romance") != -1, "the romance note names the tier")
	live.clear_service("hive")
	var dropped: Array = gates.refresh(_order(), _catalog(), _bell_world(live, 3, 2))
	t.expect(str(gates.tiers.get("bellhelp", "")) == "visit", "losing pollination drops romance back to visit")
	t.expect(dropped.size() == 1 and str(dropped[0]).find("unmet Pollination across the beds") != -1, "the drop names the unmet service")
	var shut: Array = gates.refresh(_order(), _catalog(), _bell_world(live, 0, 2))
	t.expect(str(gates.tiers.get("bellhelp", "")) == "closed", "losing the meadowbells closes the gate")
	t.expect(shut.size() == 1 and str(shut[0]).find("to closed") != -1, "the close note names the tier")
	t.expect(causal.all_entries().size() == 5, "each gate change is logged")
	var entry: Dictionary = causal.all_entries()[0]
	t.expect(str(entry.get("kind", "")) == "gate_changed", "the log kind is gate_changed")
	t.expect(str(entry.get("target", "")) == "bellhelp", "the log target is the species")
	t.expect(str(entry.get("cause", "")).find("moved from closed to visit") != -1, "the log stores the visit reason")


func _food(t: PetalAssert) -> void:
	var first := _run_web(4242)
	var second := _run_web(4242)
	var other := _run_web(99)
	t.expect(first["rows"] == second["rows"], "the same seed over 72 hours matches")
	t.expect(first["digest"] == second["digest"], "the same seed writes the same food-web log")
	t.expect(first["rows"] != other["rows"], "a different seed changes the 72 hour run")
	t.expect(bool(first["floor_ok"]), "grapling stays at or above the surplus floor")
	t.expect(bool(other["floor_ok"]), "the other seed also respects the surplus floor")
	t.expect(int(first["pred_spread"]) > 1, "the predator count changes across 72 hours")
	t.expect(str(first["digest"]).find("food_web") != -1, "the log records predation")
	t.expect(str(first["digest"]).find("ate") != -1, "the reason says who ate whom")

	var pinned := FoodWeb.new()
	pinned.reseed(4242)
	pinned.counts["grapling"] = 8
	pinned.counts["gushorn"] = 3
	pinned.hour(_catalog())
	t.expect(int(pinned.counts.get("grapling", 0)) == 7, "the first hour eats one grapling")
	t.expect(int(pinned.counts.get("gushorn", 0)) == 3, "the predator does not grow on the first hour")

	var held := FoodWeb.new()
	held.reseed(4242)
	held.counts["grapling"] = 3
	held.counts["gushorn"] = 4
	held.hour(_catalog())
	t.expect(int(held.counts.get("grapling", 0)) == 3, "prey at the surplus floor is not eaten")
	var spare := FoodWeb.new()
	spare.reseed(4242)
	spare.counts["grapling"] = 4
	spare.counts["gushorn"] = 2
	spare.hour(_catalog())
	t.expect(int(spare.counts.get("grapling", 0)) == 3, "only the surplus above the floor is eaten")

	var snap: Dictionary = pinned.to_state()
	var copy := FoodWeb.new()
	copy.apply_state(snap)
	pinned.hour(_catalog())
	copy.hour(_catalog())
	t.expect(int(copy.counts.get("grapling", 0)) == int(pinned.counts.get("grapling", 0)), "food-web counts survive a save round-trip")
	t.expect(int(copy.counts.get("gushorn", 0)) == int(pinned.counts.get("gushorn", 0)), "predator counts survive a save round-trip")
	t.expect(copy.hour_index == pinned.hour_index, "the food-web hour survives a save round-trip")


func _blight(t: PetalAssert) -> void:
	var soil := _neglected_soil()
	var blight := _new_blight(soil)
	var causal := CausalLog.new()
	blight.log = causal
	for _i in 3:
		blight.hour(_pest_world(0.1), PackedStringArray())
	t.expect(blight.moths.is_empty(), "moths wait for the spawn interval")
	var settled: String = blight.hour(_pest_world(0.1), PackedStringArray())
	t.expect(blight.moths.size() == 1, "a blight-moth settles on the fourth neglected hour")
	t.expect(settled.find("bed 0,0") != -1, "the moth takes the lowest neglected bed")
	t.expect(is_equal_approx(_growth(soil), 0.8), "the arrival hour does not also chew")
	blight.hour(_pest_world(0.1), PackedStringArray())
	t.expect(_growth(soil) < 0.8, "the next hour chews the bed")
	t.expect(_wilt(soil) > 2.0, "the moth also wilts the bed")
	var spawned := false
	for item_v in causal.all_entries():
		var item: Dictionary = item_v
		if str(item.get("kind", "")) == "blight_spawned":
			spawned = true
	t.expect(spawned, "the causal log records the moth")

	var quiet := _new_blight(_neglected_soil())
	for _i in 6:
		quiet.hour(_pest_world(0.8), PackedStringArray())
	t.expect(quiet.moths.is_empty(), "a cared-for garden does not draw moths")

	var lantern := _new_blight(soil)
	lantern.moths = blight.moths.duplicate(true)
	var field := ServiceField.new()
	field.setup(10, 8)
	field.stamp("lantern", Vector2i(0, 0), 3.0, 1.0)
	lantern.services = field
	var cleared: String = lantern.hour(_pest_world(0.1), PackedStringArray())
	t.expect(lantern.moths.is_empty(), "lantern light sends the moths off")
	t.expect(cleared.find("lantern") != -1, "the clear reason names the lantern")
	lantern.hour(_pest_world(0.1), PackedStringArray())
	t.expect(lantern.moths.is_empty(), "lantern light keeps a new moth from settling")

	var well := _new_blight(_neglected_soil())
	var well_field := ServiceField.new()
	well_field.setup(10, 8)
	well_field.stamp("well", Vector2i(0, 0), 3.0, 1.0)
	well.services = well_field
	for _i in 4:
		well.hour(_pest_world(0.1), PackedStringArray())
	t.expect(well.moths.size() == 1, "a well does not counter blight-moths")

	var helped := _new_blight(_neglected_soil())
	for _i in 4:
		helped.hour(_pest_world(0.1), PackedStringArray())
	var helper_why: String = helped.hour(_pest_world(0.1), PackedStringArray(["bram"]))
	t.expect(helped.moths.is_empty(), "a helper sends the moths off")
	t.expect(helper_why.find("helper") != -1, "the clear reason names the helper")

	var fenced := _new_blight(_neglected_soil())
	for _i in 4:
		fenced.hour(_pest_world(0.1), PackedStringArray())
	var fence_world := _pest_world(0.1)
	fence_world["structures"] = {"fence": 1}
	var fence_why: String = fenced.hour(fence_world, PackedStringArray())
	t.expect(fenced.moths.is_empty() and fence_why.find("fence") != -1, "a fence sends the moths off")

	var planted := _new_blight(_neglected_soil())
	for _i in 4:
		planted.hour(_pest_world(0.1), PackedStringArray())
	var plant_world := _pest_world(0.1)
	plant_world["mature"] = {"nightlantern": 1}
	var plant_why: String = planted.hour(plant_world, PackedStringArray())
	t.expect(planted.moths.is_empty() and plant_why.find("warding plant") != -1, "a mature nightlantern sends the moths off")

	var guarded := _new_blight(_neglected_soil())
	guarded.rules = EcologyRules.new()
	for _i in 4:
		guarded.hour(_pest_world(0.1), PackedStringArray())
	var guard_world := _pest_world(0.1)
	guard_world["species_state"] = {"cirlark": "resident"}
	var guard_why: String = guarded.hour(guard_world, PackedStringArray())
	t.expect(guarded.moths.is_empty() and guard_why.find("guardian") != -1, "a resident guardian sends the moths off")


func _save(t: PetalAssert) -> void:
	var eco = _eco()
	eco.gates.tiers["bellhelp"] = "resident"
	eco.notes.append("Bellhelp moved from visit to resident because met Pollination across the beds.")
	eco.food.counts["grapling"] = 6
	eco.food.hour_index = 4
	eco.food.seed = 11
	eco.blight.moths.append({"id": 2, "ix": 1, "iz": 4})
	eco.blight.spawn_bank = 2
	eco.hour_bank = 0.4
	var saved: Dictionary = eco.to_state()
	var again = _eco()
	again.apply_state(saved)
	t.expect(str(again.gates.tiers.get("bellhelp", "")) == "resident", "gate tiers survive a save round-trip")
	t.expect(again.notes.size() == 1 and str(again.notes[0]).find("resident") != -1, "gate notes survive a save round-trip")
	t.expect(int(again.food.counts.get("grapling", 0)) == 6, "food-web counts survive the ecology save")
	t.expect(again.food.hour_index == 4 and again.food.seed == 11, "food-web hour and seed survive the ecology save")
	t.expect(again.blight.moths.size() == 1, "blight-moths survive the ecology save")
	var moth: Dictionary = again.blight.moths[0]
	t.expect(int(moth.get("ix", -1)) == 1 and int(moth.get("iz", -1)) == 4, "the moth bed survives the ecology save")
	t.expect(again.blight.spawn_bank == 2, "the blight spawn bank survives the ecology save")
	t.expect(is_equal_approx(again.hour_bank, 0.4), "the partial sim hour survives the ecology save")

	var save := root.get_node("SaveGame")
	var recorded := FileAccess.get_file_as_string("res://tests/fixtures/save_v1_day3.json")
	var from_v1: Dictionary = save.call("migrate_text", recorded)
	var eco_v1: Dictionary = from_v1.get("ecology", {})
	t.expect((eco_v1.get("actors", []) as Array).size() == 1, "v1 migration keeps the ecology actors")
	t.expect(typeof(eco_v1.get("gates", null)) == TYPE_DICTIONARY and (eco_v1.get("gates", {}) as Dictionary).is_empty(), "v1 migration defaults gates to empty")
	t.expect(typeof(eco_v1.get("gate_notes", null)) == TYPE_ARRAY and (eco_v1.get("gate_notes", []) as Array).is_empty(), "v1 migration defaults gate notes to empty")
	var food_v1: Dictionary = eco_v1.get("food_web", {})
	t.expect(typeof(food_v1.get("counts", null)) == TYPE_DICTIONARY and (food_v1.get("counts", {}) as Dictionary).is_empty(), "v1 migration defaults food-web counts")
	var pests_v1: Dictionary = eco_v1.get("blight", {})
	t.expect(typeof(pests_v1.get("moths", null)) == TYPE_ARRAY and (pests_v1.get("moths", []) as Array).is_empty(), "v1 migration defaults blight-moths to empty")

	var bare: Dictionary = save.call("migrate_parsed", {"version": 3, "state": {"name": "Bare", "sim": {"schema": 1}}})
	var bare_eco: Dictionary = bare.get("ecology", {})
	t.expect(typeof(bare_eco.get("gates", null)) == TYPE_DICTIONARY, "a v3 save without ecology gets empty gates")
	t.expect(typeof(bare_eco.get("food_web", {}).get("counts", null)) == TYPE_DICTIONARY, "a v3 save without ecology gets empty food-web counts")
	var odd: Dictionary = save.call("migrate_parsed", {
		"version": 3,
		"state": {
			"ecology": {"actors": [{"species": "bellhelp"}], "gates": "nope", "gate_notes": {"nope": true}, "food_web": [], "blight": {"moths": "no"}},
			"sim": {"schema": 1},
		},
	})
	var odd_eco: Dictionary = odd.get("ecology", {})
	t.expect((odd_eco.get("actors", []) as Array).size() == 1, "repairing gates keeps the actors")
	t.expect(typeof(odd_eco.get("gates", null)) == TYPE_DICTIONARY and (odd_eco.get("gates", {}) as Dictionary).is_empty(), "a bad gates value migrates to empty")
	t.expect(typeof(odd_eco.get("gate_notes", null)) == TYPE_ARRAY, "a bad gate-notes value migrates to a list")
	t.expect(typeof(odd_eco.get("food_web", {}).get("counts", null)) == TYPE_DICTIONARY, "a bad food-web value migrates to empty counts")
	t.expect(typeof(odd_eco.get("blight", {}).get("moths", null)) == TYPE_ARRAY and (odd_eco.get("blight", {}).get("moths", []) as Array).is_empty(), "a bad moth list migrates to empty")

	var slot := 97
	var path := str(save.call("path_for", slot))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var wrote: Variant = save.call("write_slot", slot, {"name": "Gates", "ecology": saved, "sim": {"schema": 1}})
	t.expect(bool(wrote), "a v3 ecology slot writes")
	var raw := FileAccess.get_file_as_string(path)
	var payload: Variant = JSON.parse_string(raw)
	t.expect(typeof(payload) == TYPE_DICTIONARY and int((payload as Dictionary).get("version", 0)) == 3, "ecology saves stay on version 3")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _tick_wiring(t: PetalAssert) -> void:
	var eco = _eco()
	var hits := [0]
	eco.event_happened.connect(func(_text: String) -> void:
		hits[0] += 1
	)
	eco.tick(0.2, {"sim_hours": 0.0, "mature": {}, "resident_count": {}, "species_state": {}, "structures": {}})
	t.expect(hits[0] == 0, "a closed hour does not announce a visitor")
	t.expect(eco.notes.is_empty(), "closed gates do not journal")
	var live := ServiceField.new()
	live.setup(10, 8)
	live.stamp("hive", Vector2i(4, 3), 4.0, 1.0)
	eco.services = live
	eco._refresh_gates(_bell_world(live, 3, 2))
	t.expect(str(eco.gates.tiers.get("bellhelp", "")) == "romance", "ecology refresh applies the three gates")
	t.expect(eco.notes.size() == 1 and str(eco.notes[0]).find("romance") != -1, "the tier change is a journal note")
	t.expect(hits[0] == 0, "a tier change does not toast over the ecology signal")
	var row: Dictionary = eco.gate_journal_row()
	t.expect(str(row.get("name", "")) == "Species gates", "the journal has a species-gates row")
	t.expect(str(row.get("blurb", "")).find("romance") != -1, "the journal blurb names the tier")
	_neglect(eco.soil)
	var before := _growth(eco.soil)
	eco.tick(0.2, {"sim_hours": 4.0, "garden_quality": 0.1, "mature": {}, "resident_count": {}, "species_state": {}, "structures": {}})
	t.expect(eco.blight.moths.size() == 1, "ecology advances blight across sim hours")
	t.expect(is_equal_approx(_growth(eco.soil), before), "the moth waits a sim hour before chewing")
	eco.tick(0.2, {"sim_hours": 1.0, "garden_quality": 0.1, "mature": {}, "resident_count": {}, "species_state": {}, "structures": {}})
	t.expect(_growth(eco.soil) < before, "the following sim hour chews the neglected bed")
	var saw_moth := false
	for line in eco.notes:
		if line.find("blight-moth") != -1:
			saw_moth = true
	t.expect(saw_moth, "the journal notes the blight-moth")


func _bell_world(field: ServiceField, bells: int, residents: int) -> Dictionary:
	return {
		"mature": {"meadowbell": bells},
		"service_field": field,
		"resident_count": {"bellhelp": residents},
		"species_state": {},
		"moisture": 0.2,
		"fertility": 0.2,
		"pond_cells": 0,
		"chem": {},
		"weather": "clear",
		"hour": 12.0,
		"garden_quality": 0.2,
		"structures": {},
	}


func _run_web(seed_value: int) -> Dictionary:
	var web := FoodWeb.new()
	web.reseed(seed_value)
	web.log = CausalLog.new()
	web.counts["grapling"] = 8
	web.counts["gushorn"] = 3
	var rows: Array = []
	var floor_ok := true
	var seen := {}
	for _i in 72:
		web.hour(_catalog())
		var prey := int(web.counts.get("grapling", 0))
		var pred := int(web.counts.get("gushorn", 0))
		if prey < 3:
			floor_ok = false
		seen[pred] = true
		rows.append("%d,%d" % [prey, pred])
	return {
		"rows": rows,
		"floor_ok": floor_ok,
		"digest": web.log.digest(),
		"pred_spread": seen.size(),
	}


func _new_soil() -> Object:
	var script: Script = load("res://scripts/garden/soil_field.gd")
	return script.new()


func _cell(soil: Object, ix: int) -> Object:
	return soil.call("get_cell", ix, 0)


func _growth(soil: Object) -> float:
	return float(_cell(soil, 0).get("growth"))


func _wilt(soil: Object) -> float:
	return float(_cell(soil, 0).get("wilt"))


func _neglected_soil() -> Object:
	var soil := _new_soil()
	_neglect(soil)
	return soil


func _neglect(soil: Object) -> void:
	for ix in 3:
		var plot := _cell(soil, ix)
		plot.set("plant_id", "meadowbell")
		plot.set("growth", 0.8)
		plot.set("wilt", 2.0)
		plot.set("moisture", 0.1)
		plot.set("tilled", true)


func _pest_world(quality: float) -> Dictionary:
	return {
		"garden_quality": quality,
		"mature": {},
		"species_state": {},
		"structures": {},
	}


func _new_blight(soil: Object) -> Object:
	var script: Script = load("res://scripts/ecology/blight.gd")
	var blight: Object = script.new()
	blight.soil = soil
	blight.rules = EcologyRules.new()
	return blight


func _eco() -> Object:
	var script: Script = load("res://scripts/ecology/ecology.gd")
	var eco: Object = script.new()
	var folder := Node3D.new()
	root.add_child(folder)
	root.add_child(eco)
	eco.call("boot", folder)
	var field := ServiceField.new()
	field.setup(10, 8)
	eco.call("bind_parish", CausalLog.new(), field, _new_soil(), {})
	return eco

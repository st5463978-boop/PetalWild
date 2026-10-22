extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")


func _initialize() -> void:
	var t: PetalAssert = PA.new("service_field")
	_catalog(t)
	_falloff(t)
	_overlap_and_clear(t)
	_quality(t)
	_requirement(t)
	_upkeep(t)
	_save_roundtrip(t)
	t.done()


func _catalog(t: PetalAssert) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/services.json"))
	t.expect(typeof(parsed) == TYPE_DICTIONARY, "services.json is an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	var by_id := {}
	for item in root.get("services", []):
		if typeof(item) == TYPE_DICTIONARY:
			by_id[str(item.get("id", ""))] = item
	t.expect(int(by_id["well"].get("radius", 0)) == 3, "well covers moisture at radius 3")
	t.expect(str(by_id["well"].get("channel", "")) == "moisture", "well paints moisture")
	t.expect(int(by_id["compost"].get("radius", 0)) == 2, "compost covers fertility at radius 2")
	t.expect(str(by_id["compost"].get("channel", "")) == "fertility", "compost paints fertility")
	t.expect(int(by_id["hive"].get("radius", 0)) == 4, "hive covers pollination at radius 4")
	t.expect(str(by_id["hive"].get("channel", "")) == "pollination", "hive paints pollination")
	t.expect(int(by_id["lantern"].get("radius", 0)) == 3, "lantern covers light at radius 3")
	t.expect(str(by_id["lantern"].get("channel", "")) == "light", "lantern paints light")
	t.expect(int(by_id["well"].get("upkeep", 0)) > 0, "well has a daily upkeep")
	t.expect(int(by_id["compost"].get("upkeep", 0)) > 0, "compost has a daily upkeep")
	t.expect(int(by_id["hive"].get("upkeep", 0)) > 0, "hive has a daily upkeep")
	t.expect(int(by_id["lantern"].get("upkeep", 0)) > 0, "lantern has a daily upkeep")


func _falloff(t: PetalAssert) -> void:
	var field := ServiceField.new()
	field.setup(10, 8)
	field.stamp("well", Vector2i(4, 3), 3.0, 1.0)
	var center := Vector2i(4, 3)
	t.expect(is_equal_approx(field.sample(center, "moisture"), 1.0), "stamp center is full strength")
	t.expect(is_equal_approx(field.sample(Vector2i(5, 3), "moisture"), 2.0 / 3.0), "one bed out is 2/3")
	t.expect(is_equal_approx(field.sample(Vector2i(6, 3), "moisture"), 1.0 / 3.0), "two beds out is 1/3")
	t.expect(is_equal_approx(field.sample(Vector2i(7, 3), "moisture"), 0.0), "the radius rim contributes 0")
	t.expect(is_equal_approx(field.sample(Vector2i(8, 3), "moisture"), 0.0), "past the radius is 0")
	var diagonal := field.sample(Vector2i(5, 4), "moisture")
	t.expect(diagonal < field.sample(Vector2i(5, 3), "moisture"), "diagonal distance falls off faster than a neighbor")
	t.expect(diagonal > 0.0, "a diagonal inside the radius still has moisture")
	t.expect(is_equal_approx(field.sample(Vector2i(-1, 0), "moisture"), 0.0), "cells outside the bed grid are 0")
	t.expect(is_equal_approx(field.sample(Vector2i(4, 3), "fertility"), 0.0), "a well does not paint fertility")


func _overlap_and_clear(t: PetalAssert) -> void:
	var field := ServiceField.new()
	field.setup(10, 8)
	field.stamp("well", Vector2i(4, 3), 3.0, 0.4)
	field.stamp("well#2", Vector2i(4, 3), 3.0, 0.4)
	t.expect(is_equal_approx(field.sample(Vector2i(4, 3), "moisture"), 0.8), "same-channel stamps add")
	field.stamp("well", Vector2i(4, 3), 3.0, 0.8)
	field.stamp("well#2", Vector2i(4, 3), 3.0, 0.8)
	t.expect(is_equal_approx(field.sample(Vector2i(4, 3), "moisture"), 1.0), "a channel clamps at 1")
	field.clear_service("well#2")
	t.expect(is_equal_approx(field.sample(Vector2i(4, 3), "moisture"), 0.8), "clear_service drops that stamp only")
	field.stamp("well", Vector2i(0, 0), 3.0, 0.8)
	t.expect(is_equal_approx(field.sample(Vector2i(4, 3), "moisture"), 0.0), "stamping the same id moves it")
	t.expect(is_equal_approx(field.sample(Vector2i(0, 0), "moisture"), 0.8), "the moved well paints its new cell")


func _quality(t: PetalAssert) -> void:
	var field := ServiceField.new()
	field.setup(10, 8)
	field.stamp("well", Vector2i(4, 3), 3.0, 1.0)
	t.expect(is_equal_approx(field.quality_at(Vector2i(4, 3)), 0.3), "quality uses the moisture weight")
	t.expect(is_equal_approx(field.sample(Vector2i(4, 3), "quality"), 0.3), "sample of quality matches quality_at")
	t.expect(is_equal_approx(field.quality_at(Vector2i(5, 3)), 0.2), "quality follows the moisture falloff")
	field.stamp("compost", Vector2i(4, 3), 2.0, 1.0)
	t.expect(is_equal_approx(field.quality_at(Vector2i(4, 3)), 0.55), "quality adds the fertility weight")
	t.expect(field.quality_mean() > 0.0, "a stamped garden has a quality mean")
	t.expect(field.quality_mean() < field.quality_at(Vector2i(4, 3)), "the mean is below the best cell")


func _requirement(t: PetalAssert) -> void:
	var rules := EcologyRules.new()
	var field := ServiceField.new()
	field.setup(10, 8)
	var world := {"service_field": field, "moisture": 0.2, "garden_quality": 0.5}
	var pollination := {"type": "service", "channel": "pollination", "min": 0.4}
	t.expect(not rules.requirement_met(pollination, {}), "service requirements fail closed without a field")
	t.expect(not rules.requirement_met(pollination, world), "pollination 0.4 fails with no hive")
	field.stamp("hive", Vector2i(3, 3), 4.0, 1.0)
	t.expect(rules.requirement_met(pollination, world), "hive coverage meets pollination 0.4")
	var far := {"type": "service", "channel": "pollination", "min": 0.4, "x": 9, "z": 0}
	t.expect(not rules.requirement_met(far, world), "a far bed stays under the pollination minimum")
	t.expect(rules.requirement_met({"type": "moisture", "min": 0.1}, world), "moisture requirements still pass")
	t.expect(not rules.requirement_met({"type": "moisture", "min": 0.9}, world), "moisture requirements still fail")
	t.expect(rules.requirement_met({"type": "garden_quality", "min": 0.4}, world), "garden quality requirements still pass")
	t.expect(not rules.requirement_met({"type": "nope"}, world), "unknown requirements still fail")
	t.expect(rules.requirement_met({"type": "mature_plant", "plant": "reed", "min": 1}, {"mature": {"reed": 2}}), "mature plant requirements still pass")


func _upkeep(t: PetalAssert) -> void:
	var economy := root.get_node("Economy")
	var before := int(economy.get("coins"))
	economy.set("coins", 36)
	var field := ServiceField.new()
	field.setup(10, 8)
	t.expect(field.charge_daily(1) == 0, "an empty field charges nothing")
	t.expect(int(economy.get("coins")) == 36, "empty upkeep leaves the purse")
	field.stamp("well", Vector2i(1, 1), 3.0, 1.0)
	field.stamp("hive", Vector2i(2, 2), 4.0, 1.0)
	t.expect(field.upkeep_total() == 5, "well plus hive upkeep is 5")
	t.expect(field.charge_daily(1) == 0, "the day already observed is not charged again")
	field.charged_day = 0
	t.expect(field.charge_daily(1) == 5, "day 1 collects service upkeep")
	t.expect(int(economy.get("coins")) == 31, "upkeep leaves the purse")
	t.expect(field.charge_daily(1) == 0, "the same day does not charge twice")
	t.expect(int(economy.get("coins")) == 31, "a second charge the same day is a no-op")
	t.expect(field.charge_daily(2) == 5, "the next day collects upkeep again")
	t.expect(int(economy.get("coins")) == 26, "day 2 upkeep leaves the purse")
	economy.set("coins", 3)
	t.expect(field.charge_daily(3) == 3, "upkeep takes only the coins on hand")
	t.expect(int(economy.get("coins")) == 0, "a short purse ends at zero")
	economy.set("coins", before)


func _save_roundtrip(t: PetalAssert) -> void:
	var save := root.get_node("SaveGame")
	var migrated: Dictionary = save.call("migrate_parsed", {
		"version": 2,
		"state": {"name": "Before city", "economy": {"coins": 15}, "sim": {"schema": 1, "clock": {"seed": 9}}},
	})
	t.expect(typeof(migrated.get("city", null)) == TYPE_DICTIONARY, "v2 migration adds a city block")
	var city: Dictionary = migrated.get("city", {})
	t.expect(typeof(city.get("services", null)) == TYPE_ARRAY and (city.get("services", []) as Array).is_empty(), "migrated services default to empty")
	t.expect(int(migrated.get("economy", {}).get("coins", 0)) == 15, "v2 coins survive the city migration")
	t.expect(int(migrated.get("sim", {}).get("clock", {}).get("seed", 0)) == 9, "v2 sim seed survives the city migration")
	var recorded := FileAccess.get_file_as_string("res://tests/fixtures/save_v1_day3.json")
	var from_v1: Dictionary = save.call("migrate_text", recorded)
	var v1_city: Dictionary = from_v1.get("city", {})
	t.expect(typeof(v1_city.get("services", null)) == TYPE_ARRAY and (v1_city.get("services", []) as Array).is_empty(), "v1 migration defaults city services to empty")

	var field := ServiceField.new()
	field.setup(10, 8)
	field.stamp("well", Vector2i(1, 2), 3.0, 1.0)
	field.stamp("lantern", Vector2i(6, 5), 3.0, 0.8)
	field.charged_day = 4
	var slot := 93
	var path := str(save.call("path_for", slot))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var wrote: Variant = save.call("write_slot", slot, {
		"name": "City",
		"city": field.to_state(),
		"economy": {"coins": 9},
		"clock": {"day": 4},
	})
	t.expect(bool(wrote), "city slot writes")
	var raw := FileAccess.get_file_as_string(path)
	var payload: Variant = JSON.parse_string(raw)
	t.expect(typeof(payload) == TYPE_DICTIONARY and int((payload as Dictionary).get("version", 0)) == 3, "city saves are version 3")
	var loaded: Dictionary = save.call("read_slot", slot)
	var again := ServiceField.new()
	again.setup(10, 8)
	again.apply_state(loaded.get("city", {}))
	t.expect(is_equal_approx(again.sample(Vector2i(1, 2), "moisture"), 1.0), "well survives the save round-trip")
	t.expect(is_equal_approx(again.sample(Vector2i(6, 5), "light"), 0.8), "lantern survives the save round-trip")
	t.expect(is_equal_approx(again.sample(Vector2i(1, 2), "light"), 0.0), "channels stay separate after load")
	t.expect(again.charged_day == 4, "upkeep day survives the save round-trip")
	t.expect(again.to_state() == field.to_state(), "city state matches after the round-trip")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

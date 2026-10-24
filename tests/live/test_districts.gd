extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")

var _anchors: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t: PetalAssert = PA.new("districts")
	_catalog(t)
	_paint(t)
	_policies(t)
	_demand_and_coins(t)
	_food_and_pests(t)
	_land_and_lod(t)
	_overlay(t)
	_save(t)
	t.done()


func _clock() -> Node:
	return root.get_node("Clock")


func _economy() -> Node:
	return root.get_node("Economy")


func _catalog(t: PetalAssert) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/policies.json"))
	t.expect(typeof(parsed) == TYPE_DICTIONARY, "policies.json is an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root_data: Dictionary = parsed
	var by_id := {}
	for item in root_data.get("policies", []):
		if typeof(item) == TYPE_DICTIONARY:
			by_id[str(item.get("id", ""))] = item
	for policy_id in ["organic_only", "night_lanterns", "pollinator_haven", "market_day"]:
		t.expect(by_id.has(policy_id), "policies.json includes %s" % policy_id)
	t.expect(typeof(root_data.get("lod", null)) == TYPE_DICTIONARY, "policies.json carries SimLod strides")
	var organic: Dictionary = by_id.get("organic_only", {})
	var service: Dictionary = organic.get("service", {})
	t.expect(float(service.get("pollination", 0.0)) > 0.0, "organic only raises pollination")
	t.expect(float(service.get("fertility", 0.0)) < 0.0, "organic only lowers fertility")
	var night: Dictionary = by_id.get("night_lanterns", {})
	t.expect(int(night.get("upkeep", 0)) > 0, "night lanterns have upkeep")
	t.expect(typeof(night.get("hours", null)) == TYPE_DICTIONARY, "night lanterns are limited to night hours")
	var market: Dictionary = by_id.get("market_day", {})
	var demand: Dictionary = market.get("demand", {})
	t.expect(float(demand.get("market", 0.0)) > 0.0, "market day raises market demand")
	t.expect(int(market.get("income", 0)) > 0, "market day pays a coin bonus")
	var haven: Dictionary = by_id.get("pollinator_haven", {})
	var food: Dictionary = haven.get("food", {})
	t.expect(float(food.get("grow", 1.0)) > 1.0, "pollinator haven speeds the food web")


func _paint(t: PetalAssert) -> void:
	var districts := _new()
	var causal: CausalLog = districts.log
	var first := districts.begin_next()
	t.expect(first.find("North Beds") != -1, "the first painted group is North Beds")
	t.expect(districts.active_id == "north_beds", "the active id is slug of the name")
	var claimed := districts.toggle_paint(Vector2i(1, 2))
	t.expect(claimed.find("bed 1,2") != -1, "painting names the bed")
	t.expect(districts.owner_of(Vector2i(1, 2)) == "north_beds", "the bed joins the active group")
	districts.toggle_paint(Vector2i(1, 3))
	districts.begin_next()
	var moved := districts.toggle_paint(Vector2i(1, 2))
	t.expect(districts.owner_of(Vector2i(1, 2)) == "willow_corner", "painting a bed moves it to the new group")
	t.expect(districts.owner_of(Vector2i(1, 3)) == "north_beds", "the other bed stays in North Beds")
	t.expect(moved.find("from North Beds") != -1, "the move reason names both groups")
	var released := districts.toggle_paint(Vector2i(1, 2))
	t.expect(districts.owner_of(Vector2i(1, 2)) == "", "painting the same bed again releases it")
	t.expect(released.find("released") != -1, "the release reason says the bed left the group")
	var saw := false
	for entry_v in causal.all_entries():
		var entry: Dictionary = entry_v
		if str(entry.get("kind", "")) == "district_painted" and str(entry.get("cause", "")).find("painted") != -1:
			saw = true
	t.expect(saw, "the causal log records the paint")
	var idle := GardenDistricts.new()
	idle.setup(ServiceField.new(), null)
	t.expect(idle.cycle_policy() == "Paint a bed group before setting a policy.", "a policy needs a painted bed")


func _policies(t: PetalAssert) -> void:
	var clock := _clock()
	clock.call("reset_new")
	clock.set("running", false)
	var field := ServiceField.new()
	field.setup(10, 8)
	var districts := _bound(field)
	var cell := Vector2i(2, 2)
	field.stamp("compost", cell, 2.0, 1.0)
	var before_feed := field.sample(cell, "fertility")
	districts.paint_cell("north_beds", cell, "North Beds")
	districts.paint_cell("north_beds", Vector2i(2, 3), "North Beds")
	var adopted := districts.set_policy("north_beds", "organic_only", true)
	t.expect(adopted.find("Organic only") != -1, "adopting a policy names it")
	t.expect(field.sample(cell, "pollination") > 0.1, "organic only paints pollination on the group")
	t.expect(field.sample(Vector2i(8, 7), "pollination") == 0.0, "an unpainted bed is left alone")
	t.expect(field.sample(cell, "fertility") < before_feed, "organic only cuts fertility on a fed bed")
	clock.call("set_hour", 12.0)
	districts.set_policy("north_beds", "night_lanterns", true)
	t.expect(is_equal_approx(field.sample(cell, "light"), 0.0), "night lanterns are dark at noon")
	clock.call("set_hour", 21.0)
	t.expect(field.sample(cell, "light") > 0.25, "night lanterns paint light after dusk")
	clock.call("set_hour", 2.0)
	t.expect(field.sample(cell, "light") > 0.25, "night lanterns stay lit before dawn")
	var dropped := districts.set_policy("north_beds", "organic_only", false)
	t.expect(dropped.find("dropped") != -1, "clearing a policy says so")
	t.expect(is_equal_approx(field.sample(cell, "pollination"), 0.0), "dropping organic only removes its pollination")
	clock.call("reset_new")


func _demand_and_coins(t: PetalAssert) -> void:
	var economy := _economy()
	economy.set("coins", 40)
	var field := ServiceField.new()
	field.setup(10, 8)
	var causal := CausalLog.new()
	var districts := _bound(field, causal)
	var cell := Vector2i(1, 1)
	districts.paint_cell("lane_edge", cell, "Lane Edge")
	districts.set_policy("lane_edge", "market_day", true)
	var demand := CityDemand.new()
	demand.setup(field, causal, null, null)
	demand.districts = districts
	var signals := {
		"resident_total": 4,
		"free_beds": 20,
		"quality_mean": 0.5,
		"coins": 40,
		"stall_stock": 2,
		"footfall": 0,
	}
	var plain := CityDemand.new()
	plain.recompute(signals)
	demand.recompute(signals)
	t.expect(demand.market == plain.market + 9, "market day adds its demand offset")
	t.expect(demand.bloom == plain.bloom, "market day does not move bloom")
	var why := ""
	for entry_v in causal.all_entries():
		var entry: Dictionary = entry_v
		if str(entry.get("target", "")) == "market":
			why = str(entry.get("cause", ""))
	t.expect(why.find("Market day on Lane Edge") != -1, "the demand reason names the policy and the group")
	var before := int(economy.get("coins"))
	t.expect(districts.charge_daily(1) > 0, "market day charges upkeep")
	t.expect(int(economy.get("coins")) == before - 1, "a one-bed market group pays upkeep but earns nothing")
	var held := int(economy.get("coins"))
	t.expect(districts.charge_daily(1) == 0, "the same day does not charge policies twice")
	t.expect(int(economy.get("coins")) == held, "a second policy charge is a no-op")
	districts.paint_cell("lane_edge", Vector2i(2, 1))
	districts.paint_cell("lane_edge", Vector2i(3, 1))
	districts.charge_daily(2)
	t.expect(int(economy.get("coins")) == held + 3, "market day income is 4 and upkeep is 1 once the group has 3 beds")
	var night := _bound(ServiceField.new())
	night.paint_cell("pond_bank", Vector2i(0, 1), "Pond Bank")
	night.set_policy("pond_bank", "night_lanterns", true)
	economy.set("coins", 1)
	t.expect(night.charge_daily(2) == 1, "policy upkeep takes only the coins on hand")
	t.expect(int(economy.get("coins")) == 0, "a short purse ends at zero")
	var saw_pay := false
	for entry_v in night.log.all_entries():
		var entry: Dictionary = entry_v
		if str(entry.get("kind", "")) == "district_upkeep" and str(entry.get("cause", "")).find("Night lanterns") != -1:
			saw_pay = true
	t.expect(saw_pay, "upkeep writes a causal reason")


func _food_and_pests(t: PetalAssert) -> void:
	var plain := _web_count(false)
	var fed := _web_count(true)
	t.expect(fed > plain, "a pollinator haven grows the web faster")
	var eaten_plain := _eaten(false)
	var eaten_soft := _eaten(true)
	t.expect(eaten_soft < eaten_plain, "organic only slows predation")
	var open_moths := _moth_count(false)
	var soft_moths := _moth_count(true)
	t.expect(open_moths > soft_moths, "organic only lowers pest pressure")
	t.expect(soft_moths > 0, "pests still arrive under an organic group")


func _land_and_lod(t: PetalAssert) -> void:
	var field := ServiceField.new()
	field.setup(10, 8)
	var districts := _bound(field)
	var near_cell := Vector2i(1, 1)
	var far_cell := Vector2i(8, 6)
	districts.paint_cell("north_beds", near_cell, "North Beds")
	districts.paint_cell("north_beds", Vector2i(1, 2), "North Beds")
	districts.paint_cell("far_hedge", far_cell, "Far Hedge")
	districts.set_policy("north_beds", "pollinator_haven", true)
	districts.set_policy("far_hedge", "market_day", true)
	field.stamp("hive", near_cell, 2.0, 1.0)
	t.expect(is_equal_approx(districts.demand_offset("market"), 9.0), "an unclassified group pays the full market offset")
	var focus := districts.centroid("north_beds")
	districts.refresh(focus, 0)
	t.expect(districts.tier_of("north_beds") <= 1, "a group under the camera target is full detail")
	t.expect(field.sample(near_cell, "pollination") > 0.9, "a near haven keeps its pollination")
	t.expect(districts.land_value("north_beds") > districts.land_value("far_hedge"), "land value follows service quality")
	var distant := districts.centroid("far_hedge") + Vector3(80, 0, 0)
	districts.refresh(distant, 0)
	t.expect(districts.tier_of("far_hedge") == 4, "a far group is statistical")
	var far_rows: Array = root.get_node("SimLod").get("district_rows")
	var saw_far := false
	for item in far_rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var far_row: Dictionary = item
		if str(far_row.get("id", "")) == "far_hedge" and bool(far_row.get("statistical", false)):
			saw_far = true
	t.expect(saw_far, "the far group is marked statistical on the lod board")
	t.expect(is_equal_approx(districts.demand_offset("market"), 4.5), "a statistical group pays half the market offset")
	t.expect(is_equal_approx(field.sample(far_cell, "pollination"), 0.0), "a statistical group does not paint the service field")
	var cached := districts.quality_of("far_hedge")
	field.stamp("well", far_cell, 3.0, 1.0)
	districts.refresh(distant, 1)
	t.expect(is_equal_approx(districts.quality_of("far_hedge"), cached), "statistical quality waits out the hour stride")
	districts.refresh(distant, 6)
	t.expect(districts.quality_of("far_hedge") > cached, "statistical quality refreshes on its hour")
	var stride_focus := districts.centroid("north_beds") + Vector3(20, 0, 0)
	districts.refresh(stride_focus, 0)
	t.expect(districts.tier_of("north_beds") == 3, "the mid band is SimLod tier 3")
	var mid := districts.quality_of("north_beds")
	field.stamp("compost", near_cell, 2.0, 1.0)
	districts.refresh(stride_focus, 1)
	t.expect(is_equal_approx(districts.quality_of("north_beds"), mid), "tier 3 samples every fourth hour")
	districts.refresh(stride_focus, 4)
	t.expect(districts.quality_of("north_beds") > mid, "tier 3 catches up on the stride hour")
	t.expect(field.sample(near_cell, "pollination") > 0.2, "tier 3 still applies policy bias between samples")
	var lod := root.get_node("SimLod")
	lod.call("note_population", 2, 3, 0.4, 11)
	districts.refresh(focus, 8)
	var stats: Dictionary = lod.get("district_stats")
	t.expect(int(stats.get("coins", 0)) == 11, "district lod does not replace the parish purse")
	t.expect(str(stats.get("id", "")) == "hedge_hollow", "the parish row keeps its name")
	var rows: Array = lod.get("district_rows")
	t.expect(rows.size() >= 2, "SimLod records every painted group")
	t.expect(int(lod.call("stride_for", 1)) == 1, "near groups tick every hour")
	t.expect(int(lod.call("stride_for", 4)) == 0, "the far band is statistical")


func _overlay(t: PetalAssert) -> void:
	var field := ServiceField.new()
	field.setup(10, 8)
	var districts := _bound(field)
	var cell := Vector2i(3, 3)
	districts.paint_cell("north_beds", cell, "North Beds")
	districts.set_policy("north_beds", "pollinator_haven", true)
	districts.refresh(districts.centroid("north_beds"), 0)
	var view_script: Script = load("res://scripts/ui/overlays.gd")
	var view: Object = view_script.new()
	view.call("bind", field, PathGraph.new(), CityDemand.new(), CausalLog.new(), null)
	view.set("districts", districts)
	view.call("set_channel", "districts")
	t.expect(str(view.call("source_of", "districts")) == "district", "the district overlay source is district")
	t.expect(is_equal_approx(float(view.call("sample", cell)), districts.paint_amount(cell)), "the district map matches land value")
	t.expect(float(view.call("painted_amount", cell)) > 0.0, "a painted bed shows on the district map")
	t.expect(is_equal_approx(float(view.call("painted_amount", Vector2i(9, 7))), 0.0), "an unpainted bed stays dark")


func _save(t: PetalAssert) -> void:
	var save := root.get_node("SaveGame")
	var from_v1: Dictionary = save.call("migrate_text", FileAccess.get_file_as_string("res://tests/fixtures/save_v1_day3.json"))
	_expect_empty_districts(t, from_v1, "v1 migration defaults districts to empty")
	var from_v2: Dictionary = save.call("migrate_parsed", {
		"version": 2,
		"state": {"name": "Before districts", "economy": {"coins": 15}, "sim": {"schema": 1, "clock": {"seed": 9}}},
	})
	_expect_empty_districts(t, from_v2, "v2 migration defaults districts to empty")
	t.expect(typeof(from_v2.get("city", {}).get("services", null)) == TYPE_ARRAY, "v2 migration still defaults services to empty")
	var early_v3: Dictionary = save.call("migrate_parsed", {
		"version": 3,
		"state": {
			"name": "Early v3",
			"city": {"services": [{"id": "well", "x": 1, "z": 2, "radius": 3, "strength": 1}], "paths": [], "charged_day": 2},
			"sim": {"schema": 1},
		},
	})
	_expect_empty_districts(t, early_v3, "an earlier v3 save defaults districts to empty")
	t.expect((early_v3.get("city", {}).get("services", []) as Array).size() == 1, "earlier v3 services stay in place")
	var odd: Dictionary = save.call("migrate_parsed", {
		"version": 3,
		"state": {"city": {"services": [], "paths": [], "districts": "nope"}, "sim": {"schema": 1}},
	})
	_expect_empty_districts(t, odd, "a bad districts value migrates to empty")
	var kept: Dictionary = save.call("migrate_parsed", {
		"version": 3,
		"state": {
			"city": {
				"services": [],
				"paths": [],
				"districts": {
					"rows": [{"id": "north_beds", "name": "North Beds", "cells": [{"x": 4, "z": 5}], "policies": ["organic_only"]}],
					"charged_day": 3,
					"active": "north_beds",
					"next_index": 2,
				},
			},
			"sim": {"schema": 1},
		},
	})
	var kept_rows: Array = kept.get("city", {}).get("districts", {}).get("rows", [])
	t.expect(kept_rows.size() == 1, "a v3 save with districts keeps them")
	if not kept_rows.is_empty():
		var row: Dictionary = kept_rows[0]
		t.expect((row.get("policies", []) as Array).has("organic_only"), "saved policies survive migration")
	var field := ServiceField.new()
	field.setup(10, 8)
	var districts := _bound(field)
	districts.paint_cell("north_beds", Vector2i(4, 1), "North Beds")
	districts.paint_cell("north_beds", Vector2i(4, 2), "North Beds")
	districts.set_policy("north_beds", "organic_only", true)
	districts.set_policy("north_beds", "night_lanterns", true)
	districts.charged_day = 4
	var slot := 94
	var path := str(save.call("path_for", slot))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var wrote: Variant = save.call("write_slot", slot, {"name": "Districts", "city": {"services": field.to_state().get("services", []), "paths": [], "districts": districts.to_state()}, "economy": {"coins": 9}})
	t.expect(bool(wrote), "district slot writes")
	var loaded: Dictionary = save.call("read_slot", slot)
	var again := GardenDistricts.new()
	again.setup(ServiceField.new(), null)
	again.apply_state(loaded.get("city", {}))
	t.expect(again.owner_of(Vector2i(4, 1)) == "north_beds", "painted beds survive the save")
	t.expect(again.owner_of(Vector2i(4, 2)) == "north_beds", "the whole group survives the save")
	var policies: PackedStringArray = again._policy_ids("north_beds")
	t.expect(policies.has("organic_only") and policies.has("night_lanterns"), "policies survive the save")
	t.expect(again.charged_day == 4, "policy upkeep day survives the save")
	t.expect(again.active_id == "north_beds", "the active group survives the save")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _expect_empty_districts(t: PetalAssert, state: Dictionary, label: String) -> void:
	var pack: Variant = state.get("city", {}).get("districts", null)
	t.expect(typeof(pack) == TYPE_DICTIONARY, label)
	if typeof(pack) != TYPE_DICTIONARY:
		return
	var body: Dictionary = pack
	t.expect(typeof(body.get("rows", null)) == TYPE_ARRAY and (body.get("rows", []) as Array).is_empty(), label)


func _web_count(haven: bool) -> int:
	var web := FoodWeb.new()
	web.reseed(4242)
	if haven:
		var districts := _anchor(_bound(ServiceField.new()))
		districts.paint_cell("north_beds", Vector2i(0, 0), "North Beds")
		districts.set_policy("north_beds", "pollinator_haven", true)
		web.food_scale = Callable(districts, "food_scale")
	web.counts["grapling"] = 2
	for _i in 24:
		web.hour(_species())
	return int(web.counts.get("grapling", 0))


func _eaten(organic: bool) -> int:
	var web := FoodWeb.new()
	web.reseed(4242)
	if organic:
		var districts := _anchor(_bound(ServiceField.new()))
		districts.paint_cell("north_beds", Vector2i(0, 0), "North Beds")
		districts.set_policy("north_beds", "organic_only", true)
		web.food_scale = Callable(districts, "food_scale")
	web.counts["grapling"] = 14
	web.counts["gushorn"] = 3
	for _i in 8:
		web.hour(_species())
	return int(web.eaten.get("gushorn>grapling", 0))


func _moth_count(organic: bool) -> int:
	var soil_script: Script = load("res://scripts/garden/soil_field.gd")
	var soil: Object = soil_script.new()
	for cell in [Vector2i(0, 0), Vector2i(1, 0)]:
		var plot: Object = soil.call("get_cell", cell.x, cell.y)
		plot.set("plant_id", "meadowbell")
		plot.set("moisture", 0.05)
		plot.set("wilt", 2.0)
	var blight_script: Script = load("res://scripts/ecology/blight.gd")
	var blight: Object = blight_script.new()
	blight.set("soil", soil)
	if organic:
		var districts := _anchor(_bound(ServiceField.new()))
		districts.paint_cell("north_beds", Vector2i(0, 0), "North Beds")
		districts.set_policy("north_beds", "organic_only", true)
		blight.pest_scale = Callable(districts, "pest_scale")
	var world := {"garden_quality": 0.1, "mature": {}, "species_state": {}, "structures": {}}
	for _i in 8:
		blight.call("hour", world, PackedStringArray())
	return (blight.get("moths") as Array).size()


func _species() -> Dictionary:
	var catalog: Variant = root.get_node("ContentDB").get("species")
	if typeof(catalog) != TYPE_DICTIONARY:
		return {}
	return catalog


func _anchor(districts: GardenDistricts) -> GardenDistricts:
	_anchors.append(districts)
	return districts


func _new() -> GardenDistricts:
	var districts := GardenDistricts.new()
	districts.setup(ServiceField.new(), CausalLog.new())
	return districts


func _bound(field: ServiceField, causal: CausalLog = null) -> GardenDistricts:
	var log := causal
	if log == null:
		log = CausalLog.new()
	var districts := GardenDistricts.new()
	districts.setup(field, log)
	field.bias_for = Callable(districts, "service_bias")
	return districts

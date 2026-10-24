extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")


func _initialize() -> void:
	var t: PetalAssert = PA.new("path_graph")
	_catalog(t)
	_graph(t)
	_forty_eight(t)
	_market(t)
	_save(t)
	t.done()


func _clock() -> Node:
	return root.get_node("Clock")


func _paths_root() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/paths.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _catalog(t: PetalAssert) -> void:
	var root_data := _paths_root()
	t.expect(not root_data.is_empty(), "paths.json is an object")
	var anchors: Array = root_data.get("anchors", [])
	var runs: Array = root_data.get("runs", [])
	var by_id := {}
	for item in anchors:
		if typeof(item) == TYPE_DICTIONARY:
			by_id[str(item.get("id", ""))] = true
	for anchor_id in ["stall", "shed", "beds", "hive", "pond", "gate"]:
		t.expect(by_id.has(anchor_id), "paths.json anchors include %s" % anchor_id)
	t.expect(runs.size() >= 4, "paths.json links the anchors with runs")
	var stall: Dictionary = root_data.get("stall", {})
	t.expect(str(stall.get("keeper", "")) == "bram", "the stall keeper is bram")
	t.expect(float(stall.get("open_from", -1)) == 5.0, "the stall opens at the morning hour")
	t.expect(float(stall.get("open_until", -1)) == 19.5, "the stall shuts at dusk")
	t.expect(int(stall.get("footfall_per_sale", 0)) > 0, "footfall converts to sales")
	var demand: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/demand.json"))
	t.expect(typeof(demand) == TYPE_DICTIONARY, "demand.json is an object")
	if typeof(demand) == TYPE_DICTIONARY:
		var market: Dictionary = (demand as Dictionary).get("kinds", {}).get("market", {})
		var weights: Dictionary = market.get("weights", {})
		t.expect(is_equal_approx(float(weights.get("footfall", 0)), 0.85), "market demand weights footfall at 0.85")


func _graph(t: PetalAssert) -> void:
	var root_data := _paths_root()
	var graph := PathGraph.new()
	graph.setup(null, null, null)
	for item in root_data.get("anchors", []):
		if typeof(item) == TYPE_DICTIONARY:
			var anchor_id := str(item.get("id", ""))
			t.expect(graph.has_anchor(anchor_id), "graph builds anchor %s" % anchor_id)
	for item in root_data.get("runs", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var walked := graph.path_between(str(row.get("from", "")), str(row.get("to", "")))
		t.expect(walked.size() >= 2, "run %s is a path" % str(row.get("id", "")))
	var shed := graph.path_between("shed", "stall")
	t.expect(shed.size() >= 2, "the keeper walk reaches the stall")
	t.expect(shed[0].distance_to(Vector3(-11.15, 0.0, 3.55)) < 0.05, "the keeper walk starts at the shed")
	t.expect(shed[shed.size() - 1].distance_to(Vector3(-4.55, 0.0, 5.15)) < 0.05, "the keeper walk ends at the stall")
	t.expect(graph.path_between("gate", "pond").size() >= 2, "the gate reaches the pond")
	t.expect(graph.path_between("beds", "hive").size() >= 2, "the beds reach the hive")
	t.expect(graph.path_between("nope", "stall").is_empty(), "unknown anchors do not invent a path")
	var before := graph.point_count()
	graph.add_stones([
		Vector3(0.18, 0.07, -12.05),
		Vector3(-0.22, 0.06, -12.72),
		Vector3(0.08, 0.07, -13.4),
		Vector3(80.0, 0.0, 80.0),
	])
	t.expect(graph.point_count() == before + 4, "each road stone becomes a point")
	t.expect(graph.reaches(Vector3(0.08, 0.07, -13.4), "stall"), "road stones chain to the stall")
	t.expect(not graph.reaches(Vector3(80.0, 0.0, 80.0), "stall"), "a stone outside the radius stays disconnected")
	var placed_before := graph.point_count()
	graph.add_placed("cut", Vector3(30.0, 0.0, 30.0), Vector3(34.0, 0.0, 30.0))
	t.expect(graph.point_count() > placed_before, "a placed path adds points")
	t.expect(graph.reaches_point(Vector3(30.0, 0.0, 30.0), Vector3(34.0, 0.0, 30.0)), "a placed path is walkable")
	t.expect(not graph.reaches(Vector3(30.0, 0.0, 30.0), "stall"), "a far placed path does not jump to the stall")

	var holder := Node3D.new()
	root.add_child(holder)
	var stone_mesh := BoxMesh.new()
	stone_mesh.size = Vector3(0.46, 0.07, 0.32)
	var stone := MeshInstance3D.new()
	stone.mesh = stone_mesh
	stone.position = Vector3(0.18, 0.07, -12.05)
	stone.add_to_group("parish_road_stone")
	holder.add_child(stone)
	var strip := BoxMesh.new()
	strip.size = Vector3(1.05, 0.03, 4.0)
	var path := MeshInstance3D.new()
	path.mesh = strip
	path.position = Vector3(0.0, 0.02, -13.8)
	path.add_to_group("parish_road_path")
	holder.add_child(path)
	var bare := PathGraph.new()
	bare.setup(null, null, null)
	t.expect(not bare.reaches(Vector3(0.0, 0.02, -15.8), "stall"), "the catalog does not already reach past the gate")
	var scene_graph := PathGraph.new()
	scene_graph.setup(null, null, null)
	var before_scene := scene_graph.point_count()
	scene_graph.ingest_scene(holder)
	t.expect(scene_graph.point_count() > before_scene, "scene roads add graph points")
	t.expect(scene_graph.reaches(Vector3(0.0, 0.02, -15.8), "stall"), "a placed road strip joins the stall")
	holder.free()


func _forty_eight(t: PetalAssert) -> void:
	var first := _series(4242)
	var second := _series(4242)
	var other := _series(99)
	t.expect(first.size() == 49, "48 hours plus the causal digest")
	t.expect(first == second, "the same seed over 48 hours matches")
	t.expect(first != other, "a different seed changes the 48 hour footfall")
	var busy := false
	var lifted := false
	for i in 48:
		var parts := str(first[i]).split(",")
		t.expect(parts.size() >= 3, "each hour records footfall and market")
		var hour_steps := int(parts[0])
		var total := int(parts[1])
		var market := int(parts[2])
		t.expect(hour_steps >= 0 and total >= 0, "footfall stays non-negative")
		t.expect(market >= 0 and market <= 100, "market stays in 0–100")
		if hour_steps > 0:
			busy = true
		if market > 18:
			lifted = true
	t.expect(busy, "footfall happens across 48 hours")
	t.expect(lifted, "market rises when the paths are walked")
	t.expect(str(first[48]).find("footfall") != -1, "the 48 hour log records footfall")


func _series(seed_value: int) -> Array:
	var clock := _clock()
	clock.call("reset_new")
	clock.set("running", false)
	var causal := CausalLog.new()
	var graph := PathGraph.new()
	graph.setup(causal, null, null)
	graph.reseed(seed_value)
	graph.census_for = _census_for(seed_value)
	var demand := CityDemand.new()
	demand.reseed(seed_value)
	var series: Array = []
	for step in 48:
		clock.call("set_from_absolute", float(step) * 60.0)
		graph.tick()
		demand.recompute({
			"resident_total": 4,
			"free_beds": 20,
			"quality_mean": 0.5,
			"coins": 40,
			"stall_stock": 2,
			"footfall": graph.footfall_signal(),
		})
		series.append("%d,%d,%d,%s" % [graph.hour_footfall, graph.footfall_total, demand.market, graph.edge_digest()])
	series.append(causal.digest())
	return series


func _census_for(seed_value: int) -> Callable:
	var clock := _clock()
	return func() -> Dictionary:
		var step := (int(clock.get("day")) - 1) * 24 + int(floor(float(clock.call("hour"))))
		var roll := RandomNumberGenerator.new()
		roll.seed = seed_value
		var n := 0
		while n < step:
			roll.randi()
			n += 1
		return {
			"residents": roll.randi() % 4,
			"creatures": roll.randi() % 3,
			"ripe": roll.randi() % 4,
			"hour": float(clock.call("hour")),
			"weather": str(clock.get("weather")),
		}


func _market(t: PetalAssert) -> void:
	var clock := _clock()
	clock.call("reset_new")
	clock.set("running", false)
	clock.call("set_from_absolute", 10.0 * 60.0)
	var causal := CausalLog.new()
	var graph := PathGraph.new()
	graph.setup(causal, null, null)
	graph.reseed(3)
	graph.census_for = func() -> Dictionary:
		return {"residents": 1, "creatures": 1, "ripe": 1, "hour": 10.0, "weather": "clear"}
	graph.tick()
	var steps := graph.hour_footfall
	t.expect(steps > 0, "an open clear hour records footfall")
	var held := graph.footfall_total
	graph.tick()
	t.expect(graph.footfall_total == held, "the same hour does not walk twice")
	var quiet := CityDemand.new()
	quiet.reseed(4242)
	var base := {
		"resident_total": 4,
		"free_beds": 20,
		"quality_mean": 0.5,
		"coins": 40,
		"stall_stock": 2,
		"footfall": 0,
	}
	quiet.recompute(base)
	t.expect(quiet.bloom == 38 and quiet.hive == 41 and quiet.market == 26, "zero footfall keeps the market formula")
	var with_feet := base.duplicate()
	with_feet["footfall"] = 10
	quiet.recompute(with_feet)
	t.expect(quiet.bloom == 38 and quiet.hive == 41, "footfall leaves bloom and hive alone")
	t.expect(quiet.market == 35, "ten footfall steps add the footfall weight")

	var reasons: Array = []
	var demand := CityDemand.new()
	demand.setup(ServiceField.new(), causal, null, null, graph)
	demand.reseed(4242)
	demand.demand_changed.connect(func(kind: String, _old_value: int, _new_value: int, why: String) -> void:
		reasons.append("%s:%s" % [kind, why])
	)
	demand.signals_for = func() -> Dictionary:
		var signals := base.duplicate()
		signals["footfall"] = graph.footfall_signal()
		return signals
	demand.tick()
	var expected := clampi(26 + int(round(float(steps) * 0.85)), 0, 100)
	t.expect(demand.market == expected, "the hour tick links path footfall to market")
	t.expect(demand.market > 26, "walked paths raise market above the empty hour")
	var saw_reason := false
	for line in reasons:
		if str(line).find("footfall %d" % steps) != -1:
			saw_reason = true
	t.expect(saw_reason, "the market reason names the footfall")
	var saw_footfall := false
	for entry in causal.all_entries():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		if str(row.get("kind", "")) == "footfall" and str(row.get("cause", "")).find("stall") != -1:
			saw_footfall = true
		if str(row.get("kind", "")) == "demand_changed" and str(row.get("cause", "")).find("footfall") != -1:
			saw_reason = true
	t.expect(saw_footfall, "the causal log records why footfall changed")

	var economy := root.get_node("Economy")
	var before_coins := int(economy.get("coins"))
	var before_bells := int(economy.call("count", "meadowbell"))
	economy.call("add", "meadowbell", 3)
	var stall: Dictionary = _paths_root().get("stall", {})
	var per := maxi(int(stall.get("footfall_per_sale", 1)), 1)
	var cap := int(stall.get("max_sales", 1))
	var bonus := int(stall.get("price_bonus", 0))
	var units := mini(cap, int(floor(float(steps) / float(per))))
	units = mini(units, 3)
	t.expect(units >= 1, "the open hour covers at least one stall sale")
	var gained := graph.settle_stall()
	t.expect(gained == units * (5 + bonus), "Bram's stall pays the footfall price")
	t.expect(int(economy.call("count", "meadowbell")) == before_bells + 3 - units, "the stall takes the walked stock")
	t.expect(int(economy.get("coins")) == before_coins + gained, "the sale lands in the tin")
	var again := graph.settle_stall()
	t.expect(again == 0, "the same hour does not sell twice")
	var saw_sale := false
	for entry in causal.all_entries():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		if str(row.get("kind", "")) == "stall_sale" and str(row.get("target", "")) == "bram" and str(row.get("cause", "")).find("Bram") != -1 and str(row.get("cause", "")).find("footfall") != -1:
			saw_sale = true
	t.expect(saw_sale, "the causal log records Bram's stall sale")

	clock.call("set_from_absolute", 22.0 * 60.0)
	var night := PathGraph.new()
	night.setup(CausalLog.new(), null, null)
	night.reseed(3)
	night.census_for = func() -> Dictionary:
		return {"residents": 2, "creatures": 1, "ripe": 2, "hour": 22.0, "weather": "clear"}
	night.tick()
	t.expect(night.hour_footfall > 0, "residents still walk after the stall shuts")
	var night_bells := int(economy.call("count", "meadowbell"))
	t.expect(night.settle_stall() == 0, "a shut stall does not sell")
	t.expect(int(economy.call("count", "meadowbell")) == night_bells, "a shut stall keeps the stock")

	clock.call("set_from_absolute", 36.0 * 60.0)
	var rain := PathGraph.new()
	rain.setup(CausalLog.new(), null, null)
	rain.reseed(3)
	rain.census_for = func() -> Dictionary:
		return {
			"residents": 4,
			"creatures": 2,
			"ripe": 3,
			"hour": float(clock.call("hour")),
			"weather": str(clock.get("weather")),
		}
	rain.tick()
	t.expect(str(clock.get("weather")) == "rain", "the even afternoon is rain")
	t.expect(rain.hour_footfall == 0, "rain keeps the paths empty")

	var have := int(economy.call("count", "meadowbell"))
	if have > before_bells:
		economy.call("take", "meadowbell", have - before_bells)
	economy.set("coins", before_coins)


func _save(t: PetalAssert) -> void:
	var save := root.get_node("SaveGame")
	var migrated: Dictionary = save.call("migrate_parsed", {
		"version": 2,
		"state": {"name": "Before paths", "economy": {"coins": 15}, "sim": {"schema": 1, "clock": {"seed": 9}}},
	})
	var city: Dictionary = migrated.get("city", {})
	t.expect(typeof(city.get("paths", null)) == TYPE_ARRAY and (city.get("paths", []) as Array).is_empty(), "v2 migration defaults paths to empty")
	t.expect(typeof(city.get("services", null)) == TYPE_ARRAY and (city.get("services", []) as Array).is_empty(), "v2 migration still defaults services to empty")
	var recorded := FileAccess.get_file_as_string("res://tests/fixtures/save_v1_day3.json")
	var from_v1: Dictionary = save.call("migrate_text", recorded)
	var v1_paths: Variant = from_v1.get("city", {}).get("paths", null)
	t.expect(typeof(v1_paths) == TYPE_ARRAY and (v1_paths as Array).is_empty(), "v1 migration defaults paths to empty")
	var missing: Dictionary = save.call("migrate_parsed", {
		"version": 3,
		"state": {"city": {"services": [{"id": "well", "x": 1, "z": 2, "radius": 3, "strength": 1}], "charged_day": 2}, "sim": {"schema": 1}},
	})
	var missing_city: Dictionary = missing.get("city", {})
	t.expect(typeof(missing_city.get("paths", null)) == TYPE_ARRAY and (missing_city.get("paths", []) as Array).is_empty(), "a v3 city block without paths migrates to empty")
	t.expect((missing_city.get("services", []) as Array).size() == 1, "adding paths keeps the stamped services")
	var odd: Dictionary = save.call("migrate_parsed", {
		"version": 3,
		"state": {"city": {"services": [], "paths": {"nope": true}}, "sim": {"schema": 1}},
	})
	t.expect(typeof(odd.get("city", {}).get("paths", null)) == TYPE_ARRAY and (odd.get("city", {}).get("paths", []) as Array).is_empty(), "a non-list paths value migrates to empty")

	var clock := _clock()
	clock.call("reset_new")
	clock.set("running", false)
	var graph := PathGraph.new()
	graph.setup(CausalLog.new(), null, null)
	graph.reseed(11)
	graph.census_for = _census_for(11)
	graph.add_placed("cut", Vector3(30.0, 0.0, 30.0), Vector3(34.0, 0.0, 30.0))
	var series: Array = []
	var snap: Array = []
	for step in 15:
		clock.call("set_from_absolute", float(step) * 60.0)
		graph.tick()
		series.append({"hour": graph.hour_footfall, "total": graph.footfall_total, "edges": graph.edge_digest()})
		if step == 9:
			snap = graph.to_state()
	var saw_placed := false
	var saw_meta := false
	for item in snap:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		if str(row.get("kind", "")) == "placed" and str(row.get("id", "")) == "cut":
			saw_placed = true
		if str(row.get("kind", "")) == "meta":
			saw_meta = true
	t.expect(saw_placed, "the save lists the placed path")
	t.expect(saw_meta, "the save keeps the footfall hour")
	var other := PathGraph.new()
	other.setup(CausalLog.new(), null, null)
	other.census_for = _census_for(11)
	other.apply_state(snap)
	var mid: Dictionary = series[9]
	t.expect(other.edge_digest() == str(mid.get("edges", "")), "footfall survives the save round-trip")
	t.expect(other.footfall_total == int(mid.get("total", -1)), "total footfall survives the save round-trip")
	t.expect(other.reaches_point(Vector3(30.0, 0.0, 30.0), Vector3(34.0, 0.0, 30.0)), "the placed path survives the save round-trip")
	for step in range(10, 15):
		clock.call("set_from_absolute", float(step) * 60.0)
		other.tick()
		var want: Dictionary = series[step]
		t.expect(other.hour_footfall == int(want.get("hour", -2)), "hour %d footfall continues after load" % step)
		t.expect(other.edge_digest() == str(want.get("edges", "")), "hour %d edges continue after load" % step)

	var field := ServiceField.new()
	field.setup(10, 8)
	field.stamp("well", Vector2i(1, 2), 3.0, 1.0)
	field.charged_day = 4
	var block := field.to_state()
	block["paths"] = graph.to_state()
	var slot := 94
	var path := str(save.call("path_for", slot))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var wrote: Variant = save.call("write_slot", slot, {"name": "Paths", "city": block, "economy": {"coins": 9}, "clock": {"day": 4}})
	t.expect(bool(wrote), "city paths slot writes")
	var raw := FileAccess.get_file_as_string(path)
	var payload: Variant = JSON.parse_string(raw)
	t.expect(typeof(payload) == TYPE_DICTIONARY and int((payload as Dictionary).get("version", 0)) == 3, "path saves stay on version 3")
	var loaded: Dictionary = save.call("read_slot", slot)
	var loaded_city: Dictionary = loaded.get("city", {})
	var again_field := ServiceField.new()
	again_field.setup(10, 8)
	again_field.apply_state(loaded_city)
	t.expect(is_equal_approx(again_field.sample(Vector2i(1, 2), "moisture"), 1.0), "services survive beside paths")
	t.expect(again_field.charged_day == 4, "service upkeep day survives beside paths")
	var loaded_graph := PathGraph.new()
	loaded_graph.setup(null, null, null)
	loaded_graph.apply_state(loaded_city)
	t.expect(loaded_graph.edge_digest() == graph.edge_digest(), "the slot reloads the same footfall")
	t.expect(loaded_graph.reaches_point(Vector3(30.0, 0.0, 30.0), Vector3(34.0, 0.0, 30.0)), "the slot reloads the placed path")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

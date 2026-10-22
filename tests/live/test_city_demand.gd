extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")


func _initialize() -> void:
	var t: PetalAssert = PA.new("city_demand")
	_formula(t)
	_hour_tick(t)
	_forty_eight_hours(t)
	t.done()


func _clock() -> Node:
	return root.get_node("Clock")


func _formula(t: PetalAssert) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/demand.json"))
	t.expect(typeof(parsed) == TYPE_DICTIONARY, "demand.json is an object")
	if typeof(parsed) == TYPE_DICTIONARY:
		var kinds: Dictionary = (parsed as Dictionary).get("kinds", {})
		for factor in ["resident_total", "free_beds", "quality_mean", "coins", "stall_stock"]:
			var found := false
			for kind_v in kinds.keys():
				var spec: Dictionary = kinds[kind_v]
				var weights: Dictionary = spec.get("weights", {})
				if weights.has(factor):
					found = true
			t.expect(found, "demand.json weights include %s" % factor)
	var demand := CityDemand.new()
	var causal := CausalLog.new()
	demand.setup(ServiceField.new(), causal, null, null)
	demand.reseed(4242)
	var reasons: Array = []
	demand.demand_changed.connect(func(kind: String, old_value: int, new_value: int, why: String) -> void:
		reasons.append("%s:%d:%d:%s" % [kind, old_value, new_value, why])
	)
	var signals := {
		"resident_total": 4,
		"free_beds": 20,
		"quality_mean": 0.5,
		"coins": 40,
		"stall_stock": 2,
	}
	demand.recompute(signals)
	t.expect(demand.bloom == 64, "bloom matches the demand.json weights")
	t.expect(demand.hive == 40, "hive matches the demand.json weights")
	t.expect(demand.market == 18, "market matches the demand.json weights")
	t.expect(demand.journal_line() == "Bloom 64 · Hive 40 · Market 18", "journal line is Bloom, Hive, Market")
	t.expect(reasons.size() == 3, "a change emits bloom, hive, and market")
	t.expect(str(reasons[0]).begins_with("bloom:0:64:"), "bloom reports the old and new values")
	t.expect(str(reasons[2]).find("Market demand +18 because residents 4, free beds 20, quality 0.50, coins 40, stall stock 2") != -1, "the reason names the signals")
	t.expect(causal.all_entries().size() == 3, "the causal log records each demand change")
	var entry: Dictionary = causal.all_entries()[0]
	t.expect(str(entry.get("kind", "")) == "demand_changed", "the log kind is demand_changed")
	t.expect(str(entry.get("cause", "")) == str(reasons[0]).split(":")[-1] or str(entry.get("cause", "")).find("Bloom demand +64") != -1, "the log stores the bloom reason")
	var before := reasons.size()
	demand.recompute(signals)
	t.expect(reasons.size() == before, "identical signals do not emit again")
	demand.recompute({
		"resident_total": 100,
		"free_beds": 100,
		"quality_mean": 1.0,
		"coins": 100,
		"stall_stock": 100,
	})
	t.expect(demand.bloom == 100 and demand.hive == 100 and demand.market == 100, "demand clamps at 100")
	demand.recompute({
		"resident_total": 0,
		"free_beds": 100,
		"quality_mean": 0.0,
		"coins": 0,
		"stall_stock": 0,
	})
	t.expect(demand.market == 0, "demand clamps at 0")


func _hour_tick(t: PetalAssert) -> void:
	var clock := _clock()
	clock.call("reset_new")
	clock.set("running", false)
	clock.call("set_from_absolute", 180.0)
	var demand := CityDemand.new()
	demand.setup(ServiceField.new(), CausalLog.new(), null, null)
	demand.reseed(4242)
	var hits := [0]
	demand.demand_changed.connect(func(_kind: String, _old_value: int, _new_value: int, _why: String) -> void:
		hits[0] += 1
	)
	var phase := [0]
	demand.signals_for = func() -> Dictionary:
		var residents := 4 if phase[0] == 0 else 0
		return {
			"resident_total": residents,
			"free_beds": 20,
			"quality_mean": 0.5,
			"coins": 40,
			"stall_stock": 2,
		}
	demand.tick()
	t.expect(demand.bloom == 64 and demand.hive == 40 and demand.market == 18, "the hour tick applies the formula")
	t.expect(hits[0] == 3, "the first hour emits three changes")
	demand.tick()
	t.expect(hits[0] == 3, "the same hour does not recompute")
	clock.call("set_from_absolute", 200.0)
	demand.tick()
	t.expect(hits[0] == 3, "minutes inside the hour stay quiet")
	phase[0] = 1
	clock.call("set_from_absolute", 240.0)
	demand.tick()
	t.expect(hits[0] == 6, "the next hour recomputes from the new signals")
	t.expect(demand.bloom == 68 and demand.hive == 20 and demand.market == 14, "the next hour uses the new resident total")


func _forty_eight_hours(t: PetalAssert) -> void:
	var first := _series(4242)
	var second := _series(4242)
	var other := _series(99)
	t.expect(first.size() == 49, "48 hours plus the causal digest")
	t.expect(first == second, "the same seed over 48 hours matches")
	t.expect(first != other, "a different seed changes the 48 hour run")
	var distinct := {}
	var in_range := true
	for i in 48:
		var row := str(first[i])
		distinct[row] = true
		var parts := row.split(",")
		for part in parts:
			var value := int(part)
			if value < 0 or value > 100:
				in_range = false
	t.expect(distinct.size() > 1, "demand moves across 48 hours")
	t.expect(in_range, "bloom, hive, and market stay in 0–100")
	t.expect(str(first[48]).find("demand_changed") != -1, "the 48 hour log records demand changes")


func _series(seed_value: int) -> Array:
	var clock := _clock()
	clock.call("reset_new")
	clock.set("running", false)
	var field := ServiceField.new()
	field.setup(10, 8)
	field.stamp("well", Vector2i(4, 3), 3.0, 1.0)
	field.stamp("compost", Vector2i(4, 3), 2.0, 1.0)
	field.stamp("hive", Vector2i(4, 3), 4.0, 1.0)
	field.stamp("lantern", Vector2i(4, 3), 3.0, 1.0)
	var causal := CausalLog.new()
	var demand := CityDemand.new()
	demand.setup(field, causal, null, null)
	demand.reseed(seed_value)
	demand.signals_for = func() -> Dictionary:
		var step := (int(clock.get("day")) - 1) * 24 + int(floor(float(clock.call("hour"))))
		var roll := RandomNumberGenerator.new()
		roll.seed = seed_value
		var n := 0
		while n < step:
			roll.randi()
			n += 1
		return {
			"resident_total": roll.randi() % 6,
			"free_beds": 20 + (roll.randi() % 15),
			"quality_mean": field.quality_mean(),
			"coins": 10 + (roll.randi() % 30),
			"stall_stock": roll.randi() % 5,
		}
	var series: Array = []
	for step in 48:
		clock.call("set_from_absolute", float(step) * 60.0)
		demand.tick()
		series.append("%d,%d,%d" % [demand.bloom, demand.hive, demand.market])
	series.append(causal.digest())
	return series

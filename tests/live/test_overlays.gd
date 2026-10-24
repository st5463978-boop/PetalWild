extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var t: PetalAssert = PA.new("overlays")
	_catalog(t)
	_service_samples(t)
	_toggle(t)
	_footfall(t)
	_blight(t)
	_bars(t)
	await _garden(t)
	t.done()


func _catalog(t: PetalAssert) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/overlays.json"))
	t.expect(typeof(parsed) == TYPE_DICTIONARY, "overlays.json is an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	var by_id := {}
	for item in root.get("channels", []):
		if typeof(item) == TYPE_DICTIONARY:
			by_id[str(item.get("id", ""))] = item
	for id in ["moisture", "fertility", "pollination", "light", "quality", "footfall", "blight", "districts"]:
		t.expect(by_id.has(id), "overlays.json includes %s" % id)
		if not by_id.has(id):
			continue
		var row: Dictionary = by_id[id]
		t.expect(str(row.get("low", "")) != "" and str(row.get("high", "")) != "", "%s has low and high colours" % id)
	if by_id.has("moisture"):
		t.expect(str(by_id["moisture"].get("source", "")) == "service", "moisture reads a service channel")
	if by_id.has("footfall"):
		t.expect(str(by_id["footfall"].get("source", "")) == "path", "footfall reads the path graph")
	if by_id.has("blight"):
		t.expect(str(by_id["blight"].get("source", "")) == "blight", "blight reads moth pressure")
	if by_id.has("districts"):
		t.expect(str(by_id["districts"].get("source", "")) == "district", "districts reads painted bed groups")
	var bars := {}
	for item in root.get("bars", []):
		if typeof(item) == TYPE_DICTIONARY:
			bars[str(item.get("id", ""))] = item
	for id in ["bloom", "hive", "market"]:
		t.expect(bars.has(id), "overlays.json bars include %s" % id)
		if bars.has(id):
			var spec: Dictionary = bars[id]
			t.expect(str(spec.get("color", "")) != "", "%s bar has a colour" % id)
	t.expect(str(root.get("empty_reason", "")) != "", "an empty demand log has a reason line")


func _service_samples(t: PetalAssert) -> void:
	var field := ServiceField.new()
	field.setup(10, 8)
	var origin := Vector2i(4, 3)
	field.stamp("well", origin, 3.0, 1.0)
	field.stamp("compost", origin, 2.0, 1.0)
	field.stamp("hive", origin, 4.0, 1.0)
	field.stamp("lantern", origin, 3.0, 1.0)
	var view := _view(field, PathGraph.new(), CityDemand.new(), CausalLog.new())
	var listed: Array = view.call("channels")
	t.expect(listed.size() == 8, "eight map channels are toggleable")
	t.expect(field.sample(origin, "moisture") > 0.9, "the fixture paints moisture")
	for id in ["moisture", "fertility", "pollination", "light", "quality"]:
		view.call("set_channel", id)
		var mismatch := false
		for x in field.width:
			for z in field.height:
				var cell := Vector2i(x, z)
				var expected := field.sample(cell, id)
				if not is_equal_approx(float(view.call("sample", cell)), expected):
					mismatch = true
				if not is_equal_approx(float(view.call("painted_amount", cell)), expected):
					mismatch = true
		t.expect(not mismatch, "%s paint matches ServiceField on every bed" % id)
		t.expect(float(view.call("painted_amount", origin)) > 0.0, "%s paints the stamped bed" % id)
	var before := field.sample(origin, "moisture")
	view.call("set_channel", "fertility")
	view.call("set_channel", "moisture")
	t.expect(is_equal_approx(field.sample(origin, "moisture"), before), "toggling a map does not rewrite the field")
	t.expect(is_equal_approx(float(view.call("sample", Vector2i(-1, 0))), 0.0), "a cell outside the bed grid samples as 0")


func _toggle(t: PetalAssert) -> void:
	var view := _view(ServiceField.new(), PathGraph.new(), CityDemand.new(), CausalLog.new())
	t.expect(str(view.call("channel_id")) == "", "maps start off")
	t.expect(not bool(view.call("maps_visible")), "a hidden map draws no heat")
	view.call("cycle")
	t.expect(str(view.call("channel_id")) == "moisture", "the first cycle shows moisture")
	t.expect(bool(view.call("maps_visible")), "the moisture map is shown")
	var ids: Array = view.call("channels")
	var saw_blight := false
	for _i in ids.size() - 1:
		view.call("cycle")
		if str(view.call("channel_id")) == "blight":
			saw_blight = true
	t.expect(saw_blight, "cycling reaches blight-moth pressure")
	t.expect(str(view.call("channel_id")) == "districts", "cycling ends on the district map")
	t.expect(str(view.call("source_of", "districts")) == "district", "the district map reads painted groups")
	view.call("set_channel", "blight")
	t.expect(str(view.call("source_of", view.call("channel_id"))) == "blight", "the blight map uses blight pressure")
	view.call("set_channel", "districts")
	view.call("cycle")
	t.expect(str(view.call("channel_id")) == "", "the cycle returns to off")
	t.expect(not bool(view.call("maps_visible")), "off hides the heat map")
	var light: Button = view.call("button_for", "light") as Button
	t.expect(light != null, "light has a toggle")
	if light != null:
		light.pressed.emit()
	t.expect(str(view.call("channel_id")) == "light", "the light control shows the light map")
	t.expect(bool(view.call("maps_visible")), "the light map is shown")
	view.call("set_channel", "nope")
	t.expect(str(view.call("channel_id")) == "light", "an unknown map is ignored")
	var off: Button = view.call("button_for", "") as Button
	t.expect(off != null, "maps have an off control")
	if off != null:
		off.pressed.emit()
	t.expect(str(view.call("channel_id")) == "", "the off control clears the map")
	view.call("set_channel", "footfall")
	t.expect(str(view.call("source_of", "footfall")) == "path", "footfall is a path overlay")
	t.expect(bool(view.call("maps_visible")), "the footfall map is shown")
	view.call("set_channel", "quality")
	t.expect(str(view.call("channel_id")) == "quality", "quality can be selected directly")


func _footfall(t: PetalAssert) -> void:
	var clock := root.get_node("Clock")
	clock.call("reset_new")
	clock.call("set_hour", 8.0)
	var walk := PathGraph.new()
	walk.setup(null, null, null)
	walk.reseed(7)
	walk.tick()
	var records: Array = walk.edge_records()
	t.expect(records.size() > 0, "a walk leaves footfall on the path graph")
	var view := _view(ServiceField.new(), walk, CityDemand.new(), CausalLog.new())
	view.call("set_channel", "footfall")
	var peak := float(view.call("footfall_peak"))
	var mismatch := false
	for item in records:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var from_at: Vector3 = row.get("from", Vector3.ZERO) as Vector3
		var to_at: Vector3 = row.get("to", Vector3.ZERO) as Vector3
		var expected := clampf(float(int(row.get("count", 0))) / peak, 0.0, 1.0)
		if not is_equal_approx(float(view.call("edge_amount", from_at, to_at)), expected):
			mismatch = true
	t.expect(not mismatch, "footfall paint matches each PathGraph edge")
	t.expect(is_equal_approx(float(view.call("edge_amount", Vector3(80, 0, 80), Vector3(81, 0, 80))), 0.0), "an unwalked span has no footfall paint")


func _blight(t: PetalAssert) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/overlays.json"))
	var occupied := 1.0
	var neglected := 0.4
	if typeof(parsed) == TYPE_DICTIONARY:
		var root: Dictionary = parsed
		occupied = float(root.get("blight_occupied", occupied))
		neglected = float(root.get("blight_neglected", neglected))
	var soil: Object = load("res://scripts/garden/soil_field.gd").new()
	var moth_cell := Vector2i(3, 2)
	var dry_cell := Vector2i(1, 1)
	var wilt_cell := Vector2i(2, 2)
	var healthy_cell := Vector2i(4, 4)
	var bare_cell := Vector2i(0, 0)
	_bed(soil, dry_cell, "meadowbell", 0.05, 0.0)
	_bed(soil, wilt_cell, "meadowbell", 0.8, 1.2)
	_bed(soil, healthy_cell, "meadowbell", 0.8, 0.0)
	_bed(soil, bare_cell, "", 0.02, 0.0)
	var pests: Object = load("res://scripts/ecology/blight.gd").new()
	pests.set("soil", soil)
	var moths: Array = pests.get("moths")
	moths.append({"id": 1, "ix": moth_cell.x, "iz": moth_cell.y})
	var view := _view(ServiceField.new(), PathGraph.new(), CityDemand.new(), CausalLog.new())
	view.set("blight", pests)
	view.call("set_channel", "blight")
	t.expect(is_equal_approx(float(view.call("sample", moth_cell)), occupied), "a moth cell samples full pressure")
	t.expect(is_equal_approx(float(view.call("painted_amount", moth_cell)), occupied), "a moth cell paints full pressure")
	t.expect(is_equal_approx(float(view.call("painted_amount", dry_cell)), neglected), "a dry bed paints the neglected pressure")
	t.expect(is_equal_approx(float(view.call("painted_amount", wilt_cell)), neglected), "a wilted bed paints the neglected pressure")
	t.expect(is_equal_approx(float(view.call("painted_amount", healthy_cell)), 0.0), "a watered bed has no blight pressure")
	t.expect(is_equal_approx(float(view.call("painted_amount", bare_cell)), 0.0), "a bare bed has no blight pressure")


func _bars(t: PetalAssert) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/overlays.json"))
	var empty := "No demand change has been recorded."
	var colors := {}
	if typeof(parsed) == TYPE_DICTIONARY:
		var root: Dictionary = parsed
		empty = str(root.get("empty_reason", empty))
		for item in root.get("bars", []):
			if typeof(item) == TYPE_DICTIONARY:
				var spec: Dictionary = item
				colors[str(spec.get("id", ""))] = str(spec.get("color", ""))
	var quiet := CityDemand.new()
	var quiet_log := CausalLog.new()
	var quiet_view := _view(ServiceField.new(), PathGraph.new(), quiet, quiet_log)
	for kind in ["bloom", "hive", "market"]:
		t.expect(int(quiet_view.call("bar_value", kind)) == 0, "%s starts at zero" % kind)
		t.expect(str(quiet_view.call("bar_reason", kind)) == empty, "%s tooltip uses the empty reason" % kind)
		t.expect(str(quiet_view.call("readout_text", kind)) == "0", "%s readout starts at zero" % kind)
	var causal := CausalLog.new()
	var demand := CityDemand.new()
	demand.setup(ServiceField.new(), causal, null, null)
	demand.reseed(1)
	var view := _view(ServiceField.new(), PathGraph.new(), demand, causal)
	demand.recompute({
		"resident_total": 4,
		"free_beds": 20,
		"quality_mean": 0.5,
		"coins": 40,
		"stall_stock": 2,
		"footfall": 0,
	})
	view.call("refresh")
	t.expect(demand.bloom != 0 or demand.hive != 0 or demand.market != 0, "the fixture moves demand off zero")
	for kind in ["bloom", "hive", "market"]:
		var value := int(demand.get(kind))
		t.expect(int(view.call("bar_value", kind)) == value, "%s bar tracks CityDemand" % kind)
		t.expect(str(view.call("readout_text", kind)) == str(value), "%s readout shows the demand value" % kind)
		t.expect(str(view.call("bar_reason", kind)) == _cause(causal, kind), "%s tooltip is the latest causal reason" % kind)
		if colors.has(kind):
			var got: Color = view.call("bar_color", kind) as Color
			t.expect(got == Color(str(colors[kind])), "%s bar uses its data colour" % kind)
	var first_bloom := int(view.call("bar_value", "bloom"))
	var first_reason := str(view.call("bar_reason", "hive"))
	demand.recompute({
		"resident_total": 0,
		"free_beds": 100,
		"quality_mean": 0.0,
		"coins": 0,
		"stall_stock": 0,
		"footfall": 0,
	})
	view.call("refresh")
	for kind in ["bloom", "hive", "market"]:
		t.expect(int(view.call("bar_value", kind)) == int(demand.get(kind)), "%s bar follows the next recompute" % kind)
		t.expect(str(view.call("bar_reason", kind)) == _cause(causal, kind), "%s tooltip follows the latest reason" % kind)
	t.expect(int(view.call("bar_value", "bloom")) != first_bloom, "the bloom bar moves when demand moves")
	t.expect(str(view.call("bar_reason", "hive")) != first_reason, "the hive tooltip changes with the new reason")


func _garden(t: PetalAssert) -> void:
	var packed: PackedScene = load("res://scenes/garden.tscn")
	t.expect(packed != null, "garden scene loads for the map overlay")
	if packed == null:
		return
	var garden: Node = packed.instantiate()
	root.add_child(garden)
	await process_frame
	var view: Object = garden.get("overlays")
	var field: ServiceField = garden.get("services") as ServiceField
	var demand: CityDemand = garden.get("city") as CityDemand
	t.expect(view != null, "the garden owns the map overlay")
	t.expect(field != null, "the garden owns the service field")
	t.expect(demand != null, "the garden owns city demand")
	if view == null or field == null or demand == null:
		garden.queue_free()
		await process_frame
		return
	var origin := Vector2i(4, 3)
	field.stamp("hive", origin, 4.0, 1.0)
	view.call("set_channel", "pollination")
	var mismatch := false
	for x in field.width:
		for z in field.height:
			var cell := Vector2i(x, z)
			if not is_equal_approx(float(view.call("painted_amount", cell)), field.sample(cell, "pollination")):
				mismatch = true
	t.expect(not mismatch, "the loaded garden overlay matches ServiceField")
	t.expect(float(view.call("painted_amount", origin)) > 0.0, "the loaded garden paints the hive")
	var causal := demand.log
	t.expect(causal != null, "the loaded garden demand keeps a causal log")
	if causal == null:
		garden.queue_free()
		await process_frame
		return
	demand.recompute({
		"resident_total": 4,
		"free_beds": 20,
		"quality_mean": 0.5,
		"coins": 40,
		"stall_stock": 2,
		"footfall": 0,
	})
	view.call("refresh")
	t.expect(int(view.call("bar_value", "bloom")) == demand.bloom, "the loaded garden bloom bar tracks CityDemand")
	t.expect(int(view.call("bar_value", "hive")) == demand.hive, "the loaded garden hive bar tracks CityDemand")
	t.expect(int(view.call("bar_value", "market")) == demand.market, "the loaded garden market bar tracks CityDemand")
	t.expect(str(view.call("bar_reason", "market")) == _cause(causal, "market"), "the loaded garden market tooltip uses the causal log")
	view.call("cycle")
	t.expect(str(view.call("channel_id")) == "light", "the loaded garden cycles off pollination")
	garden.queue_free()
	await process_frame


func _view(field: ServiceField, walk: PathGraph, demand: CityDemand, causal: CausalLog) -> Object:
	var script: Script = load("res://scripts/ui/overlays.gd")
	var view: Object = script.new()
	view.call("bind", field, walk, demand, causal, null)
	return view


func _bed(soil: Object, cell: Vector2i, plant_id: String, moisture: float, wilt: float) -> void:
	var plot: Object = soil.call("get_cell", cell.x, cell.y)
	plot.set("plant_id", plant_id)
	plot.set("moisture", moisture)
	plot.set("wilt", wilt)


func _cause(causal: CausalLog, kind: String) -> String:
	var tail: Array = causal.for_target(StringName(kind))
	if tail.is_empty():
		return ""
	var entry: Variant = tail[tail.size() - 1]
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	return str((entry as Dictionary).get("cause", ""))

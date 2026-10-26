extends SceneTree

## Grok Town: the square beyond the hedge, fitted door steps, and the corner map.

const PA := preload("res://tests/support/petal_assert.gd")

var errors: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	OS.add_logger(ErrorSink.new(self))
	call_deferred("_boot")


func _boot() -> void:
	var t: PetalAssert = PA.new("grok_town")
	var town := GrokTown.new()
	town.setup()
	_layout(t, town)
	town.free()
	var packed: PackedScene = load("res://scenes/garden.tscn")
	var garden: Node = packed.instantiate()
	root.add_child(garden)
	for _i in 4:
		await process_frame
	await _visit(t, garden)
	garden.queue_free()
	await process_frame
	var bad := 0
	for row in errors:
		if row.find("Parse Error") != -1 or row.find("previously freed") != -1 or row.find("Invalid call") != -1 or row.find("Invalid access") != -1:
			bad += 1
			print("ERR ", row)
	t.expect(bad == 0, "no script errors during the town checks")
	t.done()


func _layout(t: PetalAssert, town: GrokTown) -> void:
	t.expect(town.piece_count() == 94, "the court plants 94 beds, flowers and path tiles (got %d)" % town.piece_count())
	t.expect(town.planter_total == 2, "the town hall has two planters")
	t.expect(is_equal_approx(town.gate_yaw_deg, 0.0), "the parish gate is turned to face the hedge road")
	t.expect(town.gate_faces == "parish", "the gate faces the parish")
	t.expect(town.stall_gap() < 0.05, "the market stalls sit against the hall gable (gap %.3f)" % town.stall_gap())
	t.expect(town.civic_ids.size() == 4, "four civic buildings stand in the square")
	t.expect(town.door_color("lane_post").is_equal_approx(Color("#8c2f2a")), "the lane post door is red")
	var wide := 0
	for id in town.civic_ids:
		t.expect(town.step_fits(id), "%s steps meet the door" % id)
		var old_w := town.old_step_width(id)
		if old_w > town.step_width(id) + 0.4:
			wide += 1
			t.expect(town.step_width(id) < old_w, "%s no longer uses the wide step" % id)
	t.expect(wide == 2, "the two wide front steps were the ones refitted")
	var lines := town.card_lines()
	t.expect(lines.size() >= 6, "the town card names the square")
	var joined := " ".join(lines)
	t.expect(joined.find("steps meet the door") != -1, "the card says the steps meet the doors")
	t.expect(joined.find("Grove Park") == -1, "Grove Park stays off this card")


func _visit(t: PetalAssert, garden: Node) -> void:
	var live := garden.get("town") as GrokTown
	var hud: Node = garden.get("hud")
	var camera: Node = garden.get("camera")
	t.expect(live != null and hud.get("town_map") != null, "the garden shows the town map")
	t.expect(not (hud.get("town_card") as Control).visible, "the town card starts closed")
	var home: Vector3 = camera.get("target")
	var before := live.marker_uv(home)
	garden.call("toggle_town")
	await process_frame
	t.expect((hud.get("town_card") as Control).visible, "C opens the town card")
	t.expect(bool(garden.get("town_seen")), "a visit is remembered")
	var looked: Vector3 = camera.get("target")
	t.expect(looked.distance_to(live.focus_point()) < 1.0, "C looks at the square")
	var there := live.marker_uv(looked)
	t.expect(before.distance_to(there) > 0.05, "the map dot follows the camera into town")
	var state: Dictionary = garden.call("to_state")
	t.expect(bool(state.get("town_seen", false)), "the save remembers the visit")
	garden.set("town_seen", false)
	garden.call("apply_state", state)
	t.expect(bool(garden.get("town_seen")), "load keeps the visit")
	garden.call("toggle_town")
	await process_frame
	t.expect(not (hud.get("town_card") as Control).visible, "C again closes the card")
	var back: Vector3 = camera.get("target")
	var home_again: Vector3 = camera.get("home_target")
	t.expect(back.distance_to(home_again) < 0.2, "C again returns to the garden")
	garden.call("toggle_town")
	await process_frame
	garden.call("_esc")
	await process_frame
	t.expect(not (hud.get("town_card") as Control).visible, "Esc closes the town card before pausing")
	t.expect(not bool(garden.get("town_open")), "Esc leaves the town view")
	t.expect(not paused, "closing the town card does not pause")
	var place: Dictionary = garden.call("_place_stats", garden.call("world_snapshot"))
	var saw_town := false
	var saw_unbuilt := false
	for line_v in place.get("venues", []):
		var line := str(line_v)
		if line.find("Grok Town") != -1 and line.find("open") != -1:
			saw_town = true
		if line.find("not built") != -1:
			saw_unbuilt = true
	t.expect(saw_town, "the parish page lists Grok Town as open")
	t.expect(saw_unbuilt, "Grove Park stays unbuilt")


class ErrorSink:
	extends Logger
	var host: SceneTree

	func _init(tree: SceneTree) -> void:
		host = tree

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
		host.errors.append("%s:%d %s %s" % [file, line, code, rationale])

	func _log_message(message: String, error: bool) -> void:
		if error:
			host.errors.append(message)

extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")

var errors: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var capture := ErrorSink.new(self)
	OS.add_logger(capture)
	call_deferred("_boot")


func _boot() -> void:
	var t: PetalAssert = PA.new("garden_scene")
	var script: Script = load("res://scripts/game/garden.gd")
	t.expect(script != null, "garden.gd compiles")
	var packed: PackedScene = load("res://scenes/garden.tscn")
	t.expect(packed != null, "garden scene loads")
	if packed == null or script == null:
		_fail_freed(t)
		t.done()
		return
	var garden: Node = packed.instantiate()
	t.expect(garden.get_script() != null, "garden scene keeps its script")
	if garden.get_script() == null:
		_fail_freed(t)
		t.done()
		return
	root.add_child(garden)
	t.expect(garden.paths.soil == garden.soil, "path graph keeps the soil field")
	t.expect(garden.paths.ecology == garden.ecology, "path graph keeps the ecology")
	for _i in 3:
		await process_frame
	var jelly: Jelly = garden.ecology.force_spawn("bellhelp")
	t.expect(jelly != null, "the garden can spawn a creature")
	if jelly != null:
		jelly.queue_free()
		await process_frame
		t.expect(not is_instance_valid(jelly), "a queued creature is freed on the next frame")
		garden._process(1.0)
		await process_frame
	var state: Dictionary = garden.to_state()
	garden.apply_state(state)
	garden._process(1.0)
	await process_frame
	t.expect(garden.get_script() != null, "garden script stays attached after a reload")
	_fail_freed(t)
	garden.queue_free()
	await process_frame
	t.done()


func _fail_freed(t: PetalAssert) -> void:
	var freed := 0
	for row in errors:
		if row.find("previously freed") != -1 or row.find("Parse Error") != -1 or row.find("Failed to load script") != -1:
			freed += 1
			print("ERR ", row)
	t.expect(freed == 0, "garden load and frames assign no freed instances")


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

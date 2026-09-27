extends SceneTree

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var packed: PackedScene = load("res://scenes/parish.tscn") as PackedScene
	if packed == null:
		push_error("parish scene missing")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	var grid: GridMap = main.get_node("GridMap")
	var pieces: int = main.get_node("Builder").structures.size()
	var cash: String = main.get_node("CanvasLayer/Top/Cash").text
	print("BOOT_CELLS ", grid.get_used_cells().size(), " PIECES ", pieces, " CASH ", cash)
	if grid.get_used_cells().size() != 0 or pieces != 15 or cash != "$10000":
		push_error("boot state is not the kit")
		quit(1)
		return
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F3
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	var used: int = grid.get_used_cells().size()
	cash = main.get_node("CanvasLayer/Top/Cash").text
	print("SAMPLE_CELLS ", used, " CASH ", cash)
	if used != 122 or cash != "$5860":
		push_error("F3 did not load the sample town")
		quit(1)
		return
	quit(0)

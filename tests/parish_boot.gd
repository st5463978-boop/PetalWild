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
	var used: int = grid.get_used_cells().size()
	var pieces: int = main.get_node("Builder").structures.size()
	print("PARISH_CELLS ", used, " PIECES ", pieces)
	if used != 123 or pieces != 16:
		push_error("parish town did not load")
		quit(1)
		return
	quit(0)

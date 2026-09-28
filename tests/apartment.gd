extends SceneTree

func _initialize() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var main := (load("res://scenes/parish.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var grid: GridMap = main.get_node("GridMap")
	var home := main.get_node("Apartment")
	grid.set_cell_item(Vector3i(2, 0, 3), 7, 0)
	if home.try_enter(Vector3(2, 0, 3)) == false:
		push_error("apartment building did not open")
		quit(1)
		return
	if home.try_enter(Vector3(0, 0, 0)):
		push_error("empty street opened an apartment")
		quit(1)
		return
	var outside = home.move_object("sit", Vector3(4, 0, 0))
	if outside == "":
		push_error("furniture left the room")
		quit(1)
		return
	var blocked = home.move_object("sit", Vector3(0, 0, 0.5))
	if blocked != "The jelly needs this space.":
		push_error("jelly pad was not kept: " + blocked)
		quit(1)
		return
	var moved = home.move_object("sit", Vector3(-1.0, 0, -0.4))
	if moved != "":
		push_error("legal move failed: " + moved)
		quit(1)
		return
	home.complete("sit")
	home.complete("kettle")
	if home.done.size() != 2:
		push_error("rituals did not stick")
		quit(1)
		return
	home.close_home()
	if not main.get_node("Builder").is_processing():
		push_error("street stayed paused")
		quit(1)
		return
	if not home.try_enter(Vector3(2, 0, 3)):
		push_error("reopen failed")
		quit(1)
		return
	if home.done.size() != 2:
		push_error("the day did not save")
		quit(1)
		return
	home.close_home()
	var library: MeshLibrary = grid.mesh_library
	if library.get_item_list().size() != 20 or library.get_item_mesh(15) == null or library.get_item_mesh(19) == null:
		push_error("civic buildings missing from the mesh library")
		quit(1)
		return
	grid.set_cell_item(Vector3i(4, 0, 3), 15, 0)
	grid.set_cell_item(Vector3i(6, 0, 3), 16, 0)
	if not home.try_enter(Vector3(4, 0, 3)):
		push_error("church did not open")
		quit(1)
		return
	if home.title.text != "Church":
		push_error("church title was " + home.title.text)
		quit(1)
		return
	home.complete("pew")
	if home.done.size() != 1:
		push_error("church ritual did not stick")
		quit(1)
		return
	home.close_home()
	if not home.try_enter(Vector3(6, 0, 3)):
		push_error("restaurant did not open")
		quit(1)
		return
	if home.title.text != "Restaurant":
		push_error("restaurant title was " + home.title.text)
		quit(1)
		return
	if home.done.size() != 0:
		push_error("restaurant shared the church day")
		quit(1)
		return
	print("APARTMENT_OK ", home.done.size())
	home.close_home()
	quit(0)

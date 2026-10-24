extends SceneTree
## Renders the VC art in the live garden. Needs a display (xvfb-run) and opengl3:
##   xvfb-run -a -s "-screen 0 1440x900x24" godot --path . --rendering-driver opengl3 --script res://tools/art_capture.gd
## PETAL_ART_SHOTS sets the output folder (default user://art_shots).

var out_dir := ""


func _initialize() -> void:
	out_dir = OS.get_environment("PETAL_ART_SHOTS")
	if out_dir == "":
		out_dir = "user://art_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var packed: PackedScene = load("res://scenes/garden.tscn")
	var garden: Node = packed.instantiate()
	root.add_child(garden)
	for _i in 6:
		await process_frame
	var settings: Node = root.get_node_or_null("/root/Settings")
	if settings != null:
		settings.set("reduce_motion", true)
	var clock: Node = root.get_node_or_null("/root/Clock")
	if clock != null:
		clock.call("set_hour", 15.3)
		clock.set("running", false)
	var ids: Array[String] = []
	var species: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/species.json"))
	for row_v in species:
		ids.append(str((row_v as Dictionary).get("id", "")))
	var lineup := Vector3(-3.4, 0.0, -6.2)
	var jellies: Array[Node3D] = []
	for i in ids.size():
		var jelly: Node3D = garden.ecology.force_spawn(ids[i])
		if jelly == null:
			continue
		jelly.set("reduce_motion", true)
		jelly.set("held", true)
		jellies.append(jelly)
	garden.ecology.blight.moths.append({"id": 901, "ix": 2, "iz": 5})
	garden.ecology.blight.moths.append({"id": 902, "ix": 7, "iz": 1})
	garden.garden_art.sync()
	garden.atmosphere.apply(15.3, str(clock.get("weather")) if clock != null else "clear", garden.camera)
	garden.camera.snap_home()
	if OS.get_environment("PETAL_ART_ONLY") != "species":
		await _hold(jellies, lineup, 1.0)
		await _shot("art_overview.png")
	# lineup shot: the meadow is tall, so everything but the creatures, terrain and lights is hidden for this frame
	var hidden: Array[Node3D] = []
	for child in garden.get_children():
		var spatial := child as Node3D
		if spatial == null or not spatial.visible or spatial is Light3D or spatial is Camera3D:
			continue
		if spatial.name in ["Creatures", "Terrain"]:
			continue
		spatial.visible = false
		hidden.append(spatial)
	var stand := Camera3D.new()
	stand.fov = 48.0
	garden.add_child(stand)
	stand.global_position = lineup + Vector3(0.0, 1.35, -3.3)
	stand.look_at(lineup + Vector3(0.0, 0.3, 0.0))
	stand.make_current()
	await _hold(jellies, lineup, 0.8)
	await _shot("art_species.png")
	garden.camera.make_current()
	stand.queue_free()
	for spatial in hidden:
		spatial.visible = true
	if OS.get_environment("PETAL_ART_ONLY") == "species":
		quit(0)
		return
	garden.camera.focus_on(Vector3(5.2, 0.2, 1.9), 5.5)
	await _hold(jellies, lineup, 0.8)
	await _shot("art_props.png")
	garden.overlays.set_channel("blight")
	garden.hud.toggle_journal()
	garden.refresh_panels()
	garden.camera.snap_home()
	await _hold(jellies, lineup, 0.8)
	await _shot("art_hud.png")
	print("ART_CAPTURE_OK")
	quit(0)


func _hold(jellies: Array[Node3D], lineup: Vector3, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		for i in jellies.size():
			var jelly := jellies[i]
			if not is_instance_valid(jelly):
				continue
			var at := lineup + Vector3(float(i % 5) * 0.95 - 1.9 + float(i / 5) * 0.47, 0.0, float(i / 5) * -0.55)
			at.y = GardenLayout.height_at(at.x, at.z)
			jelly.global_position = at
			jelly.set("vel", Vector3.ZERO)
			jelly.set("goal", at)
			jelly.set("hold_target", at)
			jelly.rotation.y = 0.0
		await process_frame
		left -= 1.0 / 60.0


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := out_dir.path_join(file)
	image.save_png(path)
	print("saved ", path)

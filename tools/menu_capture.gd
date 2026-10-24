extends SceneTree
## VC11 menu screenshots. Title panels, then the garden HUD, journal tabs, stall, pause, help and maps.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --script res://tools/menu_capture.gd
## PETAL_MENU_SHOTS sets the output folder (default user://menu_shots).
## PETAL_MENU_SIZE is WxH (default 1280x720). PETAL_MENU_PREFIX defaults to "vc11_".

var out_dir := ""
var prefix := "vc11_"
var tag := "1280x720"


func _initialize() -> void:
	out_dir = OS.get_environment("PETAL_MENU_SHOTS")
	if out_dir == "":
		out_dir = "user://menu_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	if OS.get_environment("PETAL_MENU_PREFIX") != "":
		prefix = OS.get_environment("PETAL_MENU_PREFIX")
	if OS.get_environment("PETAL_MENU_SIZE") != "":
		tag = OS.get_environment("PETAL_MENU_SIZE")
	call_deferred("_run")


func _run() -> void:
	var parts := tag.split("x")
	var size := Vector2i(int(parts[0]), int(parts[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	var settings: Node = root.get_node_or_null("/root/Settings")
	if settings != null:
		settings.set("reduce_motion", true)
	var title: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(title)
	await _frames(4)
	await _shot("title_new")
	for step in [["_show_continue", "title_continue"], ["_show_settings", "title_settings"], ["_show_licences", "title_licences"]]:
		title.call(step[0])
		await _frames(3)
		await _shot(step[1])
	if title.has_method("_show_controls"):
		title.call("_show_controls")
		await _frames(3)
		await _shot("title_controls")
	title.queue_free()
	await _frames(2)
	var garden: Node = (load("res://scenes/garden.tscn") as PackedScene).instantiate()
	root.add_child(garden)
	await _frames(8)
	var clock: Node = root.get_node_or_null("/root/Clock")
	clock.call("set_hour", 10.0)
	clock.set("running", false)
	garden.camera.snap_home()
	await _frames(4)
	await _shot("hud")
	var hud: Node = garden.hud
	for page in ["journal", "people", "trust", "place"]:
		garden.show_directory(page)
		await _frames(3)
		await _shot("journal_" + page)
	hud.journal.visible = false
	hud.toggle_shop()
	await _frames(3)
	await _shot("stall")
	hud.shop.visible = false
	_key(KEY_O)
	await _frames(3)
	await _shot("maps")
	garden.overlays.set_channel("")
	_key(KEY_8)
	await _frames(3)
	await _shot("district_tool")
	garden.set_tool("hands")
	hud.show_nessa()
	await _frames(3)
	await _shot("proposal")
	hud.proposal.visible = false
	if hud.has_method("toggle_help"):
		hud.call("toggle_help")
		await _frames(3)
		await _shot("help")
		hud.call("toggle_help")
	_key(KEY_ESCAPE)
	await _frames(3)
	await _shot("pause")
	_key(KEY_ESCAPE)
	await _frames(3)
	print("menu_capture: paused after second Esc = ", paused)
	paused = false
	quit(0)


func _key(code: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s/%s%s_%s.png" % [out_dir, prefix, name, tag]
	image.save_png(path)
	print("menu_capture: ", path, " ", image.get_size())

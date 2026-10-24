extends SceneTree

## Saves two frames of the live garden: a service overlay, and the demand bars.


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/garden.tscn")
	if packed == null:
		push_error("garden scene missing")
		quit(1)
		return
	var garden: Node = packed.instantiate()
	root.add_child(garden)
	garden.set("gossip_done", true)
	root.get_node("Clock").set("running", false)
	root.get_node("Settings").set("reduce_motion", true)
	for _i in 3:
		await process_frame
	var field: ServiceField = garden.get("services") as ServiceField
	var demand: CityDemand = garden.get("city") as CityDemand
	var view: Object = garden.get("overlays")
	var camera: Object = garden.get("camera")
	if field == null or demand == null or view == null or camera == null:
		push_error("garden city view missing")
		quit(1)
		return
	field.stamp("well", Vector2i(2, 2), 3.0, 1.0)
	field.stamp("compost", Vector2i(7, 4), 2.0, 1.0)
	field.stamp("hive", Vector2i(4, 3), 4.0, 1.0)
	field.stamp("lantern", Vector2i(8, 1), 3.0, 1.0)
	demand.recompute({
		"resident_total": 4,
		"free_beds": 20,
		"quality_mean": 0.5,
		"coins": 40,
		"stall_stock": 2,
		"footfall": 0,
	})
	view.call("set_channel", "moisture")
	camera.set("pitch", 68.0)
	camera.set("yaw", 176.0)
	camera.set("distance", 13.5)
	camera.set("target", GardenLayout.cell_center(4, 3))
	camera.set("user_moved", true)
	camera.set("intro", 1.0)
	for _i in 8:
		await process_frame
	await _shot("/opt/cursor/artifacts/screenshots/vc4_overlay_moisture.png", false)
	var rect: Rect2 = view.call("panel_rect")
	var region := Rect2i(int(rect.position.x) - 8, int(rect.position.y) - 8, int(rect.size.x) + 16, int(rect.size.y) + 16)
	await _shot("/opt/cursor/artifacts/screenshots/vc4_demand_bars.png", true, region)
	print("VC4_CAPTURE_OK")
	quit(0)


func _shot(path: String, crop: bool, region: Rect2i = Rect2i()) -> void:
	await RenderingServer.frame_post_draw
	var viewport := root.get_viewport()
	var image := viewport.get_texture().get_image()
	if crop and region.size.x > 0 and region.size.y > 0:
		var view_size := viewport.get_visible_rect().size
		var scaled := region
		if view_size.x > 1.0 and image.get_width() != int(view_size.x):
			var sx := float(image.get_width()) / view_size.x
			var sy := float(image.get_height()) / view_size.y
			scaled = Rect2i(
				int(float(region.position.x) * sx),
				int(float(region.position.y) * sy),
				int(float(region.size.x) * sx),
				int(float(region.size.y) * sy)
			)
		scaled = Rect2i(scaled.position, scaled.size).intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
		if scaled.size.x > 0 and scaled.size.y > 0:
			image = image.get_region(scaled)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := image.save_png(path)
	print("SHOT ", path, " ", err, " ", image.get_width(), "x", image.get_height())

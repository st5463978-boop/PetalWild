extends Node3D

const BASE_SCALE := 6.0

var mats: ParkMaterials
var world: ParkWorld
var cam: ParkCamera
var hud: ParkHud
var env_node: WorldEnvironment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var speed_mult := 0.0
var weather_override := "golden"


func _ready() -> void:
	ThemeKit.boot()
	_freeze_clock()
	mats = ParkMaterials.new()
	mats.load_all()
	world = ParkWorld.new()
	world.build(self, mats)
	cam = ParkCamera.new()
	cam.name = "ParkCamera"
	add_child(cam)
	cam.build()
	hud = ParkHud.new()
	add_child(hud)
	hud.build()
	_build_lights()
	_apply_look()
	if OS.get_environment("PETAL_PARK_SMOKE") == "1":
		print("PETAL_PARK_OK tiles=square cameras=ring,builder,pond,free weather=", weather_override)
		await get_tree().process_frame
		get_tree().quit()
		return
	if OS.get_environment("PETAL_PARK_SHOT") != "":
		await _shots()


func _freeze_clock() -> void:
	Clock.running = false
	Clock.minute = 16.5 * 60.0
	Clock.weather = "golden"
	weather_override = "golden"
	speed_mult = 0.0


func _build_lights() -> void:
	env_node = WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.22
	environment.ambient_light_sky_contribution = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.18
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.12
	environment.glow_enabled = true
	environment.glow_intensity = 0.38
	environment.glow_bloom = 0.03
	environment.fog_enabled = true
	environment.fog_light_color = Color("e8d7b0")
	environment.fog_density = 0.0018
	environment.fog_aerial_perspective = 0.32
	environment.fog_sky_affect = 0.18
	var soft := _soft_gpu()
	if not soft:
		environment.ssao_enabled = true
		environment.ssao_radius = 0.6
		environment.ssao_intensity = 1.8
		environment.ssil_enabled = true
		environment.ssil_radius = 3.0
		environment.ssil_intensity = 0.8
		environment.ssr_enabled = true
		environment.ssr_max_steps = 32
		environment.sdfgi_enabled = true
		environment.sdfgi_use_occlusion = true
		environment.sdfgi_min_cell_size = 0.2
		environment.sdfgi_cascades = 4
		environment.sdfgi_bounce_feedback = 0.4
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 0.008
		environment.volumetric_fog_albedo = Color("e3ca82")
		environment.volumetric_fog_anisotropy = 0.6
		environment.volumetric_fog_length = 48.0
		environment.volumetric_fog_ambient_inject = 0.35
	else:
		environment.ssao_enabled = false
		environment.glow_intensity = 0.28
	env_node.environment = environment
	add_child(env_node)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("f0d18a")
	sun.light_energy = 1.65 if soft else 1.85
	sun.light_angular_distance = 1.5
	sun.shadow_enabled = not soft
	sun.shadow_blur = 1.5
	sun.shadow_opacity = 0.72
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if soft else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.rotation_degrees = Vector3(-28, -38, 0)
	add_child(sun)

	fill = DirectionalLight3D.new()
	fill.light_color = Color("f3e0b4")
	fill.light_energy = 0.42
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-18, 125, 0)
	add_child(fill)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color("466177")
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.name = "Moon"
	add_child(moon)


func _soft_gpu() -> bool:
	var name := RenderingServer.get_video_adapter_name().to_lower()
	return name.find("llvmpipe") != -1 or name.find("software") != -1


func _apply_look() -> void:
	var hour := Clock.hour()
	var weather := weather_override
	if weather == "":
		weather = Clock.weather
	var day := smoothstep(5.0, 7.2, hour) * (1.0 - smoothstep(18.4, 20.6, hour))
	var golden := 1.0 - clampf(absf(hour - 16.5) / 2.2, 0.0, 1.0)
	if weather == "golden":
		golden = maxf(golden, 0.72)
	var night := 1.0 - day
	var elev := 12.0 + day * 38.0
	if weather == "golden":
		elev = 10.0 + golden * 18.0
	sun.rotation_degrees = Vector3(-elev, -45.0 - hour * 1.5, 0.0)
	sun.light_color = Color("f0d18a").lerp(Color("e0a24a"), golden * 0.4)
	if weather == "rain" or weather == "overcast":
		sun.light_energy = 0.7
	elif weather == "night" or night > 0.7:
		sun.light_energy = 0.16
	else:
		sun.light_energy = (1.55 if _soft_gpu() else 1.8) + golden * 0.18
	sky_mat.sky_top_color = Color("9eb8d0").lerp(Color("d9a45a"), golden * 0.45).lerp(Color("12272f"), night)
	sky_mat.sky_horizon_color = Color("f7deb1").lerp(Color("f3d7a4"), golden).lerp(Color("466177"), night)
	sky_mat.ground_horizon_color = Color("7a8440")
	sky_mat.ground_bottom_color = Color("4a5420")
	sky_mat.sun_angle_max = 28.0
	var environment := env_node.environment
	environment.fog_light_color = Color("f0d9a8") if weather == "golden" else Color("cfdbe1")
	environment.tonemap_exposure = 1.12 + golden * 0.1
	environment.ambient_light_energy = 1.05 + golden * 0.18
	var glow := 0.2 + golden * 1.4
	if hour < 8.0 or hour > 19.0:
		glow = 1.6
	for light in world.lanterns:
		light.light_energy = glow
	hud.set_clock(hour, weather)
	hud.set_speed(not Clock.running, Clock.scale)
	hud.set_camera(cam.mode_name())


func _process(_delta: float) -> void:
	_apply_look()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				cam.set_mode(ParkCamera.Mode.RING)
			KEY_F2:
				cam.set_mode(ParkCamera.Mode.BUILDER)
			KEY_F3:
				cam.set_mode(ParkCamera.Mode.POND_EDGE)
			KEY_F4:
				cam.set_mode(ParkCamera.Mode.FREE)
			KEY_C:
				cam.cycle()
			KEY_SPACE:
				_toggle_pause()
			KEY_1:
				_set_speed(1.0)
			KEY_2:
				_set_speed(2.0)
			KEY_3:
				_set_speed(4.0)
			KEY_O:
				cam.toggle_dof()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/main.tscn")
			KEY_P:
				_photo()
	cam.handle_input(event)


func _toggle_pause() -> void:
	if Clock.running:
		Clock.running = false
		speed_mult = 0.0
	else:
		_set_speed(1.0)


func _set_speed(mult: float) -> void:
	speed_mult = mult
	if mult <= 0.0:
		Clock.running = false
		return
	Clock.running = true
	Clock.scale = BASE_SCALE * mult


func _photo() -> void:
	var dir := "user://park_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir + "/park_%s.png" % cam.mode_name().replace(" ", "_").to_lower()
	img.save_png(path)
	print("PARK_PHOTO ", path)


func _shots() -> void:
	var out := OS.get_environment("PETAL_PARK_SHOT_DIR")
	if out == "":
		out = "/workspace/docs/screenshots/city-park"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	for lab in get_tree().get_nodes_in_group("park_debug_label"):
		lab.visible = false
	for mark in get_tree().get_nodes_in_group("park_marker_visual"):
		mark.visible = false
	if hud:
		hud.visible = false
	await get_tree().create_timer(1.8).timeout
	var modes: Array = [
		[ParkCamera.Mode.RING, "ring"],
		[ParkCamera.Mode.BUILDER, "builder"],
		[ParkCamera.Mode.POND_EDGE, "pond_edge"],
	]
	for item in modes:
		cam.set_mode(int(item[0]))
		cam.snap()
		await get_tree().create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/park_%s.png" % [out, str(item[1])]
		img.save_png(path)
		print("PARK_SHOT ", path)
	print("PETAL_PARK_SHOT_OK")
	get_tree().quit()

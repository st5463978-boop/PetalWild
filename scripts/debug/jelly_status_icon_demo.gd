extends Node3D

## Standalone neon status-icon desk. Placeholders sit still; the overlay is live.
## Keys: 1 email, 2 idea, 3 working, 4 happy, 5 interested, 6 locked, 7 none,
## C cycle, [ ] work intensity, Esc quit.
## PETAL_ICON_CAPTURE=1 writes shots, a frame strip, gif, and mp4 then quits.

const _CAPTURE_DIR := "/workspace/docs/screenshots/jelly_status_icons"
const _ARTIFACT_DIR := "/opt/cursor/artifacts/jelly_status_icons"

var _jellies: Array[Jelly] = []
var _cycle := true
var _cycle_t := 0.0
var _cycle_i := 0
var _kind_order: Array[String] = [
	JellyActivity.EMAIL,
	JellyActivity.IDEA,
	JellyActivity.WORKING,
	JellyActivity.ROMANCE_INTERESTED,
	JellyActivity.ROMANCE_LOCKED,
]
var _hud: Label
var _intensity := 1.0
var _camera: Camera3D

func _ready() -> void:
	_build_world()
	_spawn_jellies()
	_build_hud()
	if OS.get_environment("PETAL_ICON_CAPTURE") == "1":
		await _capture()
		get_tree().quit(0)


func _build_world() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("7eadd4")
	sky_mat.sky_horizon_color = Color("f2c7a0")
	sky_mat.ground_horizon_color = Color("d9c49a")
	sky_mat.ground_bottom_color = Color("4f7a38")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	var settings := get_node_or_null("/root/Settings")
	if settings != null and bool(settings.photosensitivity):
		env.glow_enabled = false
	env.glow_intensity = 0.48
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 0.85
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color("f3d7b4")
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_energy = 0.85
	sun.light_color = Color("fff1d2")
	sun.shadow_enabled = false
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 140.0, 0.0)
	fill.light_energy = 0.22
	fill.light_color = Color("9eb8e6")
	fill.shadow_enabled = false
	add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 10.0)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color("5c8a3e")
	grass.roughness = 0.92
	ground.material_override = grass
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 36.0
	_camera.near = 0.08
	_camera.far = 80.0
	_camera.current = true
	add_child(_camera)
	_aim(Vector3(0.0, 0.45, 0.0), 6.4)


func _aim(at: Vector3, distance: float) -> void:
	var yaw := 0.42
	var pitch := 0.52
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	_camera.global_position = at + offset
	_camera.look_at(at, Vector3.UP)


func _spawn_jellies() -> void:
	var defs: Array = [
		{"id": "mail", "name": "Post", "shape": "droplet", "deep": "#1d6db8", "lit": "#9fd6ff", "glow": "#5ec2ff", "eye": "#f4fbff", "radius": 0.34},
		{"id": "idea", "name": "Glim", "shape": "stacked", "deep": "#2f8f55", "lit": "#d5ffb0", "glow": "#b6ff6a", "eye": "#f4ffd2", "radius": 0.32},
		{"id": "work", "name": "Cog", "shape": "crown", "deep": "#1b8a86", "lit": "#b8fff4", "glow": "#5bffd4", "eye": "#e7fff8", "radius": 0.33},
		{"id": "crush", "name": "Pip", "shape": "lobes", "deep": "#c4457a", "lit": "#ffd0e8", "glow": "#ff7eb6", "eye": "#fff0f6", "radius": 0.34},
		{"id": "pair", "name": "Vee", "shape": "stacked", "deep": "#7a1f58", "lit": "#ffc4e4", "glow": "#ff5fa8", "eye": "#fff0f6", "radius": 0.33},
	]
	for i in defs.size():
		var jelly := Jelly.new()
		add_child(jelly)
		jelly.setup(defs[i])
		jelly.reduce_motion = true
		jelly.bound = false
		jelly.hop_wait = 99.0
		jelly.tier = 0
		jelly.vel = Vector3.ZERO
		jelly.global_position = Vector3(-2.2 + float(i) * 1.1, 0.0, 0.0)
		var to_cam := _camera.global_position - jelly.global_position
		to_cam.y = 0.0
		if to_cam.length() > 0.01:
			jelly.look_at(jelly.global_position + to_cam, Vector3.UP)
		var kind: String = _kind_order[i]
		jelly.force_activity(kind, 1.15 if kind == JellyActivity.WORKING else 1.0)
		_jellies.append(jelly)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18, 16)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.modulate = Color(0.95, 0.97, 0.9)
	layer.add_child(_hud)
	_refresh_hud()


func _refresh_hud() -> void:
	if _hud == null:
		return
	_hud.text = "Neon status icons  ·  1 email  2 idea  3 working  4 happy  5 interested  6 locked  7 none  C cycle  [ ] intensity %.2f" % _intensity


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_force_all(JellyActivity.EMAIL)
		KEY_2:
			_force_all(JellyActivity.IDEA)
		KEY_3:
			_force_all(JellyActivity.WORKING)
		KEY_4:
			_force_all(JellyActivity.HAPPY)
		KEY_5:
			_force_all(JellyActivity.ROMANCE_INTERESTED)
		KEY_6:
			_force_all(JellyActivity.ROMANCE_LOCKED)
		KEY_7:
			_force_all(JellyActivity.NONE)
		KEY_C:
			_cycle = not _cycle
		KEY_BRACKETLEFT:
			_intensity = clampf(_intensity - 0.25, 0.35, 2.2)
			_apply_intensity()
		KEY_BRACKETRIGHT:
			_intensity = clampf(_intensity + 0.25, 0.35, 2.2)
			_apply_intensity()
		KEY_ESCAPE:
			get_tree().quit()
	_refresh_hud()


func _force_all(kind: String) -> void:
	_cycle = false
	for jelly in _jellies:
		jelly.force_activity(kind, _intensity)


func _apply_intensity() -> void:
	for jelly in _jellies:
		if jelly.activity == JellyActivity.WORKING:
			jelly.work_intensity = _intensity
			if jelly.status_icon:
				jelly.status_icon.set_intensity(_intensity)
	_refresh_hud()


func _process(delta: float) -> void:
	if not _cycle or _jellies.is_empty():
		return
	_cycle_t += delta
	if _cycle_t < 2.4:
		return
	_cycle_t = 0.0
	_cycle_i = (_cycle_i + 1) % _kind_order.size()
	for i in _jellies.size():
		var kind: String = _kind_order[(i + _cycle_i) % _kind_order.size()]
		_jellies[i].force_activity(kind, _intensity)


func _capture() -> void:
	_cycle = false
	if _hud:
		_hud.visible = false
	DirAccess.make_dir_recursive_absolute(_CAPTURE_DIR)
	DirAccess.make_dir_recursive_absolute(_ARTIFACT_DIR)
	_restore_row()
	for i in _jellies.size():
		_jellies[i].force_activity(_kind_order[i], 1.15 if _kind_order[i] == JellyActivity.WORKING else 1.0)
	await _settle(0.55)
	_aim(Vector3(0.0, 0.5, 0.0), 6.2)
	_restore_row()
	for i in _jellies.size():
		_jellies[i].force_activity(_kind_order[i], 1.15 if _kind_order[i] == JellyActivity.WORKING else 1.0)
	await _settle(0.2)
	await _shot("lineup.png")
	if OS.get_environment("PETAL_ICON_ONLY") == "gear":
		await _record_kind(2, JellyActivity.WORKING, "gear", 0.55, 16)
		_ffmpeg("gear")
		print("PETAL_ICON_CAPTURE_OK")
		return
	await _record_kind(0, JellyActivity.EMAIL, "envelope", 0.85, 16)
	await _record_kind(1, JellyActivity.IDEA, "bulb", 0.7, 16)
	await _record_kind(2, JellyActivity.WORKING, "gear", 0.55, 16)
	await _record_heart()
	await _record_kind(3, JellyActivity.ROMANCE_INTERESTED, "heart_interested", 0.55, 16, 0.11)
	await _record_locked()
	_stitch_gifs()
	print("PETAL_ICON_CAPTURE_OK")


func _record_kind(index: int, kind: String, stem: String, hold: float, frames: int, step := 0.07) -> void:
	_solo(index)
	_jellies[index].force_activity(kind, 1.35 if kind == JellyActivity.WORKING else 1.0)
	await _settle(hold)
	var images: Array[Image] = []
	for i in frames:
		if kind == JellyActivity.WORKING:
			_jellies[index].work_intensity = 0.7 + 0.08 * float(i)
			if _jellies[index].status_icon:
				_jellies[index].status_icon.set_intensity(_jellies[index].work_intensity)
		await _settle(step)
		var img := await _grab()
		var path := "%s/%s_%02d.png" % [_CAPTURE_DIR, stem, i]
		img.save_png(path)
		images.append(img)
	_write_strip(images, "%s/%s_strip.png" % [_CAPTURE_DIR, stem])
	_write_strip(images, "%s/%s_strip.png" % [_ARTIFACT_DIR, stem])
	await _shot("%s.png" % stem)


func _record_heart() -> void:
	_solo(3)
	_jellies[3].force_activity(JellyActivity.HAPPY)
	await _settle(0.08)
	var images: Array[Image] = []
	for i in 18:
		await _settle(0.055)
		var img := await _grab()
		img.save_png("%s/heart_%02d.png" % [_CAPTURE_DIR, i])
		images.append(img)
		if i == 1:
			img.save_png("%s/heart.png" % _CAPTURE_DIR)
			img.save_png("%s/heart.png" % _ARTIFACT_DIR)
			print("SHOT heart.png ", img.get_width(), "x", img.get_height())
	_write_strip(images, "%s/heart_strip.png" % _CAPTURE_DIR)
	_write_strip(images, "%s/heart_strip.png" % _ARTIFACT_DIR)


func _record_locked() -> void:
	_solo(4)
	_jellies[4].force_activity(JellyActivity.ROMANCE_INTERESTED)
	await _settle(0.4)
	_jellies[4].force_activity(JellyActivity.ROMANCE_LOCKED)
	await _settle(0.05)
	var images: Array[Image] = []
	for i in 18:
		await _settle(0.055)
		var img := await _grab()
		img.save_png("%s/heart_locked_%02d.png" % [_CAPTURE_DIR, i])
		images.append(img)
		if i == 0:
			img.save_png("%s/heart_locked.png" % _CAPTURE_DIR)
			img.save_png("%s/heart_locked.png" % _ARTIFACT_DIR)
			print("SHOT heart_locked.png ", img.get_width(), "x", img.get_height())
	_write_strip(images, "%s/heart_locked_strip.png" % _CAPTURE_DIR)
	_write_strip(images, "%s/heart_locked_strip.png" % _ARTIFACT_DIR)


func _solo(index: int) -> void:
	for i in _jellies.size():
		if i == index:
			_jellies[i].tier = 0
			_jellies[i].global_position = Vector3(0.0, 0.0, 0.0)
		else:
			_jellies[i].tier = 3
			_jellies[i].force_activity(JellyActivity.NONE)
			if _jellies[i].status_icon:
				_jellies[i].status_icon.visible = false
			_jellies[i].global_position = Vector3(0.0, -25.0, 0.0)
	_aim(Vector3(0.0, 0.62, 0.0), 3.7)
	var face := _jellies[index]
	var to_cam := _camera.global_position - face.global_position
	to_cam.y = 0.0
	if to_cam.length() > 0.01:
		face.look_at(face.global_position + to_cam, Vector3.UP)


func _restore_row() -> void:
	for i in _jellies.size():
		_jellies[i].tier = 0
		_jellies[i].global_position = Vector3(-2.2 + float(i) * 1.1, 0.0, 0.0)
		if _jellies[i].status_icon:
			_jellies[i].status_icon.visible = true
		var to_cam := _camera.global_position - _jellies[i].global_position
		to_cam.y = 0.0
		if to_cam.length() > 0.01:
			_jellies[i].look_at(_jellies[i].global_position + to_cam, Vector3.UP)


func _write_strip(images: Array[Image], path: String) -> void:
	if images.is_empty():
		return
	var w := images[0].get_width()
	var h := images[0].get_height()
	var step := maxi(1, int(floor(float(images.size()) / 8.0)))
	var picked: Array[Image] = []
	var i := 0
	while i < images.size() and picked.size() < 8:
		picked.append(images[i])
		i += step
	if picked.is_empty():
		return
	var strip := Image.create(w * picked.size(), h, false, Image.FORMAT_RGBA8)
	for s in picked.size():
		strip.blit_rect(picked[s], Rect2i(0, 0, w, h), Vector2i(s * w, 0))
	strip.save_png(path)


func _stitch_gifs() -> void:
	for stem in ["envelope", "bulb", "gear", "heart", "heart_interested", "heart_locked"]:
		_ffmpeg(stem)


func _ffmpeg(stem: String) -> void:
	var src := "%s/%s_%%02d.png" % [_CAPTURE_DIR, stem]
	for dir in [_CAPTURE_DIR, _ARTIFACT_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)
		var gif := "%s/%s.gif" % [dir, stem]
		var mp4 := "%s/%s.mp4" % [dir, stem]
		OS.execute("ffmpeg", ["-y", "-framerate", "12", "-i", src, "-pix_fmt", "yuv420p", "-an", mp4], [], false, false)
		OS.execute("ffmpeg", ["-y", "-framerate", "12", "-i", src, "-vf", "palettegen=stats_mode=diff", "%s/%s_palette.png" % [dir, stem]], [], false, false)
		OS.execute("ffmpeg", ["-y", "-framerate", "12", "-i", src, "-i", "%s/%s_palette.png" % [dir, stem], "-lavfi", "paletteuse=dither=bayer", gif], [], false, false)


func _shot(name: String) -> void:
	var img := await _grab()
	img.save_png("%s/%s" % [_CAPTURE_DIR, name])
	img.save_png("%s/%s" % [_ARTIFACT_DIR, name])
	print("SHOT ", name, " ", img.get_width(), "x", img.get_height())


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

extends Node3D

const ACTOR := preload("res://art_preview/carrot_actor.gd")

var _shots_done := false


func _ready() -> void:
	_world()
	# Human is the scale stick. Folk stand about knee-high beside it.
	_spawn("res://assets/characters/human.glb", Vector3(-0.85, 0.0, 0.0), "", false, Color.WHITE, false)
	_spawn("res://assets/characters/carrot.glb", Vector3(0.15, 0.0, 0.12), "idle", false, Color(1.0, 0.96, 0.9), true)
	_spawn("res://assets/characters/tomato.glb", Vector3(0.62, 0.0, -0.02), "idle", false, Color(1.0, 0.94, 0.92), true)
	_spawn("res://assets/characters/leek.glb", Vector3(1.05, 0.0, 0.08), "walk", true, Color(0.96, 0.98, 0.9), true)
	_tag(Vector3(-0.85, 1.85, 0.0), "human")
	_tag(Vector3(0.15, 0.62, 0.12), "carrot")
	_tag(Vector3(0.62, 0.62, -0.02), "tomato")
	_tag(Vector3(1.05, 0.62, 0.08), "leek")
	if OS.get_environment("PETALWILD_ART_SHOT") != "":
		await _capture()
		get_tree().quit()


func _world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# Palette: sky #BFD9F2, sun #FFE2A8, foliage #6FAE45. Late morning.
	environment.background_color = Color(0.749, 0.851, 0.949)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.84, 0.78)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.886, 0.659)
	sun.light_energy = 1.45
	sun.rotation_degrees = Vector3(-42, 32, 0)
	sun.shadow_enabled = false
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.light_color = Color(0.749, 0.851, 0.949)
	fill.light_energy = 1.4
	fill.omni_range = 10.0
	fill.position = Vector3(-1.6, 2.2, -1.4)
	add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.435, 0.682, 0.271)
	gmat.roughness = 0.9
	ground.material_override = gmat
	add_child(ground)

	var cam := Camera3D.new()
	cam.name = "PreviewCam"
	# glTF face lands on -Z.
	cam.position = Vector3(0.15, 1.15, -3.15)
	cam.fov = 38.0
	cam.current = true
	add_child(cam)
	cam.look_at(Vector3(0.2, 0.72, 0.0), Vector3.UP)


func _spawn(path: String, at: Vector3, action: String, do_pace: bool, tint: Color, skin: bool) -> void:
	var actor := Node3D.new()
	actor.set_script(ACTOR)
	actor.position = at
	add_child(actor)
	actor.call("setup", path, action, do_pace, tint, skin)


func _tag(at: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 28
	label.position = at
	label.modulate = Color(0.12, 0.14, 0.18)
	label.outline_size = 4
	label.outline_modulate = Color(0.98, 0.95, 0.88)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _capture() -> void:
	if _shots_done:
		return
	_shots_done = true
	DirAccess.make_dir_recursive_absolute("/workspace/art/characters/previews")
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	_shot("/workspace/art/characters/previews/godot_lineup.png")
	var cam := get_node_or_null("PreviewCam") as Camera3D
	if cam != null:
		cam.position = Vector3(0.55, 0.42, -1.15)
		cam.look_at(Vector3(0.6, 0.2, 0.05), Vector3.UP)
		await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout
		_shot("/workspace/art/characters/previews/godot_folk.png")
		cam.position = Vector3(-0.15, 0.95, -1.7)
		cam.look_at(Vector3(-0.55, 0.85, 0.0), Vector3.UP)
		await get_tree().process_frame
		await get_tree().create_timer(0.25).timeout
		_shot("/workspace/art/characters/previews/godot_human.png")
	print("ART_PREVIEW_SHOT_OK")


func _shot(path: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path)
	print("wrote ", path)

extends Node3D

const ACTOR := preload("res://art_preview/carrot_actor.gd")
const GLB := "res://assets/characters/carrot.glb"

var _shots_done := false


func _ready() -> void:
	_world()
	_spawn(Vector3(-0.7, 0.0, 0.0), "idle", false)
	_spawn(Vector3(0.75, 0.0, 0.0), "walk", true)
	_labels()
	if OS.get_environment("PETALWILD_ART_SHOT") != "":
		await _capture()
		get_tree().quit()


func _world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.78, 0.88)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.7)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.78)
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-48, 38, 0)
	sun.shadow_enabled = false
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.light_color = Color(0.75, 0.86, 1.0)
	fill.light_energy = 1.8
	fill.omni_range = 8.0
	fill.position = Vector3(-2.2, 2.4, 2.0)
	add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.36, 0.56, 0.28)
	gmat.roughness = 0.9
	ground.material_override = gmat
	add_child(ground)

	var cam := Camera3D.new()
	cam.position = Vector3(1.55, 1.05, 2.35)
	cam.look_at(Vector3(0.05, 0.52, 0.0), Vector3.UP)
	cam.fov = 42.0
	cam.current = true
	cam.name = "PreviewCam"
	add_child(cam)


func _spawn(at: Vector3, action: String, pace: bool) -> void:
	var actor := Node3D.new()
	actor.set_script(ACTOR)
	actor.position = at
	add_child(actor)
	actor.call("setup", GLB, action, pace)


func _labels() -> void:
	_tag(Vector3(-0.7, 1.28, 0.0), "idle")
	_tag(Vector3(0.75, 1.28, 0.0), "walk")


func _tag(at: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.position = at
	label.modulate = Color(0.98, 0.95, 0.88)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _capture() -> void:
	if _shots_done:
		return
	_shots_done = true
	var dir := "res://art/characters/previews"
	DirAccess.make_dir_recursive_absolute("/workspace/art/characters/previews")
	await get_tree().process_frame
	await get_tree().create_timer(1.1).timeout
	_shot("/workspace/art/characters/previews/godot_pair.png")
	var cam := get_node_or_null("PreviewCam") as Camera3D
	if cam != null:
		cam.position = Vector3(0.15, 0.78, 1.15)
		cam.look_at(Vector3(-0.7, 0.68, 0.0), Vector3.UP)
		await get_tree().process_frame
		await get_tree().create_timer(0.25).timeout
		_shot("/workspace/art/characters/previews/godot_idle.png")
		cam.position = Vector3(1.55, 0.72, 1.35)
		cam.look_at(Vector3(0.75, 0.55, 0.0), Vector3.UP)
		await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout
		_shot("/workspace/art/characters/previews/godot_walk.png")
	print("ART_PREVIEW_SHOT_OK %s" % dir)


func _shot(path: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path)
	print("wrote ", path)

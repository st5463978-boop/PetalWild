extends Node3D

const MeshKit = preload("res://game/world/mesh_kit.gd")
const JellyShader = preload("res://game/shaders/jelly.gdshader")

var spec: Dictionary = {}
var velocity := Vector3.ZERO
var held := false
var impact := 0.0
var mood := "calm"
var fidelity := 1
var moving := false
var pivot: Node3D
var mouth: MeshInstance3D
var material: ShaderMaterial
var base_scale := Vector3.ONE
var clock := 0.0
var eyes: Array[Node3D] = []


func setup(entry: Dictionary) -> void:
	spec = entry
	pivot = Node3D.new()
	add_child(pivot)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = MeshKit.jelly(str(spec.get("shape", "pear")))
	material = ShaderMaterial.new()
	material.shader = JellyShader
	material.set_shader_parameter("deep_color", Color(str(spec.get("deep", "#88cc66"))))
	material.set_shader_parameter("shallow_color", Color(str(spec.get("shallow", "#eeffcc"))))
	mesh_instance.material_override = material
	pivot.add_child(mesh_instance)
	_face(Color(str(spec.get("eye", "#223322"))))
	if str(spec.get("shape", "")) == "botanical":
		_sprout()
	base_scale = _shape_scale(str(spec.get("shape", "")))
	pivot.scale = base_scale
	var label := Label3D.new()
	label.text = str(spec.get("name", ""))
	label.font_size = 28
	label.position = Vector3(0, 0.85, 0)
	label.modulate = Color(0.98, 0.96, 0.9)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visible = false
	label.name = "Name"
	add_child(label)


func set_mood(next: String) -> void:
	mood = next
	if mouth == null:
		return
	match mood:
		"happy", "bonded", "playful", "awed":
			mouth.scale = Vector3(0.18, 0.07, 0.05)
			mouth.position.y = -0.02
		"annoyed", "flee":
			mouth.scale = Vector3(0.16, 0.025, 0.04)
			mouth.position.y = -0.08
		"dizzy":
			mouth.scale = Vector3(0.1, 0.1, 0.04)
		_:
			mouth.scale = Vector3(0.12, 0.04, 0.04)
			mouth.position.y = -0.05


func set_fidelity(level: int) -> void:
	fidelity = level
	var label := get_node_or_null("Name")
	if label:
		label.visible = level <= 1


func animate(delta: float) -> void:
	clock += delta
	var hop := 0.0
	if moving and not held and fidelity <= 2:
		var rate := 7.0 if str(spec.get("locomotion", "")) == "charge" else 5.0
		hop = absf(sin(clock * rate))
	impact = lerpf(impact, 0.0, clampf(delta * 2.5, 0.0, 1.0))
	var squash := impact if fidelity == 0 else impact * 0.45
	var wobble := 0.05 if fidelity <= 1 else 0.015
	if material:
		material.set_shader_parameter("impact", squash)
		material.set_shader_parameter("wobble", wobble)
	var sx := base_scale.x * (1.0 + squash * 0.35 + hop * 0.06)
	var sy := base_scale.y * (1.0 - squash * 0.32 - hop * 0.08)
	pivot.scale = Vector3(sx, maxf(0.2, sy), base_scale.z * (1.0 + squash * 0.28))
	pivot.position.y = hop * 0.14
	if str(spec.get("locomotion", "")) == "roll" and moving and not held:
		pivot.rotate_z(delta * 4.0)
	if mood == "dizzy":
		pivot.rotation.z = sin(clock * 8.0) * 0.25
	elif not held:
		pivot.rotation.z = lerpf(pivot.rotation.z, 0.0, 0.1)


func launch(speed: Vector3) -> void:
	held = false
	velocity = speed
	impact = clampf(speed.length() / 6.0, 0.2, 1.0)
	if speed.length() > 4.0:
		set_mood("dizzy")
	elif speed.length() > 1.5:
		set_mood("annoyed")


func _face(eye_color: Color) -> void:
	for side in [-1.0, 1.0]:
		var white := _orb(0.075, Color(0.97, 0.94, 0.9), Vector3(0.11 * side, 0.08, 0.3))
		eyes.append(white)
		_orb(0.04, eye_color, Vector3(0.12 * side, 0.07, 0.35))
		_orb(0.02, Color(0.08, 0.06, 0.05), Vector3(0.13 * side, 0.06, 0.38))
		_orb(0.012, Color(1, 1, 1), Vector3(0.145 * side, 0.09, 0.39))
		var brow := _orb(0.03, Color(0.15, 0.1, 0.08), Vector3(0.11 * side, 0.16, 0.3))
		brow.scale = Vector3(1.8, 0.35, 0.4)
	mouth = _orb(0.05, Color(0.45, 0.12, 0.16), Vector3(0, -0.05, 0.34))
	mouth.scale = Vector3(1.6, 0.45, 0.4)
	var blush_color := Color(0.9, 0.35, 0.4)
	_orb(0.045, blush_color, Vector3(-0.18, -0.02, 0.28)).scale = Vector3(1.2, 0.7, 0.4)
	_orb(0.045, blush_color, Vector3(0.18, -0.02, 0.28)).scale = Vector3(1.2, 0.7, 0.4)


func _sprout() -> void:
	var stem := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.05
	mesh.height = 0.28
	stem.mesh = mesh
	stem.position = Vector3(0, 0.48, 0)
	stem.material_override = _plain(Color(0.25, 0.5, 0.18))
	pivot.add_child(stem)
	var leaf := MeshInstance3D.new()
	leaf.mesh = MeshKit.canopy()
	leaf.scale = Vector3(0.18, 0.1, 0.12)
	leaf.position = Vector3(0.08, 0.62, 0)
	leaf.material_override = _plain(Color(0.4, 0.7, 0.25))
	pivot.add_child(leaf)


func _orb(radius: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	node.position = pos
	node.material_override = _plain(color)
	pivot.add_child(node)
	return node


func _plain(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.45
	return mat


func _shape_scale(shape: String) -> Vector3:
	match shape:
		"long":
			return Vector3(0.55, 1.65, 0.55)
		"flat":
			return Vector3(1.4, 0.48, 1.2)
		"stacked":
			return Vector3(0.86, 1.2, 0.86)
		"droplet":
			return Vector3(0.9, 1.25, 0.9)
		"crown":
			return Vector3(1.05, 0.95, 1.05)
		"multi":
			return Vector3(1.15, 0.85, 1.05)
		"botanical":
			return Vector3(0.95, 1.05, 0.95)
		_:
			return Vector3(0.98, 1.12, 0.98)

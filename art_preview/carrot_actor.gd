extends Node3D

const JELLY_SHADER: Shader = preload("res://shaders/veg_jelly.gdshader")

@export var glb_path: String = "res://assets/characters/carrot.glb"
@export var action: String = "idle"
@export var deep_color: Color = Color(0.96, 0.38, 0.07)
@export var shallow_color: Color = Color(1.0, 0.74, 0.38)
@export var rim_color: Color = Color(1.0, 0.92, 0.7)
@export var pace: bool = false

var _prev: Vector3 = Vector3.ZERO
var _mats: Array[ShaderMaterial] = []
var _player: AnimationPlayer
var _clock: float = 0.0
var _home: Vector3 = Vector3.ZERO


func setup(path: String, next_action: String, do_pace: bool) -> void:
	glb_path = path
	action = next_action
	pace = do_pace
	_build()


func _ready() -> void:
	pass


func _build() -> void:
	if not FileAccess.file_exists(glb_path):
		push_error("Missing character glb at %s" % glb_path)
		return
	var packed: PackedScene = load(glb_path) as PackedScene
	if packed == null:
		push_error("Could not load %s" % glb_path)
		return
	var root: Node = packed.instantiate()
	add_child(root)
	_player = _find_anim(root)
	if _player != null:
		var clip := _pick_clip(action)
		if clip != "":
			_player.play(clip)
	_apply_jelly(root)
	_prev = global_position
	_home = global_position


func _process(delta: float) -> void:
	if pace:
		_clock += delta
		var x: float = _home.x + sin(_clock * 1.15) * 0.55
		var next: Vector3 = Vector3(x, global_position.y, _home.z)
		var heading: Vector3 = next - global_position
		global_position = next
		heading.y = 0.0
		if heading.length() > 0.002:
			look_at(global_position + heading, Vector3.UP)
	var vel: Vector3 = (global_position - _prev) / maxf(delta, 0.0001)
	_prev = global_position
	for mat in _mats:
		mat.set_shader_parameter("move_velocity", vel)


func _apply_jelly(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node
		if _is_jelly_mesh(mesh_node):
			var mat := ShaderMaterial.new()
			mat.shader = JELLY_SHADER
			mat.set_shader_parameter("deep_color", deep_color)
			mat.set_shader_parameter("shallow_color", shallow_color)
			mat.set_shader_parameter("rim_color", rim_color)
			mat.set_shader_parameter("wobble_amount", 0.012)
			var imported: Material = mesh_node.get_active_material(0)
			if imported is StandardMaterial3D:
				var std: StandardMaterial3D = imported
				if std.albedo_texture != null:
					mat.set_shader_parameter("albedo_tex", std.albedo_texture)
			mesh_node.material_override = mat
			_mats.append(mat)
	for child in node.get_children():
		_apply_jelly(child)


func _is_jelly_mesh(node: MeshInstance3D) -> bool:
	var n: String = node.name.to_lower()
	if "leaf" in n or "eye" in n or "face" in n or "mouth" in n or "cheek" in n:
		return false
	return "jelly" in n or "body" in n or "arm" in n or "leg" in n or n.begins_with("carrot")


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found: AnimationPlayer = _find_anim(child)
		if found != null:
			return found
	return null


func _pick_clip(wanted: String) -> String:
	if _player == null:
		return ""
	if _player.has_animation(wanted):
		return wanted
	for clip in _player.get_animation_list():
		var lower: String = String(clip).to_lower()
		if wanted in lower or lower.ends_with("/" + wanted):
			return clip
	if _player.get_animation_list().size() > 0:
		return _player.get_animation_list()[0]
	return ""

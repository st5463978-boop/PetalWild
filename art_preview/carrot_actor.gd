extends Node3D

const SKIN_SHADER: Shader = preload("res://shaders/veg_skin.gdshader")

@export var glb_path: String = "res://assets/characters/carrot.glb"
@export var action: String = "idle"
@export var skin_tint: Color = Color(1, 1, 1)
@export var pace: bool = false
@export var use_skin: bool = true

var _prev: Vector3 = Vector3.ZERO
var _player: AnimationPlayer
var _clock: float = 0.0
var _home: Vector3 = Vector3.ZERO


func setup(path: String, next_action: String, do_pace: bool, tint: Color = Color(1, 1, 1), skin: bool = true) -> void:
	glb_path = path
	action = next_action
	pace = do_pace
	skin_tint = tint
	use_skin = skin
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
	if _player != null and action != "":
		var clip := _pick_clip(action)
		if clip != "":
			_player.play(clip)
	if use_skin:
		_apply_skin(root)
	_prev = global_position
	_home = global_position


func _process(delta: float) -> void:
	if not pace:
		return
	_clock += delta
	var x: float = _home.x + sin(_clock * 1.15) * 0.35
	var next: Vector3 = Vector3(x, global_position.y, _home.z)
	var heading: Vector3 = next - global_position
	global_position = next
	heading.y = 0.0
	if heading.length() > 0.002:
		look_at(global_position + heading, Vector3.UP)
	_prev = global_position


func _apply_skin(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node
		if _is_skin_mesh(mesh_node):
			var mat := ShaderMaterial.new()
			mat.shader = SKIN_SHADER
			mat.set_shader_parameter("skin_tint", skin_tint)
			mat.set_shader_parameter("roughness", 0.42)
			mat.set_shader_parameter("sss_strength", 0.35)
			var imported: Material = mesh_node.get_active_material(0)
			if imported is StandardMaterial3D:
				var std: StandardMaterial3D = imported
				if std.albedo_texture != null:
					mat.set_shader_parameter("albedo_tex", std.albedo_texture)
			mesh_node.material_override = mat
	for child in node.get_children():
		_apply_skin(child)


func _is_skin_mesh(node: MeshInstance3D) -> bool:
	var n: String = node.name.to_lower()
	if "leaf" in n or "eye" in n or "face" in n or "mouth" in n or "cheek" in n:
		return false
	if "hat" in n or "can" in n or "rake" in n or "tine" in n or "straw" in n or "metal" in n:
		return false
	return "body" in n


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

class_name JellyStatusIcon
extends Node3D

## Billboarded neon status overlay. Bind it to any jelly (or a placeholder).
## Drive it with set_activity(EMAIL | IDEA | WORKING | HAPPY |
## ROMANCE_INTERESTED | ROMANCE_LOCKED | NONE).
## HAPPY is a one-shot. The two romance hearts loop. Interested→locked morphs
## in place and bursts mini hearts. Only one icon is visible.

const _SHADER := preload("res://shaders/jelly_status_icon.gdshader")

const _CORE_WIDTH := 0.018
const _HALO_WIDTH := 0.038

signal finished(kind: String)

var activity := JellyActivity.NONE
var work_intensity := 1.0
var host: Node3D
var host_height := 0.92

var _forced := false
var _face: Node3D
var _spin: Node3D
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _glow: MeshInstance3D
var _light: OmniLight3D
var _core_mat: ShaderMaterial
var _halo_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _meshes := {}
var _tween: Tween
var _alpha := 0.0
var _energy := 1.0
var _pop := 1.0
var _lift := 0.0
var _spin_angle := 0.0
var _flicker := 1.0
var _looping := false
var _reduce_motion := false
var _photosensitive := false
var _kind_playing := JellyActivity.NONE
var _bloom := 1.0
var _sparks: Array = []

func _ready() -> void:
	top_level = true
	process_priority = 10
	name = "StatusIcon"
	_build()
	visible = false
	if activity != JellyActivity.NONE:
		var pending := activity
		activity = JellyActivity.NONE
		_play(pending, true)


func bind(node: Node3D, height := 0.92) -> void:
	host = node
	host_height = height
	if node is Jelly:
		var jelly := node as Jelly
		host_height = jelly.radius * 2.7 + 0.28
		set_activity(jelly.activity, jelly.work_intensity)


func set_activity(kind: String, intensity := 1.0) -> void:
	if not JellyActivity.is_kind(kind):
		kind = JellyActivity.NONE
	work_intensity = maxf(intensity, 0.05)
	if kind == JellyActivity.HAPPY:
		_play(kind, true)
		return
	if kind == activity and _looping:
		return
	_play(kind, false)


func replay() -> void:
	_play(activity, true)


func set_intensity(intensity: float) -> void:
	work_intensity = maxf(intensity, 0.05)


func _build() -> void:
	_core_mat = _make_mat(3.6, 0)
	_halo_mat = _make_mat(1.05, 0)
	_glow_mat = _make_mat(1.35, 1)
	_face = Node3D.new()
	_face.name = "Face"
	add_child(_face)
	_spin = Node3D.new()
	_spin.name = "Spin"
	_face.add_child(_spin)
	_halo = _mesh_node("Halo", _halo_mat)
	_core = _mesh_node("Core", _core_mat)
	_glow = MeshInstance3D.new()
	_glow.name = "Bloom"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.72)
	_glow.mesh = quad
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position = Vector3(0, 0, 0.02)
	_face.add_child(_glow)
	_light = OmniLight3D.new()
	_light.name = "Wash"
	_light.omni_range = 1.05
	_light.omni_attenuation = 1.6
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.light_indirect_energy = 0.0
	add_child(_light)
	_meshes[JellyActivity.EMAIL] = [_stroke(_envelope(), _HALO_WIDTH), _stroke(_envelope(), _CORE_WIDTH)]
	_meshes[JellyActivity.IDEA] = [_stroke(_bulb(), _HALO_WIDTH), _stroke(_bulb(), _CORE_WIDTH)]
	_meshes[JellyActivity.WORKING] = [_stroke(_gear(), _HALO_WIDTH), _stroke(_gear(), _CORE_WIDTH)]
	var heart := [_stroke(_heart(), _HALO_WIDTH), _stroke(_heart(), _CORE_WIDTH)]
	_meshes[JellyActivity.HAPPY] = heart
	_meshes[JellyActivity.ROMANCE_INTERESTED] = heart
	_meshes[JellyActivity.ROMANCE_LOCKED] = heart


func _mesh_node(node_name: String, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(node)
	return node


func _make_mat(energy: float, glow_mode: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("neon_color", Color.WHITE)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("glow_mode", glow_mode)
	mat.render_priority = 2 if glow_mode == 0 else 1
	return mat


func _play(kind: String, restart: bool) -> void:
	if not is_inside_tree():
		activity = kind
		return
	if kind == activity and not restart and kind != JellyActivity.NONE:
		_kind_playing = kind
		_looping = kind != JellyActivity.HAPPY and kind != JellyActivity.NONE
		return
	var leaving := activity
	var morph := (
		leaving == JellyActivity.ROMANCE_INTERESTED
		and kind == JellyActivity.ROMANCE_LOCKED
		and _alpha > 0.05
	)
	_kill()
	activity = kind
	if kind == JellyActivity.NONE:
		if leaving == JellyActivity.NONE or _alpha <= 0.01:
			_idle()
			return
		_pop_out()
		return
	_kind_playing = kind
	visible = true
	if morph:
		_morph_to_locked()
		return
	_clear_sparks()
	_spin_angle = 0.0
	_spin.rotation.z = 0.0
	if leaving != JellyActivity.NONE and leaving != kind and _alpha > 0.05:
		_cross(kind)
	else:
		_lift = 0.0
		_apply_look(kind)
		_pop_in(kind)


func _apply_look(kind: String) -> void:
	var packed: Array = _meshes.get(kind, [null, null])
	_halo.mesh = packed[0]
	_core.mesh = packed[1]
	var color: Color = JellyActivity.color_of(kind)
	_core_mat.set_shader_parameter("neon_color", color)
	_halo_mat.set_shader_parameter("neon_color", Color(color, 0.45))
	_glow_mat.set_shader_parameter("neon_color", Color(color, 0.55))
	_light.light_color = color


func _pop_in(kind: String) -> void:
	_looping = false
	_alpha = 0.0
	_pop = 0.2
	_energy = 1.0
	_bloom = 1.0
	_flicker = 1.0
	var tw := _motion()
	match kind:
		JellyActivity.EMAIL:
			_pop = 0.15
			tw.tween_property(self, "_pop", 1.22, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(self, "_alpha", 1.0, 0.12)
			tw.tween_property(self, "_pop", 1.0, 0.1)
			tw.tween_callback(_pulse_loop)
		JellyActivity.IDEA:
			_energy = 2.6
			_pop = 0.7
			tw.tween_property(self, "_alpha", 1.0, 0.16)
			tw.parallel().tween_property(self, "_pop", 1.08, 0.16)
			tw.parallel().tween_property(self, "_energy", 1.0, 0.22)
			tw.tween_callback(_flicker_loop)
		JellyActivity.WORKING:
			_pop = 0.55
			tw.tween_property(self, "_pop", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(self, "_alpha", 1.0, 0.12)
			tw.tween_callback(_work_loop)
		JellyActivity.HAPPY:
			_beat()
		JellyActivity.ROMANCE_INTERESTED:
			_energy = 0.62
			_bloom = 0.58
			_pop = 0.78
			tw.tween_property(self, "_alpha", 1.0, 0.22)
			tw.parallel().tween_property(self, "_pop", 0.94, 0.22)
			tw.tween_callback(_interest_loop)
		JellyActivity.ROMANCE_LOCKED:
			_energy = 0.7
			_bloom = 1.0
			_pop = 0.55
			_spawn_burst()
			tw.tween_property(self, "_pop", 1.16, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(self, "_alpha", 1.0, 0.12)
			tw.parallel().tween_property(self, "_energy", 1.22, 0.2)
			tw.parallel().tween_property(self, "_bloom", 1.75, 0.2)
			tw.tween_property(self, "_pop", 1.0, 0.1)
			tw.tween_callback(_lock_loop)
		_:
			_idle()


func _cross(kind: String) -> void:
	var tw := _motion()
	tw.tween_property(self, "_alpha", 0.0, 0.12)
	tw.parallel().tween_property(self, "_pop", 0.45, 0.12)
	tw.tween_callback(_swap.bind(kind))


func _swap(kind: String) -> void:
	_lift = 0.0
	_apply_look(kind)
	_pop_in(kind)


func _pop_out() -> void:
	_looping = false
	var tw := _motion()
	if activity == JellyActivity.NONE and _kind_playing == JellyActivity.EMAIL:
		tw.tween_property(self, "_pop", 1.12, 0.08)
		tw.tween_property(self, "_pop", 0.15, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "_alpha", 0.0, 0.16)
	else:
		tw.tween_property(self, "_alpha", 0.0, 0.16)
		tw.parallel().tween_property(self, "_pop", 0.35, 0.16)
	tw.tween_callback(_idle)


func _pulse_loop() -> void:
	_looping = true
	if _reduce_motion:
		_pop = 1.0
		return
	var tw := _motion()
	tw.set_loops()
	tw.tween_property(self, "_pop", 1.09, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "_pop", 0.95, 0.7).set_trans(Tween.TRANS_SINE)


func _flicker_loop() -> void:
	_looping = true


func _work_loop() -> void:
	_looping = true


func _interest_loop() -> void:
	_looping = true
	_energy = 0.62
	_bloom = 0.58
	if _reduce_motion:
		_pop = 0.92
		return
	var tw := _motion()
	tw.set_loops()
	tw.tween_property(self, "_pop", 1.04, 1.15).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "_energy", 0.78, 1.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "_pop", 0.82, 1.15).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "_energy", 0.5, 1.15).set_trans(Tween.TRANS_SINE)


func _lock_loop() -> void:
	_looping = true
	_energy = 1.22
	_bloom = 1.75
	if _reduce_motion:
		_pop = 1.0
		return
	var tw := _motion()
	tw.set_loops()
	tw.tween_property(self, "_pop", 1.24, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_pop", 0.9, 0.07)
	tw.tween_property(self, "_pop", 1.34, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_pop", 1.0, 0.1)
	tw.tween_property(self, "_pop", 1.0, 0.14)


func _morph_to_locked() -> void:
	_looping = false
	_lift = 0.0
	_apply_look(JellyActivity.ROMANCE_LOCKED)
	_spawn_burst()
	var tw := _motion()
	tw.tween_property(self, "_energy", 1.22, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "_bloom", 1.75, 0.28)
	tw.parallel().tween_property(self, "_alpha", 1.0, 0.1)
	tw.parallel().tween_property(self, "_pop", 1.18, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_pop", 1.0, 0.1)
	tw.tween_callback(_lock_loop)


func _spawn_burst() -> void:
	_clear_sparks()
	if _reduce_motion or _photosensitive:
		return
	var packed: Array = _meshes.get(JellyActivity.HAPPY, [null, null])
	var mesh: ArrayMesh = packed[1]
	if mesh == null:
		return
	var color := JellyActivity.color_of(JellyActivity.ROMANCE_LOCKED)
	for i in 5:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		var mat := _make_mat(2.4, 0)
		mat.set_shader_parameter("neon_color", color)
		mat.set_shader_parameter("fade", 1.0)
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU * float(i) / 5.0 + 0.18
		node.position = Vector3(cos(ang) * 0.12, 0.04, 0.05)
		node.scale = Vector3.ONE * 0.28
		_face.add_child(node)
		_sparks.append({
			"node": node,
			"mat": mat,
			"vel": Vector3(cos(ang) * 0.7, 0.48 + 0.1 * float(i % 2), 0.0),
			"life": 0.58,
			"age": 0.0,
		})


func _tick_sparks(delta: float) -> void:
	if _sparks.is_empty():
		return
	var remain: Array = []
	for spark in _sparks:
		var node: MeshInstance3D = spark["node"]
		if not is_instance_valid(node):
			continue
		spark["age"] = float(spark["age"]) + delta
		var t := float(spark["age"]) / float(spark["life"])
		if t >= 1.0:
			node.queue_free()
			continue
		node.position += spark["vel"] * delta
		var vel: Vector3 = spark["vel"]
		vel.y += 0.4 * delta
		spark["vel"] = vel
		node.scale = Vector3.ONE * lerpf(0.22, 0.07, t)
		var mat: ShaderMaterial = spark["mat"]
		mat.set_shader_parameter("fade", 1.0 - t)
		remain.append(spark)
	_sparks = remain


func _clear_sparks() -> void:
	for spark in _sparks:
		var node: MeshInstance3D = spark["node"]
		if is_instance_valid(node):
			node.queue_free()
	_sparks.clear()


func _beat() -> void:
	_looping = false
	_alpha = 1.0
	_pop = 0.7
	_lift = 0.0
	var tw := _motion()
	tw.tween_property(self, "_pop", 1.28, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_pop", 0.9, 0.09)
	tw.tween_property(self, "_pop", 1.34, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_pop", 1.0, 0.12)
	tw.tween_property(self, "_lift", 0.46, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "_alpha", 0.0, 0.55)
	tw.tween_callback(_heart_done)


func _heart_done() -> void:
	var kind := JellyActivity.HAPPY
	_idle()
	finished.emit(kind)


func _idle() -> void:
	_kill()
	_looping = false
	_alpha = 0.0
	_pop = 1.0
	_lift = 0.0
	_energy = 1.0
	_bloom = 1.0
	_flicker = 1.0
	_spin_angle = 0.0
	_kind_playing = JellyActivity.NONE
	activity = JellyActivity.NONE
	visible = false
	_clear_sparks()
	_paint()


func _kill() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null


func _motion() -> Tween:
	_kill()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	return _tween


func _process(delta: float) -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		_photosensitive = bool(settings.photosensitivity)
		_reduce_motion = bool(settings.reduce_motion)
	_follow_host()
	_billboard()
	if activity == JellyActivity.WORKING and _looping:
		var speed := 2.15 * work_intensity
		if _reduce_motion:
			speed *= 0.35
		_spin_angle += delta * speed
		_spin.rotation.z = _spin_angle
	else:
		_spin.rotation.z = 0.0
	if activity == JellyActivity.IDEA and _looping and not _reduce_motion:
		var t := Time.get_ticks_msec() * 0.001
		_flicker = 0.82 + 0.18 * absf(sin(t * 7.4)) + 0.12 * absf(sin(t * 19.0))
	else:
		_flicker = 1.0
	_tick_sparks(delta)
	_paint()


func _follow_host() -> void:
	if host == null or not is_instance_valid(host):
		return
	if host is Jelly:
		var jelly := host as Jelly
		if jelly.tier >= 3:
			visible = false
		elif activity != JellyActivity.NONE or _alpha > 0.02:
			visible = true
	var height := host_height
	if host is Node3D:
		height *= maxf(host.scale.y, 0.55)
	global_position = host.global_position + Vector3(0.0, height + _lift, 0.0)
	if not host.is_visible_in_tree():
		visible = false


func _billboard() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var origin := global_position
	var to_cam := cam.global_position - origin
	if to_cam.length_squared() < 0.0001:
		return
	var up := Vector3.UP
	if absf(to_cam.normalized().dot(up)) > 0.94:
		up = cam.global_transform.basis.y
	_face.look_at(cam.global_position, up)
	var dist := to_cam.length()
	var keep := clampf(dist / 7.2, 1.0, 2.5)
	scale = Vector3.ONE * keep


func _paint() -> void:
	_face.scale = Vector3.ONE * maxf(_pop, 0.01)
	_glow.scale = Vector3.ONE * clampf(0.72 + 0.42 * _bloom, 0.72, 1.55)
	var fade := clampf(_alpha, 0.0, 1.0)
	var flash := _energy * _flicker
	_core_mat.set_shader_parameter("fade", fade)
	_core_mat.set_shader_parameter("energy", 2.8 * flash)
	_halo_mat.set_shader_parameter("fade", fade * 0.55)
	_halo_mat.set_shader_parameter("energy", 0.85 * flash)
	_glow_mat.set_shader_parameter("fade", fade * 0.28 * _bloom)
	_glow_mat.set_shader_parameter("energy", 1.15 * flash * _bloom)
	var wash := 0.0 if _photosensitive else 0.42 * fade * _bloom
	_light.light_energy = wash
	_light.omni_range = 1.05 + 0.38 * maxf(_bloom - 1.0, 0.0)
	_light.position = Vector3(0.0, -0.42, 0.0)
	_glow.visible = fade > 0.02
	if host != null and is_instance_valid(host):
		_light.global_position = host.global_position + Vector3(0.0, host_height * 0.62, 0.0)


func _stroke(paths: Array, width: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := width * 0.5
	for path in paths:
		var pts: PackedVector2Array = path
		if pts.size() < 2:
			continue
		var closed := pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.0008
		var count := pts.size() - 1
		for i in count:
			_seg(tool, pts[i], pts[i + 1], half)
		if closed:
			_disc(tool, pts[0], half, 7)
		else:
			_disc(tool, pts[0], half, 7)
			_disc(tool, pts[count], half, 7)
	tool.generate_normals()
	return tool.commit()


func _seg(tool: SurfaceTool, a: Vector2, b: Vector2, half: float) -> void:
	var delta := b - a
	if delta.length_squared() < 0.0000001:
		return
	var n := Vector2(-delta.y, delta.x).normalized() * half
	var a0 := Vector3(a.x + n.x, a.y + n.y, 0.0)
	var a1 := Vector3(a.x - n.x, a.y - n.y, 0.0)
	var b0 := Vector3(b.x + n.x, b.y + n.y, 0.0)
	var b1 := Vector3(b.x - n.x, b.y - n.y, 0.0)
	_tri(tool, a0, b0, b1)
	_tri(tool, a0, b1, a1)


func _disc(tool: SurfaceTool, c: Vector2, r: float, segs: int) -> void:
	var mid := Vector3(c.x, c.y, 0.0)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		_tri(
			tool,
			mid,
			Vector3(c.x + cos(a0) * r, c.y + sin(a0) * r, 0.0),
			Vector3(c.x + cos(a1) * r, c.y + sin(a1) * r, 0.0)
		)


func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


func _envelope() -> Array:
	var body := _round_rect(0.78, 0.5, 0.07, 5)
	var flap := PackedVector2Array([
		Vector2(-0.39, 0.25),
		Vector2(0.0, -0.04),
		Vector2(0.39, 0.25),
	])
	return [body, flap]


func _bulb() -> Array:
	var paths: Array = []
	paths.append(_arc(Vector2(0.0, 0.08), 0.2, -0.55, PI + 0.55, 18))
	var neck := PackedVector2Array([
		Vector2(-0.07, -0.12),
		Vector2(-0.08, -0.2),
		Vector2(0.08, -0.2),
		Vector2(0.07, -0.12),
	])
	paths.append(neck)
	paths.append(PackedVector2Array([Vector2(-0.09, -0.24), Vector2(0.09, -0.24)]))
	paths.append(PackedVector2Array([Vector2(-0.07, -0.29), Vector2(0.07, -0.29)]))
	for i in 7:
		var ang := -0.35 + float(i) * (PI + 0.7) / 6.0
		var inner := Vector2(cos(ang), sin(ang)) * 0.26 + Vector2(0.0, 0.08)
		var outer := Vector2(cos(ang), sin(ang)) * 0.36 + Vector2(0.0, 0.08)
		paths.append(PackedVector2Array([inner, outer]))
	return paths


func _gear() -> Array:
	# Ring + 8 rectangular teeth + hub hole. Sides of each tooth run
	# along the radius so they read as a cog, not sun rays.
	var r_ring := 0.168
	var tooth_h := 0.135
	var da := 0.24
	var teeth := 8
	var outline := PackedVector2Array()
	for i in teeth:
		var a := TAU * float(i) / float(teeth)
		var d := Vector2(cos(a), sin(a))
		var inner_a := Vector2(cos(a - da), sin(a - da)) * r_ring
		var inner_b := Vector2(cos(a + da), sin(a + da)) * r_ring
		outline.append(inner_a)
		outline.append(inner_a + d * tooth_h)
		outline.append(inner_b + d * tooth_h)
		outline.append(inner_b)
		var a_next := TAU * float(i + 1) / float(teeth)
		var ang0 := a + da
		var ang1 := a_next - da
		if ang1 < ang0:
			ang1 += TAU
		for s in 4:
			var t := float(s + 1) / 5.0
			var ang := lerpf(ang0, ang1, t)
			outline.append(Vector2(cos(ang), sin(ang)) * r_ring)
	outline.append(outline[0])
	return [outline, _arc(Vector2.ZERO, 0.078, 0.0, TAU, 18)]


func _heart() -> Array:
	var pts := PackedVector2Array()
	var steps := 36
	for i in steps + 1:
		var t := PI * 2.0 * float(i) / float(steps) + PI
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(x, y) * 0.0125 + Vector2(0.0, 0.02))
	return [pts]


func _round_rect(w: float, h: float, r: float, corner: int) -> PackedVector2Array:
	var hw := w * 0.5
	var hh := h * 0.5
	var pts := PackedVector2Array()
	var corners: Array = [
		[Vector2(hw - r, hh - r), 0.0],
		[Vector2(-hw + r, hh - r), PI * 0.5],
		[Vector2(-hw + r, -hh + r), PI],
		[Vector2(hw - r, -hh + r), PI * 1.5],
	]
	for entry in corners:
		var c: Vector2 = entry[0]
		var a0: float = entry[1]
		for i in corner + 1:
			var a := a0 + (PI * 0.5) * float(i) / float(corner)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
	pts.append(pts[0])
	return pts


func _arc(center: Vector2, radius: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := lerpf(a0, a1, t)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

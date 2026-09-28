class_name ParkCamera
extends Node3D

enum Mode { RING, BUILDER, POND_EDGE, FREE }

var mode: int = Mode.RING
var yaw := -0.42
var pitch := 0.58
var distance := 22.5
var pivot := Vector3(0.2, 0.7, -2.2)
var target_yaw := -0.42
var target_pitch := 0.58
var target_distance := 22.5
var target_pivot := Vector3(0.2, 0.7, -2.2)
var camera: Camera3D
var intro := 0.0
var dof_on := false
var _attrs: CameraAttributesPractical
var free_yaw := -0.62
var free_pitch := 0.18
var free_pos := Vector3(-8.0, 3.2, 10.0)


func build() -> void:
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.08
	camera.far = 280.0
	camera.current = true
	_attrs = CameraAttributesPractical.new()
	_attrs.dof_blur_far_enabled = false
	_attrs.dof_blur_far_distance = 22.0
	_attrs.dof_blur_far_transition = 14.0
	_attrs.dof_blur_amount = 0.08
	camera.attributes = _attrs
	add_child(camera)
	set_mode(Mode.RING)
	distance = 28.0
	pitch = 0.82
	intro = 0.0


func set_mode(next: int) -> void:
	mode = next
	intro = 1.0
	match mode:
		Mode.RING:
			target_yaw = -0.42
			target_pitch = 0.40
			target_distance = 27.0
			target_pivot = Vector3(0.2, 0.9, -3.0)
			camera.fov = 50.0
		Mode.BUILDER:
			target_yaw = 0.04
			target_pitch = 1.28
			target_distance = 24.0
			target_pivot = Vector3(0.0, 0.1, 0.15)
			camera.fov = 36.0
		Mode.POND_EDGE:
			target_yaw = 0.15
			target_pitch = 0.18
			target_distance = 5.2
			target_pivot = Vector3(0.5, 0.12, 1.2)
			camera.fov = 62.0
		Mode.FREE:
			free_pos = camera.global_position
			free_yaw = yaw
			free_pitch = pitch
			camera.fov = 55.0
	_apply_dof()


func snap() -> void:
	intro = 1.0
	yaw = target_yaw
	pitch = target_pitch
	distance = target_distance
	pivot = target_pivot


func cycle() -> void:
	set_mode((mode + 1) % 4)


func mode_name() -> String:
	match mode:
		Mode.RING:
			return "Ring orbit"
		Mode.BUILDER:
			return "Builder"
		Mode.POND_EDGE:
			return "Pond edge"
		_:
			return "Free cam"


func toggle_dof() -> void:
	dof_on = not dof_on
	_apply_dof()


func _apply_dof() -> void:
	if _attrs == null:
		return
	var on := dof_on or mode == Mode.POND_EDGE
	_attrs.dof_blur_far_enabled = on
	if mode == Mode.POND_EDGE:
		_attrs.dof_blur_far_distance = 9.0
		_attrs.dof_blur_amount = 0.1
	elif mode == Mode.RING:
		_attrs.dof_blur_far_distance = 26.0
		_attrs.dof_blur_amount = 0.07
	else:
		_attrs.dof_blur_far_enabled = dof_on
		_attrs.dof_blur_far_distance = 32.0


func _process(delta: float) -> void:
	if intro < 1.0:
		intro = minf(1.0, intro + delta * 0.32)
		var t := smoothstep(0.0, 1.0, intro)
		target_distance = lerpf(32.0, 27.0, t)
		target_pitch = lerpf(0.62, 0.40, t)
	if mode == Mode.FREE:
		_free_move(delta)
		return
	if mode == Mode.POND_EDGE:
		# Look down onto the near water so the surface fills the frame.
		camera.fov = 68.0
		camera.global_position = Vector3(0.15, 0.4, 3.72)
		camera.look_at(Vector3(0.7, -0.04, 1.35), Vector3.UP)
		return
	if mode == Mode.RING:
		# Slow Viva Piñata crawl while the player is idle.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not _wasd():
			target_yaw += delta * 0.045
	var blend := 1.0 - exp(-4.2 * delta)
	yaw = lerpf(yaw, target_yaw, blend)
	pitch = lerpf(pitch, target_pitch, blend)
	distance = lerpf(distance, target_distance, blend)
	pivot = pivot.lerp(target_pivot, blend)
	pitch = clampf(pitch, 0.08, 1.4)
	distance = clampf(distance, 2.8, 48.0)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var pos := pivot + offset
	if pos.y < 0.55:
		pos.y = 0.55
	camera.global_position = pos
	if camera.global_position.distance_squared_to(pivot) > 0.04:
		camera.look_at(pivot, Vector3.UP)
	_wasd_pan(delta)


func _wasd() -> bool:
	return Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)


func _wasd_pan(delta: float) -> void:
	if mode == Mode.FREE:
		return
	var look := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(look.z, 0.0, -look.x)
	var speed := 9.0 * clampf(distance / 14.0, 0.5, 2.2)
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move += look
	if Input.is_key_pressed(KEY_S):
		move -= look
	if Input.is_key_pressed(KEY_D):
		move += right
	if Input.is_key_pressed(KEY_A):
		move -= right
	if move != Vector3.ZERO:
		target_pivot += move.normalized() * speed * delta
		target_pivot.x = clampf(target_pivot.x, -16.0, 16.0)
		target_pivot.z = clampf(target_pivot.z, -16.0, 16.0)
	if Input.is_key_pressed(KEY_Q):
		target_yaw -= 1.1 * delta
	if Input.is_key_pressed(KEY_E):
		target_yaw += 1.1 * delta


func _free_move(delta: float) -> void:
	var basis_look := Basis.from_euler(Vector3(-free_pitch, free_yaw, 0.0))
	var forward := -basis_look.z
	var right := basis_look.x
	var speed := 8.0
	if Input.is_key_pressed(KEY_SHIFT):
		speed = 18.0
	if Input.is_key_pressed(KEY_W):
		free_pos += forward * speed * delta
	if Input.is_key_pressed(KEY_S):
		free_pos -= forward * speed * delta
	if Input.is_key_pressed(KEY_D):
		free_pos += right * speed * delta
	if Input.is_key_pressed(KEY_A):
		free_pos -= right * speed * delta
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		free_pos.y += speed * delta
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		free_pos.y -= speed * delta
	free_pos.y = maxf(free_pos.y, 0.4)
	camera.global_position = free_pos
	camera.rotation = Vector3(-free_pitch, free_yaw, 0.0)


func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if mode == Mode.FREE:
			free_yaw -= event.relative.x * 0.005
			free_pitch = clampf(free_pitch - event.relative.y * 0.004, -0.2, 1.3)
		else:
			target_yaw -= event.relative.x * 0.005
			target_pitch = clampf(target_pitch - event.relative.y * 0.0035, 0.08, 1.32)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		if mode != Mode.FREE:
			var look := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var right := Vector3(look.z, 0.0, -look.x)
			target_pivot += (-right * event.relative.x + look * event.relative.y) * 0.012 * distance * 0.12
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mode == Mode.FREE:
				free_pos += -camera.global_transform.basis.z * 0.8
			else:
				target_distance = clampf(target_distance * 0.9, 2.8, 48.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mode == Mode.FREE:
				free_pos -= -camera.global_transform.basis.z * 0.8
			else:
				target_distance = clampf(target_distance * 1.1, 2.8, 48.0)

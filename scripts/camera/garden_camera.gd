class_name GardenCamera
extends Camera3D

var yaw := 176.0
var pitch := 48.0
var distance := 13.0
var target := Vector3(-2.8, 0.55, -0.2)
var home_yaw := 176.0
var home_pitch := 48.0
var home_distance := 13.0
var home_target := Vector3(-2.8, 0.55, -0.2)
var user_moved := false
var intro := 0.0
var focus_blend := 1.0

func _ready() -> void:
	current = true
	fov = 40.0
	near = 0.08
	far = 220.0
	_apply()

func _process(delta: float) -> void:
	if not user_moved and intro < 1.0:
		intro = minf(1.0, intro + delta / 5.5)
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		user_moved = true
		intro = 1.0
		yaw -= event.relative.x * 0.22
		pitch = clampf(pitch - event.relative.y * 0.16, 8.0, 62.0)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		user_moved = true
		intro = 1.0
		_pan(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - 1.05, 7.0, 22.0)
			user_moved = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + 1.05, 7.0, 22.0)
			user_moved = true

func nudge(delta: float) -> void:
	var speed := 4.2 * delta * (distance / 13.0)
	var basis_now := global_transform.basis
	var right := basis_now.x
	var forward := -basis_now.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	if forward.length() > 0.01:
		forward = forward.normalized()
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_A):
		move -= right * speed
	if Input.is_key_pressed(KEY_D):
		move += right * speed
	if Input.is_key_pressed(KEY_W):
		move += forward * speed
	if Input.is_key_pressed(KEY_S):
		move -= forward * speed
	if Input.is_key_pressed(KEY_Q):
		yaw -= 28.0 * delta
		user_moved = true
	if Input.is_key_pressed(KEY_E):
		yaw += 28.0 * delta
		user_moved = true
	if move != Vector3.ZERO:
		target += move
		user_moved = true

func focus_on(point: Vector3, next_distance: float) -> void:
	target = point + Vector3(0, 0.4, 0)
	distance = next_distance
	user_moved = true
	intro = 1.0

func snap_home() -> void:
	yaw = home_yaw
	pitch = home_pitch
	distance = home_distance
	target = home_target
	intro = 1.0
	user_moved = true
	_apply()

func _pan(relative: Vector2) -> void:
	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	target += (-right.normalized() * relative.x + forward.normalized() * relative.y) * 0.012 * distance * 0.18

func _apply() -> void:
	var shown_pitch := home_pitch
	var shown_yaw := home_yaw - 8.0
	var shown_distance := clampf(home_distance + 3.0, 7.0, 22.0)
	var shown_target := home_target
	var k := smoothstep(0.0, 1.0, intro)
	var use_pitch := lerpf(shown_pitch, pitch, k)
	var use_yaw := lerpf(shown_yaw, yaw, k)
	var use_distance := lerpf(shown_distance, distance, k)
	var use_target := shown_target.lerp(target, k)
	var offset := Vector3(
		sin(deg_to_rad(use_yaw)) * cos(deg_to_rad(use_pitch)),
		sin(deg_to_rad(use_pitch)),
		cos(deg_to_rad(use_yaw)) * cos(deg_to_rad(use_pitch))
	) * use_distance
	var position := use_target + offset
	var ground := GardenLayout.height_at(position.x, position.z) + 0.45
	if position.y < ground:
		position.y = ground
	global_position = position
	look_at(use_target, Vector3.UP)

extends Node3D

var yaw := -0.45
var pitch := 0.62
var distance := 18.0
var focus := Vector3.ZERO
var want_distance := 18.0
var want_focus := Vector3.ZERO
var spinning := false
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 36.0
	camera.current = true
	add_child(camera)


func play_pose() -> void:
	spinning = false
	want_distance = 15.5
	pitch = 0.66
	yaw = -0.35
	want_focus = Vector3(0, 0.4, 0.6)


func title_pose() -> void:
	spinning = true
	want_distance = 22.0
	pitch = 0.52
	want_focus = Vector3(0, 0.6, 0)


func focus_on(point: Vector3, close: float) -> void:
	spinning = false
	want_focus = point
	want_distance = close


func drag(dx: float, dy: float) -> void:
	spinning = false
	yaw -= dx * 0.005
	pitch = clampf(pitch - dy * 0.004, 0.18, 1.15)


func zoom(steps: float) -> void:
	want_distance = clampf(want_distance * (1.0 - steps * 0.08), 2.4, 34.0)


func pan(horizontal: float, vertical: float) -> void:
	spinning = false
	var look := Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()
	var right := Vector3(look.z, 0.0, -look.x)
	want_focus += right * horizontal + look * vertical
	focus = want_focus


func _process(delta: float) -> void:
	if spinning and not PetalWorld.reduce_motion:
		yaw += delta * 0.07
	var blend := 1.0 - exp(-3.2 * delta)
	focus = focus.lerp(want_focus, blend)
	distance = lerpf(distance, want_distance, blend)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var cam_pos := focus + offset
	if cam_pos.y < 0.45:
		cam_pos.y = 0.45
	camera.global_position = cam_pos
	if camera.global_position.distance_squared_to(focus) > 0.04:
		camera.look_at(focus, Vector3.UP)

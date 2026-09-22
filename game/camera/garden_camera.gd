extends Node3D

var yaw := 0.62
var pitch := 0.9
var distance := 19.0
var pivot := Vector3(2.2, 0.5, 2.8)
var target_pivot := Vector3(2.2, 0.5, 2.8)
var target_distance := 19.0
var target_pitch := 0.9
var camera: Camera3D
var dragging := false
var intro := 1.0
var blocked := false


func build() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.current = true
	add_child(camera)
	if not _reduce_motion():
		distance = 28.0
		pitch = 1.08
		intro = 0.0


func _process(delta: float) -> void:
	if blocked:
		return
	if intro < 1.0:
		intro = minf(1.0, intro + delta * 0.28)
		var t := smoothstep(0.0, 1.0, intro)
		target_distance = lerpf(28.0, 19.0, t)
		target_pitch = lerpf(1.08, 0.9, t)
	distance = lerpf(distance, target_distance, clampf(delta * 4.0, 0.0, 1.0))
	pitch = lerpf(pitch, target_pitch, clampf(delta * 4.0, 0.0, 1.0))
	pivot = pivot.lerp(target_pivot, clampf(delta * 4.0, 0.0, 1.0))
	pitch = clampf(pitch, 0.22, 1.15)
	distance = clampf(distance, 4.5, 32.0)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var pos := pivot + offset
	camera.global_position = pos
	camera.look_at(pivot, Vector3.UP)


func pan(right_amount: float, forward_amount: float, delta: float) -> void:
	var look := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(look.z, 0, -look.x)
	var speed := 8.0 * clampf(distance / 12.0, 0.6, 2.0)
	target_pivot += (right * right_amount + look * forward_amount) * speed * delta
	target_pivot.x = clampf(target_pivot.x, -18.0, 18.0)
	target_pivot.z = clampf(target_pivot.z, -14.0, 16.0)


func orbit(dx: float, dy: float) -> void:
	yaw -= dx * 0.005
	target_pitch = clampf(target_pitch - dy * 0.003, 0.25, 1.1)


func zoom(amount: float) -> void:
	target_distance = clampf(target_distance * (1.0 - amount), 4.5, 32.0)


func focus_on(point: Vector3) -> void:
	target_pivot = Vector3(point.x, 0.5, point.z)
	target_distance = minf(target_distance, 8.0)
	target_pitch = 0.42


func ground_ray(mouse: Vector2, plane_y: float) -> Vector3:
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return origin
	var t := (plane_y - origin.y) / dir.y
	if t < 0.0:
		return origin
	return origin + dir * t


func _reduce_motion() -> bool:
	return Session != null and bool(Session.reduce_motion)

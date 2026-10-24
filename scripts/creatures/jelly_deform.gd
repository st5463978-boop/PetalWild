class_name JellyDeform
extends RefCounted

## Damped stretch for one jelly.
## Original spring. It does not copy a tetrahedral soft-body solver.
## Grabbing, throwing, and walking stay on Jelly.

var axis := Vector3.UP
var stretch := 0.0
var stretch_rate := 0.0
var lag := Vector3.ZERO
var lag_rate := Vector3.ZERO
var impact := 0.0

const STIFFNESS := 28.0
const DAMPING := 7.5


func reset() -> void:
	axis = Vector3.UP
	stretch = 0.0
	stretch_rate = 0.0
	lag = Vector3.ZERO
	lag_rate = Vector3.ZERO
	impact = 0.0


func advance(delta: float, held: bool, pull: Vector3, landed: bool, motion: bool) -> void:
	if not motion or delta <= 0.0:
		reset()
		return
	if pull.length() > 0.08:
		axis = pull.normalized()
	var target := 0.0
	if held:
		target = clampf(pull.length() * 0.18, 0.0, 0.42)
	else:
		target = clampf(pull.length() * 0.015, 0.0, 0.1)
	if landed:
		impact = 1.0
		stretch_rate += 2.2
	var accel := (target - stretch) * STIFFNESS - stretch_rate * DAMPING
	stretch_rate += accel * delta
	stretch += stretch_rate * delta
	stretch = clampf(stretch, -0.08, 0.48)
	var lag_target := -axis * stretch * 0.06
	var lag_accel := (lag_target - lag) * 22.0 - lag_rate * 8.0
	lag_rate += lag_accel * delta
	lag += lag_rate * delta
	if lag.length() > 0.1:
		lag = lag.normalized() * 0.1
	impact = move_toward(impact, 0.0, delta * 2.4)


func release_flick(pull: Vector3) -> Vector3:
	# A fast pointer still owes the body a shove after the grip ends.
	if pull.length() < 0.2:
		return Vector3.ZERO
	var extra := pull * 0.55
	if extra.length() > 0.8:
		extra = extra.normalized() * 0.8
	return extra


func basis_for(direction: Vector3, amount: float) -> Basis:
	if direction.length() < 0.001 or absf(amount) < 0.001:
		return Basis.IDENTITY
	var ax := direction.normalized()
	var along := 1.0 + amount
	var side := clampf(1.0 - amount * 0.42, 0.65, 1.2)
	var diff := along - side
	return Basis(
		Vector3(side, 0.0, 0.0) + ax * ax.x * diff,
		Vector3(0.0, side, 0.0) + ax * ax.y * diff,
		Vector3(0.0, 0.0, side) + ax * ax.z * diff
	)

class_name JellyFeel
extends RefCounted

const GRAVITY := 14.0
const MAX_SPEED := 11.0
const HOLD_SPRING := 30.0
const HOLD_DAMP := 0.76
const RESTITUTION := 0.42
const AIR_DAMP := 0.996
const GROUND_FRICTION := 0.8
const STRETCH_GAIN := 0.42
const STRETCH_MAX := 0.7
const SQUASH_MIN := 0.52
const SQUASH_MAX := 1.22
const RECOVER_TIME := 0.4
const BOUNCE_MIN := 1.15
const THROW_FAST := 3.4
const THROW_HARD := 5.6
const DROP_SPEED := 1.5
const FLOOR_MIN := -0.35
const CEIL_Y := 6.4
const GARDEN_MIN := Vector3(-12.6, FLOOR_MIN, -9.2)
const GARDEN_MAX := Vector3(11.6, CEIL_Y, 7.2)

static func substeps(held: bool, airborne: bool, speed: float) -> int:
	if held or airborne or speed > 4.0:
		return 4
	if speed > 1.6:
		return 2
	return 1


static func clamp_vel(v: Vector3) -> Vector3:
	if not v.is_finite():
		return Vector3.ZERO
	var speed := v.length()
	if speed > MAX_SPEED and speed > 0.0001:
		return v * (MAX_SPEED / speed)
	return v


static func clamp_pos(p: Vector3, fallback: Vector3) -> Vector3:
	if not p.is_finite():
		return fallback
	return p.clamp(GARDEN_MIN, GARDEN_MAX)


static func hold_follow(pos: Vector3, target: Vector3, vel: Vector3, dt: float) -> Vector3:
	var pull := target - pos
	vel += pull * HOLD_SPRING * dt
	vel *= HOLD_DAMP
	return clamp_vel(vel)


static func fall(vel: Vector3, dt: float) -> Vector3:
	vel.y -= GRAVITY * dt
	vel.x *= AIR_DAMP
	vel.z *= AIR_DAMP
	return clamp_vel(vel)


static func land(pos: Vector3, vel: Vector3, floor_y: float) -> Dictionary:
	var hit := false
	var bounced := false
	var squash := 1.0
	var ripple := 0.0
	if pos.y < floor_y:
		hit = true
		var impact := absf(vel.y)
		pos.y = floor_y
		if impact > BOUNCE_MIN:
			squash = clampf(1.0 - impact * 0.075, SQUASH_MIN, 1.0)
			ripple = clampf(impact * 0.2, 0.0, 1.0)
			vel.y = impact * RESTITUTION
			bounced = vel.y > 1.05
		else:
			vel.y = 0.0
		vel.x *= GROUND_FRICTION
		vel.z *= GROUND_FRICTION
		vel = clamp_vel(vel)
	return {
		"pos": pos,
		"vel": vel,
		"squash": squash,
		"ripple": ripple,
		"hit": hit,
		"bounced": bounced,
	}


static func stretch_amount(pull_len: float, speed: float, held: bool) -> float:
	if held:
		return clampf(pull_len * STRETCH_GAIN, 0.0, STRETCH_MAX)
	return clampf(speed * 0.065, 0.0, 0.34)


static func body_scale(squash: float, stretch: float) -> Vector3:
	var sy := clampf(squash * (1.0 - stretch * 0.62), SQUASH_MIN, SQUASH_MAX)
	var sx := clampf(sqrt(1.0 / maxf(sy, 0.2)) * (1.0 + stretch * 0.28), 0.58, 1.8)
	return Vector3(sx, sy, sx)


static func release_kind(speed: float) -> String:
	if speed > THROW_FAST:
		return "throw"
	if speed > DROP_SPEED:
		return "drop"
	return "pet"


static func throw_from_samples(points: Array, times_ms: Array, spring_vel: Vector3) -> Vector3:
	if points.size() < 2 or times_ms.size() < 2:
		return clamp_vel(spring_vel)
	var span_ms := int(times_ms[times_ms.size() - 1]) - int(times_ms[0])
	var dt := float(span_ms) / 1000.0
	if dt < 0.018:
		return clamp_vel(spring_vel)
	var start: Vector3 = points[0]
	var last: Vector3 = points[points.size() - 1]
	var sampled: Vector3 = (last - start) / dt
	if sampled.length() >= spring_vel.length():
		return clamp_vel(sampled * 0.94)
	return clamp_vel(spring_vel)


static func separate(
	a_pos: Vector3,
	a_radius: float,
	a_vel: Vector3,
	a_held: bool,
	b_pos: Vector3,
	b_radius: float,
	b_vel: Vector3,
	b_held: bool
) -> Dictionary:
	var delta := Vector3(b_pos.x - a_pos.x, 0.0, b_pos.z - a_pos.z)
	var dist := delta.length()
	var need := a_radius + b_radius
	if need <= 0.001 or dist >= need:
		return {
			"a_pos": a_pos,
			"a_vel": a_vel,
			"b_pos": b_pos,
			"b_vel": b_vel,
			"hit": false,
		}
	if dist < 0.0008:
		delta = Vector3(0.08, 0.0, 0.03)
		dist = delta.length()
	var normal := delta / dist
	var overlap := need - dist
	if a_held and not b_held:
		b_pos += normal * overlap
	elif b_held and not a_held:
		a_pos -= normal * overlap
	else:
		a_pos -= normal * overlap * 0.5
		b_pos += normal * overlap * 0.5
	var closing := (b_vel.x - a_vel.x) * normal.x + (b_vel.z - a_vel.z) * normal.z
	if closing < 0.0:
		var bump := closing * 0.52
		if not a_held:
			a_vel += Vector3(normal.x * bump, 0.0, normal.z * bump)
		if not b_held:
			b_vel -= Vector3(normal.x * bump, 0.0, normal.z * bump)
	return {
		"a_pos": a_pos,
		"a_vel": clamp_vel(a_vel),
		"b_pos": b_pos,
		"b_vel": clamp_vel(b_vel),
		"hit": true,
	}


static func bounce_prop(pos: Vector3, vel: Vector3, radius: float, water_ok: bool) -> Dictionary:
	var hit := false
	for box in _props():
		var center: Vector3 = box[0]
		var half: Vector2 = box[1]
		var top: float = box[2]
		if pos.y > top + radius * 0.4:
			continue
		var dx := pos.x - center.x
		var dz := pos.z - center.z
		var px := half.x + radius
		var pz := half.y + radius
		if absf(dx) >= px or absf(dz) >= pz:
			continue
		hit = true
		var ox := px - absf(dx)
		var oz := pz - absf(dz)
		if ox < oz:
			var dir := 1.0 if dx >= 0.0 else -1.0
			pos.x = center.x + dir * px
			if vel.x * dir < 0.0:
				vel.x = -vel.x * RESTITUTION
		else:
			var dirz := 1.0 if dz >= 0.0 else -1.0
			pos.z = center.z + dirz * pz
			if vel.z * dirz < 0.0:
				vel.z = -vel.z * RESTITUTION
	if not water_ok:
		var pond := Vector2(pos.x - GardenLayout.POND_CENTER.x, pos.z - GardenLayout.POND_CENTER.z)
		var rim := GardenLayout.POND_RADIUS * 0.9 + radius
		if pond.length() < rim:
			hit = true
			var n := pond if pond.length() > 0.001 else Vector2(1.0, 0.0)
			n = n.normalized()
			pos.x = GardenLayout.POND_CENTER.x + n.x * rim
			pos.z = GardenLayout.POND_CENTER.z + n.y * rim
			var outward := Vector3(n.x, 0.0, n.y)
			var into := vel.x * outward.x + vel.z * outward.z
			if into < 0.0:
				vel -= outward * into * (1.0 + RESTITUTION)
	return {"pos": pos, "vel": clamp_vel(vel), "hit": hit}


static func _props() -> Array:
	return [
		[GardenLayout.STALL, Vector2(1.25, 0.55), 0.92],
		[GardenLayout.SHED, Vector2(1.25, 1.0), 1.75],
		[GardenLayout.TEA, Vector2(1.1, 0.95), 1.45],
		[GardenLayout.HUT, Vector2(1.05, 0.95), 1.45],
		[GardenLayout.FOUNDRY, Vector2(1.05, 0.95), 1.45],
		[GardenLayout.HALL, Vector2(0.72, 0.42), 1.15],
	]

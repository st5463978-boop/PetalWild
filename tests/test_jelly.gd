extends SceneTree

func _init() -> void:
	_scale()
	_release()
	_throw_samples()
	_land()
	_tunnel()
	_speed()
	_separate()
	_stall()
	print("JELLY_FEEL_OK")
	quit(0)

func _scale() -> void:
	var held := JellyFeel.body_scale(1.0, 0.5)
	_expect(held.y < held.x, "held stretch is wider than it is tall")
	var squat := JellyFeel.body_scale(0.6, 0.0)
	_expect(squat.y < 0.75 and squat.x > 1.0, "land squash is volume-preserving")
	_expect(JellyFeel.stretch_amount(1.2, 0.0, true) > 0.3, "a long pull stretches")
	_expect(JellyFeel.stretch_amount(0.0, 1.0, false) < 0.2, "a slow hop barely stretches")

func _release() -> void:
	_expect(JellyFeel.release_kind(0.4) == "pet", "a gentle let-go is a pet")
	_expect(JellyFeel.release_kind(2.0) == "drop", "a short toss is a drop")
	_expect(JellyFeel.release_kind(4.2) == "throw", "a fast flick is a throw")

func _throw_samples() -> void:
	var points: Array = [Vector3.ZERO, Vector3(2.0, 1.0, 0.0)]
	var times: Array = [0, 100]
	var thrown: Vector3 = JellyFeel.throw_from_samples(points, times, Vector3(0.2, 0.0, 0.0))
	_expect(thrown.x > 4.0, "sampled drag becomes throw speed")
	_expect(thrown.length() <= JellyFeel.MAX_SPEED + 0.01, "throw speed stays capped")

func _land() -> void:
	var landed: Dictionary = JellyFeel.land(Vector3(0.0, -0.2, 0.0), Vector3(1.0, -4.0, 0.0), 0.0)
	var pos: Vector3 = landed["pos"]
	var vel: Vector3 = landed["vel"]
	_expect(bool(landed["hit"]), "a below-floor step hits")
	_expect(pos.y >= 0.0, "the body rests on the floor")
	_expect(vel.y > 0.0, "a hard landing bounces")
	_expect(float(landed["squash"]) < 1.0, "a hard landing squashes")

func _tunnel() -> void:
	var pos := Vector3(0.0, 0.4, 0.0)
	var vel := Vector3(0.0, -40.0, 0.0)
	vel = JellyFeel.clamp_vel(vel)
	_expect(vel.length() <= JellyFeel.MAX_SPEED + 0.01, "a dive is speed-capped")
	var dt := 1.0 / 60.0
	for _i in 20:
		vel = JellyFeel.fall(vel, dt)
		pos += vel * dt
		var step: Dictionary = JellyFeel.land(pos, vel, 0.0)
		pos = step["pos"]
		vel = step["vel"]
	_expect(pos.y >= -0.001, "substeps do not leave the body under the lawn")
	_expect(pos.is_finite() and vel.is_finite(), "bounce stays finite")

func _speed() -> void:
	var nan_vel := Vector3(NAN, 1.0, 0.0)
	_expect(JellyFeel.clamp_vel(nan_vel) == Vector3.ZERO, "NaN velocity is cleared")
	var lost: Vector3 = JellyFeel.clamp_pos(Vector3(NAN, NAN, NAN), Vector3(1.0, 0.0, 2.0))
	_expect(lost.x == 1.0, "NaN position snaps back")

func _separate() -> void:
	var split: Dictionary = JellyFeel.separate(
		Vector3.ZERO, 0.4, Vector3.ZERO, false,
		Vector3(0.1, 0.0, 0.0), 0.4, Vector3.ZERO, false
	)
	_expect(bool(split["hit"]), "overlap is detected")
	var a_pos: Vector3 = split["a_pos"]
	var b_pos: Vector3 = split["b_pos"]
	_expect(a_pos.distance_to(b_pos) >= 0.79, "bodies are pushed apart")
	var held_split: Dictionary = JellyFeel.separate(
		Vector3.ZERO, 0.4, Vector3.ZERO, true,
		Vector3(0.1, 0.0, 0.0), 0.4, Vector3.ZERO, false
	)
	var held_pos: Vector3 = held_split["a_pos"]
	var other_pos: Vector3 = held_split["b_pos"]
	_expect(held_pos.length() < 0.02, "a held jelly keeps its place")
	_expect(other_pos.x > 0.7, "the free jelly slides off the hands")

func _stall() -> void:
	var inside := Vector3(GardenLayout.STALL.x, 0.3, GardenLayout.STALL.z)
	var bounced: Dictionary = JellyFeel.bounce_prop(inside, Vector3(3.0, 0.0, 0.0), 0.3, false)
	var pos: Vector3 = bounced["pos"]
	_expect(bool(bounced["hit"]), "the stall is solid")
	_expect(pos.distance_to(inside) > 0.4, "a jelly is pushed off the stall")
	var pond := Vector3(GardenLayout.POND_CENTER.x, 0.2, GardenLayout.POND_CENTER.z)
	var bank: Dictionary = JellyFeel.bounce_prop(pond, Vector3.ZERO, 0.3, false)
	var bank_pos: Vector3 = bank["pos"]
	var dist := Vector2(bank_pos.x - GardenLayout.POND_CENTER.x, bank_pos.z - GardenLayout.POND_CENTER.z).length()
	_expect(dist >= GardenLayout.POND_RADIUS * 0.9, "a land jelly is kept off the pond")
	var wader: Dictionary = JellyFeel.bounce_prop(pond, Vector3.ZERO, 0.3, true)
	var wader_pos: Vector3 = wader["pos"]
	_expect(wader_pos.distance_to(pond) < 0.05, "a water jelly may sit in the pond")

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("jelly: " + label)
	quit(1)

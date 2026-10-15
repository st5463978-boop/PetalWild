extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")
const SimClockScript := preload("res://scripts/game/sim_clock.gd")


func _initialize() -> void:
	var t: PetalAssert = PA.new("event_queue")
	_order(t)
	_recurrence(t)
	_cancel(t)
	_determinism(t)
	_save_mid_queue(t)
	t.done()


func _clock() -> Node:
	return root.get_node("Clock")


func _fresh(seed: int = 4242) -> SimClock:
	var clock := _clock()
	clock.call("reset_new")
	clock.set("day", 1)
	clock.set("minute", 0.0)
	clock.set("running", false)
	var sim: SimClock = SimClockScript.new()
	sim.clock_node = clock
	sim.reseed(seed)
	return sim


func _order(t: PetalAssert) -> void:
	var sim := _fresh()
	var fired: Array = []
	sim.queue.register(&"note", func(ev: Dictionary) -> float:
		fired.append(str(ev.get("kind", "")) + ":" + str(ev.get("target", "")))
		return -1.0
	)
	sim.queue.schedule(30.0, &"note", &"c")
	sim.queue.schedule(10.0, &"note", &"a")
	sim.queue.schedule(10.0, &"note", &"b")
	sim.skip_to(30.0)
	t.expect(fired == ["note:a", "note:b", "note:c"], "events fire in (at, seq) order")


func _recurrence(t: PetalAssert) -> void:
	var sim := _fresh()
	var hits := [0]
	sim.queue.register(&"pulse", func(ev: Dictionary) -> float:
		hits[0] += 1
		return float(ev.get("at", 0.0)) + 10.0
	)
	sim.queue.schedule(10.0, &"pulse", &"well")
	sim.skip_to(100.0)
	t.expect(hits[0] == 10, "recurring event fires floor(span / period) times")
	t.expect(is_equal_approx(sim.now(), 100.0), "skip_to lands on absolute minutes")
	sim.skip_to(1500.0)
	t.expect(is_equal_approx(sim.now(), 1500.0), "absolute minutes wrap into the next day")
	t.expect(int(_clock().get("day")) == 2, "day 2 starts at 1440")
	t.expect(is_equal_approx(float(_clock().get("minute")), 60.0), "minute 60 on day 2")


func _cancel(t: PetalAssert) -> void:
	var sim := _fresh()
	var fired: Array = []
	sim.queue.register(&"note", func(ev: Dictionary) -> float:
		fired.append(str(ev.get("target", "")))
		return -1.0
	)
	sim.queue.schedule(5.0, &"note", &"keep")
	sim.queue.schedule(6.0, &"note", &"drop")
	sim.queue.schedule(7.0, &"note", &"drop")
	sim.queue.cancel_for(&"drop")
	sim.skip_to(20.0)
	t.expect(fired == ["keep"], "cancel_for removes every event for a target")


func _determinism(t: PetalAssert) -> void:
	var a := _run_scripted(4242)
	var b := _run_scripted(4242)
	t.expect(a == b, "same seed and inputs hash to the same causal log")
	var c := _run_scripted(99)
	t.expect(a != c, "a different seed changes the log")


func _run_scripted(seed: int) -> String:
	var sim := _fresh(seed)
	sim.queue.register(&"roll", func(ev: Dictionary) -> float:
		ev["summary"] = str(sim.rng.randi())
		return -1.0
	)
	sim.queue.schedule(4.0, &"roll", &"a")
	sim.queue.schedule(4.0, &"roll", &"b")
	sim.queue.schedule(12.0, &"roll", &"c")
	sim.skip_to(20.0)
	return sim.log.digest()


func _save_mid_queue(t: PetalAssert) -> void:
	var live := _fresh()
	var hits: Array = []
	live.queue.register(&"tick", func(ev: Dictionary) -> float:
		hits.append(str(ev.get("target", "")))
		return -1.0
	)
	live.queue.schedule(10.0, &"tick", &"one")
	live.queue.schedule(20.0, &"tick", &"two")
	live.queue.schedule(30.0, &"tick", &"three")
	live.skip_to(15.0)
	var at := live.now()
	var snapshot := live.to_state()
	var resumed := _fresh()
	resumed.apply_state(snapshot)
	resumed.skip_to(at)
	# skip_to also drains; remaining events are still in the future.
	resumed.queue.register(&"tick", func(ev: Dictionary) -> float:
		hits.append(str(ev.get("target", "")))
		return -1.0
	)
	resumed.skip_to(35.0)

	var control := _fresh()
	var control_hits: Array = []
	control.queue.register(&"tick", func(ev: Dictionary) -> float:
		control_hits.append(str(ev.get("target", "")))
		return -1.0
	)
	control.queue.schedule(10.0, &"tick", &"one")
	control.queue.schedule(20.0, &"tick", &"two")
	control.queue.schedule(30.0, &"tick", &"three")
	control.skip_to(35.0)
	t.expect(hits == control_hits, "save mid-queue then load matches an uninterrupted run")
	t.expect(hits == ["one", "two", "three"], "all three ticks still fire across the save")

class_name SimClock
extends RefCounted

## Thin wrapper over Clock minutes plus a seeded RNG and the event queue.
## Looks Clock up on the SceneTree so headless --script tests can drive it.

var rng := RandomNumberGenerator.new()
var queue := EventQueue.new()
var log := CausalLog.new()
var seed := 4242
var clock_node: Node = null
var _now_min := 0.0


func _init() -> void:
	rng.seed = seed
	queue.log = log


func now() -> float:
	var clock := _clock()
	if clock != null and clock.has_method("absolute_minutes"):
		return float(clock.call("absolute_minutes"))
	return _now_min


func advance(_dt_min: float = 0.0) -> void:
	queue.run_until(now())


func skip(dt_min: float) -> void:
	_set_now(now() + dt_min)
	queue.run_until(now(), 0)


func skip_to(abs_min: float) -> void:
	_set_now(abs_min)
	queue.run_until(now(), 0)


func reseed(next_seed: int) -> void:
	seed = next_seed
	rng.seed = seed


func to_state() -> Dictionary:
	return {
		"seed": seed,
		"rng_state": str(rng.state),
		"queue": queue.to_state(),
		"log": log.to_state(),
		"now": now(),
	}


func apply_state(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var body: Dictionary = data
	if body.has("seed"):
		seed = int(body.get("seed", seed))
		rng.seed = seed
	if body.has("rng_state"):
		rng.state = int(str(body.get("rng_state", str(rng.state))))
	var rows: Variant = body.get("queue", [])
	queue.apply_state(rows)
	if body.has("log"):
		log.apply_state(body.get("log", {}))
	if body.has("now"):
		_set_now(float(body.get("now", now())))
	queue.log = log


func _set_now(abs_min: float) -> void:
	_now_min = maxf(abs_min, 0.0)
	var clock := _clock()
	if clock != null and clock.has_method("set_from_absolute"):
		clock.call("set_from_absolute", _now_min)


func _clock() -> Node:
	if clock_node != null and is_instance_valid(clock_node):
		return clock_node
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		if tree.root != null:
			return tree.root.get_node_or_null("Clock")
	return null

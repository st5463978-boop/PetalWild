class_name CausalLog
extends RefCounted

## Ring of fired events for the inspector "Why?" view. Per-target tails stay short.

const CAP := 2048
const PER_TARGET := 16

var _ring: Array = []
var _by_target: Dictionary = {}


func add(event: Dictionary, t: float) -> void:
	var target := str(event.get("target", ""))
	var entry := {
		"t": t,
		"kind": str(event.get("kind", "")),
		"target": target,
		"cause": str(event.get("cause", "")),
		"summary": _summary(event, t),
		"id": int(event.get("id", 0)),
	}
	_ring.append(entry)
	if _ring.size() > CAP:
		_ring.pop_front()
	var tail: Array = _by_target.get(target, [])
	if typeof(tail) != TYPE_ARRAY:
		tail = []
	tail.append(entry)
	if tail.size() > PER_TARGET:
		tail.pop_front()
	_by_target[target] = tail


func for_target(target: StringName) -> Array:
	var tail: Variant = _by_target.get(str(target), [])
	if typeof(tail) != TYPE_ARRAY:
		return []
	return (tail as Array).duplicate(true)


func all_entries() -> Array:
	return _ring.duplicate(true)


func digest() -> String:
	return JSON.stringify(_ring)


func to_state() -> Dictionary:
	return {
		"ring": _ring.duplicate(true),
		"by_target": _by_target.duplicate(true),
	}


func apply_state(data: Variant) -> void:
	_ring.clear()
	_by_target.clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var body: Dictionary = data
	var ring: Variant = body.get("ring", [])
	if typeof(ring) == TYPE_ARRAY:
		for item in ring:
			if typeof(item) == TYPE_DICTIONARY:
				_ring.append((item as Dictionary).duplicate(true))
		if _ring.size() > CAP:
			_ring = _ring.slice(_ring.size() - CAP)
	var by_target: Variant = body.get("by_target", {})
	if typeof(by_target) == TYPE_DICTIONARY:
		for key in (by_target as Dictionary).keys():
			var tail: Variant = by_target[key]
			if typeof(tail) != TYPE_ARRAY:
				continue
			var kept: Array = []
			for item in tail:
				if typeof(item) == TYPE_DICTIONARY:
					kept.append((item as Dictionary).duplicate(true))
			if kept.size() > PER_TARGET:
				kept = kept.slice(kept.size() - PER_TARGET)
			_by_target[str(key)] = kept


func _summary(event: Dictionary, t: float) -> String:
	var written := str(event.get("summary", ""))
	if written != "":
		return written
	return "%s %s @ %.3f" % [str(event.get("kind", "")), str(event.get("target", "")), t]

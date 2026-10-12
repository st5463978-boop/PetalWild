class_name EventQueue
extends RefCounted

## Min-heap of [at_min, seq, event]. Ties break on seq so equal times stay stable.

var handlers: Dictionary = {}
var log: CausalLog
var budget_usec := 2000
var _heap: Array = []
var _seq := 0


func register(kind: StringName, handler: Callable) -> void:
	handlers[kind] = handler


func schedule(at_min: float, kind: StringName, target: StringName, data: Dictionary = {}) -> int:
	_seq += 1
	var event := {
		"id": _seq,
		"at": at_min,
		"kind": str(kind),
		"target": str(target),
		"data": data.duplicate(true),
		"cause": str(data.get("cause", "")),
	}
	_push([at_min, _seq, event])
	return _seq


func cancel_for(target: StringName) -> void:
	var want := str(target)
	var keep: Array = []
	for item in _heap:
		var row: Array = item
		var event: Dictionary = row[2]
		if str(event.get("target", "")) != want:
			keep.append(row)
	_heap = keep
	_heapify()


func run_until(now_min: float, slice_usec: int = -1) -> void:
	# slice_usec 0 means unlimited (tests and catch-up). Negative uses the frame budget.
	var budget := slice_usec if slice_usec >= 0 else budget_usec
	var t0 := Time.get_ticks_usec()
	while not _heap.is_empty() and float(_heap[0][0]) <= now_min:
		var row: Array = _pop()
		var event: Dictionary = row[2]
		var at_min := float(row[0])
		event["at"] = at_min
		var kind := StringName(str(event.get("kind", "")))
		var next_at := -1.0
		if handlers.has(kind):
			var handler: Callable = handlers[kind]
			if handler.is_valid():
				var result: Variant = handler.call(event)
				if typeof(result) == TYPE_FLOAT or typeof(result) == TYPE_INT:
					next_at = float(result)
		if log != null:
			log.add(event, at_min)
		if next_at > at_min:
			var payload: Variant = event.get("data", {})
			var data := {}
			if typeof(payload) == TYPE_DICTIONARY:
				data = payload
			schedule(next_at, kind, StringName(str(event.get("target", ""))), data)
		if budget > 0 and Time.get_ticks_usec() - t0 > budget:
			break


func pending_count() -> int:
	return _heap.size()


func to_state() -> Array:
	var rows: Array = []
	for item in _heap:
		var row: Array = item
		var event: Dictionary = row[2]
		rows.append([float(row[0]), int(row[1]), event.duplicate(true)])
	return rows


func apply_state(rows: Variant) -> void:
	_heap.clear()
	_seq = 0
	if typeof(rows) != TYPE_ARRAY:
		return
	for item in rows:
		if typeof(item) != TYPE_ARRAY or item.size() < 3:
			continue
		var row: Array = item
		var event: Variant = row[2]
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var seq := int(row[1])
		if seq > _seq:
			_seq = seq
		var copied: Dictionary = event
		copied = copied.duplicate(true)
		copied["at"] = float(row[0])
		_heap.append([float(row[0]), seq, copied])
	_heapify()


func _push(item: Array) -> void:
	_heap.append(item)
	_sift_up(_heap.size() - 1)


func _pop() -> Array:
	var n := _heap.size()
	if n == 0:
		return []
	var top: Array = _heap[0]
	var last: Array = _heap[n - 1]
	_heap.remove_at(n - 1)
	if not _heap.is_empty():
		_heap[0] = last
		_sift_down(0)
	return top


func _heapify() -> void:
	if _heap.size() < 2:
		return
	var i := (_heap.size() >> 1) - 1
	while i >= 0:
		_sift_down(i)
		i -= 1


func _sift_up(index: int) -> void:
	var i := index
	while i > 0:
		var parent := (i - 1) >> 1
		if not _before(_heap[i], _heap[parent]):
			break
		_swap(i, parent)
		i = parent


func _sift_down(index: int) -> void:
	var i := index
	var n := _heap.size()
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var best := i
		if left < n and _before(_heap[left], _heap[best]):
			best = left
		if right < n and _before(_heap[right], _heap[best]):
			best = right
		if best == i:
			break
		_swap(i, best)
		i = best


func _before(a: Variant, b: Variant) -> bool:
	var left: Array = a
	var right: Array = b
	var at_a := float(left[0])
	var at_b := float(right[0])
	if at_a < at_b:
		return true
	if at_a > at_b:
		return false
	return int(left[1]) < int(right[1])


func _swap(i: int, j: int) -> void:
	var tmp: Array = _heap[i]
	_heap[i] = _heap[j]
	_heap[j] = tmp

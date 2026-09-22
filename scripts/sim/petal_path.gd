class_name PetalPath
extends RefCounted

static func astar(start: Vector2i, goal: Vector2i, blocked: Dictionary, width: int, height: int) -> Array:
	if not _inside(start, width, height) or not _inside(goal, width, height):
		return []
	if blocked.has(start) or blocked.has(goal):
		return []
	if start == goal:
		return [start]
	var open: Array[Vector2i] = [start]
	var came := {}
	var gscore := {start: 0}
	var fscore := {start: _heuristic(start, goal)}
	while not open.is_empty():
		var best_i := 0
		var best_f: int = fscore[open[0]]
		for i in range(1, open.size()):
			var score: int = fscore.get(open[i], 999999)
			if score < best_f:
				best_f = score
				best_i = i
		var current: Vector2i = open[best_i]
		open.remove_at(best_i)
		if current == goal:
			return _rebuild(came, current)
		for nxt in _neighbors(current):
			if not _inside(nxt, width, height) or blocked.has(nxt):
				continue
			var tentative: int = int(gscore[current]) + 1
			if tentative < int(gscore.get(nxt, 999999)):
				came[nxt] = current
				gscore[nxt] = tentative
				fscore[nxt] = tentative + _heuristic(nxt, goal)
				if not open.has(nxt):
					open.append(nxt)
	return []


static func blocked_from_state(state: Dictionary) -> Dictionary:
	var blocked := {}
	var width := int(state.get("width", 0))
	var height := int(state.get("height", 0))
	var plots: Array = state.get("plots", [])
	for y in height:
		for x in width:
			var plot: Dictionary = plots[y * width + x]
			if String(plot.get("g", "")) == "pond":
				blocked[Vector2i(x, y)] = true
	return blocked


static func _inside(cell: Vector2i, width: int, height: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(cell.x + 1, cell.y),
		Vector2i(cell.x - 1, cell.y),
		Vector2i(cell.x, cell.y + 1),
		Vector2i(cell.x, cell.y - 1),
	]


static func _rebuild(came: Dictionary, current: Vector2i) -> Array:
	var path: Array = [current]
	while came.has(current):
		current = came[current]
		path.push_front(current)
	return path

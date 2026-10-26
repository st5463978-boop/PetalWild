class_name TownMap
extends Control

## Small map of Grok Town. The dot is the camera target, clamped to the square.

var marker := Vector2(0.5, 0.85)
var spots: Array = []


func load_town(town: GrokTown) -> void:
	spots = town.spot_uvs()
	queue_redraw()


func set_marker(uv: Vector2) -> void:
	marker = uv
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color("1c2418"), true)
	draw_rect(rect, Color("e2b15a"), false, 2.0)
	var inner := rect.grow(-10.0)
	draw_rect(inner, Color("2f5a34"), true)
	for spot_v in spots:
		if typeof(spot_v) != TYPE_DICTIONARY:
			continue
		var spot: Dictionary = spot_v
		var uv: Vector2 = spot.get("uv", Vector2(0.5, 0.5))
		var point := inner.position + Vector2(uv.x * inner.size.x, (1.0 - uv.y) * inner.size.y)
		draw_circle(point, 5.0, Color("e2b15a"))
	var dot := inner.position + Vector2(marker.x * inner.size.x, (1.0 - marker.y) * inner.size.y)
	draw_circle(dot, 6.5, Color("f7f1e6"))
	draw_circle(dot, 3.0, Color("c4653d"))

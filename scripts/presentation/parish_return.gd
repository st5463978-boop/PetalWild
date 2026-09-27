extends Node

func _ready() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "Esc returns to the grove"
	label.position = Vector2(24, 78)
	layer.add_child(label)
	add_child(layer)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main.tscn")

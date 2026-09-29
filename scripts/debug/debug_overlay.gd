class_name DebugOverlay
extends CanvasLayer

var host: Node
var label: Label
var panel: Panel

func build(owner: Node) -> void:
	host = owner
	layer = 20
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = Panel.new()
	panel.theme = ThemeKit.make_theme()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -360
	panel.offset_right = -16
	panel.offset_top = 90
	panel.offset_bottom = 620
	add_child(panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40
	box.offset_top = 36
	box.offset_right = -40
	box.offset_bottom = -36
	panel.add_child(box)
	label = ThemeKit.label("", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	_button(box, "Grow plants", func(): host.debug_grow())
	_button(box, "Spawn Bellhelp", func(): host.debug_spawn("bellhelp"))
	_button(box, "Add 25 coins", func(): host.debug_coins(25))
	_button(box, "Next hour", func(): host.debug_hour(1.0))
	_button(box, "Force rain", func(): host.debug_weather("rain"))
	_button(box, "Make resident", func(): host.debug_resident())
	_button(box, "Self-play beat", func(): host.self_play_beat())
	_button(box, "Save", func(): host.quick_save())
	_button(box, "Load", func(): host.quick_load())

func toggle() -> void:
	visible = not visible

func set_text(text: String) -> void:
	if label:
		label.text = text

func _button(parent: Node, text: String, call: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(call)
	parent.add_child(button)

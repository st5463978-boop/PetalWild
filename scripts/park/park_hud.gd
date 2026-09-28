class_name ParkHud
extends CanvasLayer

var camera_label: Label
var speed_label: Label
var help_label: Label
var clock_label: Label


func build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 18
	panel.offset_top = 16
	panel.offset_right = 430
	panel.offset_bottom = 132
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.97, 0.94, 0.88, 0.82)
	box.set_corner_radius_all(12)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", box)
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_top = 8
	col.offset_right = -12
	col.offset_bottom = -8
	panel.add_child(col)
	camera_label = _lab("Camera  ·  Ring orbit", 18)
	speed_label = _lab("Speed  ·  Pause", 16)
	clock_label = _lab("16:30  ·  golden", 14)
	col.add_child(camera_label)
	col.add_child(speed_label)
	col.add_child(clock_label)
	help_label = _lab("F1 ring  F2 builder  F3 pond  F4 free  C cycle\nSpace pause  1/2/3 = 1× 2× 4×  O depth of field  Esc title", 13)
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.offset_left = 18
	help_label.offset_top = -78
	help_label.offset_right = 720
	help_label.offset_bottom = -16
	root.add_child(help_label)


func _lab(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("1c2418"))
	return label


func set_camera(name: String) -> void:
	if camera_label:
		camera_label.text = "Camera  ·  %s" % name


func set_speed(paused: bool, scale: float) -> void:
	if speed_label == null:
		return
	if paused:
		speed_label.text = "Speed  ·  Pause"
	elif scale <= 7.0:
		speed_label.text = "Speed  ·  1×"
	elif scale <= 14.0:
		speed_label.text = "Speed  ·  2×"
	else:
		speed_label.text = "Speed  ·  4×"


func set_clock(hour: float, weather: String) -> void:
	if clock_label == null:
		return
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	clock_label.text = "%02d:%02d  ·  %s" % [h, m, weather]

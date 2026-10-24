class_name MapOverlays
extends Node3D

## Toggleable bed heat maps and Bloom / Hive / Market bars.
## Colours and thresholds live in data/overlays.json.
## Service paint reads ServiceField. Footfall paint reads PathGraph edges.
## A bar tooltip is the latest CausalLog reason for that demand.

var channel := ""
var blight: Blight

var services: ServiceField
var paths: PathGraph
var city: CityDemand
var districts: GardenDistricts
var log: CausalLog

var lift := 0.36
var cell_scale := 0.94
var path_width := 0.38
var path_lift := 0.28
var empty_reason := "No demand change has been recorded."
var blight_occupied := 1.0
var blight_neglected := 0.4

var _peak := 8.0
var _bar_width := 268.0
var _bar_max := 100
var _built := false
var _edge_digest := ""
var _shader: Shader
var _order: PackedStringArray = PackedStringArray()
var _rows: Dictionary = {}
var _bar_order: PackedStringArray = PackedStringArray()
var _bar_rows: Dictionary = {}
var _cell_mats: Dictionary = {}
var _edge_amounts: Dictionary = {}
var _buttons: Dictionary = {}
var _bars: Dictionary = {}
var _readouts: Dictionary = {}
var _columns: Dictionary = {}
var _cells: Node3D
var _edges: Node3D
var _panel: Panel


func _init() -> void:
	_load()


func _process(_delta: float) -> void:
	if not _built:
		return
	refresh()


func bind(field: ServiceField, walk: PathGraph, demand: CityDemand, causal: CausalLog, parish: Node) -> void:
	services = field
	paths = walk
	city = demand
	log = causal
	_capture_blight(parish)
	_ensure_built()
	refresh()


func channels() -> PackedStringArray:
	return _order.duplicate()


func channel_id() -> String:
	return channel


func source_of(id: String) -> String:
	return str(_channel_row(id).get("source", ""))


func set_channel(next: String) -> void:
	if next != "" and _channel_row(next).is_empty():
		return
	channel = next
	_ensure_built()
	_edge_digest = ""
	refresh()
	_style_buttons()


func cycle() -> void:
	if _order.is_empty():
		set_channel("")
		return
	if channel == "":
		set_channel(_order[0])
		return
	var index := _order.find(channel)
	if index < 0 or index + 1 >= _order.size():
		set_channel("")
		return
	set_channel(_order[index + 1])


func maps_visible() -> bool:
	if channel == "":
		return false
	if _source() == "path":
		return _edges != null and _edges.visible
	return _cells != null and _cells.visible


func sample(cell: Vector2i) -> float:
	var source := _source()
	if source == "service":
		if services == null:
			return 0.0
		return services.sample(cell, channel)
	if source == "blight":
		return blight_pressure(cell)
	if source == "district":
		if districts == null:
			return 0.0
		return districts.paint_amount(cell)
	return 0.0


func painted_amount(cell: Vector2i) -> float:
	var mat := _mat(cell)
	if mat == null:
		return -1.0
	var amount: Variant = mat.get_shader_parameter("amount")
	return float(amount)


func footfall_peak() -> float:
	return maxf(_peak, 1.0)


func edge_amount(from_at: Vector3, to_at: Vector3) -> float:
	return float(_edge_amounts.get(_pair_key(from_at, to_at), 0.0))


func blight_pressure(cell: Vector2i) -> float:
	if blight == null:
		return 0.0
	for moth_v in blight.moths:
		if typeof(moth_v) != TYPE_DICTIONARY:
			continue
		var moth: Dictionary = moth_v
		if int(moth.get("ix", -1)) == cell.x and int(moth.get("iz", -1)) == cell.y:
			return blight_occupied
	if blight.soil == null:
		return 0.0
	var plot := blight.soil.get_cell(cell.x, cell.y)
	if plot == null or plot.plant_id == "":
		return 0.0
	var dry_at := float(blight.tuning.get("neglected_moisture", 0.18))
	var wilt_at := float(blight.tuning.get("neglected_wilt", 1.0))
	if plot.moisture <= dry_at or plot.wilt >= wilt_at:
		return blight_neglected
	return 0.0


func button_for(id: String) -> Button:
	var found: Variant = _buttons.get(id, null)
	return found as Button


func bar_value(kind: String) -> int:
	var bar := _bar(kind)
	if bar == null:
		return -1
	return int(round(bar.value))


func bar_reason(kind: String) -> String:
	var bar := _bar(kind)
	if bar == null:
		return ""
	return bar.tooltip_text


func readout_text(kind: String) -> String:
	var found: Variant = _readouts.get(kind, null)
	if found is Label:
		return (found as Label).text
	return ""


func bar_color(kind: String) -> Color:
	var bar := _bar(kind)
	if bar == null:
		return Color(0, 0, 0, 0)
	var style := bar.get_theme_stylebox("fill")
	if style is StyleBoxFlat:
		return (style as StyleBoxFlat).bg_color
	return Color(0, 0, 0, 0)


func panel_rect() -> Rect2:
	if _panel == null:
		return Rect2()
	return _panel.get_global_rect()


func refresh() -> void:
	_ensure_built()
	_paint_cells()
	if _source() == "path":
		_sync_edges()
	_paint_bars()
	_show_layers()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_O:
		return
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	cycle()
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var loaded: Variant = load("res://shaders/overlay_heat.gdshader")
	if loaded is Shader:
		_shader = loaded
	else:
		push_error("Missing shader res://shaders/overlay_heat.gdshader")
	_cells = Node3D.new()
	_cells.name = "HeatCells"
	add_child(_cells)
	_edges = Node3D.new()
	_edges.name = "HeatEdges"
	add_child(_edges)
	_build_cells()
	_build_hud()
	_show_layers()


func _build_cells() -> void:
	var columns := GardenLayout.BED_W
	var rows := GardenLayout.BED_H
	if services != null:
		columns = services.width
		rows = services.height
	var plane := PlaneMesh.new()
	plane.size = Vector2(GardenLayout.CELL_W * cell_scale, GardenLayout.CELL_D * cell_scale)
	for x in columns:
		for z in rows:
			var node := MeshInstance3D.new()
			node.mesh = plane
			var center := GardenLayout.cell_center(x, z)
			node.position = Vector3(center.x, center.y + lift, center.z)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			var mat := ShaderMaterial.new()
			mat.shader = _shader
			mat.render_priority = 10
			node.material_override = mat
			_cells.add_child(node)
			_cell_mats["%d,%d" % [x, z]] = mat


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DemandHud"
	layer.layer = 11
	add_child(layer)
	_panel = Panel.new()
	_panel.name = "DemandPanel"
	_panel.theme = ThemeKit.make_theme()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 16
	_panel.offset_top = 86
	_panel.offset_right = 540
	_panel.offset_bottom = 348
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_top = 8
	box.offset_right = -10
	box.offset_bottom = -8
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	for kind_v in _bar_order:
		box.add_child(_demand_column(str(kind_v)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	_add_channel_button(grid, "", "Off")
	for id in _order:
		_add_channel_button(grid, id, str(_channel_row(id).get("label", id)))
	_style_buttons()


func _demand_column(kind: String) -> Control:
	var spec: Dictionary = _bar_rows.get(kind, {})
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := ThemeKit.label(str(spec.get("label", kind.capitalize())), 15, ThemeKit.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var readout := ThemeKit.label("0", 16, _hex_color(str(spec.get("color", "#1f8a45"))))
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.custom_minimum_size = Vector2(36, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var badge := ArtKit.icon("bars", kind)
	if badge != null:
		var art := TextureRect.new()
		art.name = "Icon"
		art.texture = badge
		art.custom_minimum_size = Vector2(20, 20)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
	row.add_child(title)
	row.add_child(readout)
	column.add_child(row)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = _bar_max
	bar.value = 0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(_bar_width, 16)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(ThemeKit.INK, 0.14)
	back.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = _hex_color(str(spec.get("color", "#1f8a45")))
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	column.add_child(bar)
	_bars[kind] = bar
	_readouts[kind] = readout
	_columns[kind] = column
	return column


func _add_channel_button(parent: Node, id: String, label: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(120, 30)
	button.focus_mode = Control.FOCUS_NONE
	var badge := ArtKit.icon("channels", id)
	if badge != null:
		button.icon = badge
		button.expand_icon = false
		button.add_theme_constant_override("icon_max_width", 20)
	button.pressed.connect(_on_channel_pressed.bind(id))
	parent.add_child(button)
	_buttons[id] = button


func _on_channel_pressed(id: String) -> void:
	set_channel(id)


func _paint_cells() -> void:
	var row := _channel_row(channel)
	var low := _rgba(row, "low", "low_alpha", 0.4)
	var high := _rgba(row, "high", "high_alpha", 0.9)
	for key_v in _cell_mats.keys():
		var key := str(key_v)
		var mat: ShaderMaterial = _cell_mats[key] as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("low_color", low)
		mat.set_shader_parameter("high_color", high)
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2:
			continue
		var amount := sample(Vector2i(int(parts[0]), int(parts[1])))
		mat.set_shader_parameter("amount", amount)


func _sync_edges() -> void:
	var digest := ""
	if paths != null:
		digest = paths.edge_digest()
	if digest == _edge_digest:
		return
	_edge_digest = digest
	_clear_edges()
	if paths == null:
		return
	var records: Array = paths.edge_records()
	var row := _channel_row("footfall")
	for item in records:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var body: Dictionary = item
		var from_at: Vector3 = body.get("from", Vector3.ZERO) as Vector3
		var to_at: Vector3 = body.get("to", Vector3.ZERO) as Vector3
		var count := int(body.get("count", 0))
		var amount := clampf(float(count) / footfall_peak(), 0.0, 1.0)
		_edge_amounts[_pair_key(from_at, to_at)] = amount
		_add_edge(from_at, to_at, amount, row)


func _add_edge(from_at: Vector3, to_at: Vector3, amount: float, row: Dictionary) -> void:
	var flat_from := Vector3(from_at.x, 0.0, from_at.z)
	var flat_to := Vector3(to_at.x, 0.0, to_at.z)
	var span := flat_from.distance_to(flat_to)
	if span < 0.05:
		return
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(path_width, 0.045, span)
	node.mesh = box
	var dir := (flat_to - flat_from) / span
	var x_axis := Vector3.UP.cross(dir)
	if x_axis.length() < 0.001:
		x_axis = Vector3.RIGHT
	else:
		x_axis = x_axis.normalized()
	var y_axis := dir.cross(x_axis).normalized()
	node.basis = Basis(x_axis, y_axis, dir)
	node.position = (flat_from + flat_to) * 0.5 + Vector3(0.0, path_lift, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.render_priority = 10
	mat.set_shader_parameter("low_color", _rgba(row, "low", "low_alpha", 0.35))
	mat.set_shader_parameter("high_color", _rgba(row, "high", "high_alpha", 0.92))
	mat.set_shader_parameter("amount", amount)
	node.material_override = mat
	_edges.add_child(node)


func _clear_edges() -> void:
	if _edges == null:
		_edge_amounts.clear()
		return
	for child in _edges.get_children():
		_edges.remove_child(child)
		child.queue_free()
	_edge_amounts.clear()


func _paint_bars() -> void:
	for kind_v in _bar_order:
		var kind := str(kind_v)
		var value := _demand_value(kind)
		var why := _reason(kind)
		var bar := _bar(kind)
		if bar != null:
			bar.max_value = _bar_max
			bar.value = value
			bar.tooltip_text = why
		var readout: Variant = _readouts.get(kind, null)
		if readout is Label:
			(readout as Label).text = str(value)
		var column: Variant = _columns.get(kind, null)
		if column is Control:
			(column as Control).tooltip_text = why


func _show_layers() -> void:
	var source := _source()
	if _cells != null:
		_cells.visible = source == "service" or source == "blight" or source == "district"
	if _edges != null:
		_edges.visible = source == "path"


func _style_buttons() -> void:
	for key_v in _buttons.keys():
		var key := str(key_v)
		var button: Button = _buttons[key] as Button
		if button == null:
			continue
		var on := key == channel
		button.add_theme_stylebox_override("normal", ThemeKit.button_box(on))
		button.add_theme_stylebox_override("hover", ThemeKit.button_box(true))
		button.add_theme_stylebox_override("pressed", ThemeKit.button_box(true))
		button.add_theme_color_override("font_color", ThemeKit.CREAM if on else ThemeKit.INK)


func _demand_value(kind: String) -> int:
	if city == null:
		return 0
	return int(city.get(kind))


func _reason(kind: String) -> String:
	if log == null:
		return empty_reason
	var tail: Array = log.for_target(StringName(kind))
	if tail.is_empty():
		return empty_reason
	var entry: Variant = tail[tail.size() - 1]
	if typeof(entry) != TYPE_DICTIONARY:
		return empty_reason
	var body: Dictionary = entry
	var why := str(body.get("cause", ""))
	if why == "":
		why = str(body.get("summary", ""))
	if why == "":
		return empty_reason
	return why


func _source() -> String:
	return source_of(channel)


func _capture_blight(parish: Node) -> void:
	blight = null
	if parish == null:
		return
	var found: Variant = parish.get("blight")
	if found is Blight:
		blight = found as Blight


func _mat(cell: Vector2i) -> ShaderMaterial:
	var found: Variant = _cell_mats.get("%d,%d" % [cell.x, cell.y], null)
	return found as ShaderMaterial


func _bar(kind: String) -> ProgressBar:
	var found: Variant = _bars.get(kind, null)
	return found as ProgressBar


func _channel_row(id: String) -> Dictionary:
	var found: Variant = _rows.get(id, {})
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return found


func _pair_key(a: Vector3, b: Vector3) -> String:
	var left := a
	var right := b
	if _before(b, a):
		left = b
		right = a
	return "%s|%s" % [_snap(left), _snap(right)]


func _before(a: Vector3, b: Vector3) -> bool:
	var ax := snappedf(a.x, 0.01)
	var bx := snappedf(b.x, 0.01)
	if not is_equal_approx(ax, bx):
		return ax < bx
	var ay := snappedf(a.y, 0.01)
	var by := snappedf(b.y, 0.01)
	if not is_equal_approx(ay, by):
		return ay < by
	return snappedf(a.z, 0.01) < snappedf(b.z, 0.01)


func _snap(at: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


func _rgba(row: Dictionary, key: String, alpha_key: String, alpha_fallback: float) -> Color:
	var color := _hex_color(str(row.get(key, "#1c2418")))
	color.a = float(row.get(alpha_key, alpha_fallback))
	return color


func _hex_color(hex: String) -> Color:
	if hex == "":
		return Color("#1c2418")
	return Color(hex)


func _load() -> void:
	_order = PackedStringArray()
	_rows = {}
	_bar_order = PackedStringArray()
	_bar_rows = {}
	var parsed: Variant = _read_json("res://data/overlays.json")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	lift = float(root.get("lift", lift))
	cell_scale = float(root.get("cell_scale", cell_scale))
	path_width = float(root.get("path_width", path_width))
	path_lift = float(root.get("path_lift", path_lift))
	_peak = float(root.get("footfall_peak", _peak))
	_bar_width = float(root.get("bar_width", _bar_width))
	empty_reason = str(root.get("empty_reason", empty_reason))
	blight_occupied = float(root.get("blight_occupied", blight_occupied))
	blight_neglected = float(root.get("blight_neglected", blight_neglected))
	var channel_rows: Variant = root.get("channels", [])
	if typeof(channel_rows) == TYPE_ARRAY:
		for item in channel_rows:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = item
			var id := str(row.get("id", ""))
			if id == "":
				continue
			_rows[id] = row
			_order.append(id)
	var bar_rows: Variant = root.get("bars", [])
	if typeof(bar_rows) == TYPE_ARRAY:
		for item in bar_rows:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = item
			var id := str(row.get("id", ""))
			if id == "":
				continue
			_bar_rows[id] = row
			_bar_order.append(id)
	var demand: Variant = _read_json("res://data/demand.json")
	if typeof(demand) != TYPE_DICTIONARY:
		return
	_bar_max = maxi(int((demand as Dictionary).get("max", 100)), 1)


func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Missing data file %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in %s" % path)
		return null
	return parsed

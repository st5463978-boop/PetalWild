class_name ControlsHelp
extends RefCounted

## Controls card, tool tooltips, time speeds and autosave interval from data/controls.json.
## The title screen and the in-game HUD build the same card from this data.

const PATH := "res://data/controls.json"

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Missing or bad %s; using a short card." % PATH)
		parsed = {"groups": [{"name": "Game", "keys": [["Esc", "Close the open panel, or pause"]]}]}
	_cache = parsed
	return _cache


static func groups() -> Array:
	var rows: Variant = data().get("groups", [])
	return rows if typeof(rows) == TYPE_ARRAY else []


## Every key label on the card, for tests and the hint line.
static func keys() -> PackedStringArray:
	var out := PackedStringArray()
	for group_v in groups():
		for row_v in (group_v as Dictionary).get("keys", []):
			out.append(str((row_v as Array)[0]))
	return out


static func tooltip(id: String) -> String:
	var tips: Variant = data().get("tooltips", {})
	if typeof(tips) != TYPE_DICTIONARY:
		return ""
	return str((tips as Dictionary).get(id, ""))


static func speeds() -> Array:
	var rows: Variant = data().get("speeds", [])
	if typeof(rows) != TYPE_ARRAY or (rows as Array).is_empty():
		return [{"scale": 6.0, "label": "1×"}]
	return rows


static func speed_label(scale: float) -> String:
	for row_v in speeds():
		var row: Dictionary = row_v
		if is_equal_approx(float(row.get("scale", 0.0)), scale):
			return str(row.get("label", ""))
	return "%.0f×" % (scale / 6.0)


## The scale after `scale` in the speed list; wraps to the first.
static func next_speed(scale: float) -> float:
	var rows := speeds()
	for i in rows.size():
		if is_equal_approx(float((rows[i] as Dictionary).get("scale", 0.0)), scale):
			return float((rows[(i + 1) % rows.size()] as Dictionary).get("scale", 6.0))
	return float((rows[0] as Dictionary).get("scale", 6.0))


static func autosave_seconds() -> float:
	return maxf(float(data().get("autosave_seconds", 0.0)), 0.0)


## Two columns of key / meaning rows under group headings.
static func build_card(base_px: int = 14) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "ControlsCard"
	box.add_theme_constant_override("separation", 4)
	for group_v in groups():
		var group: Dictionary = group_v
		box.add_child(ThemeKit.title(str(group.get("name", "")), base_px + 4))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 2)
		for row_v in group.get("keys", []):
			var row: Array = row_v
			var key := ThemeKit.label(str(row[0]), base_px, ThemeKit.MOSS_DEEP)
			key.custom_minimum_size = Vector2(96, 0)
			grid.add_child(key)
			var what := ThemeKit.label(str(row[1]), base_px)
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			what.custom_minimum_size = Vector2(240, 0)
			grid.add_child(what)
		box.add_child(grid)
	return box

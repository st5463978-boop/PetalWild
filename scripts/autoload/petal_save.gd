extends Node

const DIR := "user://petalwild"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func save_slot(which: int, state: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var packed := state.duplicate(true)
	packed["version"] = 1
	var path := slot_path(which)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(packed, "\t"))
	return true


func load_slot(which: int) -> Dictionary:
	var path := slot_path(which)
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if int(parsed.get("version", 0)) != 1:
		return {}
	return parsed


func summarise(which: int) -> Dictionary:
	var data := load_slot(which)
	if data.is_empty():
		return {"empty": true, "slot": which}
	return {
		"empty": false,
		"slot": which,
		"day": int(data.get("day", 1)),
		"minute": int(data.get("minute", 0)),
		"coins": int(data.get("coins", 0)),
		"weather": String(data.get("weather", "clear")),
	}


func slot_path(which: int) -> String:
	return "%s/slot_%d.json" % [DIR, which]


func settings_path() -> String:
	return "%s/settings.json" % DIR


func load_settings() -> Dictionary:
	var path := settings_path()
	if not FileAccess.file_exists(path):
		return {"volume": 0.8, "ui_scale": 1.0, "reduce_motion": false, "fullscreen": false}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"volume": 0.8, "ui_scale": 1.0, "reduce_motion": false, "fullscreen": false}
	return parsed


func save_settings(settings: Dictionary) -> void:
	var file := FileAccess.open(settings_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))

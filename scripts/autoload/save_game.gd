extends Node

const VERSION := 1

var pending_state = null
var garden_name := "Hedge Hollow"
var active_slot := 1

func path_for(slot: int) -> String:
	return "user://saves/slot_%d.json" % slot

func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot))

func write_slot(slot: int, state: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var payload := {
		"version": VERSION,
		"meta": {
			"name": str(state.get("name", garden_name)),
			"day": int(state.get("clock", {}).get("day", 1)),
			"coins": int(state.get("economy", {}).get("coins", 0)),
			"saved_at": Time.get_datetime_string_from_system(),
		},
		"state": state,
	}
	var file := FileAccess.open(path_for(slot), FileAccess.WRITE)
	if file == null:
		push_error("Could not write save slot %d" % slot)
		return false
	file.store_string(JSON.stringify(payload))
	return true

func read_slot(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var text := FileAccess.get_file_as_string(path_for(slot))
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if int(parsed.get("version", 0)) != VERSION:
		push_error("Save slot %d is version %s and cannot be migrated yet." % [slot, str(parsed.get("version"))])
		return {}
	var state = parsed.get("state", {})
	return state if typeof(state) == TYPE_DICTIONARY else {}

func meta(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var text := FileAccess.get_file_as_string(path_for(slot))
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var header = parsed.get("meta", {})
	return header if typeof(header) == TYPE_DICTIONARY else {}

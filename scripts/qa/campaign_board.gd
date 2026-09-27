class_name CampaignBoard
extends RefCounted

const LANES_PATH := "res://data/campaign_lanes.json"
const STATUS_PATH := "res://data/campaign_status.json"

static func lanes() -> Dictionary:
	return _object(LANES_PATH)

static func status() -> Dictionary:
	return _object(STATUS_PATH)

static func landed() -> int:
	return int(status().get("landed", 0))

static func needed() -> int:
	return int(status().get("needed", 7))

static func waiting_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var rows: Dictionary = status().get("lanes", {})
	for id in rows.keys():
		var row: Dictionary = rows[id]
		if not bool(row.get("present", false)):
			ids.append(str(id))
	ids.sort()
	return ids

static func debug_line() -> String:
	var wait := waiting_ids()
	if wait.is_empty():
		return "lanes %d/%d landed" % [landed(), needed()]
	return "lanes %d/%d wait %s" % [landed(), needed(), " ".join(wait)]

static func complete() -> bool:
	return bool(status().get("complete", false)) and landed() >= needed()

static func _object(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

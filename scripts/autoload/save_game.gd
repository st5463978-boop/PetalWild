extends Node

const VERSION := 3
const MIGRATIONS := {1: "_m1_to_2", 2: "_m2_to_3"}

var pending_state = null
var garden_name := "Hedge Hollow"
var active_slot := 1

func path_for(slot: int) -> String:
	return "user://saves/slot_%d.json" % slot

func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot))

func write_slot(slot: int, state: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var clock: Variant = state.get("clock", {})
	var economy: Variant = state.get("economy", {})
	var day_meta := 1
	var coins_meta := 0
	if typeof(clock) == TYPE_DICTIONARY:
		day_meta = int(clock.get("day", 1))
	if typeof(economy) == TYPE_DICTIONARY:
		coins_meta = int(economy.get("coins", 0))
	var payload := {
		"version": VERSION,
		"meta": {
			"name": str(state.get("name", garden_name)),
			"day": day_meta,
			"coins": coins_meta,
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
	return migrate_text(FileAccess.get_file_as_string(path_for(slot)))

func migrate_text(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return migrate_parsed(parsed)

func migrate_parsed(parsed: Dictionary) -> Dictionary:
	var version := int(parsed.get("version", 1))
	if version <= 0:
		version = 1
	if version > VERSION:
		push_error("Save is from a newer build (v%d)." % version)
		return {}
	var raw: Variant = parsed.get("state", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var state: Dictionary = raw
	return _migrate_from(version, state)

func _migrate_from(version: int, state: Dictionary) -> Dictionary:
	var current := state
	var v := version
	while v < VERSION:
		if not MIGRATIONS.has(v):
			push_error("No save migration from v%d." % v)
			return {}
		var next: Variant = call(str(MIGRATIONS[v]), current)
		if typeof(next) != TYPE_DICTIONARY:
			return {}
		current = next
		v += 1
	return _finish(current)

func _finish(state: Dictionary) -> Dictionary:
	var sim: Variant = state.get("sim", {})
	if typeof(sim) != TYPE_DICTIONARY:
		state["sim"] = {"schema": 1}
	else:
		var body: Dictionary = sim
		if not body.has("schema"):
			body["schema"] = 1
		state["sim"] = body
	_ensure_city(state)
	return state

func _m1_to_2(s: Dictionary) -> Dictionary:
	## M1 only adds the sim skeleton. Economy/ecology reshape waits on later milestones.
	var out := s.duplicate(true)
	var sim: Variant = out.get("sim", {})
	if typeof(sim) != TYPE_DICTIONARY:
		out["sim"] = {"schema": 1}
		return out
	var body: Dictionary = sim
	if not body.has("schema"):
		body["schema"] = 1
	out["sim"] = body
	return out


func _m2_to_3(s: Dictionary) -> Dictionary:
	## VC1 adds the city block. Older gardens start with no stamped services.
	var out := s.duplicate(true)
	_ensure_city(out)
	return out


func _ensure_city(state: Dictionary) -> void:
	var city: Variant = state.get("city", null)
	if typeof(city) != TYPE_DICTIONARY:
		state["city"] = {"services": []}
		return
	var body: Dictionary = city
	if typeof(body.get("services", null)) != TYPE_ARRAY:
		body["services"] = []
	state["city"] = body


func meta(slot: int) -> Dictionary:
	if not has_slot(slot):
		return {}
	var text := FileAccess.get_file_as_string(path_for(slot))
	if text.strip_edges() == "":
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var header: Variant = parsed.get("meta", {})
	return header if typeof(header) == TYPE_DICTIONARY else {}

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
	_ensure_ecology(state)
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
	## VC2 keeps that block at v3 and fills a missing paths list with [].
	## VC3 stays on v3. Gate, food-web, and blight defaults are filled in _finish.
	## VC8 finalizes v3: districts and their policies default to empty.
	var out := s.duplicate(true)
	_ensure_city(out)
	return out


func _ensure_ecology(state: Dictionary) -> void:
	var eco: Variant = state.get("ecology", null)
	if typeof(eco) != TYPE_DICTIONARY:
		state["ecology"] = _blank_parish()
		return
	var body: Dictionary = eco
	if typeof(body.get("gates", null)) != TYPE_DICTIONARY:
		body["gates"] = {}
	if typeof(body.get("gate_notes", null)) != TYPE_ARRAY:
		body["gate_notes"] = []
	body["food_web"] = _food_defaults(body.get("food_web", null))
	body["blight"] = _blight_defaults(body.get("blight", null))
	state["ecology"] = body


func _blank_parish() -> Dictionary:
	return {
		"gates": {},
		"gate_notes": [],
		"food_web": {"counts": {}, "banks": {}, "eaten": {}},
		"blight": {"moths": [], "spawn_bank": 0},
	}


func _food_defaults(food: Variant) -> Dictionary:
	var body: Dictionary = {}
	if typeof(food) == TYPE_DICTIONARY:
		body = food
	if typeof(body.get("counts", null)) != TYPE_DICTIONARY:
		body["counts"] = {}
	if typeof(body.get("banks", null)) != TYPE_DICTIONARY:
		body["banks"] = {}
	if typeof(body.get("eaten", null)) != TYPE_DICTIONARY:
		body["eaten"] = {}
	return body


func _blight_defaults(pests: Variant) -> Dictionary:
	var body: Dictionary = {}
	if typeof(pests) == TYPE_DICTIONARY:
		body = pests
	if typeof(body.get("moths", null)) != TYPE_ARRAY:
		body["moths"] = []
	return body


func _ensure_city(state: Dictionary) -> void:
	var city: Variant = state.get("city", null)
	if typeof(city) != TYPE_DICTIONARY:
		state["city"] = {"services": [], "paths": [], "districts": _blank_districts()}
		return
	var body: Dictionary = city
	if typeof(body.get("services", null)) != TYPE_ARRAY:
		body["services"] = []
	if typeof(body.get("paths", null)) != TYPE_ARRAY:
		body["paths"] = []
	body["districts"] = _district_pack(body.get("districts", null))
	state["city"] = body


func _blank_districts() -> Dictionary:
	return {
		"rows": [],
		"charged_day": 0,
		"active": "",
		"next_index": 1,
		"policy_cursor": 0,
	}


func _district_pack(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_ARRAY:
		var wrapped := _blank_districts()
		wrapped["rows"] = _clean_district_rows(value)
		return wrapped
	if typeof(value) != TYPE_DICTIONARY:
		return _blank_districts()
	var body: Dictionary = value.duplicate(true)
	var rows: Variant = body.get("rows", [])
	if typeof(rows) != TYPE_ARRAY:
		rows = []
	body["rows"] = _clean_district_rows(rows)
	body["charged_day"] = int(body.get("charged_day", 0))
	body["active"] = str(body.get("active", ""))
	body["next_index"] = maxi(int(body.get("next_index", 1)), 1)
	body["policy_cursor"] = maxi(int(body.get("policy_cursor", 0)), 0)
	return body


func _clean_district_rows(rows: Variant) -> Array:
	var clean: Array = []
	if typeof(rows) != TYPE_ARRAY:
		return clean
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var district_id := str(row.get("id", ""))
		if district_id == "":
			continue
		var cells: Array = []
		var cell_rows: Variant = row.get("cells", [])
		if typeof(cell_rows) == TYPE_ARRAY:
			for cell_v in cell_rows:
				if typeof(cell_v) != TYPE_DICTIONARY:
					continue
				var cell_body: Dictionary = cell_v
				cells.append({"x": int(cell_body.get("x", 0)), "z": int(cell_body.get("z", 0))})
		var policies: Array = []
		var policy_rows: Variant = row.get("policies", [])
		if typeof(policy_rows) == TYPE_ARRAY:
			for policy_v in policy_rows:
				var policy_id := str(policy_v)
				if policy_id != "":
					policies.append(policy_id)
		clean.append({
			"id": district_id,
			"name": str(row.get("name", district_id)),
			"cells": cells,
			"policies": policies,
		})
	return clean


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

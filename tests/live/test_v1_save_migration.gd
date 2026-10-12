extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")


func _save() -> Node:
	return root.get_node("SaveGame")


func _migrate_text(text: String) -> Dictionary:
	var raw: Variant = _save().call("migrate_text", text)
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


func _migrate_parsed(payload: Dictionary) -> Dictionary:
	var raw: Variant = _save().call("migrate_parsed", payload)
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


func _initialize() -> void:
	var t: PetalAssert = PA.new("save_migration")
	_recorded_v1(t)
	_already_v2(t)
	_newer_version(t)
	_empty_and_corrupt(t)
	_missing_and_extra_keys(t)
	_write_roundtrip(t)
	t.done()


func _recorded_v1(t: PetalAssert) -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/save_v1_day3.json")
	var state := _migrate_text(text)
	t.expect(not state.is_empty(), "recorded v1 save loads")
	t.expect(int(state.get("sim", {}).get("schema", 0)) == 1, "v1 migration adds sim.schema 1")
	t.expect(int(state.get("clock", {}).get("day", 0)) == 3, "v1 clock day is kept")
	t.expect(int(state.get("economy", {}).get("coins", 0)) == 40, "v1 coins stay on economy")
	t.expect(str(state.get("extra_note", "")) == "keep extra keys", "unknown v1 keys are kept")
	t.expect(state.get("ecology", {}).get("actors", []).size() == 1, "v1 ecology actors are left in place")


func _already_v2(t: PetalAssert) -> void:
	var payload := {
		"version": 2,
		"state": {
			"name": "Already Two",
			"clock": {"day": 4, "minute": 12.0},
			"economy": {"coins": 7, "bag": {}},
			"sim": {"schema": 1, "clock": {"seed": 9}},
		},
	}
	var state := _migrate_parsed(payload)
	t.expect(int(state.get("sim", {}).get("clock", {}).get("seed", 0)) == 9, "v2 is not re-migrated")
	t.expect(int(state.get("economy", {}).get("coins", 0)) == 7, "v2 economy is unchanged")
	var again_raw: Variant = _save().call("_m1_to_2", state)
	t.expect(typeof(again_raw) == TYPE_DICTIONARY, "_m1_to_2 returns a dict")
	if typeof(again_raw) == TYPE_DICTIONARY:
		t.expect(int(again_raw.get("sim", {}).get("clock", {}).get("seed", 0)) == 9, "running _m1_to_2 on v2 keeps sim.clock")


func _newer_version(t: PetalAssert) -> void:
	var payload := {"version": 3, "state": {"name": "From the future", "sim": {"schema": 99}}}
	var state := _migrate_parsed(payload)
	t.expect(state.is_empty(), "newer saves are refused")


func _empty_and_corrupt(t: PetalAssert) -> void:
	t.expect(_migrate_text("").is_empty(), "empty text is refused")
	t.expect(_migrate_text("   \n").is_empty(), "whitespace-only text is refused")
	t.expect(_migrate_text("{not json").is_empty(), "corrupt json is refused")
	t.expect(_migrate_text("[]").is_empty(), "a json array is refused")
	t.expect(_migrate_parsed({"version": 1, "state": []}).is_empty(), "non-dict state is refused")
	var missing_state := _migrate_parsed({"version": 1})
	t.expect(int(missing_state.get("sim", {}).get("schema", 0)) == 1, "missing state still gets a sim skeleton")


func _missing_and_extra_keys(t: PetalAssert) -> void:
	var sparse := _migrate_parsed({"version": 1, "state": {"name": "Sparse"}})
	t.expect(int(sparse.get("sim", {}).get("schema", 0)) == 1, "missing sim is filled")
	t.expect(str(sparse.get("name", "")) == "Sparse", "sparse v1 name is kept")
	var extra := _migrate_parsed({
		"version": 1,
		"state": {"name": "Extra", "future_field": 12, "sim": {"schema": 1, "bonus": true}},
	})
	t.expect(int(extra.get("future_field", 0)) == 12, "extra keys survive v1 to v2")
	t.expect(bool(extra.get("sim", {}).get("bonus", false)), "extra sim keys survive v1 to v2")
	var v2_missing_schema := _migrate_parsed({"version": 2, "state": {"sim": {"clock": {}}}})
	t.expect(int(v2_missing_schema.get("sim", {}).get("schema", 0)) == 1, "v2 missing schema is filled without a re-migration")


func _write_roundtrip(t: PetalAssert) -> void:
	var slot := 91
	var path := str(_save().call("path_for", slot))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var ok: Variant = _save().call("write_slot", slot, {
		"name": "Round Trip",
		"clock": {"day": 2, "minute": 30.0},
		"economy": {"coins": 11},
		"sim": {"schema": 1, "clock": {"seed": 4242}},
	})
	t.expect(bool(ok), "v2 slot writes")
	var loaded_raw: Variant = _save().call("read_slot", slot)
	t.expect(typeof(loaded_raw) == TYPE_DICTIONARY, "written v2 slot reads a dict")
	if typeof(loaded_raw) == TYPE_DICTIONARY:
		t.expect(int(loaded_raw.get("sim", {}).get("schema", 0)) == 1, "written v2 slot reads as schema 1")
		t.expect(int(loaded_raw.get("economy", {}).get("coins", 0)) == 11, "written coins round-trip")
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	t.expect(typeof(parsed) == TYPE_DICTIONARY, "slot json is a dict")
	if typeof(parsed) == TYPE_DICTIONARY:
		t.expect(int(parsed.get("version", 0)) == 2, "new writes are version 2")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

extends Node

var levels := {}
var audit: Array = []
var lumen_proposal_day := -1
var lane_sale_day := -1
var bell_named_day := -1
var parish_bell_named_day := -1
var gate_bell_named_day := -1

func reset_new() -> void:
	levels = {"lumen": 0, "bram": 0, "nessa": 0}
	audit = []
	lumen_proposal_day = -1
	lane_sale_day = -1
	bell_named_day = -1
	parish_bell_named_day = -1
	gate_bell_named_day = -1

func level(person_id: String) -> int:
	return int(levels.get(person_id, 0))

func level_name(value: int) -> String:
	match value:
		0:
			return "Trust 0 · garden only"
		1:
			return "Trust 1 · parish notes"
		2:
			return "Trust 2 · drafts inside the parish"
		3:
			return "Trust 3 · may propose"
		4:
			return "Trust 4 · approved actions only"
		_:
			return "Trust 5 · bounded repeats"

func blurb(value: int) -> String:
	match value:
		0:
			return "No letters, no network, no spending outside the stall tin."
		1:
			return "May keep research notes in the parish book. Still no external tools."
		_:
			return "Higher trust is reserved. Nothing in this build can leave the machine."

func notices() -> PackedStringArray:
	# ponytail: two proposal lines; a board page if more than the tray and the draft are approved.
	var lines := PackedStringArray()
	for entry in audit:
		var action := str(entry.get("action", ""))
		if action == "peach_tray":
			lines.append("Peach tray set aside. The coins stayed in the parish.")
		elif action == "parish_draft":
			lines.append("Three episodes kept in the book. Nothing was sent.")
	return lines

func has_action(action_id: String) -> bool:
	for entry in audit:
		if str(entry.get("action", "")) == action_id:
			return true
	return false

func file_draft(person_id: String) -> void:
	# ponytail: one draft in the book; a stack of episodes if the parish keeps more than three.
	audit.append({
		"person": person_id,
		"action": "parish_draft",
		"result": "kept in the parish book",
		"impact": "simulation only",
		"external": false,
		"cost": 0,
		"note": "Three garden episodes drafted. Nothing was sent or spent.",
		"at": Time.get_datetime_string_from_system(),
	})

func file_lane_sale(person_id: String) -> void:
	# ponytail: one line a day; file_notes if a lane sale should raise trust.
	if lane_sale_day == Clock.day:
		return
	lane_sale_day = Clock.day
	audit.append({
		"person": person_id,
		"action": "parish_lane_sale",
		"result": "kept in the parish book",
		"impact": "simulation only",
		"external": false,
		"cost": 0,
		"note": "The lane paid one extra petal. Nothing left the parish.",
		"at": Time.get_datetime_string_from_system(),
	})

func file_road_rumour(person_id: String) -> void:
	# ponytail: one approved line; file_notes if a rumour should raise trust.
	if has_action("parish_road_rumour"):
		return
	audit.append({
		"person": person_id,
		"action": "parish_road_rumour",
		"result": "kept in the parish book",
		"impact": "simulation only",
		"external": false,
		"cost": 0,
		"note": "The road beyond the hedge is a rumour. Nothing left the parish.",
		"at": Time.get_datetime_string_from_system(),
	})

func file_bee_note(person_id: String, note: String = "Bees on the bed. Nothing was spent.") -> void:
	# ponytail: one bee line; file_notes if a note should raise trust.
	audit.append({
		"person": person_id,
		"action": "parish_bee_note",
		"result": "kept in the parish book",
		"impact": "simulation only",
		"external": false,
		"cost": 0,
		"note": note,
		"at": Time.get_datetime_string_from_system(),
	})

func file_notes(person_id: String, note: String) -> void:
	audit.append({
		"person": person_id,
		"action": "file_parish_notes",
		"result": "filed in the parish book",
		"impact": "simulation only",
		"note": note,
		"at": Time.get_datetime_string_from_system(),
	})
	if level(person_id) < 1:
		levels[person_id] = 1

func approve_spend(person_id: String, action_id: String, note: String, cost: int) -> bool:
	if not Economy.spend(cost):
		return false
	audit.append({
		"person": person_id,
		"action": action_id,
		"result": "approved",
		"impact": "parish coins only",
		"cost": cost,
		"note": note,
		"at": Time.get_datetime_string_from_system(),
	})
	lumen_proposal_day = Clock.day
	return true

func to_state() -> Dictionary:
	return {
		"levels": levels.duplicate(),
		"audit": audit.duplicate(true),
		"lumen_proposal_day": lumen_proposal_day,
		"lane_sale_day": lane_sale_day,
		"bell_named_day": bell_named_day,
		"parish_bell_named_day": parish_bell_named_day,
		"gate_bell_named_day": gate_bell_named_day,
	}

func apply_state(data: Dictionary) -> void:
	var saved_levels = data.get("levels", {})
	if typeof(saved_levels) == TYPE_DICTIONARY:
		levels = saved_levels.duplicate()
	var saved_audit = data.get("audit", [])
	audit = saved_audit.duplicate(true) if typeof(saved_audit) == TYPE_ARRAY else []
	lumen_proposal_day = int(data.get("lumen_proposal_day", -1))
	lane_sale_day = int(data.get("lane_sale_day", -1))
	bell_named_day = int(data.get("bell_named_day", -1))
	parish_bell_named_day = int(data.get("parish_bell_named_day", -1))
	gate_bell_named_day = int(data.get("gate_bell_named_day", -1))

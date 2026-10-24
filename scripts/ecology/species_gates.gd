class_name SpeciesGates
extends RefCounted

## Visit, resident, and romance tiers from species.json.
## A CausalLog, when bound, records why a tier changed.

const NOTE_CAP := 24

var rules := EcologyRules.new()
var tiers: Dictionary = {}
var notes: Array[String] = []
var log: CausalLog
var note_cb: Callable = Callable()


func boot(order: Array) -> void:
	for id_v in order:
		var id := str(id_v)
		if not tiers.has(id):
			tiers[id] = "closed"


func refresh(order: Array, catalog: Dictionary, world: Dictionary) -> Array:
	var changes: Array[String] = []
	for id_v in order:
		var id := str(id_v)
		var definition: Dictionary = catalog.get(id, {})
		var next := rules.highest_tier(definition, world)
		var prev := str(tiers.get(id, "closed"))
		if next == prev:
			continue
		var why := _why(definition, id, prev, next, world)
		tiers[id] = next
		_remember(why)
		changes.append(why)
		_write_log(id, why)
	return changes


func journal_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var start := maxi(notes.size() - 4, 0)
	for i in range(start, notes.size()):
		lines.append(notes[i])
	return lines


func to_state() -> Dictionary:
	return tiers.duplicate()


func apply_state(data: Variant) -> void:
	tiers.clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var body: Dictionary = data
	for key_v in body.keys():
		tiers[str(key_v)] = str(body[key_v])


func _why(definition: Dictionary, id: String, prev: String, next: String, world: Dictionary) -> String:
	var display := str(definition.get("name", id))
	var focus := _focus_tier(definition, world, prev, next)
	return "%s moved from %s to %s because %s." % [display, prev, next, rules.gate_summary(definition, world, focus)]


func _focus_tier(definition: Dictionary, world: Dictionary, prev: String, next: String) -> String:
	if rules.tier_rank(next) > rules.tier_rank(prev):
		return next
	for tier in ["visit", "resident", "romance"]:
		if rules.tier_rank(tier) <= rules.tier_rank(next):
			continue
		if not rules.gate_defined(definition, tier):
			continue
		if not rules.gate_met(definition, world, tier):
			return tier
	if next == "closed":
		return "visit"
	return next


func _remember(line: String) -> void:
	notes.append(line)
	if notes.size() > NOTE_CAP:
		notes.remove_at(0)
	if note_cb.is_valid():
		note_cb.call(line)


func _write_log(id: String, why: String) -> void:
	if log == null:
		return
	log.add({
		"kind": "gate_changed",
		"target": id,
		"cause": why,
		"summary": why,
	}, _now_min())


func _now_min() -> float:
	var clock := ServiceField.autoload("Clock")
	if clock != null and clock.has_method("absolute_minutes"):
		return float(clock.call("absolute_minutes"))
	return 0.0

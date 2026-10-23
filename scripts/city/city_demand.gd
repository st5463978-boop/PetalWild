class_name CityDemand
extends RefCounted

## Bloom, hive, and market demand in 0–100. Recomputed on each Clock hour.
## Weights live in data/demand.json. A CausalLog, when bound, records the reason.

signal demand_changed(kind: String, old: int, new: int, reason: String)

var bloom := 0
var hive := 0
var market := 0
var seed := 4242
var signals_for: Callable = Callable()

var services: ServiceField
var paths: PathGraph
var log: CausalLog
var soil: RefCounted
var ecology: Node
var rng := RandomNumberGenerator.new()

var _seen_hour := -1
var _lo := 0
var _hi := 100
var _kinds: Dictionary = {}


func _init() -> void:
	rng.seed = seed
	_load()


func setup(field: ServiceField, causal: CausalLog, beds: RefCounted, parish: Node, walk: PathGraph = null) -> void:
	services = field
	paths = walk
	log = causal
	soil = beds
	ecology = parish
	_load()


func reseed(next_seed: int) -> void:
	seed = next_seed
	rng.seed = seed


func tick() -> void:
	var key := _hour_key()
	if key == _seen_hour:
		return
	_seen_hour = key
	_apply_scores(_signals(), false)


func resync() -> void:
	_seen_hour = _hour_key()
	_apply_scores(_signals(), true)


func recompute(signals: Dictionary) -> void:
	_apply_scores(signals, false)


func journal_line() -> String:
	return "Bloom %d · Hive %d · Market %d" % [bloom, hive, market]


func journal_row() -> Dictionary:
	return {
		"name": "City demand",
		"status": "",
		"met": PackedStringArray(),
		"unmet": PackedStringArray(),
		"blurb": journal_line(),
		"romance": "",
		"romance_met": false,
		"residents": 0,
	}


func _apply_scores(signals: Dictionary, quiet: bool) -> void:
	var next := {
		"bloom": _score("bloom", signals),
		"hive": _score("hive", signals),
		"market": _score("market", signals),
	}
	for kind in ["bloom", "hive", "market"]:
		var old_value := int(get(kind))
		var new_value := int(next[kind])
		set(kind, new_value)
		if quiet or old_value == new_value:
			continue
		var why := _reason(kind, old_value, new_value, signals)
		demand_changed.emit(kind, old_value, new_value, why)
		_write_log(kind, why)


func _score(kind: String, signals: Dictionary) -> int:
	var spec: Dictionary = _kinds.get(kind, {})
	var bias := float(spec.get("bias", 0.0))
	var raw := bias
	var weight_body: Variant = spec.get("weights", {})
	if typeof(weight_body) == TYPE_DICTIONARY:
		var factors: Dictionary = weight_body
		for key_v in factors.keys():
			var factor := str(key_v)
			raw += float(factors[factor]) * float(signals.get(factor, 0.0))
	var mix := float(spec.get("seed_mix", 0.0))
	if mix != 0.0:
		raw += mix * float(rng.randi() % 5)
	return clampi(int(round(raw)), _lo, _hi)


func _reason(kind: String, old_value: int, new_value: int, signals: Dictionary) -> String:
	return "%s demand %+d because residents %d, free beds %d, quality %.2f, coins %d, stall stock %d, footfall %d" % [
		kind.capitalize(),
		new_value - old_value,
		int(signals.get("resident_total", 0)),
		int(signals.get("free_beds", 0)),
		float(signals.get("quality_mean", 0.0)),
		int(round(float(signals.get("coins", 0.0)))),
		int(signals.get("stall_stock", 0)),
		int(round(float(signals.get("footfall", 0.0)))),
	]


func _write_log(kind: String, why: String) -> void:
	if log == null:
		return
	log.add({
		"kind": "demand_changed",
		"target": kind,
		"cause": why,
		"summary": why,
	}, _now_min())


func _signals() -> Dictionary:
	if signals_for.is_valid():
		var provided: Variant = signals_for.call()
		if typeof(provided) == TYPE_DICTIONARY:
			return provided
	return _live_signals()


func _live_signals() -> Dictionary:
	var residents := 0
	if ecology != null and is_instance_valid(ecology) and ecology.has_method("resident_total"):
		residents = int(ecology.call("resident_total"))
	return {
		"resident_total": residents,
		"free_beds": _free_beds(),
		"quality_mean": services.quality_mean() if services != null else 0.0,
		"coins": _coins(),
		"stall_stock": _stall_stock(),
		"footfall": paths.footfall_signal() if paths != null else 0.0,
	}


func _free_beds() -> int:
	if soil == null or not soil.has_method("all"):
		return 0
	var cells: Variant = soil.call("all")
	if typeof(cells) != TYPE_ARRAY:
		return 0
	var free := 0
	for cell in cells:
		if typeof(cell) != TYPE_OBJECT or cell == null:
			continue
		var plot: Object = cell
		if str(plot.get("plant_id")) == "":
			free += 1
	return free


func _stall_stock() -> int:
	var content := ServiceField.autoload("ContentDB")
	var economy := ServiceField.autoload("Economy")
	if content == null or economy == null:
		return 0
	var order: Variant = content.get("plant_order")
	if typeof(order) != TYPE_ARRAY:
		return 0
	var stock := 0
	for plant_id in order:
		stock += int(economy.call("count", str(plant_id)))
	return stock


func _coins() -> int:
	var economy := ServiceField.autoload("Economy")
	if economy == null:
		return 0
	return int(economy.get("coins"))


func _hour_key() -> int:
	var clock := ServiceField.autoload("Clock")
	if clock == null:
		return _seen_hour
	return int(clock.get("day")) * 24 + int(floor(float(clock.call("hour"))))


func _now_min() -> float:
	var clock := ServiceField.autoload("Clock")
	if clock != null and clock.has_method("absolute_minutes"):
		return float(clock.call("absolute_minutes"))
	return 0.0


func _load() -> void:
	_kinds = {}
	_lo = 0
	_hi = 100
	var text := FileAccess.get_file_as_string("res://data/demand.json")
	if text == "":
		push_error("Missing data file res://data/demand.json")
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in res://data/demand.json")
		return
	var root: Dictionary = parsed
	_lo = int(root.get("min", 0))
	_hi = int(root.get("max", 100))
	var kinds: Variant = root.get("kinds", {})
	if typeof(kinds) == TYPE_DICTIONARY:
		_kinds = kinds

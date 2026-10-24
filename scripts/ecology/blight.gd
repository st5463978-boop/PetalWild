class_name Blight
extends RefCounted

## Blight-moths settle on neglected beds when garden quality is low.
## Lantern light, a helper, a warding plant, a guardian, or a fence sends them off.
## Tuning lives in data/ecology.json.

var moths: Array = []
var spawn_bank := 0
var next_id := 0
var steps := 0
var tuning: Dictionary = {}
var log: CausalLog
var services: ServiceField
var soil: SoilField
var rules: EcologyRules
var note_cb: Callable = Callable()
var pest_scale: Callable = Callable()
var _pest_frac := 0


func _init() -> void:
	_load()


func helper_catalog() -> Array:
	var body: Variant = tuning.get("counter_helpers", [])
	if typeof(body) != TYPE_ARRAY:
		return []
	return body


func hour(world: Dictionary, helpers: PackedStringArray) -> String:
	steps += 1
	if suppressed(world, helpers):
		spawn_bank = 0
		if moths.is_empty():
			return ""
		var why := "Blight-moths left because %s." % _counter_reason(world, helpers)
		moths.clear()
		_remember(why)
		_write_log("blight_cleared", why)
		return why
	var beds := _neglected()
	for moth_v in moths:
		if typeof(moth_v) != TYPE_DICTIONARY:
			continue
		var moth: Dictionary = moth_v
		var plot := _cell(int(moth.get("ix", -1)), int(moth.get("iz", -1)))
		if plot == null:
			continue
		_damage(plot)
	var quality := float(world.get("garden_quality", 1.0))
	if quality >= float(tuning.get("quality_max", 0.34)) or beds.size() < int(tuning.get("neglected_min", 2)):
		return ""
	spawn_bank += 1 + _pest_adjust()
	if spawn_bank < 0:
		spawn_bank = 0
	var every := maxi(int(tuning.get("spawn_every", 4)), 1)
	if spawn_bank < every:
		return ""
	spawn_bank = 0
	if moths.size() >= int(tuning.get("cap", 4)):
		return ""
	var spot := _pick(beds)
	if spot == null:
		return ""
	next_id += 1
	moths.append({"id": next_id, "ix": spot.ix, "iz": spot.iz})
	var settled := "A blight-moth settled on bed %d,%d because garden quality %.2f and %d neglected beds." % [spot.ix, spot.iz, quality, beds.size()]
	_remember(settled)
	_write_log("blight_spawned", settled)
	return settled


func suppressed(world: Dictionary, helpers: PackedStringArray) -> bool:
	return counter_pressure(world, helpers) + 0.0001 >= float(tuning.get("suppress_at", 1.0))


func counter_pressure(world: Dictionary, helpers: PackedStringArray) -> float:
	var total := 0.0
	if _service_on(world):
		total += float(tuning.get("service_weight", 0.0))
	if _helpers_on(helpers):
		total += float(tuning.get("helper_weight", 0.0))
	if _plants_on(world):
		total += float(tuning.get("plant_weight", 0.0))
	if _guardians_on(world):
		total += float(tuning.get("guardian_weight", 0.0))
	if _structures_on(world):
		total += float(tuning.get("structure_weight", 0.0))
	return total


func to_state() -> Dictionary:
	return {
		"moths": moths.duplicate(true),
		"spawn_bank": spawn_bank,
		"next_id": next_id,
		"steps": steps,
	}


func apply_state(data: Variant) -> void:
	moths.clear()
	spawn_bank = 0
	next_id = 0
	steps = 0
	if typeof(data) != TYPE_DICTIONARY:
		return
	var body: Dictionary = data
	spawn_bank = int(body.get("spawn_bank", 0))
	next_id = int(body.get("next_id", 0))
	steps = int(body.get("steps", 0))
	var rows: Variant = body.get("moths", [])
	if typeof(rows) != TYPE_ARRAY:
		return
	for item_v in rows:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_v
		moths.append({
			"id": int(item.get("id", 0)),
			"ix": int(item.get("ix", 0)),
			"iz": int(item.get("iz", 0)),
		})


func _pest_adjust() -> int:
	if not pest_scale.is_valid():
		return 0
	var scale := float(pest_scale.call())
	if is_equal_approx(scale, 1.0):
		return 0
	_pest_frac += int(round((scale - 1.0) * 100.0))
	var steps := 0
	while _pest_frac >= 100:
		_pest_frac -= 100
		steps += 1
	while _pest_frac <= -100:
		_pest_frac += 100
		steps -= 1
	return steps


func _damage(plot: SoilCell) -> void:
	plot.growth = maxf(0.0, plot.growth - float(tuning.get("damage_growth", 0.0)))
	plot.wilt += float(tuning.get("damage_wilt", 0.0))


func _pick(beds: Array) -> SoilCell:
	for bed_v in beds:
		var plot: SoilCell = bed_v
		if not _occupied(plot.ix, plot.iz):
			return plot
	if beds.is_empty():
		return null
	return beds[0] as SoilCell


func _occupied(ix: int, iz: int) -> bool:
	for moth_v in moths:
		if typeof(moth_v) != TYPE_DICTIONARY:
			continue
		var moth: Dictionary = moth_v
		if int(moth.get("ix", -1)) == ix and int(moth.get("iz", -1)) == iz:
			return true
	return false


func _neglected() -> Array:
	var found: Array = []
	if soil == null:
		return found
	var dry_at := float(tuning.get("neglected_moisture", 0.18))
	var wilt_at := float(tuning.get("neglected_wilt", 1.0))
	for cell_v in soil.all():
		var plot: SoilCell = cell_v
		if plot.plant_id == "":
			continue
		var dry := plot.moisture <= dry_at
		var wilted := plot.wilt >= wilt_at
		if dry or wilted:
			found.append(plot)
	found.sort_custom(func(a, b):
		var left: SoilCell = a
		var right: SoilCell = b
		if left.ix == right.ix:
			return left.iz < right.iz
		return left.ix < right.ix
	)
	return found


func _cell(ix: int, iz: int) -> SoilCell:
	if soil == null:
		return null
	return soil.get_cell(ix, iz)


func _service_on(world: Dictionary) -> bool:
	var field := _field(world)
	if field == null:
		return false
	var channel := str(tuning.get("counter_channel", ""))
	if channel != "" and field.channel_max(channel) >= float(tuning.get("counter_channel_min", 1.0)):
		return true
	var wanted: Variant = tuning.get("counter_services", [])
	if typeof(wanted) != TYPE_ARRAY:
		return false
	for stamp_v in field.stamps.keys():
		var bare := _bare(str(stamp_v))
		for item_v in wanted:
			if str(item_v) == bare:
				return true
	return false


func _field(world: Dictionary) -> ServiceField:
	if services != null:
		return services
	var body: Variant = world.get("service_field", null)
	if body is ServiceField:
		return body
	return null


func _helpers_on(helpers: PackedStringArray) -> bool:
	for item_v in helper_catalog():
		if helpers.has(str(item_v)):
			return true
	return false


func _plants_on(world: Dictionary) -> bool:
	var mature: Dictionary = world.get("mature", {})
	var wanted: Variant = tuning.get("counter_plants", [])
	if typeof(wanted) != TYPE_ARRAY:
		return false
	var minimum := int(tuning.get("counter_plant_min", 1))
	for item_v in wanted:
		if int(mature.get(str(item_v), 0)) >= minimum:
			return true
	return false


func _guardians_on(world: Dictionary) -> bool:
	if rules == null:
		return false
	var states: Dictionary = world.get("species_state", {})
	var wanted: Variant = tuning.get("counter_guardians", [])
	if typeof(wanted) != TYPE_ARRAY:
		return false
	var need := str(tuning.get("guardian_state", "resident"))
	for item_v in wanted:
		var have := str(states.get(str(item_v), "unknown"))
		if rules.rank_of(have) >= rules.rank_of(need):
			return true
	return false


func _structures_on(world: Dictionary) -> bool:
	var structures: Dictionary = world.get("structures", {})
	var wanted: Variant = tuning.get("counter_structures", [])
	if typeof(wanted) != TYPE_ARRAY:
		return false
	for item_v in wanted:
		if int(structures.get(str(item_v), 0)) >= 1:
			return true
	return false


func _counter_reason(world: Dictionary, helpers: PackedStringArray) -> String:
	var parts := PackedStringArray()
	if _service_on(world):
		parts.append("lantern light covers the beds")
	if _helpers_on(helpers):
		parts.append("a helper is on the beds")
	if _plants_on(world):
		parts.append("a warding plant is mature")
	if _guardians_on(world):
		parts.append("a guardian is resident")
	if _structures_on(world):
		parts.append("a fence stands in the parish")
	if parts.is_empty():
		return "the garden is watched"
	return ", ".join(parts)


func _bare(service_id: String) -> String:
	var cut := service_id.find("#")
	if cut == -1:
		return service_id
	return service_id.substr(0, cut)


func _remember(line: String) -> void:
	if note_cb.is_valid():
		note_cb.call(line)


func _write_log(kind: String, why: String) -> void:
	if log == null:
		return
	log.add({
		"kind": kind,
		"target": str(tuning.get("id", "blight_moth")),
		"cause": why,
		"summary": why,
	}, float(steps))


func _load() -> void:
	tuning = {}
	var text := FileAccess.get_file_as_string("res://data/ecology.json")
	if text == "":
		push_error("Missing data file res://data/ecology.json")
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in res://data/ecology.json")
		return
	var root: Dictionary = parsed
	var body: Variant = root.get("blight", {})
	if typeof(body) == TYPE_DICTIONARY:
		tuning = body

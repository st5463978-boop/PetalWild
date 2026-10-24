class_name GardenDistricts
extends RefCounted

## Player-painted bed groups. Policies from data/policies.json shift the service
## field, city demand, the food web, pest pressure, and daily upkeep.
## Distant groups use SimLod: full near the camera target, every N hours farther
## out, and statistical-only past the far band.

var active_id := ""
var charged_day := 0
var next_index := 1
var services: ServiceField
var log: CausalLog

var _order: PackedStringArray = PackedStringArray()
var _rows: Dictionary = {}
var _owners: Dictionary = {}
var _catalog: Dictionary = {}
var _policy_order: PackedStringArray = PackedStringArray()
var _names: PackedStringArray = PackedStringArray()
var _lod: Dictionary = {}
var _tiers: Dictionary = {}
var _cached_quality: Dictionary = {}
var _sampled: Dictionary = {}
var _policy_cursor := 0


func setup(field: ServiceField, causal: CausalLog) -> void:
	services = field
	log = causal
	_load()


func begin_next() -> String:
	var label := _fresh_name()
	var id := _unique_id(_slug(label))
	_add_row(id, label)
	active_id = id
	var why := "Started %s because the player opened a new bed group." % label
	_log("district_opened", id, why)
	return why


func toggle_paint(cell: Vector2i) -> String:
	if active_id == "" or not _rows.has(active_id):
		begin_next()
	if owner_of(cell) == active_id:
		return _release(active_id, cell)
	return _claim(active_id, cell)


func paint_cell(district_id: String, cell: Vector2i, district_name: String = "") -> String:
	if district_id == "":
		return ""
	if not _rows.has(district_id):
		var label := district_name
		if label == "":
			label = district_id
		_add_row(district_id, label)
	active_id = district_id
	if owner_of(cell) == district_id:
		return "%s already holds bed %d,%d." % [_name(district_id), cell.x, cell.y]
	return _claim(district_id, cell)


func set_policy(district_id: String, policy_id: String, enabled: bool) -> String:
	if not _rows.has(district_id) or not _catalog.has(policy_id):
		return ""
	var policies := _policy_map(district_id)
	var have := policies.has(policy_id)
	if enabled == have:
		return ""
	if enabled:
		policies[policy_id] = true
	else:
		policies.erase(policy_id)
	_row(district_id)["policies"] = policies
	var why := ""
	if enabled:
		why = "%s adopted %s because the player set the policy." % [_name(district_id), _policy_name(policy_id)]
	else:
		why = "%s dropped %s because the player cleared the policy." % [_name(district_id), _policy_name(policy_id)]
	_log("district_policy", district_id, why)
	return why


func cycle_policy() -> String:
	if active_id == "" or _cell_count(active_id) <= 0:
		return "Paint a bed group before setting a policy."
	if _policy_order.is_empty():
		return ""
	var policy_id := _policy_order[_policy_cursor % _policy_order.size()]
	_policy_cursor += 1
	var turning_on := not _policy_map(active_id).has(policy_id)
	return set_policy(active_id, policy_id, turning_on)


func owner_of(cell: Vector2i) -> String:
	return str(_owners.get(_key(cell), ""))


func ids() -> PackedStringArray:
	return _order.duplicate()


func tier_of(district_id: String) -> int:
	return int(_tiers.get(district_id, 1))


func centroid(district_id: String) -> Vector3:
	return _centroid(district_id)


func quality_of(district_id: String) -> float:
	if _cached_quality.has(district_id):
		return float(_cached_quality[district_id])
	return _mean_quality(district_id)


func land_value(district_id: String) -> int:
	if not _rows.has(district_id):
		return 0
	var quality := quality_of(district_id) + _land_bonus(district_id)
	return clampi(int(round(quality * 100.0)), 0, 100)


func paint_amount(cell: Vector2i) -> float:
	var district_id := owner_of(cell)
	if district_id == "":
		return 0.0
	return clampf(0.18 + 0.82 * float(land_value(district_id)) / 100.0, 0.0, 1.0)


func service_bias(cell: Vector2i, channel: String) -> float:
	var district_id := owner_of(cell)
	if district_id == "":
		return 0.0
	if _statistical(district_id):
		return 0.0
	var total := 0.0
	for policy_id in _policy_ids(district_id):
		var spec := _spec(policy_id)
		if not _hours_open(spec):
			continue
		var channels: Variant = spec.get("service", {})
		if typeof(channels) != TYPE_DICTIONARY:
			continue
		total += float((channels as Dictionary).get(channel, 0.0))
	return total


func demand_offset(kind: String) -> float:
	var total := 0.0
	for district_id in _order:
		if _cell_count(district_id) <= 0:
			continue
		var damp := _demand_damp(district_id)
		for policy_id in _policy_ids(district_id):
			var body: Variant = _spec(policy_id).get("demand", {})
			if typeof(body) != TYPE_DICTIONARY:
				continue
			total += float((body as Dictionary).get(kind, 0.0)) * damp
	return total


func demand_reason(kind: String) -> String:
	var parts := PackedStringArray()
	for district_id in _order:
		if _cell_count(district_id) <= 0:
			continue
		var damp := _demand_damp(district_id)
		for policy_id in _policy_ids(district_id):
			var body: Variant = _spec(policy_id).get("demand", {})
			if typeof(body) != TYPE_DICTIONARY:
				continue
			var delta := float((body as Dictionary).get(kind, 0.0)) * damp
			if is_zero_approx(delta):
				continue
			parts.append("%s on %s %+d" % [_policy_name(policy_id), _name(district_id), int(round(delta))])
	if parts.is_empty():
		return ""
	return "policies %s." % ", ".join(parts)


func food_scale(kind: String) -> float:
	var scale := 1.0
	var touched := false
	for district_id in _order:
		if _cell_count(district_id) <= 0 or _statistical(district_id):
			continue
		var damp := 1.0
		if _tiers.has(district_id) and _stride(tier_of(district_id)) > 1:
			damp = float(_lod.get("stride_food", 0.75))
		for policy_id in _policy_ids(district_id):
			var body: Variant = _spec(policy_id).get("food", {})
			if typeof(body) != TYPE_DICTIONARY:
				continue
			var factor := float((body as Dictionary).get(kind, 1.0))
			if is_equal_approx(factor, 1.0):
				continue
			touched = true
			scale *= lerpf(1.0, factor, damp)
	if not touched:
		return 1.0
	return maxf(scale, 0.0)


func pest_scale() -> float:
	var scale := 1.0
	for district_id in _order:
		if _cell_count(district_id) <= 0 or _statistical(district_id):
			continue
		for policy_id in _policy_ids(district_id):
			var factor := float(_spec(policy_id).get("pest", 1.0))
			if factor > 0.0 and not is_equal_approx(factor, 1.0):
				scale *= factor
	return maxf(scale, 0.0)


func upkeep_total() -> int:
	var due := 0
	for district_id in _order:
		if _cell_count(district_id) <= 0:
			continue
		for policy_id in _policy_ids(district_id):
			due += maxi(int(_spec(policy_id).get("upkeep", 0)), 0)
	return due


func income_total() -> int:
	var bonus := 0
	for district_id in _order:
		if _cell_count(district_id) <= 0:
			continue
		for policy_id in _policy_ids(district_id):
			bonus += maxi(int(_spec(policy_id).get("income", 0)), 0)
	return bonus


func charge_daily(day: int) -> int:
	if day <= charged_day:
		return 0
	charged_day = day
	var economy := ServiceField.autoload("Economy")
	if economy == null:
		return 0
	_pay_income(economy)
	return _pay_upkeep(economy)


func refresh(focus: Vector3, hour_key: int) -> void:
	var payload: Array = []
	for district_id in _order:
		var dist := focus.distance_to(_centroid(district_id))
		var tier := _classify(dist)
		_tiers[district_id] = tier
		if _sample_due(district_id, tier, hour_key):
			_cached_quality[district_id] = _mean_quality(district_id)
			_sampled[district_id] = hour_key
		payload.append(_lod_row(district_id, dist, tier))
	var lod := ServiceField.autoload("SimLod")
	if lod != null and lod.has_method("note_districts"):
		lod.call("note_districts", payload)


func hover_suffix(cell: Vector2i) -> String:
	var district_id := owner_of(cell)
	if district_id == "":
		return ""
	return "  ·  %s · land %d" % [_name(district_id), land_value(district_id)]


func journal_row() -> Dictionary:
	var lines := PackedStringArray()
	for district_id in _order:
		if _cell_count(district_id) <= 0 and _policy_ids(district_id).is_empty():
			continue
		lines.append("%s · land %d · %s" % [_name(district_id), land_value(district_id), _policy_label(district_id)])
	var blurb := "No bed groups yet. The district tool paints one."
	if not lines.is_empty():
		blurb = "Painted bed groups and the policies on them."
	return {
		"name": "Districts",
		"status": "",
		"met": lines,
		"unmet": PackedStringArray(),
		"blurb": blurb,
		"romance": "",
		"romance_met": false,
		"residents": 0,
	}


func to_state() -> Dictionary:
	return {
		"rows": _export_rows(),
		"charged_day": charged_day,
		"active": active_id,
		"next_index": next_index,
		"policy_cursor": _policy_cursor,
	}


func apply_state(data: Variant) -> void:
	_clear()
	var pack: Variant = data
	if typeof(data) == TYPE_DICTIONARY:
		var body: Dictionary = data
		if body.has("rows") or body.has("districts") or body.has("services") or body.has("paths"):
			if body.has("districts"):
				pack = body.get("districts")
			elif body.has("rows"):
				pack = body
			else:
				pack = {}
	if typeof(pack) != TYPE_DICTIONARY:
		return
	var packed: Dictionary = pack
	charged_day = int(packed.get("charged_day", 0))
	next_index = maxi(int(packed.get("next_index", 1)), 1)
	_policy_cursor = maxi(int(packed.get("policy_cursor", 0)), 0)
	var rows: Variant = packed.get("rows", [])
	if typeof(rows) != TYPE_ARRAY:
		return
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var district_id := str(row.get("id", ""))
		if district_id == "":
			continue
		_add_row(district_id, str(row.get("name", district_id)))
		var cells: Variant = row.get("cells", [])
		if typeof(cells) == TYPE_ARRAY:
			for cell_v in cells:
				if typeof(cell_v) != TYPE_DICTIONARY:
					continue
				var cell_body: Dictionary = cell_v
				_add_cell(district_id, Vector2i(int(cell_body.get("x", 0)), int(cell_body.get("z", 0))))
		var policies: Variant = row.get("policies", [])
		if typeof(policies) != TYPE_ARRAY:
			continue
		var enabled: Dictionary = {}
		for policy_v in policies:
			var policy_id := str(policy_v)
			if policy_id != "":
				enabled[policy_id] = true
		_row(district_id)["policies"] = enabled
	active_id = str(packed.get("active", ""))
	if active_id != "" and not _rows.has(active_id):
		active_id = ""
	if active_id == "" and not _order.is_empty():
		active_id = _order[0]


func _claim(district_id: String, cell: Vector2i) -> String:
	var previous := owner_of(cell)
	if previous != "" and previous != district_id:
		_drop_cell(previous, cell)
	_add_cell(district_id, cell)
	var why := "%s took bed %d,%d because the player painted it into the district." % [_name(district_id), cell.x, cell.y]
	if previous != "" and previous != district_id:
		why = "%s took bed %d,%d from %s because the player painted it into the district." % [_name(district_id), cell.x, cell.y, _name(previous)]
	_log("district_painted", district_id, why)
	return why


func _release(district_id: String, cell: Vector2i) -> String:
	_drop_cell(district_id, cell)
	var why := "%s released bed %d,%d because the player painted it out." % [_name(district_id), cell.x, cell.y]
	_log("district_painted", district_id, why)
	return why


func _pay_income(economy: Node) -> void:
	if not economy.has_method("earn"):
		return
	for district_id in _order:
		if _cell_count(district_id) <= 0:
			continue
		var bonus := 0
		var names := PackedStringArray()
		for policy_id in _policy_ids(district_id):
			var coins := maxi(int(_spec(policy_id).get("income", 0)), 0)
			if coins <= 0:
				continue
			bonus += coins
			names.append(_policy_name(policy_id))
		if bonus <= 0:
			continue
		economy.call("earn", bonus)
		var why := "%s earned %d coins because %s is in force." % [_name(district_id), bonus, ", ".join(names)]
		_log("district_income", district_id, why)


func _pay_upkeep(economy: Node) -> int:
	if not economy.has_method("deduct"):
		return 0
	var paid := 0
	for district_id in _order:
		if _cell_count(district_id) <= 0:
			continue
		var due := 0
		var names := PackedStringArray()
		for policy_id in _policy_ids(district_id):
			var coins := maxi(int(_spec(policy_id).get("upkeep", 0)), 0)
			if coins <= 0:
				continue
			due += coins
			names.append(_policy_name(policy_id))
		if due <= 0:
			continue
		var got := int(economy.call("deduct", due))
		paid += got
		if got <= 0:
			continue
		var why := "%s paid %d coins because %s is in force." % [_name(district_id), got, ", ".join(names)]
		_log("district_upkeep", district_id, why)
	return paid


func _sample_due(district_id: String, tier: int, hour_key: int) -> bool:
	if not _cached_quality.has(district_id):
		return true
	var stride := _stride(tier)
	if stride == 1:
		return true
	var seen := int(_sampled.get(district_id, -999999))
	if seen == hour_key:
		return false
	if stride > 0:
		return hour_key % stride == 0
	var every := maxi(int(_lod.get("statistical_every", 6)), 1)
	return hour_key % every == 0


func _lod_row(district_id: String, dist: float, tier: int) -> Dictionary:
	var policies: Array = []
	for policy_id in _policy_ids(district_id):
		policies.append(policy_id)
	return {
		"id": district_id,
		"name": _name(district_id),
		"tier": tier,
		"distance": dist,
		"quality": quality_of(district_id),
		"land_value": land_value(district_id),
		"policies": policies,
		"cells": _cell_count(district_id),
		"statistical": _stride(tier) == 0,
	}


func _mean_quality(district_id: String) -> float:
	if services == null or _cell_count(district_id) <= 0:
		return 0.0
	var total := 0.0
	var count := 0
	var cells: Dictionary = _cell_map(district_id)
	for key_v in cells.keys():
		var parts := str(key_v).split(",")
		if parts.size() != 2:
			continue
		total += services.quality_at(Vector2i(int(parts[0]), int(parts[1])))
		count += 1
	if count <= 0:
		return 0.0
	return total / float(count)


func _land_bonus(district_id: String) -> float:
	var bonus := 0.0
	for policy_id in _policy_ids(district_id):
		bonus += float(_spec(policy_id).get("land", 0.0))
	return bonus


func _demand_damp(district_id: String) -> float:
	if not _tiers.has(district_id):
		return 1.0
	var stride := _stride(tier_of(district_id))
	if stride == 0:
		return float(_lod.get("statistical_demand", 0.5))
	if stride > 1:
		return float(_lod.get("stride_demand", 0.85))
	return 1.0


func _statistical(district_id: String) -> bool:
	return _tiers.has(district_id) and _stride(tier_of(district_id)) == 0


func _classify(dist: float) -> int:
	var lod := ServiceField.autoload("SimLod")
	if lod != null and lod.has_method("classify"):
		return int(lod.call("classify", dist, false, false))
	if dist < 7.5:
		return 1
	if dist < 16.0:
		return 2
	if dist < 36.0:
		return 3
	return 4


func _stride(tier: int) -> int:
	var lod := ServiceField.autoload("SimLod")
	if lod != null and lod.has_method("stride_for"):
		return int(lod.call("stride_for", tier))
	if tier <= 1:
		return 1
	if tier == 2:
		return int(_lod.get("stride_2", 2))
	if tier == 3:
		return int(_lod.get("stride_3", 4))
	return 0


func _hours_open(spec: Dictionary) -> bool:
	var hours: Variant = spec.get("hours", null)
	if typeof(hours) != TYPE_DICTIONARY:
		return true
	var window: Dictionary = hours
	var clock := ServiceField.autoload("Clock")
	if clock == null or not clock.has_method("hour"):
		return true
	var h := float(clock.call("hour"))
	var start := float(window.get("from", 0.0))
	var ending := float(window.get("to", 24.0))
	if is_equal_approx(start, ending):
		return true
	if start < ending:
		return h >= start and h < ending
	return h >= start or h < ending


func _centroid(district_id: String) -> Vector3:
	var cells: Dictionary = _cell_map(district_id)
	if cells.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var count := 0
	for key_v in cells.keys():
		var parts := str(key_v).split(",")
		if parts.size() != 2:
			continue
		sum += GardenLayout.cell_center(int(parts[0]), int(parts[1]))
		count += 1
	if count <= 0:
		return Vector3.ZERO
	return sum / float(count)


func _export_rows() -> Array:
	var rows: Array = []
	for district_id in _order:
		var cells: Array = []
		var keys: Array = _cell_map(district_id).keys()
		keys.sort()
		for key_v in keys:
			var parts := str(key_v).split(",")
			if parts.size() != 2:
				continue
			cells.append({"x": int(parts[0]), "z": int(parts[1])})
		var policies: Array = []
		for policy_id in _policy_ids(district_id):
			policies.append(policy_id)
		rows.append({
			"id": district_id,
			"name": _name(district_id),
			"cells": cells,
			"policies": policies,
		})
	return rows


func _add_row(district_id: String, label: String) -> void:
	if _rows.has(district_id):
		return
	_rows[district_id] = {
		"id": district_id,
		"name": label,
		"cells": {},
		"policies": {},
	}
	_order.append(district_id)


func _add_cell(district_id: String, cell: Vector2i) -> void:
	var cells := _cell_map(district_id)
	cells[_key(cell)] = true
	_row(district_id)["cells"] = cells
	_owners[_key(cell)] = district_id


func _drop_cell(district_id: String, cell: Vector2i) -> void:
	var cells := _cell_map(district_id)
	var key := _key(cell)
	cells.erase(key)
	_row(district_id)["cells"] = cells
	if str(_owners.get(key, "")) == district_id:
		_owners.erase(key)


func _clear() -> void:
	_order = PackedStringArray()
	_rows = {}
	_owners = {}
	_tiers = {}
	_cached_quality = {}
	_sampled = {}
	active_id = ""
	charged_day = 0
	next_index = 1
	_policy_cursor = 0


func _row(district_id: String) -> Dictionary:
	var found: Variant = _rows.get(district_id, {})
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return found


func _cell_map(district_id: String) -> Dictionary:
	var body: Variant = _row(district_id).get("cells", {})
	if typeof(body) != TYPE_DICTIONARY:
		return {}
	return body


func _policy_map(district_id: String) -> Dictionary:
	var body: Variant = _row(district_id).get("policies", {})
	if typeof(body) != TYPE_DICTIONARY:
		return {}
	return body


func _policy_ids(district_id: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for policy_id in _policy_order:
		if _policy_map(district_id).has(policy_id):
			ids.append(policy_id)
	var extra: Array = _policy_map(district_id).keys()
	extra.sort()
	for policy_v in extra:
		var policy_id := str(policy_v)
		if not ids.has(policy_id):
			ids.append(policy_id)
	return ids


func _policy_label(district_id: String) -> String:
	var names := PackedStringArray()
	for policy_id in _policy_ids(district_id):
		names.append(_policy_name(policy_id))
	if names.is_empty():
		return "no policy"
	return ", ".join(names)


func _cell_count(district_id: String) -> int:
	return _cell_map(district_id).size()


func _name(district_id: String) -> String:
	return str(_row(district_id).get("name", district_id))


func _policy_name(policy_id: String) -> String:
	return str(_spec(policy_id).get("name", policy_id))


func _spec(policy_id: String) -> Dictionary:
	var found: Variant = _catalog.get(policy_id, {})
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return found


func _fresh_name() -> String:
	if _names.is_empty():
		return "Bed group %d" % next_index
	return _names[(next_index - 1) % _names.size()]


func _unique_id(base: String) -> String:
	var id := base
	if id == "":
		id = "bed_group"
	if not _rows.has(id):
		next_index += 1
		return id
	id = "%s_%d" % [base, next_index]
	next_index += 1
	return id


func _slug(label: String) -> String:
	var out := ""
	for i in label.length():
		var ch := label.substr(i, 1).to_lower()
		if ch == " ":
			out += "_"
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	if out == "":
		return "bed_group"
	return out


func _key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _log(kind: String, target: String, why: String) -> void:
	if log == null or why == "":
		return
	log.add({
		"kind": kind,
		"target": target,
		"cause": why,
		"summary": why,
	}, _now_min())


func _now_min() -> float:
	var clock := ServiceField.autoload("Clock")
	if clock != null and clock.has_method("absolute_minutes"):
		return float(clock.call("absolute_minutes"))
	return 0.0


func _load() -> void:
	_catalog = {}
	_policy_order = PackedStringArray()
	_names = PackedStringArray()
	_lod = {}
	var text := FileAccess.get_file_as_string("res://data/policies.json")
	if text == "":
		push_error("Missing data file res://data/policies.json")
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in res://data/policies.json")
		return
	var root: Dictionary = parsed
	var lod_body: Variant = root.get("lod", {})
	if typeof(lod_body) == TYPE_DICTIONARY:
		_lod = lod_body
	var name_rows: Variant = root.get("names", [])
	if typeof(name_rows) == TYPE_ARRAY:
		for item in name_rows:
			var label := str(item)
			if label != "":
				_names.append(label)
	var rows: Variant = root.get("policies", [])
	if typeof(rows) != TYPE_ARRAY:
		return
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = item
		var policy_id := str(row.get("id", ""))
		if policy_id == "":
			continue
		_catalog[policy_id] = row
		_policy_order.append(policy_id)

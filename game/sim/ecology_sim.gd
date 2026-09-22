extends RefCounted

const ORDER := [
	"UNKNOWN",
	"SIGHTED",
	"CURIOUS",
	"VISITOR",
	"REPEAT_VISITOR",
	"SETTLER",
	"RESIDENT",
	"BONDED",
	"BREEDING",
	"VARIANT",
	"LEGENDARY",
]

var defs: Dictionary = {}
var records: Dictionary = {}


func setup(species_list: Array) -> void:
	defs.clear()
	records.clear()
	for entry in species_list:
		var spec: Dictionary = entry
		var id := str(spec.get("id", ""))
		if id == "":
			continue
		defs[id] = spec
		records[id] = {
			"id": id,
			"state": "UNKNOWN",
			"dwell": 0.0,
			"unmet": 0.0,
			"visits": 0,
			"bond": 0.4,
			"mood": "calm",
			"harassment": 0,
			"home": false,
			"present": false,
			"rare": false,
			"x": 0.0,
			"z": 0.0,
			"fidelity": 2,
		}


func rank(state: String) -> int:
	var found := ORDER.find(state)
	return found if found >= 0 else 0


func requirements_met(spec: Dictionary, ctx: Dictionary) -> bool:
	for raw in spec.get("requirements", []):
		if not _req_ok(raw, ctx):
			return false
	return true


func requirements_close(spec: Dictionary, ctx: Dictionary) -> bool:
	var reqs: Array = spec.get("requirements", [])
	if reqs.is_empty():
		return false
	var hits := 0
	for raw in reqs:
		if _req_ok(raw, ctx, 0.5):
			hits += 1
	return hits * 2 >= reqs.size()


func progress_lines(spec: Dictionary, ctx: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for raw in spec.get("requirements", []):
		var req: Dictionary = raw
		var ok := _req_ok(req, ctx)
		var label := str(req.get("label", req.get("type", "need")))
		lines.append(("ready" if ok else "unmet") + " — " + label)
	return lines


func evaluate(ctx: Dictionary, delta: float) -> Array:
	var events: Array = []
	for id in records.keys():
		var spec: Dictionary = defs[id]
		var rec: Dictionary = records[id]
		var met := requirements_met(spec, ctx)
		var close := met or requirements_close(spec, ctx)
		if met:
			rec.dwell = float(rec.dwell) + delta
			rec.unmet = 0.0
		else:
			rec.dwell = maxf(0.0, float(rec.dwell) - delta * 0.35)
			rec.unmet = float(rec.unmet) + delta
		var before := str(rec.state)
		_advance(rec, spec, met, close)
		_apply_gifts(spec, rec, ctx)
		if str(rec.state) != before:
			events.append({
				"type": "state",
				"id": id,
				"name": spec.get("name", id),
				"from": before,
				"to": rec.state,
			})
	return events


func grant_home(id: String) -> bool:
	if not records.has(id):
		return false
	var rec: Dictionary = records[id]
	if rank(str(rec.state)) < rank("SETTLER"):
		return false
	rec.home = true
	if rank(str(rec.state)) < rank("RESIDENT"):
		rec.state = "RESIDENT"
	rec.present = true
	rec.bond = minf(1.0, float(rec.bond) + 0.12)
	rec.mood = "happy"
	return true


func best_settler() -> String:
	var best := ""
	var best_rank := rank("SETTLER")
	for id in records.keys():
		var rec: Dictionary = records[id]
		if bool(rec.home):
			continue
		if rank(str(rec.state)) >= best_rank:
			return id
	return best


func resident_count() -> int:
	var count := 0
	for id in records.keys():
		if rank(str(records[id].state)) >= rank("RESIDENT"):
			count += 1
	return count


func sighting_count() -> int:
	var count := 0
	for id in records.keys():
		if rank(str(records[id].state)) >= rank("SIGHTED"):
			count += 1
	return count


func adjust_bond(id: String, amount: float, mood: String) -> void:
	if not records.has(id):
		return
	var rec: Dictionary = records[id]
	rec.bond = clampf(float(rec.bond) + amount, 0.0, 1.0)
	rec.mood = mood
	if amount < 0.0:
		rec.harassment = int(rec.harassment) + 1
	if str(rec.state) == "RESIDENT" and float(rec.bond) >= 0.72:
		rec.state = "BONDED"
	if int(rec.harassment) >= 4 and rank(str(rec.state)) >= rank("VISITOR") and rank(str(rec.state)) < rank("RESIDENT"):
		rec.mood = "flee"
		rec.present = false
		rec.state = "CURIOUS"


func to_dict() -> Dictionary:
	return {"records": records.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	var loaded: Dictionary = data.get("records", {})
	for id in records.keys():
		if loaded.has(id):
			var incoming: Dictionary = loaded[id]
			var rec: Dictionary = records[id]
			for key in incoming.keys():
				rec[key] = incoming[key]


func _advance(rec: Dictionary, spec: Dictionary, met: bool, close: bool) -> void:
	var state := str(rec.state)
	match state:
		"UNKNOWN":
			if close:
				rec.state = "SIGHTED"
		"SIGHTED":
			if met:
				rec.state = "CURIOUS"
		"CURIOUS":
			if met and float(rec.dwell) >= 4.0:
				rec.state = "VISITOR"
				rec.present = true
				rec.visits = int(rec.visits) + 1
				rec.dwell = 0.0
				rec.mood = "curious"
		"VISITOR":
			if met and float(rec.dwell) >= 22.0:
				rec.state = "REPEAT_VISITOR"
				rec.dwell = 0.0
			elif float(rec.unmet) >= 16.0:
				rec.state = "CURIOUS"
				rec.present = false
				rec.unmet = 0.0
		"REPEAT_VISITOR":
			if met and float(rec.dwell) >= 28.0:
				rec.state = "SETTLER"
				rec.dwell = 0.0
				rec.mood = "hopeful"
			elif float(rec.unmet) >= 24.0:
				rec.state = "VISITOR"
				rec.unmet = 0.0
		"SETTLER":
			if bool(rec.home):
				rec.state = "RESIDENT"
			elif float(rec.unmet) >= 30.0:
				rec.state = "REPEAT_VISITOR"
				rec.unmet = 0.0
		"RESIDENT":
			if float(rec.bond) >= 0.72:
				rec.state = "BONDED"
				rec.mood = "bonded"
		"BONDED":
			if bool(spec.get("rare", false)) and met:
				rec.state = "LEGENDARY"
				rec.rare = true
				rec.mood = "awed"
		_:
			pass
	if bool(spec.get("rare", false)) and met and rank(str(rec.state)) >= rank("RESIDENT") and str(rec.state) != "LEGENDARY":
		rec.state = "LEGENDARY"
		rec.rare = true


func _apply_gifts(spec: Dictionary, rec: Dictionary, ctx: Dictionary) -> void:
	if rank(str(rec.state)) < rank("VISITOR"):
		return
	var gift := str(spec.get("chemistry_gift", ""))
	if gift == "" or not ctx.has("garden"):
		return
	var garden = ctx.garden
	var wanted := int(spec.get("gift_plots", 4))
	if garden.count_chemistry(gift) >= wanted:
		return
	garden.apply_chemistry(gift, 1)


func _req_ok(raw, ctx: Dictionary, softness: float = 1.0) -> bool:
	var req: Dictionary = raw
	var kind := str(req.get("type", ""))
	var mature: Dictionary = ctx.get("mature", {})
	var states: Dictionary = ctx.get("states", {})
	match kind:
		"mature_plant":
			var need := int(ceil(float(req.get("count", 1)) * softness))
			return int(mature.get(str(req.get("id", "")), 0)) >= need
		"water_cells":
			var need_water := int(ceil(float(req.get("count", 1)) * softness))
			return int(ctx.get("water_cells", 0)) >= need_water
		"species_at_least":
			var have := str(states.get(str(req.get("id", "")), "UNKNOWN"))
			return rank(have) >= rank(str(req.get("state", "VISITOR")))
		"chemistry_plots":
			var chem_counts: Dictionary = ctx.get("chemistry", {})
			var need_chem := int(ceil(float(req.get("count", 1)) * softness))
			return int(chem_counts.get(str(req.get("id", "")), 0)) >= need_chem
		"fertility_avg":
			return float(ctx.get("fertility", 0.0)) >= float(req.get("min", 1.0)) * softness
		"garden_quality":
			return float(ctx.get("quality", 0.0)) >= float(req.get("min", 100.0)) * softness
		"weather_any":
			var values: Array = req.get("values", [])
			return values.has(str(ctx.get("weather", "")))
		"night":
			return bool(ctx.get("night", false)) == bool(req.get("value", true))
		"season_any":
			var seasons: Array = req.get("values", [])
			return seasons.has(str(ctx.get("season", "")))
		_:
			return false

class_name ParishLife
extends RefCounted

# ponytail: one record per veg person; garden owns the bodies.
const LABELS := {
	"work": "at their job",
	"eat": "stopping at the stall",
	"social": "taking tea",
	"leisure": "on the south lawn",
	"rest": "resting at home",
	"home": "home for the night",
	"shelter": "under cover",
}

var lives: Dictionary = {}
var places: Dictionary = {}
var dialogue: Dictionary = {}

func boot(defs: Array, venue_points: Dictionary, lines: Dictionary = {}) -> void:
	places = venue_points.duplicate()
	dialogue = lines.duplicate()
	for entry in defs:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id := str(entry.get("id", ""))
		if id == "":
			continue
		lives[id] = _fresh(entry)

func tick(hours: float, ctx: Dictionary, chooser: Callable = Callable()) -> Array:
	var changed: Array = []
	var hour := float(ctx.get("hour", 12.0))
	var weather := str(ctx.get("weather", "clear"))
	var night := bool(ctx.get("night", false))
	var shower := bool(ctx.get("shower", false))
	var present: Dictionary = ctx.get("present", {})
	var busy: Dictionary = ctx.get("busy", {})
	var bucket := int(hour)
	for id in lives.keys():
		if not bool(present.get(id, false)):
			continue
		var life: Dictionary = lives[id]
		var needs: Dictionary = life["needs"]
		var activity := str(life.get("activity", "work"))
		if bool(busy.get(id, false)):
			activity = "work"
		_drain(needs, hours, activity, night)
		if not bool(busy.get(id, false)) and int(life.get("pick_hour", -99)) != bucket:
			var options := ranked_options(needs, hour, weather, night, shower)
			var question := "%s needs energy %.0f hunger %.0f social %.0f purpose %.0f at hour %.1f in %s. What do they do?" % [
				str(life.get("name", id)),
				float(needs["energy"]) * 100.0,
				float(needs["hunger"]) * 100.0,
				float(needs["social"]) * 100.0,
				float(needs["purpose"]) * 100.0,
				hour,
				weather,
			]
			var picked := str(options[0])
			if chooser.is_valid():
				picked = str(chooser.call(question, options))
			if not options.has(picked):
				picked = str(options[0])
			life["pick_hour"] = bucket
			life["decide_tier"] = str(ctx.get("decide_tier", life.get("decide_tier", "offline")))
			life["decide_confidence"] = float(ctx.get("decide_confidence", life.get("decide_confidence", 0.0)))
			if picked != activity:
				activity = picked
				life["activity"] = activity
				var line := _line(id, activity)
				changed.append({"id": id, "activity": activity, "text": line})
				remember(id, _memory_for(activity, int(ctx.get("day", 1))))
			else:
				life["activity"] = activity
		else:
			life["activity"] = activity
		life["mood"] = _mood(needs)
		lives[id] = life
	_meet(ctx)
	return changed

static func ranked_options(needs: Dictionary, hour: float, weather: String, night: bool, shower: bool) -> Array:
	if shower:
		return ["shelter", "home"]
	if night:
		return ["home", "rest"]
	var options: Array = []
	if float(needs.get("hunger", 1.0)) < 0.35:
		options.append("eat")
	if float(needs.get("energy", 1.0)) < 0.35:
		options.append("rest")
	if float(needs.get("social", 1.0)) < 0.4:
		options.append("social")
	if hour >= 16.5 and hour < 19.5:
		options.append("leisure")
	options.append("work")
	if not options.has("leisure"):
		options.append("leisure")
	if not options.has("eat"):
		options.append("eat")
	if not options.has("social"):
		options.append("social")
	return options

func destination(id: String) -> Vector3:
	var life: Dictionary = lives.get(id, {})
	if life.is_empty():
		return Vector3.INF
	var activity := str(life.get("activity", "work"))
	if activity == "work" or activity == "home" or activity == "rest" or activity == "shelter":
		return Vector3.INF
	var tag := str(life.get("places", {}).get(activity, ""))
	if tag == "" or not places.has(tag):
		return Vector3.INF
	return places[tag]

func label_for(id: String) -> String:
	var life: Dictionary = lives.get(id, {})
	var activity := str(life.get("activity", "work"))
	return str(LABELS.get(activity, activity))

func greeting(id: String) -> String:
	var lines = dialogue.get(id, {}).get("greeting", [])
	if typeof(lines) == TYPE_ARRAY and lines.size() > 0:
		return str(lines[0])
	return "Hello."

func greet(id: String, day: int) -> String:
	var life: Dictionary = lives.get(id, {})
	if life.is_empty():
		return greeting(id)
	var needs: Dictionary = life["needs"]
	needs["social"] = clampf(float(needs.get("social", 0.5)) + 0.12, 0.0, 1.0)
	var with_you := float(life.get("with_you", 0.1))
	life["with_you"] = clampf(with_you + 0.05, 0.0, 1.0)
	remember(id, "Spoke with you on day %d." % day)
	life["needs"] = needs
	lives[id] = life
	return greeting(id)

func remember(id: String, text: String) -> void:
	var life: Dictionary = lives.get(id, {})
	if life.is_empty() or text == "":
		return
	var memories: Array = life.get("memories", [])
	if memories.size() > 0 and str(memories[memories.size() - 1]) == text:
		return
	memories.append(text)
	while memories.size() > 8:
		memories.pop_front()
	life["memories"] = memories
	lives[id] = life

func last_memory(id: String) -> String:
	var memories: Array = lives.get(id, {}).get("memories", [])
	if memories.is_empty():
		return ""
	return str(memories[memories.size() - 1])

func apply_to(person: Object) -> void:
	if person == null:
		return
	var id := str(person.get("person_id"))
	var life: Dictionary = lives.get(id, {})
	if life.is_empty():
		return
	var needs: Dictionary = life.get("needs", {})
	person.set("energy", float(needs.get("energy", person.get("energy"))))
	person.set("hunger", float(needs.get("hunger", 0.64)))
	person.set("social", float(needs.get("social", 0.48)))
	person.set("purpose", float(needs.get("purpose", person.get("purpose"))))
	person.set("mood", str(life.get("mood", person.get("mood"))))
	person.set("activity", str(life.get("activity", "work")))
	person.set("memories", life.get("memories", []))
	person.set("relation", maxf(float(person.get("relation")), float(life.get("with_you", 0.0))))

func card(id: String) -> Dictionary:
	var life: Dictionary = lives.get(id, {})
	var needs: Dictionary = life.get("needs", {})
	var ties: Dictionary = life.get("relations", {})
	var tie_bits: PackedStringArray = PackedStringArray()
	for other in ties.keys():
		tie_bits.append("%s %.0f" % [str(other).capitalize(), float(ties[other]) * 100.0])
	return {
		"activity": str(life.get("activity", "work")),
		"state": label_for(id),
		"household": str(life.get("household", "")),
		"motive": str(life.get("motive", "")),
		"hunger": float(needs.get("hunger", 0.64)),
		"social": float(needs.get("social", 0.48)),
		"memory": last_memory(id),
		"ties": "  ".join(tie_bits),
		"decide": str(life.get("decide_tier", "")),
	}

func to_state() -> Dictionary:
	return {"lives": lives.duplicate(true)}

func apply_state(data: Dictionary) -> void:
	var saved = data.get("lives", {})
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for id in saved.keys():
		if not lives.has(id):
			continue
		var row: Dictionary = saved[id]
		var life: Dictionary = lives[id]
		for key in row.keys():
			life[key] = row[key]
		lives[id] = life

func _fresh(definition: Dictionary) -> Dictionary:
	var ties: Dictionary = {}
	var raw_ties = definition.get("relations", {})
	if typeof(raw_ties) == TYPE_DICTIONARY:
		ties = raw_ties.duplicate()
	var spots: Dictionary = {}
	var raw_places = definition.get("places", {})
	if typeof(raw_places) == TYPE_DICTIONARY:
		spots = raw_places.duplicate()
	return {
		"id": str(definition.get("id", "")),
		"name": str(definition.get("name", "")),
		"household": str(definition.get("household", "")),
		"motive": str(definition.get("motive", "")),
		"places": spots,
		"needs": {"energy": 0.72, "hunger": 0.64, "social": 0.48, "purpose": 0.55},
		"activity": "work",
		"mood": "steady",
		"memories": [],
		"relations": ties,
		"met_day": {},
		"pick_hour": -1,
		"with_you": float(definition.get("relation", 0.1)),
		"decide_tier": "offline",
		"decide_confidence": 0.0,
	}

func _drain(needs: Dictionary, hours: float, activity: String, night: bool) -> void:
	var step := maxf(hours, 0.0)
	needs["hunger"] = clampf(float(needs["hunger"]) - 0.07 * step, 0.0, 1.0)
	needs["social"] = clampf(float(needs["social"]) - 0.05 * step, 0.0, 1.0)
	needs["energy"] = clampf(float(needs["energy"]) - 0.06 * step, 0.0, 1.0)
	needs["purpose"] = clampf(float(needs["purpose"]) - 0.03 * step, 0.0, 1.0)
	match activity:
		"work":
			needs["purpose"] = clampf(float(needs["purpose"]) + 0.1 * step, 0.0, 1.0)
			needs["energy"] = clampf(float(needs["energy"]) - 0.02 * step, 0.0, 1.0)
		"eat":
			needs["hunger"] = clampf(float(needs["hunger"]) + 0.28 * step, 0.0, 1.0)
		"social", "leisure":
			needs["social"] = clampf(float(needs["social"]) + 0.22 * step, 0.0, 1.0)
		"rest", "home":
			needs["energy"] = clampf(float(needs["energy"]) + 0.24 * step, 0.0, 1.0)
		"shelter":
			needs["energy"] = clampf(float(needs["energy"]) + 0.04 * step, 0.0, 1.0)
	if night and (activity == "home" or activity == "rest"):
		needs["energy"] = clampf(float(needs["energy"]) + 0.08 * step, 0.0, 1.0)

func _meet(ctx: Dictionary) -> void:
	var day := int(ctx.get("day", 1))
	var present: Dictionary = ctx.get("present", {})
	var near: Dictionary = ctx.get("near", {})
	for id in lives.keys():
		if not bool(present.get(id, false)):
			continue
		var life: Dictionary = lives[id]
		var activity := str(life.get("activity", ""))
		if activity != "social" and activity != "leisure" and activity != "eat" and activity != "shelter":
			continue
		var other_id := str(near.get(id, ""))
		if other_id == "" or other_id == id or not lives.has(other_id):
			continue
		if not bool(present.get(other_id, false)):
			continue
		var left := str(id)
		var key: String = left if left < other_id else other_id
		var pair := "%s|%s" % [key, other_id if key == left else left]
		var met: Dictionary = life.get("met_day", {})
		if int(met.get(pair, -1)) == day:
			continue
		met[pair] = day
		life["met_day"] = met
		var ties: Dictionary = life.get("relations", {})
		ties[other_id] = clampf(float(ties.get(other_id, 0.1)) + 0.08, -1.0, 1.0)
		life["relations"] = ties
		var needs: Dictionary = life["needs"]
		needs["social"] = clampf(float(needs["social"]) + 0.1, 0.0, 1.0)
		life["needs"] = needs
		var other_name := str(lives[other_id].get("name", other_id))
		remember(id, "Spent the hour with %s." % other_name)
		lives[id] = life

func _mood(needs: Dictionary) -> String:
	var avg := (float(needs["energy"]) + float(needs["hunger"]) + float(needs["social"]) + float(needs["purpose"])) / 4.0
	if avg < 0.3:
		return "worn"
	if avg < 0.45:
		return "low"
	if avg > 0.75:
		return "bright"
	return "steady"

func _memory_for(activity: String, day: int) -> String:
	match activity:
		"eat":
			return "Stopped by the stall on day %d." % day
		"social":
			return "Took tea on day %d." % day
		"leisure":
			return "Walked the south lawn on day %d." % day
		"rest", "home":
			return "Went home on day %d." % day
		"shelter":
			return "Waited out the weather on day %d." % day
		_:
			return "Kept to the day's work on day %d." % day

func _line(id: String, activity: String) -> String:
	var bank = dialogue.get(id, {}).get(activity, [])
	if typeof(bank) == TYPE_ARRAY and bank.size() > 0:
		return str(bank[0])
	match activity:
		"eat":
			return "The stall will do."
		"social":
			return "Tea, then back to it."
		"leisure":
			return "A turn around the lawn."
		"rest", "home":
			return "That is enough for today."
		"shelter":
			return "The awning holds."
		_:
			return greeting(id)

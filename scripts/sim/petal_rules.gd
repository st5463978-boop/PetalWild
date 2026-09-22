class_name PetalRules
extends RefCounted

const STATES := [
	"unknown",
	"sighted",
	"curious",
	"visitor",
	"repeat_visitor",
	"settler",
	"resident",
	"bonded",
	"legendary",
]

static func phase_for(minute: int) -> String:
	var m := posmod(minute, 1440)
	if m >= 5 * 60 and m < 8 * 60:
		return "dawn"
	if m >= 8 * 60 and m < 16 * 60:
		return "day"
	if m >= 16 * 60 and m < 19 * 60:
		return "dusk"
	return "night"


static func state_index(state_name: String) -> int:
	var idx := STATES.find(state_name)
	return idx if idx >= 0 else 0


static func state_at(index: int) -> String:
	return STATES[clampi(index, 0, STATES.size() - 1)]


static func met(req: Dictionary, ctx: Dictionary) -> bool:
	var op := String(req.get("op", ""))
	match op:
		"mature":
			return int(ctx["mature"].get(String(req.get("plant", "")), 0)) >= int(req.get("count", 1))
		"ground":
			return int(ctx["ground"].get(String(req.get("ground", "")), 0)) >= int(req.get("count", 1))
		"phase":
			return _any(ctx["phase"], req.get("any", []))
		"weather":
			return _any(ctx["weather"], req.get("any", []))
		"season":
			return _any(ctx["season"], req.get("any", []))
		"species":
			var current: String = ctx["species"].get(String(req.get("id", "")), "unknown")
			return state_index(current) >= state_index(String(req.get("min", "visitor")))
		"person":
			return bool(ctx["people"].get(String(req.get("id", "")), false))
		"flag":
			return bool(ctx["flags"].get(String(req.get("flag", req.get("id", ""))), false))
		"harvested":
			return int(ctx["harvested"].get(String(req.get("item", "")), 0)) >= int(req.get("count", 1))
		"fed":
			return int(ctx["fed"].get(String(req.get("id", "")), 0)) >= int(req.get("count", 1))
		"prop":
			return int(ctx["props"].get(String(req.get("id", "")), 0)) >= int(req.get("count", 1))
		"quality":
			return float(ctx["quality"]) >= float(req.get("min", 1.0))
		"residents":
			return int(ctx["residents"]) >= int(req.get("count", 1))
		"sales":
			return int(ctx["sales"]) >= int(req.get("count", 1))
		"fertility":
			return float(ctx["fertility"]) >= float(req.get("min", 1.0))
		"moisture":
			return float(ctx["moisture"]) >= float(req.get("min", 1.0))
		"venue":
			return bool(ctx["venue"].get(String(req.get("id", "")), false))
		_:
			return false


static func all_met(reqs: Array, ctx: Dictionary) -> bool:
	for req in reqs:
		if not met(req, ctx):
			return false
	return true


static func fraction(reqs: Array, ctx: Dictionary) -> float:
	if reqs.is_empty():
		return 1.0
	var hit := 0
	for req in reqs:
		if met(req, ctx):
			hit += 1
	return float(hit) / float(reqs.size())


static func first_unmet(reqs: Array, ctx: Dictionary) -> String:
	for req in reqs:
		if not met(req, ctx):
			return explain(req)
	return ""


static func explain(req: Dictionary) -> String:
	var op := String(req.get("op", ""))
	match op:
		"mature":
			return "Mature %s × %d" % [String(req.get("plant", "")), int(req.get("count", 1))]
		"ground":
			return "%s plots × %d" % [String(req.get("ground", "")), int(req.get("count", 1))]
		"phase":
			return "During %s" % _join(req.get("any", []))
		"weather":
			return "Weather: %s" % _join(req.get("any", []))
		"season":
			return "Season: %s" % _join(req.get("any", []))
		"species":
			return "%s is %s" % [String(req.get("id", "")), String(req.get("min", ""))]
		"person":
			return "%s is here" % String(req.get("id", ""))
		"flag":
			return "Discovered %s" % String(req.get("flag", req.get("id", "")))
		"harvested":
			return "Harvested %s × %d" % [String(req.get("item", "")), int(req.get("count", 1))]
		"fed":
			return "Fed × %d" % int(req.get("count", 1))
		"prop":
			return "%s placed × %d" % [String(req.get("id", "")), int(req.get("count", 1))]
		"quality":
			return "Garden quality %.0f%%" % (float(req.get("min", 1.0)) * 100.0)
		"residents":
			return "Residents × %d" % int(req.get("count", 1))
		"sales":
			return "Stall sales × %d" % int(req.get("count", 1))
		"fertility":
			return "Fertility %.0f%%" % (float(req.get("min", 1.0)) * 100.0)
		"moisture":
			return "Moisture %.0f%%" % (float(req.get("min", 1.0)) * 100.0)
		"venue":
			return "%s is open" % String(req.get("id", ""))
		_:
			return op


static func _any(value: String, options) -> bool:
	if typeof(options) != TYPE_ARRAY:
		return false
	for option in options:
		if String(option) == value:
			return true
	return false


static func _join(options) -> String:
	if typeof(options) != TYPE_ARRAY:
		return ""
	var parts: PackedStringArray = []
	for option in options:
		parts.append(String(option))
	return ", ".join(parts)

extends RefCounted

const HERO := 0
const NEARBY := 1
const DISTRICT := 2
const OFFSCREEN := 3
const AGGREGATE := 4

const NAMES := ["hero", "nearby", "district", "offscreen", "aggregate"]


static func fidelity_for(distance: float, inspected: bool, in_garden: bool) -> int:
	if inspected:
		return HERO
	if distance < 7.0:
		return NEARBY
	if in_garden and distance < 24.0:
		return DISTRICT
	if distance < 90.0:
		return OFFSCREEN
	return AGGREGATE


static func name_of(level: int) -> String:
	if level >= 0 and level < NAMES.size():
		return NAMES[level]
	return "aggregate"

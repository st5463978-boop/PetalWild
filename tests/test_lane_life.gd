extends SceneTree

func _init() -> void:
	_expect(GardenLayout.household_place(15.3, false) == "door", "unfiled park stays home")
	_expect(GardenLayout.household_place(17.2, false) == "door", "dusk without a filing stays home")
	_expect(GardenLayout.household_place(10.0, true) == "door", "morning is the cottage door")
	_expect(GardenLayout.household_place(15.3, true) == "door", "golden afternoon is the cottage door")
	_expect(GardenLayout.household_place(16.5, true) == "lawn", "dusk opens the lawn walk")
	_expect(GardenLayout.household_place(17.2, true) == "lawn", "dusk keeps them on the lawn")
	_expect(GardenLayout.household_place(19.5, true) == "door", "evening sends them home")
	_expect(GardenLayout.household_place(21.0, true) == "door", "night is the cottage door")
	var door := Vector3(1.2, 0.0, -8.4)
	var gate := GardenLayout.GATE
	gate.y = 0.0
	var lawn := GardenLayout.PARK + Vector3(-1.35, 0.0, 0.95)
	var out: Array[Vector3] = [door, gate, lawn]
	var home: Array[Vector3] = [lawn, gate, door]
	var span := GardenLayout.path_length(out)
	_expect(span > 6.0, "the cottage path has length")
	_expect(absf(GardenLayout.path_length(home) - span) < 0.01, "home is the same path reversed")
	_expect(GardenLayout.point_along(out, 0.0).distance_to(door) < 0.01, "start is the door")
	_expect(GardenLayout.point_along(out, span).distance_to(lawn) < 0.01, "end is the lawn")
	var mid := GardenLayout.point_along(out, span * 0.5)
	_expect(mid.distance_to(gate) < span * 0.5, "the midpoint stays on the walk")
	var mins := GardenLayout.walk_minutes(out, 6.0)
	_expect(mins > 10.0 and mins < 240.0, "the walk consumes clock time")
	var travelled := (mins / 6.0) * GardenLayout.WALK_SPEED
	_expect(absf(travelled - span) < 0.05, "clock minutes reconstruct the arrival")
	print("LANE_LIFE_OK")
	quit(0)

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("lane_life: " + label)
	quit(1)

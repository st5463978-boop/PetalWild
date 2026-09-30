extends SceneTree

func _init() -> void:
	var lamp := GardenLayout.cell_center(6, 4)
	var sit := GardenLayout.lantern_sit(lamp)
	_expect(sit.distance_to(lamp) > 0.3 and sit.distance_to(lamp) < 0.8, "sit stays beside the bulb")
	_expect(sit.y > lamp.y, "sit is off the soil")
	_expect(GardenLayout.household_place(17.6, true) == "lawn", "dusk is still the park window")
	print("DUSK_LANTERN_OK")
	quit(0)

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("dusk_lantern: " + label)
	quit(1)

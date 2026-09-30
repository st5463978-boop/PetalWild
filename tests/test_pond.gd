extends SceneTree

func _init() -> void:
	_expect(GardenLayout.pond_rim(0) == GardenLayout.POND_RADIUS, "an unscooped pond keeps the bowl")
	_expect(GardenLayout.pond_rim(4) == GardenLayout.POND_RADIUS + GardenLayout.SCOOP_GROW * 4.0, "four scoops widen the rim")
	_expect(GardenLayout.pond_rim(-1) == GardenLayout.POND_RADIUS, "a negative scoop count stays the bowl")
	var before := GardenLayout.pond_rim(2)
	_expect(GardenLayout.pond_rim(3) > before, "each scoop steps the water out")
	print("POND_RIM_OK")
	quit(0)

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("pond: " + label)
	quit(1)

extends SceneTree

func _init() -> void:
	var a := {"hue": 0.2, "stature": 0.7, "crop_yield": 0.6}
	var b := {"hue": 0.8, "stature": 1.4, "crop_yield": 1.5}
	var child := PlantGenetics.mix(a, b, 8)
	_expect(float(child["hue"]) > 0.2 and float(child["hue"]) < 0.8, "child hue sits between parents")
	_expect(float(child["stature"]) > 0.7 and float(child["stature"]) < 1.4, "child stature sits between parents")
	_expect(PlantGenetics.price(10, 1.5) == 15, "high yield raises the stall price")
	_expect(PlantGenetics.price(5, 1.0) == 5, "plain yield keeps the stall price")
	print("SYSTEMS_OK")
	quit(0)

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("systems: " + label)
	quit(1)

extends SceneTree

func _init() -> void:
	var life := ParishLife.new()
	var defs: Array = [
		{
			"id": "lumen",
			"name": "Lumen Peel",
			"household": "stall house",
			"motive": "Keep the trays honest.",
			"places": {"eat": "stall", "social": "tea", "leisure": "tea"},
			"relations": {"bram": 0.4},
		},
		{
			"id": "bram",
			"name": "Bram Cobble",
			"household": "shed house",
			"motive": "Keep the beds wet.",
			"places": {"eat": "stall", "social": "tea", "leisure": "tea"},
			"relations": {"lumen": 0.35},
		},
	]
	life.boot(defs, {
		"stall": Vector3(-4.55, 0, 5.15),
		"tea": Vector3(2.6, 0, -7.5),
	}, {
		"lumen": {"greeting": ["The trays are labelled. Ask before you spend the tin."], "eat": ["I keep a peach slice behind the till."]},
		"bram": {"greeting": ["Mind the frames. The soil remembers feet."]},
	})
	var hungry := {"energy": 0.7, "hunger": 0.2, "social": 0.6, "purpose": 0.5}
	var day_opts: Array = ParishLife.ranked_options(hungry, 10.0, "clear", false, false)
	_expect(str(day_opts[0]) == "eat", "hungry resident eats first")
	var night_opts: Array = ParishLife.ranked_options(hungry, 21.0, "clear", true, false)
	_expect(str(night_opts[0]) == "home", "night sends them home")
	var rain_opts: Array = ParishLife.ranked_options(hungry, 12.0, "rain", false, true)
	_expect(str(rain_opts[0]) == "shelter", "rain takes cover")
	var present := {"lumen": true, "bram": true}
	var busy := {"lumen": false, "bram": false}
	var ctx := {
		"hour": 10.0,
		"day": 2,
		"weather": "clear",
		"night": false,
		"shower": false,
		"present": present,
		"busy": busy,
		"near": {},
	}
	life.lives["lumen"]["needs"]["hunger"] = 0.2
	life.tick(0.2, ctx)
	_expect(str(life.lives["lumen"]["activity"]) == "eat", "lumen walks to eat when hungry")
	var dest: Vector3 = life.destination("lumen")
	_expect(dest.distance_to(Vector3(-4.55, 0, 5.15)) < 0.01, "eat destination is the stall")
	_expect(life.label_for("lumen") == "stopping at the stall", "label names the stall visit")
	var greet := life.greet("lumen", 2)
	_expect(greet.find("trays") >= 0, "greet uses lumen's line")
	_expect(life.last_memory("lumen").find("Spoke with you") >= 0, "greet writes a memory")
	_expect(float(life.lives["lumen"]["needs"]["social"]) > 0.48, "greet fills company")
	var packed: Dictionary = life.to_state()
	var again := ParishLife.new()
	again.boot(defs, {"stall": Vector3(-4.55, 0, 5.15), "tea": Vector3(2.6, 0, -7.5)}, {})
	again.apply_state(packed)
	_expect(again.last_memory("lumen") == life.last_memory("lumen"), "memories round-trip")
	ctx["hour"] = 17.0
	ctx["near"] = {"lumen": "bram", "bram": "lumen"}
	life.lives["lumen"]["needs"]["hunger"] = 0.7
	life.lives["lumen"]["needs"]["energy"] = 0.7
	life.lives["lumen"]["needs"]["social"] = 0.2
	life.lives["lumen"]["pick_hour"] = -1
	life.lives["bram"]["needs"]["hunger"] = 0.7
	life.lives["bram"]["needs"]["energy"] = 0.7
	life.lives["bram"]["needs"]["social"] = 0.2
	life.lives["bram"]["pick_hour"] = -1
	life.tick(0.2, ctx)
	_expect(str(life.lives["lumen"]["activity"]) == "social", "lonely dusk picks tea")
	_expect(life.last_memory("lumen").find("Bram") >= 0, "a shared hour is remembered")
	_expect(float(life.lives["lumen"]["relations"]["bram"]) > 0.4, "shared tea raises the tie")
	print("RESIDENT_LIFE_OK")
	quit(0)

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("resident_life: " + label)
	quit(1)

extends SceneTree

func _init() -> void:
	var bus := GardenBus.new()
	bus.note("inspect", "Bellhelp")
	bus.note("save", "Saved slot 1.")
	bus.note("time", "rest")
	_expect(bus.last_text("inspect") == "Bellhelp", "inspect stays on the bus")
	_expect(bus.last_text("save") == "Saved slot 1.", "save stays on the bus")
	_expect(bus.last_text("time") == "rest", "time rest stays on the bus")
	_expect(bus.log.size() == 3, "bus keeps three notes")

	var saver = load("res://scripts/autoload/save_game.gd").new()
	var payload := {
		"name": "Test Hollow",
		"clock": {"day": 3, "minute": 600.0, "scale": 6.0, "weather": "rain"},
		"economy": {"coins": 41, "bag": {"peach": 2}, "selected_seed": "peach_seed"},
		"crate_yields": {"peach": [1.5]},
	}
	_expect(saver.write_slot(2, payload), "foundation save writes")
	var loaded: Dictionary = saver.read_slot(2)
	_expect(str(loaded.get("name", "")) == "Test Hollow", "foundation save keeps the name")
	_expect(int(loaded.get("economy", {}).get("coins", 0)) == 41, "foundation save keeps coins")
	var yields = loaded.get("crate_yields", {})
	_expect(typeof(yields) == TYPE_DICTIONARY, "foundation save keeps crate yields")
	var peach_row = yields.get("peach", [])
	_expect(typeof(peach_row) == TYPE_ARRAY and peach_row.size() == 1 and absf(float(peach_row[0]) - 1.5) < 0.001, "foundation save keeps a peach yield")
	var header: Dictionary = saver.meta(2)
	_expect(str(header.get("name", "")) == "Test Hollow", "foundation meta keeps the name")
	_expect(int(header.get("day", 0)) == 3, "foundation meta keeps the day")

	var clock = load("res://scripts/autoload/clock.gd").new()
	clock.apply_state({"day": 4, "minute": 90.0, "scale": 6.0, "weather": "mist"})
	_expect(clock.day == 4, "clock restore day")
	_expect(absf(clock.hour() - 1.5) < 0.001, "clock restore hour")
	var packed: Dictionary = clock.to_state()
	_expect(int(packed.get("day", 0)) == 4, "clock pack day")

	var jelly := Jelly.new()
	jelly.setup({
		"id": "bellhelp",
		"name": "Bellhelp",
		"shape": "bell",
		"deep": "#2f8f55",
		"lit": "#e7ffc4",
		"glow": "#d6ff6a",
		"eye": "#f4ffd2",
		"radius": 0.34,
	})
	jelly.inspect_face()
	_expect(jelly.inspected, "a face inspect sticks")
	_expect(jelly.mood == "happy", "a poked face is happy")
	_expect(jelly.bond > 0.08, "a poked face gains bond")
	_expect(jelly.mouth != null, "a face has a mouth")
	jelly.clear_inspect()
	_expect(not jelly.inspected, "clearing a face lets go")
	jelly.free()
	print("FOUNDATION_OK")
	quit(0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("ok  ", label)
		return
	print("FAIL ", label)
	quit(1)

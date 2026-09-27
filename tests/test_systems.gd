extends SceneTree

func _init() -> void:
	var a := {"hue": 0.2, "stature": 0.7, "crop_yield": 0.6}
	var b := {"hue": 0.8, "stature": 1.4, "crop_yield": 1.5}
	var child := PlantGenetics.mix(a, b, 8)
	_expect(float(child["hue"]) > 0.2 and float(child["hue"]) < 0.8, "child hue sits between parents")
	_expect(float(child["stature"]) > 0.7 and float(child["stature"]) < 1.4, "child stature sits between parents")
	_expect(PlantGenetics.price(10, 1.5) == 15, "high yield raises the stall price")
	_expect(PlantGenetics.price(5, 1.0) == 5, "plain yield keeps the stall price")
	var rules := EcologyRules.new()
	var meadow := {"likes": "reed", "likes_label": "Reed nearby.", "crowd": 5, "habitat": "meadow"}
	_expect(rules.growth_factor(meadow, ["reed"], 1) > 1.0, "a reed neighbour hurries a meadowbell")
	_expect(rules.growth_factor(meadow, [], 1) == 1.0, "a lone meadowbell keeps its pace")
	_expect(rules.growth_factor(meadow, [], 5) < 1.0, "five meadowbells crowd")
	_expect(rules.likes_label(meadow, ["reed"]) == "Reed nearby.", "the bed names the reed")
	_expect(rules.likes_label(meadow, ["bramble"]) == "", "a bramble neighbour stays quiet")
	var plants := {
		"meadowbell": {"habitat": "meadow", "likes": "reed", "crowd": 5, "name": "Meadowbell"},
		"reed": {"habitat": "bank", "likes": "meadowbell", "crowd": 4, "name": "Reed"},
		"bramble": {"habitat": "cane", "crowd": 5, "name": "Bramble"},
	}
	var pair: Array = [
		{"plant_id": "meadowbell", "ix": 2, "iz": 2},
		{"plant_id": "reed", "ix": 3, "iz": 2},
	]
	_expect(rules.garden_line(pair, plants) == "The meadow leans on the bank.", "the parish names a reed neighbour")
	var thicket: Array = []
	for i in 5:
		thicket.append({"plant_id": "meadowbell", "ix": i, "iz": 1})
	_expect(rules.garden_line(thicket, plants) == "The meadow is crowded.", "the parish names a crowded meadow")
	_expect(rules.need_line({"food": "meadowbell"}, 0.2, {}, plants).find("Hungry") != -1, "hunger asks for food")
	_expect(rules.food_of({"food": "meadowbell"}) == "meadowbell", "bellhelp food is meadowbell")
	_expect(rules.habitat_line(pair, plants) == "Habitats  ·  Bank 1, Meadow 1", "a reed and a bell tally two habitats")
	print("SYSTEMS_OK")
	quit(0)

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("systems: " + label)
	quit(1)

extends Node

signal changed

var coins := 36
var bag := {}
var selected_seed := "meadowbell_seed"

func _ready() -> void:
	reset_new()

func reset_new() -> void:
	coins = 36
	bag = {
		"meadowbell_seed": 6,
		"peach_seed": 2,
		"reed_seed": 3,
		"bramble_seed": 0,
		"mosspear_seed": 0,
		"nightlantern_seed": 0,
		"fertilizer": 2,
		"home_kit": 0,
		"meadowbell": 0,
		"peach": 0,
		"reed": 0,
		"bramble": 0,
		"mosspear": 0,
		"nightlantern": 0,
	}
	selected_seed = "meadowbell_seed"
	changed.emit()

func count(id: String) -> int:
	return int(bag.get(id, 0))

func add(id: String, amount: int) -> void:
	bag[id] = count(id) + amount
	changed.emit()

func take(id: String, amount: int) -> bool:
	if count(id) < amount:
		return false
	bag[id] = count(id) - amount
	changed.emit()
	return true

func spend(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	changed.emit()
	return true

func earn(amount: int) -> void:
	coins += amount
	changed.emit()

func seed_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in ContentDB.item_order:
		if str(ContentDB.item(id).get("kind", "")) == "seed":
			ids.append(id)
	return ids

func to_state() -> Dictionary:
	return {"coins": coins, "bag": bag.duplicate(), "selected_seed": selected_seed}

func apply_state(data: Dictionary) -> void:
	coins = int(data.get("coins", coins))
	var saved = data.get("bag", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key in saved.keys():
			bag[str(key)] = int(saved[key])
	selected_seed = str(data.get("selected_seed", selected_seed))
	changed.emit()

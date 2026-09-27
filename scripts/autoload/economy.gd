extends Node

signal changed

var coins := 36
var bag := {}
var selected_seed := "meadowbell_seed"
var mill := ParishChain.new()

func _ready() -> void:
	mill.boot(ContentDB.recipe_rows())
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
		"hedge_tea": 0,
	}
	selected_seed = "meadowbell_seed"
	mill.reset()
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

func stock_kettle() -> bool:
	if not mill.stock(bag):
		return false
	changed.emit()
	return true

func carry_tea() -> bool:
	if not mill.deliver():
		return false
	changed.emit()
	return true

func sell_tea() -> int:
	var price := mill.price()
	if not mill.take_crate():
		return 0
	earn(price)
	return price

func mill_line(stall_open: bool, worker: bool) -> String:
	return mill.line(bag, stall_open, worker)

func seed_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in ContentDB.item_order:
		if str(ContentDB.item(id).get("kind", "")) == "seed":
			ids.append(id)
	return ids

func to_state() -> Dictionary:
	return {"coins": coins, "bag": bag.duplicate(), "selected_seed": selected_seed, "mill": mill.to_state()}

func apply_state(data: Dictionary) -> void:
	coins = int(data.get("coins", coins))
	var saved = data.get("bag", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key in saved.keys():
			bag[str(key)] = int(saved[key])
	selected_seed = str(data.get("selected_seed", selected_seed))
	var mill_data = data.get("mill", {})
	if typeof(mill_data) == TYPE_DICTIONARY:
		mill.apply_state(mill_data)
	changed.emit()

extends Node

var plants: Dictionary = {}
var plant_order: Array[String] = []
var species: Dictionary = {}
var species_order: Array[String] = []
var items: Dictionary = {}
var item_order: Array[String] = []
var people: Dictionary = {}
var people_order: Array[String] = []
var shop: Dictionary = {}
var district: Dictionary = {}
var venues: Dictionary = {}
var recipes: Dictionary = {}
var recipe_order: Array[String] = []

func _ready() -> void:
	_load_plants()
	_load_species()
	_load_items()
	_load_people()
	shop = _load_object("res://data/shop.json")
	district = _load_object("res://data/district.json")
	venues = _load_object("res://data/venues.json")
	_load_recipes()

func plant(id: String) -> Dictionary:
	return plants.get(id, {})

func species_def(id: String) -> Dictionary:
	return species.get(id, {})

func item(id: String) -> Dictionary:
	return items.get(id, {})

func person(id: String) -> Dictionary:
	return people.get(id, {})

func recipe(id: String) -> Dictionary:
	return recipes.get(id, {})

func recipe_rows() -> Array:
	var rows: Array = []
	for id in recipe_order:
		rows.append(recipes[id])
	return rows

func _load_plants() -> void:
	for entry in _load_array("res://data/plants.json"):
		plants[str(entry["id"])] = entry
		plant_order.append(str(entry["id"]))

func _load_species() -> void:
	for entry in _load_array("res://data/species.json"):
		species[str(entry["id"])] = entry
		species_order.append(str(entry["id"]))

func _load_items() -> void:
	for entry in _load_array("res://data/items.json"):
		items[str(entry["id"])] = entry
		item_order.append(str(entry["id"]))

func _load_people() -> void:
	for entry in _load_array("res://data/people.json"):
		people[str(entry["id"])] = entry
		people_order.append(str(entry["id"]))

func _load_recipes() -> void:
	for entry in _load_array("res://data/recipes.json"):
		recipes[str(entry["id"])] = entry
		recipe_order.append(str(entry["id"]))

func _load_array(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Missing data file %s" % path)
		return []
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Expected array in %s" % path)
		return []
	return parsed

func _load_object(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in %s" % path)
		return {}
	return parsed

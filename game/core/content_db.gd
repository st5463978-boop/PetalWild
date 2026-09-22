extends RefCounted

var plants: Dictionary = {}
var species: Array = []
var residents: Array = []
var items: Array = []
var venues: Array = []
var districts: Array = []
var agents: Array = []


func load_all() -> void:
	plants = _object("res://game/data/plants.json")
	species = _list("res://game/data/species.json")
	residents = _list("res://game/data/residents.json")
	items = _list("res://game/data/items.json")
	venues = _list("res://game/data/venues.json")
	districts = _list("res://game/data/districts.json")
	agents = _list("res://game/data/agents.json")


func plant_name(plant_id: String) -> String:
	return str(plants.get(plant_id, {}).get("name", plant_id))


func _object(path: String) -> Dictionary:
	var parsed = _parse(path)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _list(path: String) -> Array:
	var parsed = _parse(path)
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func _parse(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing content: %s" % path)
		return null
	return JSON.parse_string(file.get_as_text())

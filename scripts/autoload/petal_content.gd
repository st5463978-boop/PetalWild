extends Node

var plants: Dictionary = {}
var species: Dictionary = {}
var residents: Dictionary = {}
var items: Dictionary = {}
var opening: Dictionary = {}
var dialogue: Dictionary = {}
var venues: Dictionary = {}
var districts: Dictionary = {}


func _ready() -> void:
	plants = _load("res://data/plants.json")
	species = _load("res://data/species.json")
	residents = _load("res://data/residents.json")
	items = _load("res://data/items.json")
	opening = _load("res://data/opening.json")
	dialogue = _load("res://data/dialogue.json")
	venues = _load("res://data/venues.json")
	districts = _load("res://data/districts.json")


func catalogs() -> Dictionary:
	return {
		"plants": plants,
		"species": species,
		"residents": residents,
		"items": items,
		"opening": opening,
		"dialogue": dialogue,
		"venues": venues,
		"districts": districts,
	}


func _load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Bad JSON %s" % path)
		return {}
	return parsed

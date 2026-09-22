extends RefCounted

var districts: Dictionary = {}
var venues: Array = []
var stats: Dictionary = {}


func setup(district_list: Array, venue_list: Array) -> void:
	districts.clear()
	venues = venue_list.duplicate(true)
	for entry in district_list:
		var district: Dictionary = entry
		districts[str(district.get("id", ""))] = district
	stats = {
		"population": 0,
		"employment": 0.0,
		"happiness": 0.0,
		"tourism": 0.0,
		"land_value": 0.0,
		"open_venues": [],
	}


func tick(ctx: Dictionary) -> void:
	var district: Dictionary = districts.get("havenbrook", {})
	var base_pop := int(district.get("base_population", 800))
	var residents := int(ctx.get("resident_creatures", 0))
	var people := int(ctx.get("veg_people", 0))
	var quality := float(ctx.get("quality", 40.0))
	var open: Array = []
	var jobs := 0
	var happiness := 0.42 + clampf(quality / 220.0, 0.0, 0.25)
	var tourism := 0.02 + float(residents) * 0.03
	for venue in venues:
		if _venue_open(venue, ctx):
			open.append(str(venue.get("id", "")))
			jobs += int(venue.get("jobs", 0))
			happiness += float(venue.get("happiness", 0.0))
			tourism += float(venue.get("tourism", 0.0))
	happiness = clampf(happiness - float(ctx.get("thefts", 0)) * 0.03, 0.05, 0.98)
	var population := base_pop + residents * 36 + people * 12 + int(tourism * 80.0)
	var employment := clampf(float(jobs) / 18.0 + float(district.get("base_employment", 0.6)) * 0.5, 0.2, 0.95)
	stats = {
		"population": population,
		"employment": employment,
		"happiness": happiness,
		"tourism": tourism,
		"land_value": clampf(float(district.get("base_land_value", 0.4)) + quality / 180.0, 0.0, 1.0),
		"open_venues": open,
		"jobs": jobs,
		"fidelity": 4,
	}


func venue_open(id: String) -> bool:
	var open: Array = stats.get("open_venues", [])
	return open.has(id)


func _venue_open(venue: Dictionary, ctx: Dictionary) -> bool:
	var unlock: Dictionary = venue.get("unlock", {"type": "always"})
	return _unlock_ok(unlock, ctx)


func _unlock_ok(unlock: Dictionary, ctx: Dictionary) -> bool:
	match str(unlock.get("type", "always")):
		"always":
			return true
		"resident_unlocked":
			var people: Dictionary = ctx.get("people", {})
			var person: Dictionary = people.get(str(unlock.get("id", "")), {})
			return bool(person.get("unlocked", false))
		"residents":
			return int(ctx.get("veg_people", 0)) >= int(unlock.get("count", 1))
		_:
			return false


func to_dict() -> Dictionary:
	return {"stats": stats.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	if data.has("stats"):
		stats = data.stats

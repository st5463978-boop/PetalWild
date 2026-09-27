extends SceneTree

func _init() -> void:
	var town := TownSim.new()
	town.boot()
	var ctx := {
		"people": 2,
		"residents": 1,
		"quality": 0.4,
		"road": false,
		"park": false,
		"passers": 0,
		"hour": 10.0,
		"weather": "clear",
		"near_park": false,
	}
	town.tick(ctx)
	_expect(town.open_ids().size() == 1 and town.open_ids()[0] == "hollow", "garden only")
	_expect(town.aggregate() == 0, "no distant folk while the hedge is closed")
	_expect(int(town.stats.get("bodies", -1)) == 0, "town sim never spawns a body")
	_expect(not town.building_open("grove_park"), "grove park stays unbuilt")
	_expect(town.route.is_empty(), "no path through a closed lane")
	ctx["road"] = true
	ctx["passers"] = 4
	town.tick(ctx)
	_expect(town.open_ids().has("lane"), "lane opens after the road is filed")
	_expect(town.aggregate() > 0, "lane houses occupy as counts")
	_expect(town.occupancy("lane") >= 1, "at least one house is lived in")
	_expect(int(town.stats.get("bodies", -1)) == 0, "lane folk stay aggregate")
	_expect(int(town.lod_counts().get("4", 0)) == town.aggregate(), "distant houses sit at LOD 4")
	_expect(int(town.lod_counts().get("0", -1)) == 0, "no hero tick for distant folk")
	_expect(town.route.size() > 1, "a path runs from the gate to the park plot")
	var riders0 := int(town.stats.get("riders", 0))
	ctx["vale"] = 2
	town.tick(ctx)
	_expect(int(town.stats.get("riders", 0)) == riders0 + 2, "vale carts join the gate riders")
	_expect(str(town.stats.get("headline", "")).find("vale cart") != -1, "the town page names a vale cart")
	ctx["vale"] = 0
	town.tick(ctx)
	_expect(town.coverage() > 0.4, "open rooms cover the live plots")
	_expect(int(town.stats.get("town_pop", 0)) > int(town.stats.get("garden_pop", 0)), "settlement grows past the garden")
	var sparse := TownSim.new()
	sparse.boot()
	ctx["lane_fill"] = "sparse"
	sparse.tick(ctx)
	_expect(sparse.occupancy("lane") <= town.occupancy("lane"), "sparse fill keeps fewer houses")
	ctx["park"] = true
	town.tick(ctx)
	_expect(town.building_open("grove_park"), "grove park opens from the filing")
	_expect(town.occupancy("grove_park") > 0, "the lawn holds visitors")
	_expect(int(town.stats.get("bodies", -1)) == 0, "park visitors are not actors")
	var far_ids := town.folk_ids()
	_expect(town.individuals() == 0, "far folk stay aggregate")
	ctx["near_lane"] = true
	town.tick(ctx)
	_expect(town.individuals() > 0, "a near camera promotes a household")
	_expect(int(town.stats.get("bodies", -1)) == 0, "a promoted household still has no body")
	_expect(town.folk_ids() == far_ids, "promote keeps household ids")
	ctx["near_lane"] = false
	town.tick(ctx)
	_expect(town.individuals() == 0, "leaving demotes the household")
	_expect(town.folk_ids() == far_ids, "demote keeps household ids")
	ctx["near_park"] = true
	town.tick(ctx)
	_expect(town.individuals() > 0, "a near park promotes a visitor")
	ctx["near_park"] = false
	town.tick(ctx)
	_expect(town.individuals() == 0, "leaving the park folds visitors back")
	var packed: Dictionary = town.to_dict()
	var other := TownSim.new()
	other.boot()
	other.from_dict(packed)
	_expect(other.aggregate() == town.aggregate(), "town save roundtrip")
	_expect(other.folk_ids() == town.folk_ids(), "folk ids survive save")
	_expect(str(other.stats.get("headline", "")).find("Grove Park") != -1, "the page names the park")
	print("TOWN_OK")
	quit(0)

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("town: " + label)
	quit(1)

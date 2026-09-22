extends SceneTree

func _init() -> void:
	var content = load("res://game/core/content_db.gd").new()
	content.load_all()
	if content.plants.is_empty() or content.species.is_empty():
		push_error("content failed to load")
		quit(1)
		return
	var garden = load("res://game/sim/garden_sim.gd").new()
	garden.configure(content.plants)
	garden.setup_new()
	for z in 2:
		for x in 4:
			if not garden.till(x, z):
				push_error("till failed")
				quit(1)
				return
			var error: String = garden.plant_seed(x, z, "sunpetal")
			if error != "":
				push_error(error)
				quit(1)
				return
			garden.water(x, z)
			garden.fertilize(x, z)
	for _i in 160:
		garden.tick(1.0, "clear", 12.0, "spring")
	var mature: int = garden.count_mature("sunpetal")
	if mature < 4:
		push_error("expected mature sunpetal, got %s" % mature)
		quit(1)
		return
	var ecology = load("res://game/sim/ecology_sim.gd").new()
	ecology.setup(content.species)
	var ctx := {
		"mature": {"sunpetal": mature, "petal_corn": 0, "moonvine": 0, "dewberry": 0},
		"states": {},
		"water_cells": 0,
		"fertility": garden.average_fertility(),
		"chemistry": {"pollinated": 0, "compost": 0},
		"quality": 70.0,
		"weather": "clear",
		"night": false,
		"season": "spring",
		"garden": garden,
	}
	for _step in 8:
		for id in ecology.records.keys():
			ctx.states[id] = ecology.records[id].state
		ecology.evaluate(ctx, 5.0)
	var state := str(ecology.records["sunburst"].state)
	if ecology.rank(state) < ecology.rank("VISITOR"):
		push_error("sunburst stayed %s" % state)
		quit(1)
		return
	if garden.count_chemistry("pollinated") < 1:
		push_error("pollination did not change soil")
		quit(1)
		return
	var restored = load("res://game/sim/garden_sim.gd").new()
	restored.configure(content.plants)
	restored.from_dict(garden.to_dict())
	if restored.count_mature("sunpetal") < 4:
		push_error("save roundtrip lost crops")
		quit(1)
		return
	var trust = load("res://game/sim/trust_sim.gd").new()
	trust.setup(content.agents)
	trust.draft_foundry_plan(12)
	var refused: String = trust.approve(0, true)
	if refused != "Trust is too low to act.":
		push_error("trust gate failed: %s" % refused)
		quit(1)
		return
	trust.set_trust("media_foundry", 4)
	var held: String = trust.approve(0, true)
	if held != "Approved and held. Nothing left the garden.":
		push_error("hold failed: %s" % held)
		quit(1)
		return
	if bool(trust.proposals[0].executed):
		push_error("proposal executed externally")
		quit(1)
		return
	print("PETALWILD_SMOKE_OK mature=%s sunburst=%s pollinated=%s" % [mature, state, garden.count_chemistry("pollinated")])
	quit(0)

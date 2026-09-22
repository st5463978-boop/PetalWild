class_name PetalSim
extends RefCounted

const DWELL_SETTLER := 8.0
const DWELL_RESIDENT := 25.0
const WEATHER_BAG := ["clear", "clear", "clear", "clear", "clear", "mist", "mist", "rain", "rain", "golden"]

static func tick(state: Dictionary, catalogs: Dictionary, delta: float) -> Array:
	var events: Array = []
	var scale := maxf(float(state.get("time_scale", 1.0)), 0.0)
	var scaled := delta * scale
	_roll_weather(state, scaled)
	_grow(state, catalogs, scaled)
	_mischief(state, catalogs, scaled, events)
	_enrich(state, catalogs, scaled)
	var ctx := PetalContext.build(state, catalogs)
	state["flags"]["quality"] = ctx["quality"]
	_ecology(state, catalogs, ctx, scaled, events)
	_town(state, catalogs, ctx, events)
	_needs(state, catalogs, scaled, events)
	_unlocks(state, ctx, events)
	_season(state)
	return events


static func available_seeds(state: Dictionary, catalogs: Dictionary) -> Array:
	var found: Array = []
	for id in catalogs["items"].keys():
		var def: Dictionary = catalogs["items"][id]
		if String(def.get("tag", "")) != "seed":
			continue
		if int(state["inventory"].get(id, 0)) <= 0:
			continue
		var plant_id := String(def.get("plant", ""))
		var plant: Dictionary = catalogs["plants"].get(plant_id, {})
		var flag := String(plant.get("requires_flag", ""))
		if flag != "" and not bool(state["flags"].get(flag, false)):
			continue
		found.append(id)
	return found


static func till(state: Dictionary, x: int, y: int) -> Array:
	var plot := WorldState.plot_at(state, x, y)
	if plot.is_empty():
		return [_err("That is outside the terrace.")]
	if String(plot.get("plant", "")) != "":
		return [_err("A plant is using this bed.")]
	var ground := String(plot.get("g", "grass"))
	if ground == "pond":
		return [_err("Scoop the water out before you till.")]
	if ground == "path":
		plot["g"] = "soil"
		return [_ok("You break the path back into a bed.")]
	if ground == "soil":
		plot["g"] = "grass"
		return [_ok("You let the grass take the bed back.")]
	plot["g"] = "soil"
	return _with_tip(state, [_ok("You turn the grass into a bed.")], "tilled", "Turned soil is ready for a seed. Press 2, then click.")


static func plant(state: Dictionary, catalogs: Dictionary, x: int, y: int) -> Array:
	var plot := WorldState.plot_at(state, x, y)
	if plot.is_empty():
		return [_err("That is outside the terrace.")]
	if String(plot.get("g", "")) != "soil":
		return [_err("Seeds want turned soil.")]
	if String(plot.get("plant", "")) != "":
		return [_err("Something is already rooted here.")]
	var seed := String(state.get("selected_seed", ""))
	var seeds := available_seeds(state, catalogs)
	if seed == "" or not seeds.has(seed):
		if seeds.is_empty():
			return [_err("The seed pouch is empty.")]
		seed = String(seeds[0])
		state["selected_seed"] = seed
	var item: Dictionary = catalogs["items"][seed]
	var plant_id := String(item.get("plant", ""))
	var def: Dictionary = catalogs["plants"][plant_id]
	var flag := String(def.get("requires_flag", ""))
	if flag != "" and not bool(state["flags"].get(flag, false)):
		return [_err("That seed is not in the pouch yet.")]
	state["inventory"][seed] = int(state["inventory"].get(seed, 0)) - 1
	plot["plant"] = plant_id
	plot["growth"] = 0.02
	return _with_tip(state, [_ok("You press a %s into the bed." % def.get("name", plant_id))], "planted", "Water it. Dry soil keeps a seed exactly where it is.")


static func water(state: Dictionary, x: int, y: int) -> Array:
	var plot := WorldState.plot_at(state, x, y)
	if plot.is_empty():
		return [_err("That is outside the terrace.")]
	if String(plot.get("g", "")) == "path":
		return [_err("The path does not need a drink.")]
	if String(plot.get("g", "")) == "pond":
		return [_err("The pond is already a drink.")]
	plot["m"] = minf(1.0, float(plot.get("m", 0.0)) + 0.55)
	return _with_tip(state, [_ok("Water darkens the bed."), {"type": "fx", "fx": "water", "x": x, "y": y}], "watered", "Moisture fades. The journal will tell you who is watching.")


static func fertilise(state: Dictionary, x: int, y: int) -> Array:
	var plot := WorldState.plot_at(state, x, y)
	if plot.is_empty():
		return [_err("That is outside the terrace.")]
	if String(plot.get("g", "")) == "path" or String(plot.get("g", "")) == "pond":
		return [_err("Fertiliser belongs on soil or grass.")]
	if int(state["inventory"].get("fertiliser", 0)) <= 0:
		return [_err("No fertiliser packs left. Cara sells them.")]
	state["inventory"]["fertiliser"] = int(state["inventory"]["fertiliser"]) - 1
	plot["f"] = minf(1.0, float(plot.get("f", 0.0)) + 0.24)
	return [_ok("You work a pack into the bed."), {"type": "fx", "fx": "fert", "x": x, "y": y}]


static func tend(state: Dictionary, catalogs: Dictionary, x: int, y: int, uproot: bool) -> Array:
	var plot := WorldState.plot_at(state, x, y)
	if plot.is_empty():
		return [_err("That is outside the terrace.")]
	var plant_id := String(plot.get("plant", ""))
	if plant_id == "":
		if String(plot.get("g", "")) == "soil":
			plot["f"] = minf(1.0, float(plot.get("f", 0.0)) + 0.03)
			return [_ok("You fluff the empty bed.")]
		return [_err("Nothing here wants tending.")]
	var def: Dictionary = catalogs["plants"][plant_id]
	if uproot:
		plot["plant"] = ""
		plot["growth"] = 0.0
		return [_ok("You lift the plant out, roots and all.")]
	if float(plot.get("growth", 0.0)) >= 1.0:
		var item := String(def.get("harvest_item", ""))
		plot["plant"] = ""
		plot["growth"] = 0.0
		plot["m"] = maxf(0.1, float(plot.get("m", 0.0)) - 0.1)
		state["inventory"][item] = int(state["inventory"].get(item, 0)) + 1
		state["harvested"][item] = int(state["harvested"].get(item, 0)) + 1
		return [_ok("You harvest a %s." % def.get("name", plant_id)), {"type": "fx", "fx": "harvest", "x": x, "y": y}]
	plot["growth"] = minf(0.98, float(plot.get("growth", 0.0)) + 0.06)
	return [_ok("You pick the weeds back and the plant stands taller.")]


static func pond(state: Dictionary, x: int, y: int) -> Array:
	var plot := WorldState.plot_at(state, x, y)
	if plot.is_empty():
		return [_err("That is outside the terrace.")]
	if String(plot.get("plant", "")) != "":
		return [_err("Clear the plant before you change the water.")]
	if String(plot.get("g", "")) == "pond":
		plot["g"] = "grass"
		plot["m"] = 0.2
		return [_ok("You scoop the pond back into lawn.")]
	plot["g"] = "pond"
	plot["m"] = 1.0
	return [_ok("You scoop a pond into the lawn."), {"type": "fx", "fx": "water", "x": x, "y": y}]


static func interact_stall(state: Dictionary) -> Array:
	if not bool(state.get("stall_open", false)):
		state["stall_open"] = true
		return [{"type": "stall", "text": "Cara unlatches the Petal Stall. The striped awning goes up."}]
	return [{"type": "shop", "text": ""}]


static func place_prop(state: Dictionary, x: int, y: int, prop_id: String) -> Array:
	var plot := WorldState.plot_at(state, x, y)
	if plot.is_empty():
		return [_err("That is outside the terrace.")]
	if String(plot.get("plant", "")) != "":
		return [_err("Something is growing there.")]
	if String(plot.get("g", "")) == "pond":
		return [_err("It would float off.")]
	for prop in state["props"]:
		if int(prop.get("x", -1)) == x and int(prop.get("y", -1)) == y:
			return [_err("There is already something on this square.")]
	if prop_id == "lantern":
		if int(state["inventory"].get("habitat_lantern", 0)) <= 0:
			return [_err("Oshi has not made a habitat lantern yet.")]
		state["inventory"]["habitat_lantern"] = int(state["inventory"]["habitat_lantern"]) - 1
	else:
		var cost := 8 if prop_id == "lamp" else 6
		if int(state.get("coins", 0)) < cost:
			return [_err("That costs %d petal coins." % cost)]
		var limit := 8 if prop_id == "lamp" else 6
		var count := 0
		for prop in state["props"]:
			if String(prop.get("id", "")) == prop_id:
				count += 1
		if count >= limit:
			return [_err("The grove has enough of those.")]
		state["coins"] = int(state["coins"]) - cost
	state["props"].append({"id": prop_id, "x": x, "y": y})
	return [_ok("You set a %s in place." % prop_id.replace("_", " "))]


static func try_buy(state: Dictionary, catalogs: Dictionary, item_id: String) -> Array:
	if not catalogs["items"].has(item_id):
		return [_err("Cara does not know that item.")]
	var def: Dictionary = catalogs["items"][item_id]
	var price := int(def.get("buy", 0))
	if price <= 0:
		return [_err("That is not for sale.")]
	var flag := String(def.get("requires_flag", ""))
	if flag != "" and not bool(state["flags"].get(flag, false)):
		return [_err("Not on the stall yet.")]
	var person := String(def.get("requires_person", ""))
	if person != "" and not bool(state["people"][person].get("present", false)):
		return [_err("%s is not here to make that." % person.capitalize())]
	var reagent := String(def.get("requires_item", ""))
	if reagent != "" and int(state["inventory"].get(reagent, 0)) <= 0:
		return [_err("That craft needs a %s." % reagent.replace("_", " "))]
	if int(state.get("coins", 0)) < price:
		return [_err("You are short %d petal coins." % (price - int(state["coins"])))]
	state["coins"] = int(state["coins"]) - price
	if reagent != "":
		state["inventory"][reagent] = int(state["inventory"][reagent]) - 1
	state["inventory"][item_id] = int(state["inventory"].get(item_id, 0)) + 1
	state["sales"] = int(state.get("sales", 0)) + 1
	return [_ok("Bought %s." % def.get("name", item_id)), {"type": "coin"}]


static func try_sell(state: Dictionary, catalogs: Dictionary, item_id: String) -> Array:
	if not catalogs["items"].has(item_id):
		return [_err("Cara shakes her head.")]
	var def: Dictionary = catalogs["items"][item_id]
	var price := int(def.get("sell", 0))
	if price <= 0:
		return [_err("Cara has no use for that.")]
	if int(state["inventory"].get(item_id, 0)) <= 0:
		return [_err("You are not carrying any.")]
	state["inventory"][item_id] = int(state["inventory"][item_id]) - 1
	state["coins"] = int(state.get("coins", 0)) + price
	state["sales"] = int(state.get("sales", 0)) + 1
	return [_ok("Sold %s for %d." % [def.get("name", item_id), price]), {"type": "coin"}]


static func pet(state: Dictionary, catalogs: Dictionary, species_id: String) -> Array:
	var rec: Dictionary = state["species"][species_id]
	rec["relationship"] = clampf(float(rec.get("relationship", 0.0)) + 0.08, -1.0, 1.0)
	rec["mood"] = "happy"
	rec["harassment"] = maxi(int(rec.get("harassment", 0)) - 1, 0)
	var name := String(catalogs["species"][species_id].get("name", species_id))
	return [{"type": "mood", "text": "%s bounces, pleased." % name, "mood": "happy", "id": species_id}]


static func toss(state: Dictionary, catalogs: Dictionary, species_id: String, hard: bool) -> Array:
	var rec: Dictionary = state["species"][species_id]
	var hit := 0.16 if hard else 0.07
	rec["relationship"] = clampf(float(rec.get("relationship", 0.0)) - hit, -1.0, 1.0)
	rec["harassment"] = int(rec.get("harassment", 0)) + (2 if hard else 1)
	var name := String(catalogs["species"][species_id].get("name", species_id))
	var events: Array = []
	if int(rec["harassment"]) >= 4:
		rec["mood"] = "panic"
		events.append({"type": "mood", "text": "%s panics and scrabbles away." % name, "mood": "panic", "id": species_id})
		events.append({"type": "complaint", "text": _complaint(catalogs), "id": species_id})
		_gossip(state, "%s was thrown hard." % name)
		for pid in state["people"].keys():
			if bool(state["people"][pid].get("present", false)):
				state["people"][pid]["relationship"] = clampf(float(state["people"][pid].get("relationship", 0.0)) - 0.05, -1.0, 1.0)
	else:
		rec["mood"] = "annoyed" if hard else "dizzy"
		events.append({
			"type": "mood",
			"text": "%s %s." % [name, "lands in a grump" if hard else "wobbles, dizzy"],
			"mood": rec["mood"],
			"id": species_id,
		})
	return events


static func feed(state: Dictionary, catalogs: Dictionary, species_id: String) -> Array:
	var diet: Array = catalogs["species"][species_id].get("diet", [])
	var rec: Dictionary = state["species"][species_id]
	var name := String(catalogs["species"][species_id].get("name", species_id))
	for item_id in diet:
		if int(state["inventory"].get(item_id, 0)) > 0:
			state["inventory"][item_id] = int(state["inventory"][item_id]) - 1
			rec["fed"] = int(rec.get("fed", 0)) + 1
			rec["relationship"] = clampf(float(rec.get("relationship", 0.0)) + 0.12, -1.0, 1.0)
			rec["mood"] = "happy"
			var label := String(catalogs["items"].get(item_id, {}).get("name", item_id))
			return [{"type": "mood", "text": "%s takes the %s." % [name, label], "mood": "happy", "id": species_id}]
	return [_err("%s sniffs your hands and finds nothing it eats." % name)]


static func set_trust(state: Dictionary, person_id: String, level: int) -> Array:
	var person: Dictionary = state["people"][person_id]
	var next := clampi(level, 0, 5)
	person["trust"] = next
	state["audit"].append({
		"day": int(state["day"]),
		"minute": int(state["minute"]),
		"who": person_id,
		"action": "trust_set",
		"level": next,
		"external": false,
		"note": "Permission changed inside the garden. No external tool was opened.",
	})
	return [_ok("%s is now trust %d. Nothing outside the garden changed." % [person_id.capitalize(), next])]


static func propose(state: Dictionary, catalogs: Dictionary, person_id: String, approve: bool) -> Array:
	var person: Dictionary = state["people"][person_id]
	if not bool(person.get("present", false)):
		return [_err("They are not in the grove.")]
	if int(person.get("trust", 0)) < 3:
		return [_err("Trust is still too low for a proposal. Research and drafts come first.")]
	var coins_before := int(state.get("coins", 0))
	state["audit"].append({
		"day": int(state["day"]),
		"minute": int(state["minute"]),
		"who": person_id,
		"action": "production_plan",
		"approved": approve,
		"external": false,
		"cost_shown": "£40",
		"note": "No money spent. Nothing sent, posted, or deployed.",
	})
	if int(state.get("coins", 0)) != coins_before:
		state["coins"] = coins_before
	if approve:
		state["flags"]["plan_filed"] = true
		var line: String = catalogs["dialogue"][person_id]["approved"][0]
		return [{"type": "proposal", "text": line}]
	var refused: String = catalogs["dialogue"][person_id]["refused"][0]
	return [{"type": "proposal", "text": refused}]


static func force_species(state: Dictionary, species_id: String, to_state: String) -> void:
	var rec: Dictionary = state["species"][species_id]
	rec["state"] = to_state
	var present := PetalRules.state_index(to_state) >= PetalRules.state_index("visitor")
	rec["present"] = present
	if present and rec.get("pos", []).is_empty():
		rec["pos"] = _pick_pos(state)


static func _ecology(state: Dictionary, catalogs: Dictionary, ctx: Dictionary, scaled: float, events: Array) -> void:
	for id in catalogs["species"].keys():
		var def: Dictionary = catalogs["species"][id]
		var rec: Dictionary = state["species"][id]
		var visit: Array = def.get("visit", [])
		var settle: Array = def.get("settle", [])
		var vf := PetalRules.fraction(visit, ctx)
		var sf := PetalRules.fraction(settle, ctx)
		var idx := PetalRules.state_index(String(rec.get("state", "unknown")))
		if vf >= 0.34 and idx < PetalRules.state_index("sighted"):
			_promote(rec, "sighted", events, def, id, "A new presence is in the journal.")
			idx = PetalRules.state_index(String(rec["state"]))
		if vf >= 0.67 and idx < PetalRules.state_index("curious"):
			_promote(rec, "curious", events, def, id, "%s is curious." % def["name"])
			idx = PetalRules.state_index(String(rec["state"]))
		if vf >= 1.0 and idx < PetalRules.state_index("visitor"):
			_promote(rec, "visitor", events, def, id, "%s crosses the hedge for a visit." % def["name"])
			rec["visits"] = int(rec.get("visits", 0)) + 1
			rec["present"] = true
			if rec.get("pos", []).is_empty():
				rec["pos"] = _pick_pos(state)
			idx = PetalRules.state_index("visitor")
		var resident_rank := PetalRules.state_index("resident")
		if idx >= PetalRules.state_index("visitor") and idx < resident_rank:
			if vf < 0.34:
				rec["state"] = "curious"
				rec["present"] = false
				rec["dwell"] = 0.0
				events.append({"type": "leave", "text": "%s slips back into the hedge." % def["name"], "id": id})
				continue
			rec["present"] = true
			if sf >= 1.0:
				rec["dwell"] = float(rec.get("dwell", 0.0)) + scaled
			else:
				rec["dwell"] = maxf(0.0, float(rec.get("dwell", 0.0)) - scaled * 0.5)
			if int(rec.get("visits", 0)) >= 2 and PetalRules.state_index(String(rec["state"])) < PetalRules.state_index("repeat_visitor"):
				rec["state"] = "repeat_visitor"
			if float(rec["dwell"]) >= DWELL_SETTLER and PetalRules.state_index(String(rec["state"])) < PetalRules.state_index("settler"):
				_promote(rec, "settler", events, def, id, "%s is settling." % def["name"])
			if float(rec["dwell"]) >= DWELL_RESIDENT and sf >= 1.0:
				_promote(rec, "resident", events, def, id, "%s chooses the grove and stays.")
				rec["counted_day"] = int(state["day"])
				rec["days_resident"] = 0
		if PetalRules.state_index(String(rec["state"])) >= resident_rank:
			rec["present"] = true
			if int(rec.get("counted_day", -1)) == -1:
				rec["counted_day"] = int(state["day"])
			elif int(rec.get("counted_day", -1)) != int(state["day"]):
				rec["days_resident"] = int(rec.get("days_resident", 0)) + (int(state["day"]) - int(rec["counted_day"]))
				rec["counted_day"] = int(state["day"])
			if PetalRules.state_index(String(rec["state"])) < PetalRules.state_index("bonded"):
				if float(rec.get("relationship", 0.0)) >= 0.72 and int(rec.get("days_resident", 0)) >= 1:
					_promote(rec, "bonded", events, def, id, "%s trusts your hands." % def["name"])
					var chance := float(def.get("variant_chance", 0.0))
					if chance > 0.0 and not bool(rec.get("variant", false)) and randf() < chance:
						rec["variant"] = true
						events.append({"type": "variant", "text": "%s shows a paler variant." % def["name"], "id": id})
			if def.has("legendary") and PetalRules.state_index(String(rec["state"])) == PetalRules.state_index("bonded"):
				if PetalRules.all_met(def["legendary"], ctx):
					_promote(rec, "legendary", events, def, id, "%s becomes a grove legend." % def["name"])


static func _town(state: Dictionary, catalogs: Dictionary, ctx: Dictionary, events: Array) -> void:
	var pad := 1
	for id in catalogs["residents"].keys():
		var def: Dictionary = catalogs["residents"][id]
		var person: Dictionary = state["people"][id]
		if bool(person.get("present", false)):
			if int(person.get("home_pad", -1)) < 0:
				person["home_pad"] = pad
				pad += 1
			continue
		var reqs: Array = def.get("arrives", [])
		if reqs.is_empty():
			continue
		if PetalRules.all_met(reqs, ctx):
			person["present"] = true
			if int(person.get("home_pad", -1)) < 0:
				person["home_pad"] = pad
			pad += 1
			person["memories"] = ["Arrived in Garden Grove."]
			events.append({"type": "arrival", "text": "%s comes to live in the grove." % def["name"], "id": id})
		else:
			pad += 0


static func _needs(state: Dictionary, catalogs: Dictionary, scaled: float, events: Array) -> void:
	var present_people := 0
	for id in state["people"].keys():
		if bool(state["people"][id].get("present", false)):
			present_people += 1
	var phase := PetalRules.phase_for(int(state.get("minute", 0)))
	for id in state["people"].keys():
		var person: Dictionary = state["people"][id]
		if not bool(person.get("present", false)):
			continue
		var needs: Dictionary = person["needs"]
		needs["energy"] = clampf(float(needs["energy"]) - 0.004 * scaled, 0.0, 1.0)
		needs["hunger"] = clampf(float(needs["hunger"]) - 0.005 * scaled, 0.0, 1.0)
		needs["social"] = clampf(float(needs["social"]) - 0.003 * scaled, 0.0, 1.0)
		needs["purpose"] = clampf(float(needs["purpose"]) - 0.004 * scaled, 0.0, 1.0)
		if phase == "night":
			needs["energy"] = clampf(float(needs["energy"]) + 0.02 * scaled, 0.0, 1.0)
		if bool(state.get("stall_open", false)):
			needs["hunger"] = clampf(float(needs["hunger"]) + 0.008 * scaled, 0.0, 1.0)
		if present_people >= 2:
			needs["social"] = clampf(float(needs["social"]) + 0.006 * scaled, 0.0, 1.0)
		var job := String(catalogs["residents"][id].get("job", ""))
		if phase == "day" and (job == "petal_stall" and bool(state.get("stall_open", false))):
			needs["purpose"] = clampf(float(needs["purpose"]) + 0.02 * scaled, 0.0, 1.0)
		var avg := (float(needs["energy"]) + float(needs["hunger"]) + float(needs["social"]) + float(needs["purpose"])) / 4.0
		if avg < 0.3:
			person["mood"] = "grumpy"
		elif avg < 0.45:
			person["mood"] = "low"
		elif avg > 0.75:
			person["mood"] = "bright"
		else:
			person["mood"] = "content"
		if float(needs["hunger"]) < 0.25 and int(person.get("complained_day", -1)) != int(state["day"]):
			person["complained_day"] = int(state["day"])
			_remember(person, "Hungry on day %d." % int(state["day"]))
			events.append({"type": "talk", "text": "%s is hungry." % catalogs["residents"][id]["name"], "id": id})


static func _unlocks(state: Dictionary, ctx: Dictionary, events: Array) -> void:
	var rendle := String(ctx["species"].get("rendle", "unknown"))
	var ready := float(ctx["fertility"]) >= 0.58 and PetalRules.state_index(rendle) >= PetalRules.state_index("visitor")
	if ready and not bool(state["flags"].get("nightbloom_unlocked", false)):
		state["flags"]["nightbloom_unlocked"] = true
		events.append({"type": "unlock", "text": "The soil has changed. Cara can order Nightbloom seed."})


static func _grow(state: Dictionary, catalogs: Dictionary, scaled: float) -> void:
	var weather := String(state.get("weather", "clear"))
	var phase := PetalRules.phase_for(int(state.get("minute", 0)))
	var season := String(state.get("season", "spring"))
	var width := int(state["width"])
	var height := int(state["height"])
	var plots: Array = state["plots"]
	var raining := weather == "rain" or weather == "mist"
	for y in height:
		for x in width:
			var plot: Dictionary = plots[y * width + x]
			var ground := String(plot.get("g", "grass"))
			if ground == "pond":
				plot["m"] = 1.0
				continue
			if ground == "path":
				continue
			if raining:
				plot["m"] = minf(1.0, float(plot.get("m", 0.0)) + 0.04 * scaled)
			else:
				plot["m"] = maxf(0.0, float(plot.get("m", 0.0)) - 0.006 * scaled)
			var plant_id := String(plot.get("plant", ""))
			if plant_id == "" or not catalogs["plants"].has(plant_id):
				continue
			if float(plot.get("growth", 0.0)) >= 1.0:
				continue
			var def: Dictionary = catalogs["plants"][plant_id]
			var mult := 1.0
			if float(plot.get("m", 0.0)) < float(def.get("water_need", 0.3)):
				mult *= 0.15
			if float(plot.get("f", 0.0)) < float(def.get("fertility_need", 0.0)):
				mult *= 0.55
			elif float(plot.get("f", 0.0)) > float(def.get("fertility_need", 0.0)) + 0.15:
				mult *= 1.25
			var phases: Array = def.get("likes_phases", [])
			if not phases.is_empty() and not phases.has(phase):
				mult *= 0.35
			var seasons: Array = def.get("seasons", [])
			if not seasons.is_empty() and not seasons.has(season):
				mult *= 0.7
			var needed: Array = def.get("requires_weather", [])
			if not needed.is_empty() and not needed.has(weather):
				mult *= 0.12
			if String(def.get("prefers", "")) == "pond" and not _near_pond(state, x, y):
				mult *= 0.28
			var rate := 1.0 / float(def.get("grow_seconds", 40.0))
			plot["growth"] = minf(1.0, float(plot.get("growth", 0.0)) + rate * mult * scaled)


static func _mischief(state: Dictionary, catalogs: Dictionary, scaled: float, events: Array) -> void:
	var rendle: Dictionary = state["species"].get("rendle", {})
	if not bool(rendle.get("present", false)):
		return
	if String(catalogs["species"]["rendle"].get("mischief", "")) != "steal_mature":
		return
	state["mischief_acc"] = float(state.get("mischief_acc", 0.0)) + scaled
	if float(state["mischief_acc"]) < 70.0:
		return
	var mature_cells: Array = []
	var plots: Array = state["plots"]
	for i in plots.size():
		var plot: Dictionary = plots[i]
		if String(plot.get("plant", "")) != "" and float(plot.get("growth", 0.0)) >= 1.0:
			mature_cells.append(i)
	if mature_cells.size() < 3:
		return
	state["mischief_acc"] = 0.0
	var idx: int = mature_cells[randi() % mature_cells.size()]
	var plot: Dictionary = plots[idx]
	var plant_id := String(plot.get("plant", ""))
	plot["plant"] = ""
	plot["growth"] = 0.0
	state["theft"] = int(state.get("theft", 0)) + 1
	var pname := String(catalogs["plants"][plant_id].get("name", plant_id))
	events.append({"type": "theft", "text": "Rendle makes off with a %s." % pname})
	_gossip(state, "Rendle stole a %s." % pname)
	if bool(state["people"]["bran"].get("present", false)):
		_remember(state["people"]["bran"], "Rendle stole a %s." % pname)


static func _enrich(state: Dictionary, catalogs: Dictionary, scaled: float) -> void:
	for id in catalogs["species"].keys():
		var rec: Dictionary = state["species"][id]
		if PetalRules.state_index(String(rec.get("state", "unknown"))) < PetalRules.state_index("resident"):
			continue
		var bonus: Dictionary = catalogs["species"][id].get("while_resident", {})
		var per := float(bonus.get("fertility_per_second", 0.0))
		if per <= 0.0:
			continue
		for plot in state["plots"]:
			if String(plot.get("g", "")) == "soil" or String(plot.get("g", "")) == "grass":
				plot["f"] = minf(1.0, float(plot.get("f", 0.0)) + per * scaled)


static func _roll_weather(state: Dictionary, scaled: float) -> void:
	state["weather_acc"] = float(state.get("weather_acc", 0.0)) + scaled
	if float(state["weather_acc"]) < 90.0:
		return
	state["weather_acc"] = 0.0
	state["weather"] = WEATHER_BAG[randi() % WEATHER_BAG.size()]


static func _season(state: Dictionary) -> void:
	var names := ["spring", "summer", "autumn", "winter"]
	state["season"] = names[(maxi(int(state.get("day", 1)) - 1, 0) / 3) % 4]


static func _near_pond(state: Dictionary, x: int, y: int) -> bool:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var plot := WorldState.plot_at(state, x + offset.x, y + offset.y)
		if not plot.is_empty() and String(plot.get("g", "")) == "pond":
			return true
	return false


static func _pick_pos(state: Dictionary) -> Array:
	var options: Array = []
	var width := int(state["width"])
	var height := int(state["height"])
	for y in height:
		for x in width:
			var ground := String(state["plots"][y * width + x].get("g", ""))
			if ground == "grass" or ground == "path" or ground == "soil":
				options.append([x, y])
	if options.is_empty():
		return [1, 1]
	return options[randi() % options.size()]


static func _promote(rec: Dictionary, to_state: String, events: Array, def: Dictionary, id: String, text: String) -> void:
	rec["state"] = to_state
	var announced: Dictionary = rec.get("announced", {})
	if bool(announced.get(to_state, false)):
		return
	announced[to_state] = true
	rec["announced"] = announced
	events.append({"type": "species", "text": text, "id": id, "state": to_state, "name": def.get("name", id)})


static func _gossip(state: Dictionary, text: String) -> void:
	for id in state["people"].keys():
		if bool(state["people"][id].get("present", false)):
			_remember(state["people"][id], text)


static func _remember(person: Dictionary, text: String) -> void:
	var memories: Array = person.get("memories", [])
	memories.append(text)
	while memories.size() > 8:
		memories.pop_front()
	person["memories"] = memories


static func _complaint(catalogs: Dictionary) -> String:
	for id in ["cara", "mia", "bran", "pod"]:
		var lines: Array = catalogs["dialogue"].get(id, {}).get("complaint", [])
		if not lines.is_empty():
			return String(lines[0])
	return "Gently."


static func _with_tip(state: Dictionary, events: Array, key: String, text: String) -> Array:
	if not bool(state["tutorial"].get(key, false)):
		state["tutorial"][key] = true
		events.append({"type": "tip", "text": text})
	return events


static func _ok(text: String) -> Dictionary:
	return {"type": "ok", "text": text}


static func _err(text: String) -> Dictionary:
	return {"type": "error", "text": text}

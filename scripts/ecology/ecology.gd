class_name Ecology
extends Node

signal event_happened(text: String)

var rules := EcologyRules.new()
var states := {}
var actors: Array = []
var folder: Node3D
var cooldowns := {}
var extra_spawned := {}
var young_spawned := {}
var effect_done := {}
var attractor_provider: Callable
var soil_effect_cb: Callable

func boot(creature_folder: Node3D) -> void:
	folder = creature_folder
	for id in ContentDB.species_order:
		states[id] = "rumoured"

func tick(delta: float, world: Dictionary) -> void:
	_prune()
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var jelly: Jelly = actor
		if not jelly.leaving or jelly.is_queued_for_deletion():
			continue
		if jelly.young and _resident_count(jelly.species_id) > 0:
			# ponytail: the young keeps the pair; the hedge only if no resident remains.
			jelly.leaving = false
			continue
		if jelly.global_position.distance_to(GardenLayout.GATE) < 0.8 or jelly.site_time > 40.0:
			jelly.queue_free()
			continue
		var gone_def: Dictionary = ContentDB.species_def(jelly.species_id)
		var back := rules.all_met(gone_def, world)
		if back and rules.rank_of(jelly.life) < rules.rank_of("settler"):
			# ponytail: one turn back; a queue if several recover on the same tick.
			jelly.leaving = false
			if attractor_provider.is_valid():
				jelly.attract = attractor_provider.call(gone_def)
			jelly.goal = jelly.attract
			event_happened.emit("%s turns back from the hedge." % jelly.display_name)
	for id in ContentDB.species_order:
		cooldowns[id] = float(cooldowns.get(id, 0.0)) - delta
		var definition: Dictionary = ContentDB.species_def(id)
		var met := rules.all_met(definition, world)
		if _count(id) == 0 and met and float(cooldowns.get(id, 0.0)) <= 0.0:
			_spawn(definition, false)
			cooldowns[id] = 2.5
		if (
			not bool(extra_spawned.get(id, false))
			and definition.has("romance")
			and _resident_count(id) >= 1
			and _count(id) < int(definition.get("cap", 1))
			and met
		):
			_spawn(definition, true)
			extra_spawned[id] = true
			event_happened.emit("%s has company." % definition.get("name", id))
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var jelly: Jelly = actor
		if jelly.leaving or jelly.is_queued_for_deletion():
			continue
		var definition: Dictionary = ContentDB.species_def(jelly.species_id)
		var met := rules.all_met(definition, world)
		if not met and rules.rank_of(jelly.life) < rules.rank_of("settler"):
			if jelly.young and _resident_count(jelly.species_id) > 0:
				continue
			jelly.leaving = true
			jelly.goal = GardenLayout.GATE
			jelly.attract = GardenLayout.GATE
			event_happened.emit("%s slips back toward the hedge." % jelly.display_name)
			continue
		if not met:
			continue
		_promote(jelly, definition)
	_romance(world)

func try_promote(jelly: Jelly) -> void:
	if jelly == null or not is_instance_valid(jelly):
		return
	_promote(jelly, ContentDB.species_def(jelly.species_id))

func force_spawn(id: String) -> Jelly:
	var jelly := _spawn(ContentDB.species_def(id), false)
	jelly.life = "visitor"
	_raise(id, "visitor")
	return jelly

func first(id: String) -> Jelly:
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var jelly: Jelly = actor
		if jelly.species_id == id:
			return jelly
	return null

func resident_counts() -> Dictionary:
	_prune()
	var counts := {}
	for actor in actors:
		var jelly: Jelly = actor
		if rules.rank_of(jelly.life) >= rules.rank_of("resident"):
			counts[jelly.species_id] = int(counts.get(jelly.species_id, 0)) + 1
	return counts

func resident_total() -> int:
	var total := 0
	for value in resident_counts().values():
		total += int(value)
	return total

func status_line(id: String, world: Dictionary) -> String:
	var definition: Dictionary = ContentDB.species_def(id)
	var state := str(states.get(id, "rumoured"))
	if _all_leaving(id) and rules.rank_of(state) < rules.rank_of("settler"):
		return "heading for the hedge"
	if state == "repeat":
		return "back again"
	var met := rules.all_met(definition, world)
	if rules.rank_of(state) >= rules.rank_of("breeding"):
		return "breeding"
	if rules.rank_of(state) >= rules.rank_of("resident"):
		return state
	if met and rules.rank_of(state) < rules.rank_of("visitor"):
		return "ready to visit"
	if not met and rules.rank_of(state) < rules.rank_of("visitor"):
		return "conditions unmet"
	return state

func clear_actors() -> void:
	for actor in actors:
		if is_instance_valid(actor):
			actor.queue_free()
	actors.clear()

func _young(id: String, definition: Dictionary) -> void:
	# ponytail: one young per breeding species; a clutch if a parish keeps more than a pair.
	if bool(young_spawned.get(id, false)):
		return
	if _count(id) >= int(definition.get("cap", 1)) + 1:
		return
	var anchor: Jelly = null
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var jelly: Jelly = actor
		if jelly.species_id != id or jelly.leaving:
			continue
		if rules.rank_of(jelly.life) < rules.rank_of("resident"):
			continue
		anchor = jelly
		break
	var child := _spawn(definition, false, true)
	young_spawned[id] = true
	if anchor == null:
		return
	child.global_position = anchor.global_position + Vector3(0.7, 0.2, 0.35)
	child.attract = anchor.global_position
	child.goal = anchor.global_position

func _spawn(definition: Dictionary, companion: bool, young := false) -> Jelly:
	var jelly := Jelly.new()
	folder.add_child(jelly)
	jelly.setup(definition)
	var spot := GardenLayout.GATE + Vector3(randf_range(-0.6, 0.6), 0.2, 0.4)
	jelly.global_position = spot
	if attractor_provider.is_valid():
		jelly.attract = attractor_provider.call(definition)
	else:
		jelly.attract = Vector3(-3.5, 0, -2)
	jelly.goal = jelly.attract
	var prior := str(states.get(jelly.species_id, "rumoured"))
	var returning := rules.rank_of(prior) >= rules.rank_of("visitor")
	if young:
		jelly.young = true
		jelly.life = "curious"
	elif companion:
		jelly.life = "curious"
	elif returning:
		jelly.life = "repeat"
	actors.append(jelly)
	var name := str(definition.get("name", "Someone"))
	if young:
		event_happened.emit("A young %s is in the parish." % name)
		return jelly
	if returning and not companion:
		# ponytail: one repeat rank; a visit count if the journal keeps a history.
		_raise(jelly.species_id, "repeat")
		event_happened.emit("%s is back for another look." % name)
	else:
		if not returning:
			_raise(jelly.species_id, "curious")
		event_happened.emit("%s has come to look." % name)
	return jelly

func _promote(jelly: Jelly, definition: Dictionary) -> void:
	var name := jelly.display_name
	if jelly.young:
		if jelly.site_time < 8.0:
			return
		jelly.young = false
	if jelly.life == "curious" and jelly.site_time > 6.0:
		jelly.life = "visitor"
		_raise(jelly.species_id, "visitor")
		event_happened.emit("%s is visiting." % name)
	elif jelly.life == "repeat" and jelly.site_time > 8.0:
		jelly.life = "settler"
		_raise(jelly.species_id, "settler")
		event_happened.emit("%s is settling." % name)
	elif jelly.life == "visitor" and jelly.site_time > 18.0:
		var choice := PetalDecide.choose(
			"%s has visited. The garden still fits. Settle or keep visiting?" % name,
			["settle", "keep visiting"]
		)
		if choice != "settle":
			return
		jelly.life = "settler"
		_raise(jelly.species_id, "settler")
		event_happened.emit("%s is settling." % name)
	elif jelly.life == "settler" and jelly.site_time > 32.0:
		jelly.life = "resident"
		_raise(jelly.species_id, "resident")
		event_happened.emit("%s has made a home here." % name)
		_soil_effect(definition)
	elif jelly.life == "resident" and jelly.bond >= 0.55:
		jelly.life = "bonded"
		_raise(jelly.species_id, "bonded")
		event_happened.emit("%s trusts your hands." % name)

func _romance(world: Dictionary) -> void:
	for id in ContentDB.species_order:
		var definition: Dictionary = ContentDB.species_def(id)
		if not rules.romance_met(definition, world):
			continue
		if rules.rank_of(str(states.get(id, ""))) < rules.rank_of("resident"):
			continue
		if str(states.get(id, "")) != "breeding":
			_raise(id, "breeding")
			event_happened.emit("%s has a partner in the parish." % definition.get("name", id))
		_young(id, definition)

func _soil_effect(definition: Dictionary) -> void:
	var id := str(definition.get("id", ""))
	if effect_done.get(id, false):
		return
	if not definition.has("soil_effect"):
		return
	effect_done[id] = true
	if soil_effect_cb.is_valid():
		var effect: Dictionary = definition.get("soil_effect", {})
		var count: int = soil_effect_cb.call(effect)
		event_happened.emit("%s left night-loam in %d beds." % [definition.get("name", id), count])

func _raise(id: String, state: String) -> void:
	if rules.rank_of(state) > rules.rank_of(str(states.get(id, "unknown"))):
		states[id] = state

func _all_leaving(id: String) -> bool:
	var saw := false
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var jelly: Jelly = actor
		if jelly.species_id != id:
			continue
		if not jelly.leaving:
			return false
		saw = true
	return saw

func _count(id: String) -> int:
	var total := 0
	for actor in actors:
		if not is_instance_valid(actor):
			continue
		var jelly: Jelly = actor
		if jelly.species_id == id and not jelly.leaving:
			total += 1
	return total

func _resident_count(id: String) -> int:
	return int(resident_counts().get(id, 0))

func _prune() -> void:
	var keep: Array = []
	for actor in actors:
		if is_instance_valid(actor):
			keep.append(actor)
	actors = keep

func to_state() -> Dictionary:
	var saved: Array = []
	for actor in actors:
		if is_instance_valid(actor):
			saved.append(actor.to_state())
	return {
		"states": states.duplicate(),
		"actors": saved,
		"extra_spawned": extra_spawned.duplicate(),
		"effect_done": effect_done.duplicate(),
		"young_spawned": young_spawned.duplicate(),
	}

func apply_state(data: Dictionary) -> void:
	clear_actors()
	var saved_states = data.get("states", {})
	if typeof(saved_states) == TYPE_DICTIONARY:
		for key in saved_states.keys():
			states[str(key)] = str(saved_states[key])
	extra_spawned = data.get("extra_spawned", {}).duplicate() if typeof(data.get("extra_spawned")) == TYPE_DICTIONARY else {}
	young_spawned = data.get("young_spawned", {}).duplicate() if typeof(data.get("young_spawned")) == TYPE_DICTIONARY else {}
	effect_done = data.get("effect_done", {}).duplicate() if typeof(data.get("effect_done")) == TYPE_DICTIONARY else {}
	for entry in data.get("actors", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var definition := ContentDB.species_def(str(entry.get("species", "")))
		if definition.is_empty():
			continue
		var jelly := Jelly.new()
		folder.add_child(jelly)
		jelly.setup(definition)
		jelly.life = str(entry.get("life", "curious"))
		jelly.bond = float(entry.get("bond", 0.1))
		jelly.mood = str(entry.get("mood", "content"))
		jelly.site_time = float(entry.get("site_time", 0.0))
		jelly.bite_wait = float(entry.get("bite_wait", 2.0))
		jelly.leaving = bool(entry.get("leaving", false))
		jelly.young = bool(entry.get("young", false))
		var pos = entry.get("position", [0, 0, 0])
		jelly.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		jelly.attract = jelly.global_position
		if jelly.leaving:
			jelly.goal = GardenLayout.GATE
			jelly.attract = GardenLayout.GATE
		actors.append(jelly)

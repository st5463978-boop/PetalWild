class_name RegionSim
extends RefCounted

const PATH := "res://data/regions.json"
const HOME := "hollow"

var catalog: Dictionary = {}
var state: Dictionary = {}
var last_day := -1
var last_hour := -1.0
var decide_cb: Callable
var last_pick_confidence := 0.0


func boot(saved: Dictionary = {}) -> void:
	catalog = _read()
	if saved.is_empty():
		state = fresh()
	else:
		state = ensure(saved)
	last_day = int(state.get("tick_day", -1))
	last_hour = float(state.get("tick_hour", -1.0))
	_refresh_lod()


func fresh() -> Dictionary:
	var settlements := {}
	var claims := {}
	for entry in catalog.get("settlements", []):
		var row: Dictionary = entry
		var id := str(row.get("id", ""))
		var stock_raw = row.get("stock", {})
		var stock: Dictionary = stock_raw if typeof(stock_raw) == TYPE_DICTIONARY else {}
		settlements[id] = {
			"id": id,
			"name": str(row.get("name", id)),
			"faction": str(row.get("faction", "")),
			"player": bool(row.get("player", false)),
			"q": int(row.get("q", 0)),
			"r": int(row.get("r", 0)),
			"specialty": str(row.get("specialty", "peach")),
			"need": str(row.get("need", "reed")),
			"stock": stock.duplicate(true),
			"hands": int(row.get("hands", 3)),
			"mood": str(row.get("mood", "open")),
			"hunger": 0,
			"lod": 4,
		}
		claims["%d,%d" % [int(row.get("q", 0)), int(row.get("r", 0))]] = id
	var factions := {}
	for entry in catalog.get("factions", []):
		var row: Dictionary = entry
		var id := str(row.get("id", ""))
		factions[id] = {
			"id": id,
			"name": str(row.get("name", id)),
			"home": str(row.get("home", "")),
			"stance": str(row.get("stance", "neighbor")),
			"choice": "",
			"confidence": 0.0,
		}
	return {
		"vale": str(catalog.get("name", "Petal Vale")),
		"home": str(catalog.get("home", HOME)),
		"settlements": settlements,
		"factions": factions,
		"carts": [],
		"migrants": [],
		"claims": claims,
		"log": [],
		"tick_day": -1,
		"tick_hour": -1.0,
		"withheld": {},
		"asks": [],
	}


func ensure(saved: Dictionary) -> Dictionary:
	var blank := fresh()
	for key in blank.keys():
		if not saved.has(key):
			saved[key] = blank[key]
	var blank_towns: Dictionary = blank["settlements"]
	var towns_raw = saved.get("settlements", {})
	var towns: Dictionary = towns_raw if typeof(towns_raw) == TYPE_DICTIONARY else {}
	for id in blank_towns.keys():
		var seed: Dictionary = blank_towns[id]
		if not towns.has(id):
			towns[id] = seed.duplicate(true)
		else:
			var live: Dictionary = towns[id]
			for field in seed.keys():
				if not live.has(field):
					live[field] = seed[field]
	saved["settlements"] = towns
	var blank_fac: Dictionary = blank["factions"]
	var fac_raw = saved.get("factions", {})
	var fac: Dictionary = fac_raw if typeof(fac_raw) == TYPE_DICTIONARY else {}
	for id in blank_fac.keys():
		if not fac.has(id):
			var seed_fac: Dictionary = blank_fac[id]
			fac[id] = seed_fac.duplicate(true)
	saved["factions"] = fac
	return saved


func to_dict() -> Dictionary:
	return state.duplicate(true)


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	var towns: Dictionary = state.get("settlements", {})
	for id in towns.keys():
		out.append(str(id))
	return out


func town(id: String) -> Dictionary:
	var towns: Dictionary = state.get("settlements", {})
	var row = towns.get(id, {})
	return row if typeof(row) == TYPE_DICTIONARY else {}


func stock_of(id: String, crop: String) -> int:
	var row := town(id)
	if row.is_empty():
		return 0
	var stock_raw = row.get("stock", {})
	var stock: Dictionary = stock_raw if typeof(stock_raw) == TYPE_DICTIONARY else {}
	return int(stock.get(crop, 0))


func traffic(id: String) -> int:
	var n := 0
	for entry in state.get("carts", []):
		var cart: Dictionary = entry
		if str(cart.get("to", "")) == id:
			n += 1
	return n


func headline() -> String:
	var carts: Array = state.get("carts", [])
	if not carts.is_empty():
		var cart: Dictionary = carts[0]
		return "%s is %d hours from %s." % [_crop_name(str(cart.get("crop", ""))), int(cart.get("eta", 0)), _town_name(str(cart.get("to", "")))]
	var asks: Array = state.get("asks", [])
	if not asks.is_empty():
		return str(asks[asks.size() - 1])
	var log: Array = state.get("log", [])
	if not log.is_empty():
		return str(log[0])
	return "The vale beyond the hedge is awake."


func page() -> Dictionary:
	var rows: Array = []
	var towns: Dictionary = state.get("settlements", {})
	var facs: Dictionary = state.get("factions", {})
	for id in towns.keys():
		var row: Dictionary = towns[id]
		var fac_id := str(row.get("faction", ""))
		var fac_raw = facs.get(fac_id, {})
		var fac: Dictionary = fac_raw if typeof(fac_raw) == TYPE_DICTIONARY else {}
		rows.append({
			"id": id,
			"name": str(row.get("name", id)),
			"specialty": str(row.get("specialty", "")),
			"need": str(row.get("need", "")),
			"hands": int(row.get("hands", 0)),
			"hunger": int(row.get("hunger", 0)),
			"mood": str(row.get("mood", "open")),
			"lod": int(row.get("lod", 4)),
			"stance": str(fac.get("stance", "neighbor")),
			"choice": str(fac.get("choice", "")),
			"confidence": float(fac.get("confidence", 0.0)),
			"stock_line": _stock_line(row),
			"player": bool(row.get("player", false)),
		})
	var cart_lines: Array = []
	for entry in state.get("carts", []):
		var cart: Dictionary = entry
		cart_lines.append("%s cart · %s → %s · %dh" % [_crop_name(str(cart.get("crop", ""))), _town_name(str(cart.get("from", ""))), _town_name(str(cart.get("to", ""))), int(cart.get("eta", 0))])
	var walk_lines: Array = []
	for entry in state.get("migrants", []):
		var walk: Dictionary = entry
		walk_lines.append("%d from %s walking to %s · %dd" % [int(walk.get("hands", 1)), _town_name(str(walk.get("from", ""))), _town_name(str(walk.get("to", ""))), int(walk.get("eta", 0))])
	return {
		"title": str(state.get("vale", "Petal Vale")),
		"settlements": rows,
		"carts": cart_lines,
		"migrants": walk_lines,
		"log": _log_slice(),
		"asks": state.get("asks", []),
		"sends": _send_options(),
		"can_welcome": _hollow_migrant() >= 0,
	}


func pulse(day: int, hour: float, garden: Dictionary) -> Array:
	var events: Array = []
	_apply_garden(garden)
	_refresh_lod()
	if last_day < 0:
		events.append_array(_day(day, garden))
		events.append_array(_hour(day, hour))
		_stamp(day, hour)
		return events
	if day != last_day:
		events.append_array(_day(day, garden))
	if int(hour) != int(last_hour) or day != last_day:
		events.append_array(_hour(day, hour))
	_stamp(day, hour)
	return events


func send_cart(from_id: String, to_id: String, crop: String, qty: int = 1) -> Dictionary:
	if qty < 1:
		return {"ok": false, "text": "Nothing to send."}
	if town(from_id).is_empty() or town(to_id).is_empty():
		return {"ok": false, "text": "That parish is not on the vale."}
	if stock_of(from_id, crop) < qty:
		return {"ok": false, "text": "%s has no %s to send." % [_town_name(from_id), _crop_name(crop)]}
	_add_stock(from_id, crop, -qty)
	var eta := _route_hours(from_id, to_id)
	var carts: Array = state.get("carts", [])
	carts.append({"from": from_id, "to": to_id, "crop": crop, "qty": qty, "eta": eta})
	state["carts"] = carts
	_warm(from_id, to_id, 1)
	var text := "A %s cart left %s for %s." % [_crop_name(crop), _town_name(from_id), _town_name(to_id)]
	_note(text)
	return {"ok": true, "text": text, "eta": eta}


func welcome() -> Dictionary:
	var idx := _hollow_migrant()
	if idx < 0:
		return {"ok": false, "text": "Nobody is at the hedge."}
	var walks: Array = state.get("migrants", [])
	var walk: Dictionary = walks[idx]
	walks.remove_at(idx)
	state["migrants"] = walks
	_add_hands(HOME, int(walk.get("hands", 1)))
	_add_hands(str(walk.get("from", "")), -int(walk.get("hands", 1)))
	_warm(str(walk.get("from", "")), HOME, 1)
	var text := "%s took in a walker from %s." % [_town_name(HOME), _town_name(str(walk.get("from", "")))]
	_note(text)
	return {"ok": true, "text": text, "from": str(walk.get("from", "")), "hands": int(walk.get("hands", 1))}


func share_seed(from_id: String, to_id: String, crop: String) -> Dictionary:
	if town(to_id).is_empty():
		return {"ok": false, "text": "That parish is not on the vale."}
	var dest := town(to_id)
	dest["gift"] = crop
	dest["gift_days"] = 3
	_warm(from_id, to_id, 2)
	var text := "%s shared %s seed with %s." % [_town_name(from_id), _crop_name(crop), _town_name(to_id)]
	_note(text)
	return {"ok": true, "text": text}


func _day(day: int, garden: Dictionary) -> Array:
	var events: Array = []
	var withheld: Dictionary = {}
	state["withheld"] = withheld
	state["asks"] = []
	var towns: Dictionary = state.get("settlements", {})
	for id in towns.keys():
		var row: Dictionary = towns[id]
		if not _awake(row, day):
			continue
		events.append_array(_grow(row, garden))
		events.append_array(_eat(row))
		events.append_array(_walk_if_hungry(row))
		events.append_array(_claim(row, day))
	for id in towns.keys():
		var row: Dictionary = towns[id]
		if bool(row.get("player", false)):
			continue
		if not _awake(row, day):
			continue
		events.append_array(_faction_act(row, day))
	for id in towns.keys():
		var row: Dictionary = towns[id]
		if bool(row.get("player", false)):
			continue
		if not _awake(row, day):
			continue
		if withheld.has(str(row.get("id", ""))):
			continue
		events.append_array(_trickle(row))
	_age_walks()
	return events


func _hour(_day: int, _hour_now: float) -> Array:
	var events: Array = []
	var carts: Array = state.get("carts", [])
	var kept: Array = []
	for entry in carts:
		var cart: Dictionary = entry
		cart["eta"] = int(cart.get("eta", 1)) - 1
		if int(cart["eta"]) > 0:
			kept.append(cart)
			continue
		events.append(_deliver(cart))
	state["carts"] = kept
	return events


func _grow(row: Dictionary, _garden: Dictionary) -> Array:
	if bool(row.get("player", false)):
		return []
	var spec := str(row.get("specialty", ""))
	var hands := int(row.get("hands", 3))
	var made := maxi(1, int(float(hands) * 0.5))
	_add_stock(str(row.get("id", "")), spec, made)
	var gift := str(row.get("gift", ""))
	var gift_days := int(row.get("gift_days", 0))
	if gift != "" and gift_days > 0:
		_add_stock(str(row.get("id", "")), gift, 1)
		row["gift_days"] = gift_days - 1
		if int(row["gift_days"]) <= 0:
			row["gift"] = ""
	return []


func _eat(row: Dictionary) -> Array:
	if bool(row.get("player", false)):
		return []
	var need := str(row.get("need", ""))
	var id := str(row.get("id", ""))
	if stock_of(id, need) > 0:
		_add_stock(id, need, -1)
		row["hunger"] = maxi(0, int(row.get("hunger", 0)) - 1)
		return []
	row["hunger"] = int(row.get("hunger", 0)) + 1
	return []


func _walk_if_hungry(row: Dictionary) -> Array:
	if bool(row.get("player", false)):
		return []
	if int(row.get("hunger", 0)) < 2:
		return []
	if int(row.get("hands", 0)) <= 2:
		return []
	var need := str(row.get("need", ""))
	var dest := _who_has(need, str(row.get("id", "")))
	if dest == "":
		return []
	var walks: Array = state.get("migrants", [])
	walks.append({"from": str(row.get("id", "")), "to": dest, "hands": 1, "eta": 2, "need": need})
	state["migrants"] = walks
	row["hunger"] = 0
	var text := "A walker left %s for %s." % [str(row.get("name", "")), _town_name(dest)]
	_note(text)
	return [{"type": "walk", "text": text, "from": str(row.get("id", "")), "to": dest}]


func _claim(row: Dictionary, day: int) -> Array:
	if bool(row.get("player", false)):
		return []
	if int(row.get("hands", 0)) < 7:
		return []
	var spec := str(row.get("specialty", ""))
	if stock_of(str(row.get("id", "")), spec) < 10:
		return []
	if int(row.get("lod", 4)) > 3 and day % 2 == 1:
		return []
	var q := int(row.get("q", 0))
	var r := int(row.get("r", 0))
	var ring := [[1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1], [1, -1]]
	var claims: Dictionary = state.get("claims", {})
	for step in ring:
		var nq: int = q + int(step[0])
		var nr: int = r + int(step[1])
		var key := "%d,%d" % [nq, nr]
		if claims.has(key):
			continue
		claims[key] = str(row.get("id", ""))
		state["claims"] = claims
		_add_stock(str(row.get("id", "")), spec, -4)
		var text := "%s marked a new lea at %s." % [str(row.get("name", "")), key]
		_note(text)
		return [{"type": "claim", "text": text, "id": str(row.get("id", "")), "cell": key}]
	return []


func _faction_act(row: Dictionary, _day: int) -> Array:
	var spec := str(row.get("specialty", ""))
	var id := str(row.get("id", ""))
	var needy := _who_needs(spec, id)
	var options: Array = ["hold stores", "send a cart", "ask for a crop"]
	if int(row.get("hunger", 0)) > 0:
		options = ["ask for a crop", "hold stores", "send a cart"]
	elif stock_of(id, spec) >= 4 and needy != "":
		options = ["hold stores", "send a cart", "keep the crop"]
	var question := "%s in %s have %d %s. %s needs %s. What do they do today?" % [
		_faction_name(str(row.get("faction", ""))),
		str(row.get("name", "")),
		stock_of(id, spec),
		_crop_name(spec),
		_town_name(needy) if needy != "" else "Nobody",
		_crop_name(spec),
	]
	var choice := _decide(question, options)
	var facs: Dictionary = state.get("factions", {})
	var fac_raw = facs.get(str(row.get("faction", "")), {})
	var fac: Dictionary = fac_raw if typeof(fac_raw) == TYPE_DICTIONARY else {}
	fac["choice"] = choice
	fac["confidence"] = _last_confidence()
	facs[str(row.get("faction", ""))] = fac
	state["factions"] = facs
	if choice == "send a cart" and needy != "" and stock_of(id, spec) > 0:
		return [send_cart(id, needy, spec, 1)]
	if choice == "keep the crop":
		var held: Dictionary = state.get("withheld", {})
		held[id] = true
		state["withheld"] = held
		_cool(id, needy)
		var text := "%s kept the %s in store." % [str(row.get("name", "")), _crop_name(spec)]
		_note(text)
		return [{"type": "hold", "text": text, "id": id}]
	if choice == "ask for a crop":
		var ask := "%s asked Hedge Hollow for %s." % [str(row.get("name", "")), _crop_name(str(row.get("need", "")))]
		var asks: Array = state.get("asks", [])
		asks.append(ask)
		state["asks"] = asks
		_note(ask)
		return [{"type": "ask", "text": ask, "id": id, "crop": str(row.get("need", ""))}]
	return []


func _trickle(row: Dictionary) -> Array:
	var spec := str(row.get("specialty", ""))
	var id := str(row.get("id", ""))
	if stock_of(id, spec) < 3:
		return []
	var needy := _who_needs(spec, id)
	if needy == "":
		return []
	return [send_cart(id, needy, spec, 1)]


func _deliver(cart: Dictionary) -> Dictionary:
	var to_id := str(cart.get("to", ""))
	var crop := str(cart.get("crop", ""))
	var qty := int(cart.get("qty", 1))
	_add_stock(to_id, crop, qty)
	_warm(str(cart.get("from", "")), to_id, 1)
	var text := "%s arrived in %s from %s." % [_crop_name(crop), _town_name(to_id), _town_name(str(cart.get("from", "")))]
	_note(text)
	return {"type": "deliver", "text": text, "to": to_id, "from": str(cart.get("from", "")), "crop": crop, "qty": qty}


func _age_walks() -> void:
	var walks: Array = state.get("migrants", [])
	var kept: Array = []
	for entry in walks:
		var walk: Dictionary = entry
		walk["eta"] = int(walk.get("eta", 1)) - 1
		if int(walk["eta"]) > 0:
			kept.append(walk)
			continue
		if str(walk.get("to", "")) == HOME:
			kept.append(walk)
			walk["eta"] = 0
			continue
		_add_hands(str(walk.get("to", "")), int(walk.get("hands", 1)))
		_add_hands(str(walk.get("from", "")), -int(walk.get("hands", 1)))
		_note("%s took in a walker from %s." % [_town_name(str(walk.get("to", ""))), _town_name(str(walk.get("from", "")))])
	state["migrants"] = kept


func _log_slice() -> Array:
	var log_raw = state.get("log", [])
	var log: Array = log_raw if typeof(log_raw) == TYPE_ARRAY else []
	return log.slice(0, 6)


func _apply_garden(garden: Dictionary) -> void:
	if not garden.has("bag"):
		return
	var home := town(HOME)
	if home.is_empty():
		return
	var bag_raw = garden.get("bag", {})
	var bag: Dictionary = bag_raw if typeof(bag_raw) == TYPE_DICTIONARY else {}
	var stock: Dictionary = {}
	for crop in catalog.get("crops", []):
		stock[str(crop)] = int(bag.get(str(crop), 0))
	if not stock.is_empty():
		home["stock"] = stock
	var hands := int(garden.get("hands", 0))
	if hands > 0:
		home["hands"] = hands
	var towns: Dictionary = state.get("settlements", {})
	towns[HOME] = home
	state["settlements"] = towns


func _refresh_lod() -> void:
	var home := town(HOME)
	var hq := int(home.get("q", 0))
	var hr := int(home.get("r", 0))
	var towns: Dictionary = state.get("settlements", {})
	for id in towns.keys():
		var row: Dictionary = towns[id]
		var dist := _hex(hq, hr, int(row.get("q", 0)), int(row.get("r", 0)))
		var lod := 4
		if dist <= 0:
			lod = 2
		elif dist == 1:
			lod = 3
		row["lod"] = lod
		towns[id] = row
	state["settlements"] = towns


func _awake(row: Dictionary, day: int) -> bool:
	var lod := int(row.get("lod", 4))
	if lod <= 3:
		return true
	return day % 2 == 0


func _who_needs(crop: String, skip: String) -> String:
	var best := ""
	var worst := -1
	var towns: Dictionary = state.get("settlements", {})
	for id in towns.keys():
		if str(id) == skip:
			continue
		var row: Dictionary = towns[id]
		if str(row.get("need", "")) != crop:
			continue
		var have := stock_of(str(id), crop)
		if have < 2 and (worst < 0 or have < worst):
			worst = have
			best = str(id)
	return best


func _who_has(crop: String, skip: String) -> String:
	var best := ""
	var most := 0
	var towns: Dictionary = state.get("settlements", {})
	for id in towns.keys():
		if str(id) == skip:
			continue
		var have := stock_of(str(id), crop)
		if have > most:
			most = have
			best = str(id)
	return best


func _send_options() -> Array:
	var out: Array = []
	var towns: Dictionary = state.get("settlements", {})
	for id in towns.keys():
		if str(id) == HOME:
			continue
		var row: Dictionary = towns[id]
		var need := str(row.get("need", ""))
		out.append({
			"to": str(id),
			"crop": need,
			"name": str(row.get("name", id)),
			"label": "Send %s to %s" % [_crop_name(need), str(row.get("name", id))],
		})
	return out


func _hollow_migrant() -> int:
	var walks: Array = state.get("migrants", [])
	for i in walks.size():
		var walk: Dictionary = walks[i]
		if str(walk.get("to", "")) == HOME and int(walk.get("eta", 1)) <= 0:
			return i
	return -1


func _add_stock(id: String, crop: String, delta: int) -> void:
	if crop == "":
		return
	var row := town(id)
	if row.is_empty():
		return
	var stock_raw = row.get("stock", {})
	var stock: Dictionary = stock_raw if typeof(stock_raw) == TYPE_DICTIONARY else {}
	stock[crop] = maxi(0, int(stock.get(crop, 0)) + delta)
	row["stock"] = stock
	var towns: Dictionary = state.get("settlements", {})
	towns[id] = row
	state["settlements"] = towns


func _add_hands(id: String, delta: int) -> void:
	var row := town(id)
	if row.is_empty():
		return
	row["hands"] = maxi(1, int(row.get("hands", 1)) + delta)
	var towns: Dictionary = state.get("settlements", {})
	towns[id] = row
	state["settlements"] = towns


func _warm(a: String, b: String, steps: int) -> void:
	_nudge_stance(a, steps)
	_nudge_stance(b, steps)


func _cool(a: String, b: String) -> void:
	_nudge_stance(a, -1)
	if b != "":
		_nudge_stance(b, -1)


func _nudge_stance(town_id: String, steps: int) -> void:
	var row := town(town_id)
	if row.is_empty():
		return
	var facs: Dictionary = state.get("factions", {})
	var fac_raw = facs.get(str(row.get("faction", "")), {})
	var fac: Dictionary = fac_raw if typeof(fac_raw) == TYPE_DICTIONARY else {}
	if fac.is_empty() or bool(row.get("player", false)):
		return
	var order := ["cool", "wary", "neighbor", "kin"]
	var now := str(fac.get("stance", "neighbor"))
	var idx := order.find(now)
	if idx < 0:
		idx = 2
	idx = clampi(idx + steps, 0, order.size() - 1)
	fac["stance"] = order[idx]
	facs[str(row.get("faction", ""))] = fac
	state["factions"] = facs
	row["mood"] = order[idx]
	var towns: Dictionary = state.get("settlements", {})
	towns[town_id] = row
	state["settlements"] = towns


func _route_hours(a: String, b: String) -> int:
	for entry in catalog.get("routes", []):
		var route: Dictionary = entry
		var left := str(route.get("a", ""))
		var right := str(route.get("b", ""))
		if (left == a and right == b) or (left == b and right == a):
			return int(route.get("hours", 10))
	return 12


func _stock_line(row: Dictionary) -> String:
	var stock_raw = row.get("stock", {})
	var stock: Dictionary = stock_raw if typeof(stock_raw) == TYPE_DICTIONARY else {}
	var bits: Array = []
	for crop in catalog.get("crops", []):
		var n := int(stock.get(str(crop), 0))
		if n > 0:
			bits.append("%s %d" % [_crop_name(str(crop)), n])
	if bits.is_empty():
		return "stores empty"
	return ", ".join(bits)


func _town_name(id: String) -> String:
	var row := town(id)
	if row.is_empty():
		return id
	return str(row.get("name", id))


func _faction_name(id: String) -> String:
	var facs: Dictionary = state.get("factions", {})
	var fac_raw = facs.get(id, {})
	var fac: Dictionary = fac_raw if typeof(fac_raw) == TYPE_DICTIONARY else {}
	if fac.is_empty():
		return id
	return str(fac.get("name", id))


func _crop_name(id: String) -> String:
	match id:
		"meadowbell":
			return "meadowbell"
		"peach":
			return "peach"
		"reed":
			return "reed"
		"bramble":
			return "bramble"
		"mosspear":
			return "mosspear"
		"nightlantern":
			return "nightlantern"
		_:
			return id


func _note(text: String) -> void:
	var log: Array = state.get("log", [])
	log.push_front(text)
	if log.size() > 16:
		log.resize(16)
	state["log"] = log


func _stamp(day: int, hour: float) -> void:
	last_day = day
	last_hour = hour
	state["tick_day"] = day
	state["tick_hour"] = hour


func _hex(aq: int, ar: int, bq: int, br: int) -> int:
	var dq := aq - bq
	var dr := ar - br
	return maxi(absi(dq), maxi(absi(dr), absi(-dq - dr)))


func _decide(question: String, options: Array) -> String:
	if options.is_empty():
		return ""
	if decide_cb.is_valid():
		return str(decide_cb.call(question, options))
	last_pick_confidence = 0.0
	return str(options[0])


func _last_confidence() -> float:
	return last_pick_confidence


func _read() -> Dictionary:
	var text := FileAccess.get_file_as_string(PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Expected object in %s" % PATH)
		return {}
	return parsed

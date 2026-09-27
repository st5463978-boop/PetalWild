class_name ParishChain
extends RefCounted

const TEA := "hedge_tea"
const JAM := "cane_jam"
const CAP := 3

var recipes: Dictionary = {}
var hopper: Dictionary = {}
var crate: Dictionary = {}
var pot: Dictionary = {}
var brew := ""
var left := 0.0

func boot(rows: Array) -> void:
	recipes.clear()
	for entry in rows:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var id := str(entry.get("id", ""))
		if id == "":
			continue
		recipes[id] = entry

func reset() -> void:
	hopper = {}
	crate = {}
	pot = {}
	brew = ""
	left = 0.0

func recipe(id: String = TEA) -> Dictionary:
	return recipes.get(id, {})

func hopper_count(id: String) -> int:
	return int(hopper.get(id, 0))

func crate_count(id: String = TEA) -> int:
	return int(crate.get(id, 0))

func pot_count(id: String = TEA) -> int:
	return int(pot.get(id, 0))

func brewing() -> bool:
	return brew != ""

func stock(bag: Dictionary, id: String = TEA) -> bool:
	var rec: Dictionary = recipe(id)
	if rec.is_empty():
		return false
	var inputs = rec.get("inputs", {})
	if typeof(inputs) != TYPE_DICTIONARY:
		return false
	for key in inputs.keys():
		var need := int(inputs[key])
		if int(bag.get(str(key), 0)) < need:
			return false
	for key in inputs.keys():
		var need := int(inputs[key])
		var item := str(key)
		bag[item] = int(bag.get(item, 0)) - need
		hopper[item] = hopper_count(item) + need
	_light(id)
	return true

func _light(id: String) -> bool:
	if brewing():
		return false
	var rec: Dictionary = recipe(id)
	var inputs = rec.get("inputs", {})
	if typeof(inputs) != TYPE_DICTIONARY or rec.is_empty():
		return false
	for key in inputs.keys():
		if hopper_count(str(key)) < int(inputs[key]):
			return false
	for key in inputs.keys():
		var item := str(key)
		hopper[item] = hopper_count(item) - int(inputs[key])
	brew = id
	left = float(rec.get("minutes", 18))
	return true

func tick(minutes: float) -> bool:
	if not brewing() or minutes <= 0.0:
		return false
	left -= minutes
	if left > 0.0:
		return false
	var rec: Dictionary = recipe(brew)
	var out := str(rec.get("output", brew))
	pot[out] = pot_count(out) + int(rec.get("output_count", 1))
	brew = ""
	left = 0.0
	_relight()
	return true

func _relight() -> void:
	for key in recipes.keys():
		if _light(str(key)):
			return

func deliver(id: String = TEA) -> bool:
	if pot_count(id) < 1:
		return false
	var rec: Dictionary = recipe(id)
	var cap := int(rec.get("crate_cap", CAP))
	if crate_count(id) >= cap:
		return false
	pot[id] = pot_count(id) - 1
	crate[id] = crate_count(id) + 1
	return true

func take_crate(id: String = TEA) -> bool:
	if crate_count(id) < 1:
		return false
	crate[id] = crate_count(id) - 1
	return true

func price(id: String = TEA) -> int:
	var rec: Dictionary = recipe(id)
	if rec.is_empty():
		return 1
	return int(rec.get("sell_price", 1))

func missing(bag: Dictionary, id: String = TEA) -> String:
	var rec: Dictionary = recipe(id)
	var inputs = rec.get("inputs", {})
	if typeof(inputs) != TYPE_DICTIONARY:
		return ""
	for key in inputs.keys():
		var item := str(key)
		var have := hopper_count(item) + int(bag.get(item, 0))
		if have < int(inputs[key]):
			return item
	return ""

func can_stock(bag: Dictionary, id: String = TEA) -> bool:
	var rec: Dictionary = recipe(id)
	var inputs = rec.get("inputs", {})
	if rec.is_empty() or typeof(inputs) != TYPE_DICTIONARY:
		return false
	for key in inputs.keys():
		if int(bag.get(str(key), 0)) < int(inputs[key]):
			return false
	return true

func line(bag: Dictionary, stall_open: bool, worker: bool) -> String:
	if brew == TEA:
		return "The kettle is brewing hedge tea."
	if brew == JAM:
		return "The pan is making cane jam."
	if pot_count(TEA) > 0:
		if crate_count(TEA) >= int(recipe(TEA).get("crate_cap", CAP)):
			return "The crate is full."
		if not stall_open:
			return "The stall is shut. Tea waits."
		return "Tea is waiting on the porch."
	if pot_count(JAM) > 0:
		if crate_count(JAM) >= int(recipe(JAM).get("crate_cap", CAP)):
			return "The jam crate is full."
		return "Jam is waiting at the shed."
	if crate_count(TEA) > 0:
		return "Hedge tea sits on the crate."
	if crate_count(JAM) > 0:
		return "Cane jam sits on the crate."
	if hopper_count("peach") > 0 or hopper_count("meadowbell") > 0:
		return "The kettle is ready."
	if can_stock(bag, TEA):
		return "The kettle is quiet."
	var lack := missing(bag, TEA)
	if lack != "":
		return "Kettle waits for %s." % lack
	if hopper_count("bramble") > 0 or can_stock(bag, JAM):
		return "The pan is ready."
	var jam_lack := missing(bag, JAM)
	if jam_lack != "":
		return "Pan waits for %s." % jam_lack
	return "The kettle is quiet."

func to_state() -> Dictionary:
	return {
		"hopper": hopper.duplicate(),
		"crate": crate.duplicate(),
		"pot": pot.duplicate(),
		"brew": brew,
		"left": left,
	}

func apply_state(data: Dictionary) -> void:
	reset()
	_copy_counts(hopper, data.get("hopper", {}))
	_copy_counts(crate, data.get("crate", {}))
	_copy_counts(pot, data.get("pot", {}))
	brew = str(data.get("brew", ""))
	left = float(data.get("left", 0.0))

func _copy_counts(into: Dictionary, saved) -> void:
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for key in saved.keys():
		into[str(key)] = int(saved[key])

class_name PlayDirector
extends RefCounted

const SLOT := 9

static func beat(garden: Node) -> String:
	var plot: SoilCell = _empty(garden)
	if plot == null:
		return "Self-play: no empty bed."
	var at := "%d,%d" % [plot.ix, plot.iz]
	garden.tool = "till"
	garden._use_on_cell(plot)
	if not plot.tilled:
		return "Self-play: till failed at %s." % at
	Economy.selected_seed = "meadowbell_seed"
	if Economy.count("meadowbell_seed") < 1:
		Economy.add("meadowbell_seed", 1)
	garden.tool = "seed"
	garden._use_on_cell(plot)
	if plot.plant_id != "meadowbell":
		return "Self-play: plant failed at %s." % at
	garden.tool = "water"
	garden._use_on_cell(plot)
	if plot.moisture < 0.99:
		return "Self-play: water failed at %s." % at
	return "Self-play: planted Meadowbell at %s." % at

static func run_integrate(garden: Node) -> void:
	var tree: SceneTree = garden.get_tree()
	var line := beat(garden)
	if not line.begins_with("Self-play: planted"):
		push_error("integrate: " + line)
		tree.quit(1)
		return
	garden.toast(line)
	var plot: SoilCell = _planted(garden)
	if plot == null:
		push_error("integrate: planted bed missing")
		tree.quit(1)
		return
	var grew := plot.growth
	var coins := Economy.coins
	SaveGame.active_slot = SLOT
	if not SaveGame.write_slot(SLOT, garden.to_state()):
		push_error("integrate: save failed")
		tree.quit(1)
		return
	plot.growth = minf(1.0, grew + 0.4)
	Economy.coins = coins + 99
	garden.apply_state(SaveGame.read_slot(SLOT))
	plot = _planted(garden)
	if plot == null or plot.plant_id != "meadowbell" or absf(plot.growth - grew) > 0.02 or Economy.coins != coins:
		push_error("integrate: save/load dropped the self-play bed")
		tree.quit(1)
		return
	Clock.set_hour(10.0)
	var shop_coins := Economy.coins
	var shop_peach := Economy.count("peach")
	Economy.add("peach", 1)
	var shopper: VegPerson = garden._person("nessa")
	shopper.present = true
	shopper.want = "peach"
	PetalDecide.forced = "buy"
	var deal: Dictionary = VillageShop.trade(shopper)
	if str(deal.get("choice", "")) != "buy" or int(deal.get("price", 0)) < 1 or Economy.coins <= shop_coins or Economy.count("peach") != shop_peach:
		push_error("integrate: stall did not buy")
		tree.quit(1)
		return
	PetalDecide.forced = "settle"
	var settle: Jelly = garden.ecology.force_spawn("bellhelp")
	settle.life = "visitor"
	settle.site_time = 20.0
	garden.ecology.try_promote(settle)
	if settle.life != "settler":
		push_error("integrate: settle decide failed")
		tree.quit(1)
		return
	settle.queue_free()
	PetalDecide.forced = ""
	shopper.want = ""
	var debug: String = garden._debug_text()
	if debug.find("decide") < 0 or debug.find("lanes") < 0:
		push_error("integrate: F3 is missing decide/lanes")
		tree.quit(1)
		return
	print("PETAL_INTEGRATE_OK")
	tree.quit(0)

static func run_selfplay(garden: Node) -> void:
	var line := beat(garden)
	garden.toast(line)
	if not line.begins_with("Self-play: planted"):
		push_error("selfplay: " + line)
		garden.get_tree().quit(1)
		return
	print("PETAL_SELFPLAY_OK")
	garden.get_tree().quit(0)

static func debug_block() -> String:
	return "decide %s conf %.2f p_yes %.2f\n%s" % [
		PetalDecide.last_tier,
		PetalDecide.last_confidence,
		PetalDecide.last_p_yes,
		CampaignBoard.debug_line(),
	]

static func _empty(garden: Node) -> SoilCell:
	var soil: SoilField = garden.soil
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "" and not plot.tilled:
			return plot
	return soil.get_cell(0, 7)

static func _planted(garden: Node) -> SoilCell:
	var soil: SoilField = garden.soil
	for cell in soil.all():
		var plot: SoilCell = cell
		if plot.plant_id == "meadowbell" and plot.growth < 0.2:
			return plot
	return null

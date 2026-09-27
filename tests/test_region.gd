extends SceneTree

func _init() -> void:
	var sim := RegionSim.new()
	sim.boot()
	_expect(sim.ids().size() == 5, "five parishes on the vale")
	_expect(sim.town("hollow").get("player", false) == true, "hollow is the player parish")
	_expect(int(sim.town("hollow").get("lod", -1)) == 2, "hollow lod is near")
	_expect(int(sim.town("reedbank").get("lod", -1)) == 3, "reedbank lod is neighbor")
	_expect(int(sim.town("thatch").get("lod", -1)) == 4, "thatchmere lod is far")
	_expect(sim.stock_of("reedbank", "reed") == 6, "reedbank opens with reed")
	var reed0 := sim.stock_of("reedbank", "reed")
	var events: Array = sim.pulse(1, 15.0, {})
	_expect(not events.is_empty(), "day one moves the vale")
	_expect(sim.stock_of("reedbank", "reed") < reed0 or sim.traffic("hollow") > 0, "reedbank reed moves toward hollow")
	_expect(sim.traffic("hollow") >= 1, "a cart is on the road to hollow")
	var arrived := false
	var hollow_reed := sim.stock_of("hollow", "reed")
	for h in 16:
		var hour := 15.0 + float(h + 1)
		var day := 1
		if hour >= 24.0:
			hour -= 24.0
			day = 2
		var notes: Array = sim.pulse(day, hour, {})
		for note in notes:
			var row: Dictionary = note
			if str(row.get("type", "")) == "deliver" and str(row.get("to", "")) == "hollow" and str(row.get("crop", "")) == "reed":
				arrived = true
		if arrived:
			break
	_expect(arrived, "the reed cart arrives in hollow")
	_expect(sim.stock_of("hollow", "reed") > hollow_reed, "hollow stores gain the reed")
	var moss := RegionSim.new()
	moss.boot()
	moss.decide_cb = func(_q, _opts): return "send a cart"
	var moss0 := moss.stock_of("mossford", "mosspear")
	moss.pulse(1, 8.0, {})
	_expect(moss.stock_of("mossford", "mosspear") < moss0 or moss.traffic("lea") > 0, "mossford send-a-cart moves a pear")
	var packed: Dictionary = sim.to_dict()
	var again := RegionSim.new()
	again.boot(packed)
	_expect(again.stock_of("hollow", "reed") == sim.stock_of("hollow", "reed"), "vale save keeps hollow reed")
	_expect(again.ids().size() == 5, "vale save keeps every parish")
	var grow := RegionSim.new()
	grow.boot()
	var lea: Dictionary = grow.town("lea")
	lea["hands"] = 8
	var stock_raw = lea.get("stock", {})
	var stock: Dictionary = stock_raw if typeof(stock_raw) == TYPE_DICTIONARY else {}
	stock["bramble"] = 12
	lea["stock"] = stock
	var towns: Dictionary = grow.state.get("settlements", {})
	towns["lea"] = lea
	grow.state["settlements"] = towns
	var claim_raw = grow.state.get("claims", {})
	var claim_map: Dictionary = claim_raw if typeof(claim_raw) == TYPE_DICTIONARY else {}
	var claim_n := claim_map.size()
	grow.pulse(2, 10.0, {})
	var after_raw = grow.state.get("claims", {})
	var after_map: Dictionary = after_raw if typeof(after_raw) == TYPE_DICTIONARY else {}
	_expect(after_map.size() > claim_n, "a thriving parish marks a new lea")
	var hungry := RegionSim.new()
	hungry.boot()
	var bank: Dictionary = hungry.town("reedbank")
	bank["hunger"] = 2
	bank["hands"] = 5
	var banks: Dictionary = hungry.state.get("settlements", {})
	banks["reedbank"] = bank
	hungry.state["settlements"] = banks
	hungry.pulse(2, 9.0, {})
	var walks_raw = hungry.state.get("migrants", [])
	var walks: Array = walks_raw if typeof(walks_raw) == TYPE_ARRAY else []
	_expect(walks.size() > 0, "a hungry parish sends a walker")
	var send := RegionSim.new()
	send.boot()
	var gift: Dictionary = send.send_cart("lea", "mossford", "bramble", 1)
	_expect(bool(gift.get("ok", false)), "a player cart can leave bramble lea")
	_expect(not send.page().get("cart_rows", []).is_empty(), "a sent cart is on the vale map")
	var play := RegionSim.new()
	play.boot()
	var reed_h := play.stock_of("hollow", "reed")
	var lea_b := play.stock_of("lea", "bramble")
	for d in range(1, 7):
		for h in 24:
			play.pulse(d, float(h), {})
	_expect(play.stock_of("hollow", "reed") > reed_h, "six days of trickle feed hollow reed")
	_expect(play.stock_of("lea", "bramble") != lea_b or play.traffic("mossford") > 0, "lea still moves bramble across the vale")
	var fid: Dictionary = play.fidelity()
	var sheet: Dictionary = sim.page()
	var hollow_hex := {}
	for row in sheet.get("settlements", []):
		var hamlet: Dictionary = row
		if str(hamlet.get("id", "")) == "hollow":
			hollow_hex = hamlet
	_expect(int(hollow_hex.get("q", -1)) == 0 and int(hollow_hex.get("r", -1)) == 0, "vale page keeps hex cells")
	var cart_rows_raw = sheet.get("cart_rows", [])
	var cart_rows: Array = cart_rows_raw if typeof(cart_rows_raw) == TYPE_ARRAY else []
	_expect(not cart_rows.is_empty() or sim.traffic("hollow") == 0, "cart rows match the road")
	var asker := RegionSim.new()
	asker.boot()
	asker.decide_cb = func(_q, _opts): return "ask for a crop"
	asker.pulse(1, 8.0, {})
	var ask_page: Dictionary = asker.page()
	var ask_rows_raw = ask_page.get("ask_rows", [])
	var ask_rows: Array = ask_rows_raw if typeof(ask_rows_raw) == TYPE_ARRAY else []
	_expect(not ask_rows.is_empty(), "a hungry neighbour asks hollow first")
	var asked: Dictionary = ask_rows[0]
	_expect(str(asked.get("crop", "")) != "", "the ask names a crop")
	_expect(int(fid.get("settlements", 0)) == 5, "world rollup keeps five parishes")
	_expect(int(fid.get("hands", 0)) >= 4, "world rollup counts hands")
	var packed_play: Dictionary = play.to_dict()
	var rest := RegionSim.new()
	rest.boot(packed_play)
	_expect(rest.stock_of("hollow", "reed") == play.stock_of("hollow", "reed"), "a week of vale state reloads")
	print("REGION_OK")
	quit(0)

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	push_error("region: " + label)
	quit(1)

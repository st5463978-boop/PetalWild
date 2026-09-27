class_name VillageShop
extends RefCounted

const PRODUCE := ["meadowbell", "peach", "reed", "bramble", "mosspear", "nightlantern"]
const LIKES := {
	"nessa": ["peach", "meadowbell", "mosspear", "nightlantern", "reed", "bramble"],
	"bram": ["bramble", "reed", "meadowbell", "peach", "mosspear", "nightlantern"],
	"lumen": ["meadowbell", "peach", "reed", "bramble", "mosspear", "nightlantern"],
}

static func likes(person: VegPerson) -> Array:
	if person == null:
		return PRODUCE
	var liked = LIKES.get(person.person_id, PRODUCE)
	return liked if typeof(liked) == TYPE_ARRAY else PRODUCE

static func wish(person: VegPerson) -> String:
	if person == null or not person.present:
		return ""
	if person.want != "" and PRODUCE.has(person.want):
		return person.want
	var options: Array = likes(person)
	var choice := PetalDecide.choose(
		"%s is looking over the stall. What crop do they want?" % person.display_name,
		options
	)
	if not PRODUCE.has(choice):
		choice = str(options[0]) if options.size() > 0 else ""
	person.want = choice
	return choice

static func stock() -> Array[String]:
	var ids: Array[String] = []
	for id in PRODUCE:
		if Economy.count(id) > 0:
			ids.append(id)
	return ids

static func trade(person: VegPerson) -> Dictionary:
	if person == null or not person.present:
		return {}
	wish(person)
	var held := stock()
	if held.is_empty():
		return {}
	var pick := held[0]
	if person.want != "" and held.has(person.want):
		pick = person.want
	var choice := PetalDecide.choose(
		"%s is at Petal Stall with %s on the counter. Buy or wait?" % [person.display_name, pick],
		["wait", "buy"]
	)
	if choice != "buy":
		return {"choice": choice, "id": pick, "price": 0}
	if not Economy.take(pick, 1):
		return {}
	var price := int(ContentDB.plant(pick).get("sell_price", 1))
	Economy.earn(price)
	return {"choice": "buy", "id": pick, "price": price}

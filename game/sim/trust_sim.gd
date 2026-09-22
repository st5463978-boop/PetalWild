extends RefCounted

var agents: Dictionary = {}
var proposals: Array = []
var audit: Array = []


func setup(agent_defs: Array) -> void:
	agents.clear()
	proposals.clear()
	audit.clear()
	for entry in agent_defs:
		var spec: Dictionary = entry
		var id := str(spec.get("id", ""))
		agents[id] = {
			"id": id,
			"name": spec.get("name", id),
			"role": spec.get("role", ""),
			"trust": 0,
			"success": 0,
			"mistakes": 0,
			"tools": [],
		}
	_log("observe", "town_hall", "All outside authority starts at trust 0. The town may look, then ask.")


func set_trust(id: String, level: int) -> void:
	if not agents.has(id):
		return
	agents[id].trust = clampi(level, 0, 5)
	_log("trust", id, "Trust set to %d." % agents[id].trust)


func draft_foundry_plan(petals: int) -> Dictionary:
	var text := "Havenbrook has no recurring income. The Media Foundry can prepare a small comedy-channel experiment: three episode outlines and a branding sheet. Projected outside cost is £0. No money has been spent. Petals on hand: %d. Submit the plan for approval?" % petals
	return propose("media_foundry", text, 0)


func propose(id: String, text: String, cost: int) -> Dictionary:
	var proposal := {
		"id": id,
		"text": text,
		"cost": cost,
		"status": "proposed",
		"executed": false,
	}
	proposals.append(proposal)
	_log("propose", id, text)
	return proposal


func approve(index: int, player_confirms: bool) -> String:
	if index < 0 or index >= proposals.size():
		return "No proposal."
	var proposal: Dictionary = proposals[index]
	if not player_confirms:
		proposal.status = "refused"
		_log("refuse", str(proposal.id), "Approval was not given.")
		return "Approval missing."
	var trust := int(agents.get(str(proposal.id), {}).get("trust", 0))
	if trust < 4:
		proposal.status = "refused"
		_log("refuse", str(proposal.id), "Trust %d cannot act. Need trust 4 plus a human yes." % trust)
		return "Trust is too low to act."
	proposal.status = "approved_held"
	proposal.executed = false
	_log("hold", str(proposal.id), "Human approved. No external connector is attached, so nothing was sent, spent, or published.")
	return "Approved and held. Nothing left the garden."


func _log(kind: String, id: String, note: String) -> void:
	audit.append({"kind": kind, "id": id, "note": note})
	if audit.size() > 40:
		audit.pop_front()


func to_dict() -> Dictionary:
	return {
		"agents": agents.duplicate(true),
		"proposals": proposals.duplicate(true),
		"audit": audit.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	if data.has("agents"):
		agents = data.agents
	proposals = data.get("proposals", [])
	audit = data.get("audit", [])

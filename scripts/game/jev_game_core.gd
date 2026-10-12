class_name JevGameCore
extends RefCounted

## Stub for the JEV *game core* decide bridge.
## Not the beebots trading core. Never discovers endpoints (no ntfy).
## The URL is an explicit setting. Paid calls wait on a player gate that shows the cost.

signal approval_requested(ticket: int, cost: float, summary: String, request: Dictionary)
signal decided(ticket: int, result: Dictionary)

const CORE_KIND := &"game_core"
const TRADING_CORE := &"beebots"

var configured_url := ""
var next_ticket := 1
var last_shown_cost := -1.0
var last_shown_summary := ""
var pending_paid: Dictionary = {}
var approved: Dictionary = {}
var results: Dictionary = {}


func core_kind() -> StringName:
	return CORE_KIND


func is_beebots() -> bool:
	return false


func uses_ntfy_discovery() -> bool:
	return false


func discover() -> String:
	## Studio tooling may poll ntfy. The shipped game core never does.
	return configured_url


func set_configured_url(url: String) -> bool:
	var cleaned := url.strip_edges()
	if looks_like_ntfy(cleaned):
		push_error("JevGameCore refuses ntfy discovery URLs; set an explicit game-core URL.")
		configured_url = ""
		return false
	configured_url = cleaned
	return true


func can_use_live() -> bool:
	return configured_url != ""


func is_paid_request(req: Dictionary) -> bool:
	if bool(req.get("paid", false)):
		return true
	return float(req.get("cost", 0.0)) > 0.0


func request(req: Dictionary) -> int:
	var core := str(req.get("core", CORE_KIND))
	if core == str(TRADING_CORE) or core == "trading":
		push_error("JevGameCore is the game core, not the beebots trading core.")
		return -1
	var ticket := next_ticket
	next_ticket += 1
	if is_paid_request(req):
		var cost := float(req.get("cost", 0.0))
		var summary := str(req.get("summary", req.get("question", "JEV game-core call")))
		last_shown_cost = cost
		last_shown_summary = summary
		pending_paid[ticket] = {
			"cost": cost,
			"summary": summary,
			"request": req.duplicate(true),
		}
		approval_requested.emit(ticket, cost, summary, req)
		return ticket
	_finish_offline(ticket, req, false)
	return ticket


func approve_paid(ticket: int, accepted: bool) -> bool:
	if not pending_paid.has(ticket):
		return false
	var item: Dictionary = pending_paid[ticket]
	pending_paid.erase(ticket)
	if not accepted:
		var declined := {
			"ok": false,
			"fallback": true,
			"reason": "player_declined",
			"cost": float(item.get("cost", 0.0)),
			"shown_cost": float(item.get("cost", 0.0)),
			"shown_summary": str(item.get("summary", "")),
			"core": str(CORE_KIND),
			"backend": "offline",
		}
		results[ticket] = declined
		decided.emit(ticket, declined)
		return false
	approved[ticket] = true
	_finish_offline(ticket, item.get("request", {}), true)
	return true


func dispatch_paid_without_approval(ticket: int) -> Dictionary:
	## Paid network path. Always refused until the player gate has shown the cost.
	if pending_paid.has(ticket) and not approved.has(ticket):
		return {
			"ok": false,
			"reason": "approval_required",
			"shown_cost": float(pending_paid[ticket].get("cost", 0.0)),
			"shown_summary": str(pending_paid[ticket].get("summary", "")),
		}
	if not approved.has(ticket):
		return {"ok": false, "reason": "approval_required"}
	return {"ok": false, "reason": "stub_no_network", "backend": "offline"}


func result_for(ticket: int) -> Dictionary:
	var found: Variant = results.get(ticket, {})
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return (found as Dictionary).duplicate(true)


func _finish_offline(ticket: int, req: Dictionary, paid_approved: bool) -> void:
	var body := {
		"ok": true,
		"backend": "offline",
		"index": int(req.get("fallback_index", 0)),
		"fallback": true,
		"core": str(CORE_KIND),
		"url": configured_url,
		"paid": is_paid_request(req),
		"paid_approved": paid_approved,
		"shown_cost": last_shown_cost if paid_approved else -1.0,
	}
	results[ticket] = body
	decided.emit(ticket, body)


static func looks_like_ntfy(url: String) -> bool:
	var lower := url.strip_edges().to_lower()
	if lower == "":
		return false
	if lower.begins_with("ntfy:"):
		return true
	var rest := lower
	var scheme := rest.find("://")
	if scheme >= 0:
		rest = rest.substr(scheme + 3)
	var host := rest.split("/")[0].split(":")[0]
	if host == "ntfy.sh" or host.ends_with(".ntfy.sh"):
		return true
	if host == "ntfy" or host.begins_with("ntfy."):
		return true
	return false

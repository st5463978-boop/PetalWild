extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")
const Core := preload("res://scripts/game/jev_game_core.gd")


func _initialize() -> void:
	var t: PetalAssert = PA.new("jev_game_core")
	var core: JevGameCore = Core.new()
	t.expect(core.core_kind() == &"game_core", "stub is the JEV game core")
	t.expect(not core.is_beebots(), "stub is not the beebots trading core")
	t.expect(not core.uses_ntfy_discovery(), "stub never uses ntfy discovery")
	t.expect(core.discover() == "", "discover is a no-op until a URL is set")
	t.expect(core.set_configured_url("http://127.0.0.1:8771"), "explicit URL is accepted")
	t.expect(core.configured_url == "http://127.0.0.1:8771", "configured URL is stored")
	t.expect(core.set_configured_url("http://not-ntfy.invalid:8771"), "host names that only contain ntfy as a substring are allowed")
	t.expect(core.configured_url == "http://not-ntfy.invalid:8771", "substring ntfy in a host is stored")
	t.expect(not core.set_configured_url("https://ntfy.sh/jevh-decide-05923aed092556ed/raw"), "ntfy discovery URL is refused")
	t.expect(core.configured_url == "", "refused ntfy URL is not stored")
	t.expect(core.set_configured_url("http://127.0.0.1:8771"), "explicit URL can be set again")

	var trading := core.request({"core": "beebots", "question": "buy?", "options": ["a", "b"]})
	t.expect(trading == -1, "beebots trading requests are rejected")

	var free_ticket := core.request({
		"question": "Which bed?",
		"options": ["peach", "meadowbell"],
		"fallback_index": 1,
	})
	t.expect(free_ticket > 0, "unpaid request returns a ticket")
	t.expect(int(core.result_for(free_ticket).get("index", -1)) == 1, "unpaid stub uses the fallback index")
	t.expect(str(core.result_for(free_ticket).get("backend", "")) == "offline", "unpaid stub stays offline")

	var shown := []
	core.approval_requested.connect(func(ticket: int, cost: float, summary: String, _req: Dictionary) -> void:
		shown.append({"ticket": ticket, "cost": cost, "summary": summary})
	)
	var paid := core.request({
		"question": "Ask Jev",
		"options": ["wait", "press seed"],
		"cost": 0.04,
		"paid": true,
		"summary": "OpenRouter Jev decide",
		"fallback_index": 0,
	})
	t.expect(paid > 0, "paid request still returns a ticket")
	t.expect(core.result_for(paid).is_empty(), "paid request does not run before approval")
	t.expect(shown.size() == 1, "paid request raises the player gate")
	t.expect(is_equal_approx(float(shown[0]["cost"]), 0.04), "gate shows the cost")
	t.expect(str(shown[0]["summary"]) == "OpenRouter Jev decide", "gate shows the summary")
	var blocked: Dictionary = core.dispatch_paid_without_approval(paid)
	t.expect(not bool(blocked.get("ok", true)), "paid dispatch without approval is refused")
	t.expect(str(blocked.get("reason", "")) == "approval_required", "refusal names the approval gate")
	t.expect(core.approve_paid(paid, true), "player can approve the shown cost")
	t.expect(bool(core.result_for(paid).get("ok", false)), "approved paid stub completes offline")
	t.expect(bool(core.result_for(paid).get("paid_approved", false)), "result records the approval")

	var declined_ticket := core.request({"cost": 1.25, "summary": "remote decide", "fallback_index": 0})
	t.expect(not core.approve_paid(declined_ticket, false), "player can decline")
	t.expect(not bool(core.result_for(declined_ticket).get("ok", true)), "declined paid call does not run")
	t.expect(str(core.result_for(declined_ticket).get("reason", "")) == "player_declined", "decline is recorded")
	t.done()

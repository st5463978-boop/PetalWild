extends SceneTree

func _init() -> void:
	_priority()
	_derive()
	_jelly_hooks()
	print("JELLY_ACTIVITY_OK")
	quit(0)


func _priority() -> void:
	_expect(JellyActivity.pick(["idea", "working"]) == JellyActivity.WORKING, "working beats idea")
	_expect(JellyActivity.pick(["working", "email"]) == JellyActivity.EMAIL, "email beats working")
	_expect(JellyActivity.pick(["email", "happy"]) == JellyActivity.HAPPY, "happy beats email")
	_expect(JellyActivity.pick(["none", "idea"]) == JellyActivity.IDEA, "idea beats none")
	_expect(JellyActivity.pick(["romance_interested", "email"]) == JellyActivity.EMAIL, "email beats interested")
	_expect(JellyActivity.pick(["email", "romance_locked"]) == JellyActivity.ROMANCE_LOCKED, "locked beats email")
	_expect(JellyActivity.pick(["romance_interested", "romance_locked"]) == JellyActivity.ROMANCE_LOCKED, "locked beats interested")
	_expect(JellyActivity.rank(JellyActivity.NONE) == 0, "none is rank 0")
	_expect(JellyActivity.is_heart(JellyActivity.HAPPY), "happy is a heart")
	_expect(JellyActivity.is_heart(JellyActivity.ROMANCE_INTERESTED), "interested is a heart")
	_expect(JellyActivity.color_of(JellyActivity.EMAIL).is_equal_approx(Color("#3FA9FF")), "envelope colour")
	_expect(JellyActivity.color_of(JellyActivity.ROMANCE_LOCKED).is_equal_approx(Color("#FF5FA8")), "locked heart colour")


func _derive() -> void:
	var jelly := _make()
	_expect(JellyActivity.derive(jelly) == JellyActivity.NONE, "idle is none")
	jelly.offer_mail()
	_expect(jelly.activity == JellyActivity.EMAIL, "mail pending shows envelope")
	jelly.work_intensity = 1.2
	jelly.refresh_activity()
	_expect(jelly.activity == JellyActivity.EMAIL, "mail still beats working")
	jelly.handle_mail()
	_expect(jelly.activity == JellyActivity.WORKING, "work shows after mail is handled")
	jelly.work_intensity = 0.0
	jelly.mood = "restless"
	jelly.refresh_activity()
	_expect(jelly.activity == JellyActivity.IDEA, "restless shows the bulb")
	jelly.pulse_happy()
	_expect(jelly.activity == JellyActivity.HAPPY, "a positive event shows the heart")
	jelly._on_status_icon_finished(JellyActivity.HAPPY)
	_expect(jelly.activity == JellyActivity.IDEA, "heart yields back to the bulb")
	jelly.show_interest()
	_expect(jelly.romance == "interested", "show_interest stamps romance")
	_expect(jelly.activity == JellyActivity.ROMANCE_INTERESTED, "interest shows the dim heart")
	jelly.offer_mail()
	_expect(jelly.activity == JellyActivity.EMAIL, "mail still beats interested")
	jelly.handle_mail()
	_expect(jelly.activity == JellyActivity.ROMANCE_INTERESTED, "interest returns after mail")
	jelly.lock_romance()
	_expect(jelly.romance == "locked", "lock_romance stamps locked")
	_expect(jelly.activity == JellyActivity.ROMANCE_LOCKED, "locked morphs over interested")
	jelly.offer_mail()
	_expect(jelly.activity == JellyActivity.ROMANCE_LOCKED, "locked beats mail")
	jelly.handle_mail()
	jelly.pulse_happy()
	_expect(jelly.activity == JellyActivity.HAPPY, "happy still preempts locked")
	jelly._on_status_icon_finished(JellyActivity.HAPPY)
	_expect(jelly.activity == JellyActivity.ROMANCE_LOCKED, "happy yields back to locked")
	jelly.show_interest()
	_expect(jelly.romance == "locked", "show_interest will not demote locked")
	jelly.clear_romance()
	_expect(jelly.activity == JellyActivity.IDEA, "clearing romance restores the bulb")
	jelly.force_activity(JellyActivity.WORKING, 1.4)
	_expect(jelly.activity == JellyActivity.WORKING, "debug force wins")
	jelly.work_intensity = 0.0
	jelly.clear_force()
	_expect(jelly.activity == JellyActivity.IDEA, "clearing force restores derive")
	jelly.free()


func _jelly_hooks() -> void:
	var jelly := _make()
	jelly.offer_mail()
	jelly.inspect_face()
	_expect(not jelly.mail_pending, "inspect handles mail")
	_expect(jelly.activity == JellyActivity.HAPPY, "inspect is a happy poke")
	jelly._on_status_icon_finished(JellyActivity.HAPPY)
	_expect(jelly.activity == JellyActivity.NONE, "handled mail stays gone")
	jelly.snack()
	_expect(jelly.activity == JellyActivity.HAPPY, "a snack is a happy event")
	jelly.hunger = 0.1
	jelly.mood = "hungry"
	jelly.work_intensity = 1.0
	jelly._on_status_icon_finished(JellyActivity.HAPPY)
	_expect(jelly.activity == JellyActivity.WORKING, "hungry travel is working")
	jelly.free()


func _make() -> Jelly:
	var jelly := Jelly.new()
	jelly.setup({
		"id": "bellhelp",
		"name": "Bellhelp",
		"shape": "bell",
		"deep": "#2f8f55",
		"lit": "#e7ffc4",
		"glow": "#d6ff6a",
		"eye": "#f4ffd2",
		"radius": 0.34,
	})
	return jelly


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("ok  ", label)
		return
	print("FAIL ", label)
	quit(1)

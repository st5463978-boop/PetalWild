class_name JellyActivity
extends RefCounted

## Live jelly status-icon kinds. Gameplay calls Jelly.set_activity / offer_mail /
## pulse_happy; the overlay never stays on without a current activity.
##
## Priority, highest wins, one icon at a time:
##   HAPPY (4)  >  EMAIL (3)  >  WORKING (2)  >  IDEA (1)  >  NONE (0)
## HAPPY is a one-shot event. It preempts whatever is showing, plays the heart,
## then the overlay returns to the next derived activity (mail still pending,
## still working, still restless, or none).

const NONE := "none"
const EMAIL := "email"
const IDEA := "idea"
const WORKING := "working"
const HAPPY := "happy"

const PRIORITY := {
	NONE: 0,
	IDEA: 1,
	WORKING: 2,
	EMAIL: 3,
	HAPPY: 4,
}

const COLOR := {
	EMAIL: Color("#3FA9FF"),
	IDEA: Color("#FFD84A"),
	WORKING: Color("#5BFF8A"),
	HAPPY: Color("#FF5FA8"),
}

static func rank(kind: String) -> int:
	return int(PRIORITY.get(kind, 0))


static func is_kind(kind: String) -> bool:
	return PRIORITY.has(kind)


static func pick(kinds: Array) -> String:
	var best := NONE
	for item in kinds:
		var kind := str(item)
		if rank(kind) > rank(best):
			best = kind
	return best


static func color_of(kind: String) -> Color:
	if COLOR.has(kind):
		var tint: Color = COLOR[kind]
		return tint
	return Color.WHITE


## Derive from the jelly's live fields. Forced debug activity wins.
## HAPPY is owned by pulse_happy() so a looping derive cannot restart the heart.
static func derive(jelly: Object) -> String:
	if jelly == null:
		return NONE
	var forced := str(jelly.get("_forced_activity"))
	if is_kind(forced) and forced != NONE:
		return forced
	if bool(jelly.get("_happy_playing")):
		return HAPPY
	if bool(jelly.get("mail_pending")):
		return EMAIL
	if float(jelly.get("work_intensity")) > 0.05:
		return WORKING
	if str(jelly.get("mood")) == "restless":
		return IDEA
	return NONE

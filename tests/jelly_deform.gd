extends SceneTree

func _init() -> void:
	var deform := JellyDeform.new()
	for _i in 30:
		deform.advance(1.0 / 60.0, true, Vector3(1.2, 0.2, 0.0), false, true)
	_expect(deform.stretch > 0.08, "a pull builds stretch")
	_expect(deform.axis.x > 0.8, "stretch follows the pull")
	var peak := deform.stretch
	var basis := deform.basis_for(Vector3(1.0, 0.0, 0.0), 0.4)
	var along := basis * Vector3(1.0, 0.0, 0.0)
	var side := basis * Vector3(0.0, 1.0, 0.0)
	_expect(along.x > 1.3, "the pull axis lengthens")
	_expect(side.length() < 0.9, "the waist pinches")
	for _j in 90:
		deform.advance(1.0 / 60.0, false, Vector3.ZERO, false, true)
	_expect(deform.stretch < peak * 0.35, "stretch settles after release")
	deform.advance(1.0 / 60.0, false, Vector3.ZERO, true, true)
	_expect(deform.impact > 0.5, "a landing kicks the body")
	var pet := deform.release_flick(Vector3(0.05, 0.0, 0.0))
	_expect(pet == Vector3.ZERO, "a small release stays a pet")
	var thrown := deform.release_flick(Vector3(2.0, 0.4, 0.0))
	_expect(thrown.length() > 0.2 and thrown.length() <= 0.81, "a flick adds a capped shove")
	deform.advance(1.0 / 60.0, false, Vector3.ZERO, false, false)
	_expect(deform.stretch == 0.0 and deform.impact == 0.0, "reduced motion clears the spring")
	print("JELLY DEFORM OK")
	quit(0)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("ok  ", label)
		return
	print("FAIL ", label)
	quit(1)

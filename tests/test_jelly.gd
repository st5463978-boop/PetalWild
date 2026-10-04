extends SceneTree

var failed := false

func _init() -> void:
	_scale()
	_release()
	_throw_samples()
	_land()
	_tunnel()
	_speed()
	_separate()
	_stall()
	_species()
	_hungry()
	_nuzzle()
	_park_land()
	_deform()
	_art_keeps_body()
	_icon_gel()
	_icon_faces_camera()
	if failed:
		quit(1)
		return
	print("JELLY_FEEL_OK")
	quit(0)

func _scale() -> void:
	var held := JellyFeel.body_scale(1.0, 0.5)
	_expect(held.y < held.x, "held stretch is wider than it is tall")
	var squat := JellyFeel.body_scale(0.6, 0.0)
	_expect(squat.y < 0.75 and squat.x > 1.0, "land squash is volume-preserving")
	_expect(JellyFeel.stretch_amount(1.2, 0.0, true) > 0.3, "a long pull stretches")
	_expect(JellyFeel.stretch_amount(0.0, 1.0, false) < 0.2, "a slow hop barely stretches")

func _release() -> void:
	_expect(JellyFeel.release_kind(0.4) == "pet", "a gentle let-go is a pet")
	_expect(JellyFeel.release_kind(2.0) == "drop", "a short toss is a drop")
	_expect(JellyFeel.release_kind(4.2) == "throw", "a fast flick is a throw")

func _throw_samples() -> void:
	var points: Array = [Vector3.ZERO, Vector3(2.0, 1.0, 0.0)]
	var times: Array = [0, 100]
	var thrown: Vector3 = JellyFeel.throw_from_samples(points, times, Vector3(0.2, 0.0, 0.0))
	_expect(thrown.x > 4.0, "sampled drag becomes throw speed")
	_expect(thrown.length() <= JellyFeel.MAX_SPEED + 0.01, "throw speed stays capped")

func _land() -> void:
	var landed: Dictionary = JellyFeel.land(Vector3(0.0, -0.2, 0.0), Vector3(1.0, -4.0, 0.0), 0.0, 0.016)
	var pos: Vector3 = landed["pos"]
	var vel: Vector3 = landed["vel"]
	_expect(bool(landed["hit"]), "a below-floor step hits")
	_expect(pos.y >= 0.0, "the body rests on the floor")
	_expect(vel.y > 0.0, "a hard landing bounces")
	_expect(float(landed["squash"]) < 1.0, "a hard landing squashes")

func _tunnel() -> void:
	var pos := Vector3(0.0, 0.4, 0.0)
	var vel := Vector3(0.0, -40.0, 0.0)
	vel = JellyFeel.clamp_vel(vel)
	_expect(vel.length() <= JellyFeel.MAX_SPEED + 0.01, "a dive is speed-capped")
	var dt := 1.0 / 60.0
	for _i in 20:
		vel = JellyFeel.fall(vel, dt)
		pos += vel * dt
		var step: Dictionary = JellyFeel.land(pos, vel, 0.0, dt)
		pos = step["pos"]
		vel = step["vel"]
	_expect(pos.y >= -0.001, "substeps do not leave the body under the lawn")
	_expect(pos.is_finite() and vel.is_finite(), "bounce stays finite")

func _speed() -> void:
	var nan_vel := Vector3(NAN, 1.0, 0.0)
	_expect(JellyFeel.clamp_vel(nan_vel) == Vector3.ZERO, "NaN velocity is cleared")
	var lost: Vector3 = JellyFeel.clamp_pos(Vector3(NAN, NAN, NAN), Vector3(1.0, 0.0, 2.0))
	_expect(lost.x == 1.0, "NaN position snaps back")

func _separate() -> void:
	var split: Dictionary = JellyFeel.separate(
		Vector3.ZERO, 0.4, Vector3.ZERO, false,
		Vector3(0.1, 0.0, 0.0), 0.4, Vector3.ZERO, false
	)
	_expect(bool(split["hit"]), "overlap is detected")
	var a_pos: Vector3 = split["a_pos"]
	var b_pos: Vector3 = split["b_pos"]
	_expect(a_pos.distance_to(b_pos) >= 0.79, "bodies are pushed apart")
	var held_split: Dictionary = JellyFeel.separate(
		Vector3.ZERO, 0.4, Vector3.ZERO, true,
		Vector3(0.1, 0.0, 0.0), 0.4, Vector3.ZERO, false
	)
	var held_pos: Vector3 = held_split["a_pos"]
	var other_pos: Vector3 = held_split["b_pos"]
	_expect(held_pos.length() < 0.02, "a held jelly keeps its place")
	_expect(other_pos.x > 0.7, "the free jelly slides off the hands")

func _stall() -> void:
	var inside := Vector3(GardenLayout.STALL.x, 0.3, GardenLayout.STALL.z)
	var bounced: Dictionary = JellyFeel.bounce_prop(inside, Vector3(3.0, 0.0, 0.0), 0.3, false)
	var pos: Vector3 = bounced["pos"]
	_expect(bool(bounced["hit"]), "the stall is solid")
	_expect(pos.distance_to(inside) > 0.4, "a jelly is pushed off the stall")
	var pond := Vector3(GardenLayout.POND_CENTER.x, 0.2, GardenLayout.POND_CENTER.z)
	var bank: Dictionary = JellyFeel.bounce_prop(pond, Vector3.ZERO, 0.3, false)
	var bank_pos: Vector3 = bank["pos"]
	var dist := Vector2(bank_pos.x - GardenLayout.POND_CENTER.x, bank_pos.z - GardenLayout.POND_CENTER.z).length()
	_expect(dist >= GardenLayout.POND_RADIUS * 0.9, "a land jelly is kept off the pond")
	var wader: Dictionary = JellyFeel.bounce_prop(pond, Vector3.ZERO, 0.3, true)
	var wader_pos: Vector3 = wader["pos"]
	_expect(wader_pos.distance_to(pond) < 0.05, "a water jelly may sit in the pond")

func _species() -> void:
	var grape: Dictionary = JellyFeel.tune({"wobble": 0.9, "shape": "long"})
	var reed: Dictionary = JellyFeel.tune({"wobble": 0.4, "shape": "flat"})
	_expect(float(grape["spring"]) < float(reed["spring"]), "a high-wobble jelly follows more softly")
	_expect(float(grape["stretch"]) > float(reed["stretch"]), "a high-wobble jelly stretches more")
	_expect(float(grape["bounce"]) > float(reed["bounce"]), "a high-wobble jelly bounces more")
	var forced: Dictionary = JellyFeel.tune({"wobble": 0.9, "give": 0.2, "bounce": 0.2})
	_expect(float(forced["spring"]) > float(grape["spring"]), "optional give firms the follow")
	_expect(absf(float(forced["bounce"]) - 0.2) < 0.001, "optional bounce key is used")
	_expect(absf(float(grape["damp"]) - JellyFeel.HOLD_DAMP) < 0.001, "damp stays on the lift-tuned value")

func _hungry() -> void:
	_expect(JellyFeel.hungry(0.15, "content"), "low hunger reads hungry")
	_expect(JellyFeel.hungry(0.9, "hungry"), "hungry mood reads hungry")
	_expect(not JellyFeel.hungry(0.9, "playful"), "full and playful is not hungry")

func _nuzzle() -> void:
	var still: Dictionary = JellyFeel.pet_hold(0.0, 0.05, 0.3)
	_expect(float(still["pet_time"]) > 0.2, "a still hold accumulates")
	_expect(not bool(still["nuzzle"]), "a short still hold has not nuzzled yet")
	var fire: Dictionary = JellyFeel.pet_hold(0.88, 0.05, 0.04)
	_expect(bool(fire["nuzzle"]), "a long still hold nuzzles")
	var again: Dictionary = JellyFeel.pet_hold(0.95, 0.05, 0.04)
	_expect(not bool(again["nuzzle"]), "nuzzle fires once at the threshold")
	var yank: Dictionary = JellyFeel.pet_hold(0.8, 0.5, 0.016)
	_expect(float(yank["pet_time"]) == 0.0, "a yank clears the pet")
	_expect(bool(yank["cancel"]), "a yank cancels the nuzzle")
	var stretch: Dictionary = JellyFeel.pet_hold(0.5, 0.25, 0.016)
	_expect(absf(float(stretch["pet_time"]) - 0.5) < 0.001, "a mild stretch pauses the pet")

func _park_land() -> void:
	var pad := GardenLayout.PARK + Vector3(0.2, 0.18, 0.15)
	var pos := pad + Vector3(0.0, 0.8, 0.0)
	var vel := Vector3(0.55, 3.2, 0.15)
	var grounded := false
	for _i in 180:
		vel = JellyFeel.fall(vel, 0.016)
		pos += vel * 0.016
		var step: Dictionary = JellyFeel.land(pos, vel, 0.0, 0.016)
		pos = step["pos"]
		vel = step["vel"]
		if bool(step["hit"]) and pos.y <= 0.14:
			grounded = true
			break
	_expect(grounded, "a park throw lands")
	_expect(pos.z < -14.0, "the land stays on the park lawn")
	var clamped: Vector3 = JellyFeel.clamp_pos(pad, Vector3.ZERO)
	_expect(clamped.z >= JellyFeel.GARDEN_MIN.z - 0.01, "garden clamp cannot rest on the park")

func _deform() -> void:
	var spring := JellyDeform.new()
	for _i in 30:
		spring.advance(1.0 / 60.0, true, Vector3(1.2, 0.2, 0.0), false, true)
	_expect(spring.stretch > 0.08, "a pull builds stretch")
	_expect(spring.axis.x > 0.8, "stretch follows the pull")
	var peak := spring.stretch
	var basis := spring.basis_for(Vector3(1.0, 0.0, 0.0), 0.4)
	var along := basis * Vector3(1.0, 0.0, 0.0)
	var side := basis * Vector3(0.0, 1.0, 0.0)
	_expect(along.x > 1.3, "the pull axis lengthens")
	_expect(side.length() < 0.9, "the waist pinches")
	for _j in 90:
		spring.advance(1.0 / 60.0, false, Vector3.ZERO, false, true)
	_expect(spring.stretch < peak * 0.35, "stretch settles after release")
	spring.advance(1.0 / 60.0, false, Vector3.ZERO, true, true)
	_expect(spring.impact > 0.5, "a landing kicks the body")
	var pet := spring.release_flick(Vector3(0.05, 0.0, 0.0))
	_expect(pet == Vector3.ZERO, "a small release stays a pet")
	var thrown := spring.release_flick(Vector3(2.0, 0.4, 0.0))
	_expect(thrown.length() > 0.2 and thrown.length() <= 0.81, "a flick adds a capped shove")
	spring.advance(1.0 / 60.0, false, Vector3.ZERO, false, false)
	_expect(spring.stretch == 0.0 and spring.impact == 0.0, "reduced motion clears the spring")

func _art_keeps_body() -> void:
	var jelly := Jelly.new()
	root.add_child(jelly)
	var definition := {
		"id": "bellhelp",
		"name": "Bellhelp",
		"shape": "bell",
		"radius": 0.34,
		"deep": "#3aaa66",
		"lit": "#e7ffd2",
		"glow": "#d6ff6a",
		"eye": "#fff4c8",
	}
	jelly.setup(definition)
	var body := jelly.get_node_or_null("Body") as Node3D
	_expect(body != null, "jelly has a body")
	_expect(_mesh_count(body) >= 3, "the deformable body stays when the cut-out exists")
	var art := body.get_node_or_null("Art") as Sprite3D
	_expect(art != null and art.visible, "a fed jelly rests on the approved card")
	_expect(jelly.icon_root != null and not jelly.icon_root.visible, "the icon waits behind the resting card")
	jelly.hunger = 0.16
	jelly.mood = "hungry"
	jelly._apply_deform()
	_expect(not art.visible, "hunger puts the card away")
	var icon := body.get_node_or_null("Icon/IconBody") as MeshInstance3D
	_expect(icon != null and jelly.icon_root.visible, "hunger shows the icon body")
	jelly.hunger = 1.0
	jelly.mood = "content"
	jelly.feel = "idle"
	jelly.held = true
	jelly._apply_deform()
	_expect(not art.visible and jelly.icon_root.visible, "a grab shows the icon")
	jelly.free()

func _icon_gel() -> void:
	var jelly := Jelly.new()
	root.add_child(jelly)
	jelly.setup({
		"id": "bellhelp",
		"name": "Bellhelp",
		"shape": "bell",
		"radius": 0.34,
		"deep": "#3aaa66",
		"lit": "#e7ffd2",
		"glow": "#d6ff6a",
		"eye": "#fff4c8",
	})
	var icon := jelly.get_node_or_null("Body/Icon/IconBody") as MeshInstance3D
	_expect(icon != null, "icon body exists")
	_expect(icon.material_override is ShaderMaterial, "icon uses the gel shader")
	var sm := icon.material_override as ShaderMaterial
	_expect(sm != null and sm.shader != null and str(sm.shader.resource_path).find("veg_jelly") != -1, "icon reuses veg_jelly")
	var shine := jelly.get_node_or_null("Body/Icon/IconHighlight") as MeshInstance3D
	_expect(shine != null, "icon keeps the cut-out highlight")
	var core := jelly.get_node_or_null("Body/Icon/IconCore") as MeshInstance3D
	_expect(core != null and core.material_override is ShaderMaterial, "icon keeps a darker gel core")
	var shade := jelly.get_node_or_null("ContactShadow") as MeshInstance3D
	_expect(shade != null, "the body keeps a contact shadow")
	var left := jelly.get_node_or_null("Body/Icon/IconEyeL") as MeshInstance3D
	var right := jelly.get_node_or_null("Body/Icon/IconEyeR") as MeshInstance3D
	_expect(left != null and right != null, "icon keeps two eyes")
	var eye_mat := left.material_override as StandardMaterial3D
	_expect(eye_mat != null and eye_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "eyes stay unshaded")
	_expect(eye_mat.albedo_color.r < 0.08 and eye_mat.albedo_color.g < 0.08, "eyes stay black")
	jelly.hunger = 0.16
	jelly.mood = "hungry"
	jelly._apply_deform()
	_expect(jelly.icon_root.visible, "hunger shows the gel")
	_expect(left.visible and right.visible, "gel does not hide the eyes")
	var art := jelly.get_node_or_null("Body/Art") as Sprite3D
	jelly.hunger = 1.0
	jelly.mood = "content"
	jelly.feel = "idle"
	jelly.held = false
	jelly.poke_time = 0.0
	jelly._apply_deform()
	_expect(art != null and art.visible, "resting still uses the approved card")
	_expect(not jelly.icon_root.visible, "the gel waits behind the card")
	print("ICON_GEL_OK")
	jelly.free()

func _icon_faces_camera() -> void:
	var deform := JellyDeform.new()
	var parent := deform.basis_for(Vector3(1.0, 0.0, 0.0), 0.55).scaled(Vector3(1.7, 0.55, 1.7))
	# Godot looks down -Z. A face aimed at +Z keeps local -Z toward the camera.
	var face := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	var feel := JellyFeel.body_scale(0.74, 0.48)
	var local := JellyFeel.icon_basis(parent, face, feel)
	var world := parent * local
	var shown := world.get_scale()
	_expect(shown.y < shown.x * 0.85, "the gel the player sees squashes")
	for side in [-1.0, 1.0]:
		var eye: Vector3 = world * Vector3(side * 0.11, 0.2, -0.3)
		_expect(eye.z > 0.05, "a stretched grab keeps an eye on the camera side")
	print("ICON_FACE_OK")

func _mesh_count(n: Node) -> int:
	if n == null or n.name == "Art":
		return 0
	var count := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		count = 1
	for child in n.get_children():
		count += _mesh_count(child)
	return count

func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	failed = true
	push_error("jelly: " + label)

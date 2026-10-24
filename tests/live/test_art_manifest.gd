extends SceneTree

const PA := preload("res://tests/support/petal_assert.gd")


func _initialize() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var t: PetalAssert = PA.new("art_manifest")
	ArtKit.reload()
	t.expect(ArtKit.enabled(), "art manifest loads and is enabled")
	var missing: Array[String] = []
	var paths: Array[String] = []
	_walk(ArtKit.manifest(), paths)
	for path in paths:
		if not ResourceLoader.exists(path):
			missing.append(path)
	t.expect(paths.size() >= 100, "manifest lists the VC art (%d paths)" % paths.size())
	t.expect(missing.is_empty(), "every manifest path imports %s" % [missing])

	var species: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/species.json"))
	for row_v in species:
		var id := str((row_v as Dictionary).get("id", ""))
		var node := ArtKit.mesh_node("species", id)
		t.expect(node != null, "%s has a mesh" % id)
		if node != null:
			var box := _bounds(node)
			var want := float(ArtKit.entry("species", id).get("height", 1.0))
			t.expect(absf(box.position.y) < 0.02, "%s sits on y=0" % id)
			t.expect(absf(box.size.y - want) < 0.05, "%s is scaled to its manifest height" % id)
			node.free()
		t.expect(ArtKit.sprite("species", id) != null, "%s has a journal sprite" % id)
	for id in ["well", "compost", "hive", "lantern", "stall", "pond"]:
		var node := ArtKit.mesh_node("services", id)
		t.expect(node != null, "service %s has a mesh" % id)
		if node != null:
			node.free()
	for id in ["bloom", "hive", "market"]:
		t.expect(ArtKit.icon("bars", id) != null, "demand bar %s has an icon" % id)
	for id in ["moisture", "fertility", "pollination", "light", "quality", "footfall", "blight", "districts"]:
		t.expect(ArtKit.icon("channels", id) != null, "channel %s has an icon" % id)
	t.expect(ArtKit.soil_texture(true, 0.2) != null and ArtKit.soil_texture(false, 0.2) != null, "soil lids have textures")

	# fallback: unknown ids and missing files keep the placeholder
	t.expect(ArtKit.mesh_node("species", "no_such_jelly") == null, "unknown species falls back")
	t.expect(ArtKit.texture_at("res://assets/art/vc_garden/missing.png") == null, "missing file falls back")
	t.expect(ArtKit.icon("bars", "nope") == null, "unknown bar falls back")

	var def: Dictionary = species[0]
	var jelly := Jelly.new()
	root.add_child(jelly)
	jelly.setup(def)
	var body := jelly.get_node_or_null("Body") as Node3D
	var art := body.get_node_or_null("Art") if body != null else null
	t.expect(art != null, "a jelly wears its art mesh")
	t.expect(jelly.eye_l != null and jelly.mat != null, "procedural refs survive the swap")
	var hidden := true
	for child in body.get_children():
		if child != art and (child as Node3D).visible:
			hidden = false
	t.expect(hidden, "procedural parts hide under the art mesh")
	jelly.free()

	OS.set_environment("PETAL_PLACEHOLDER_ART", "1")
	t.expect(not ArtKit.enabled(), "PETAL_PLACEHOLDER_ART forces the placeholders")
	var plain := Jelly.new()
	root.add_child(plain)
	plain.setup(def)
	t.expect(plain.get_node("Body").get_node_or_null("Art") == null, "placeholder jelly has no art mesh")
	t.expect(ArtKit.icon("bars", "bloom") == null, "placeholder mode drops icons")
	plain.free()
	OS.set_environment("PETAL_PLACEHOLDER_ART", "0")

	for row_v in ArtKit.list("service_dressing"):
		var row: Dictionary = row_v
		var at: Array = row.get("at", [])
		t.expect(GardenArt.spot_is_clear(Vector3(float(at[0]), 0.0, float(at[2])), 0.35), "dressing %s stays off paths, beds and pond" % row.get("service", ""))

	var field := ServiceField.new()
	field.setup(GardenLayout.BED_W, GardenLayout.BED_H)
	var moths := MothSource.new()
	var dressing := GardenArt.new()
	root.add_child(dressing)
	dressing.bind(field, moths)
	t.expect(dressing.placed.size() == ArtKit.list("service_dressing").size(), "all dressing props placed")
	field.stamp("well#2", Vector2i(3, 2), 2.0, 1.0)
	field.stamp("hive", Vector2i(6, 5), 2.0, 1.0)
	moths.moths.append({"id": 1, "ix": 4, "iz": 4})
	dressing.sync()
	t.expect(dressing.service_count() == 2, "stamped services get meshes")
	t.expect(dressing.moth_count() == 1, "blight moths get sprites")
	field.clear_service("well#2")
	moths.moths.clear()
	dressing.sync()
	t.expect(dressing.service_count() == 1 and dressing.moth_count() == 0, "cleared services and moths drop their art")
	dressing.queue_free()
	await process_frame
	await _vc10_wiring(t)
	t.done()


func _vc10_wiring(t: PetalAssert) -> void:
	# overlay legends: swatches + strip from the manifest, colour ramp when art is off
	var field := ServiceField.new()
	field.setup(GardenLayout.BED_W, GardenLayout.BED_H)
	var script: Script = load("res://scripts/ui/overlays.gd")
	var view: Object = script.new()
	view.call("bind", field, PathGraph.new(), CityDemand.new(), CausalLog.new(), null)
	for id in ["moisture", "fertility", "pollination", "light", "quality", "footfall", "blight"]:
		t.expect(ArtKit.overlay(id, "legend") != null, "channel %s has a legend strip" % id)
		view.call("set_channel", id)
		var state: Dictionary = view.call("legend_state")
		t.expect(bool(state.get("visible", false)) and bool(state.get("art", false)), "%s legend shows manifest art" % id)
		t.expect(state.get("legend") is AtlasTexture, "%s legend strip is cropped to its band" % id)
		t.expect(state.get("high") == ArtKit.overlay(id, "high"), "%s high swatch is the manifest swatch" % id)
	view.call("set_channel", "districts")
	var plain_state: Dictionary = view.call("legend_state")
	t.expect(bool(plain_state.get("visible", false)) and not bool(plain_state.get("art", true)), "districts legend falls back to the colour ramp")
	t.expect(plain_state.get("legend") is GradientTexture2D, "fallback legend is a gradient")
	view.call("set_channel", "")
	t.expect(not bool((view.call("legend_state") as Dictionary).get("visible", true)), "legend hides with the overlay off")
	OS.set_environment("PETAL_PLACEHOLDER_ART", "1")
	view.call("set_channel", "moisture")
	var off_state: Dictionary = view.call("legend_state")
	t.expect(not bool(off_state.get("art", true)) and off_state.get("legend") is GradientTexture2D, "placeholder mode keeps a colour legend")
	t.expect(off_state.get("low") != null, "placeholder mode keeps colour swatches")
	OS.set_environment("PETAL_PLACEHOLDER_ART", "0")
	(view as Node).free()

	# policy + district icons (loaded at run time: ThemeKit needs the Settings autoload)
	var badge_script: Script = load("res://scripts/art/district_badges.gd")
	var policies: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/policies.json"))
	for row_v in policies.get("policies", []):
		var policy_id := str((row_v as Dictionary).get("id", ""))
		t.expect(badge_script.call("policy_icon", policy_id) != null, "policy %s has an icon" % policy_id)
	t.expect(badge_script.call("flag_icon") != null, "district groups have a flag icon")
	t.expect(ArtKit.icon("tools", "district") != null, "district tool has a brush icon")
	t.expect(ArtKit.icon("tools", "till") == null, "tools without art keep text buttons")

	var bed_field := ServiceField.new()
	bed_field.setup(GardenLayout.BED_W, GardenLayout.BED_H)
	var groups := GardenDistricts.new()
	groups.setup(bed_field, null)
	var shown := [false]
	var badges: Node = badge_script.new()
	root.add_child(badges)
	badges.call("bind", groups, func() -> bool: return shown[0])
	t.expect((badges.call("strip_items") as Dictionary).size() == groups.policy_order().size(), "policy strip lists every policy")
	groups.paint_cell("north_beds", Vector2i(2, 2), "North Beds")
	groups.paint_cell("north_beds", Vector2i(3, 2), "North Beds")
	badges.call("sync")
	var flag: Node3D = badges.call("flag_for", "north_beds")
	t.expect(flag != null and flag.get_node_or_null("Flag") is Sprite3D, "a painted group gets a flag billboard")
	t.expect(not (badges.get("strip") as Control).visible, "policy strip waits for the district tool")
	shown[0] = true
	var first := groups.next_policy()
	groups.cycle_policy()
	badges.call("sync")
	t.expect((badges.get("strip") as Control).visible, "policy strip shows with the district tool")
	var items: Dictionary = badges.call("strip_items")
	var lit: Control = items.get(first) as Control
	t.expect(lit is TextureRect and bool(lit.get_meta("on", false)), "Y lights the adopted policy icon")
	var dim_ok := true
	for key in items.keys():
		if key != first and bool((items[key] as Control).get_meta("on", false)):
			dim_ok = false
	t.expect(dim_ok, "other policy icons stay dim")
	flag = badges.call("flag_for", "north_beds")
	t.expect(flag != null and flag.get_node_or_null("Policy_" + first) is Sprite3D, "the group flag carries its policy icon")
	groups.toggle_paint(Vector2i(2, 2))
	groups.toggle_paint(Vector2i(3, 2))
	badges.call("sync")
	t.expect((badges.call("flag_for", "north_beds") as Node3D) == null, "an empty group drops its flag")
	badges.queue_free()
	await process_frame


func _walk(value: Variant, out: Array[String]) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for v in (value as Dictionary).values():
				_walk(v, out)
		TYPE_ARRAY:
			for v in value:
				_walk(v, out)
		TYPE_STRING:
			if str(value).begins_with("res://"):
				out.append(str(value))


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_node as MeshInstance3D
		var xform := Transform3D.IDENTITY
		var walker: Node = mi
		while walker != null and walker != node.get_parent():
			if walker is Node3D:
				xform = (walker as Node3D).transform * xform
			walker = walker.get_parent()
		var local := xform * mi.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box


class MothSource:
	extends RefCounted
	var moths: Array = []

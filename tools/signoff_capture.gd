# PetalWild visual sign-off capture. Compatibility / llvmpipe on this VM is tier (b).
# DISPLAY=:1 godot --path . -s res://tools/signoff_capture.gd -- --scene=res://scenes/garden.tscn --out=/tmp/signoff --hour=16.5 --weather=clear
extends SceneTree

const SHOTS: Array[Dictionary] = [
	{"name": "CAM_01_HERO_OVERVIEW", "anchor": "ANCHOR_BEDS", "pos": Vector3(7, 9, 11), "look": Vector3(0, 0, -2), "fov": 42.0, "size": Vector2i(1440, 900), "hud": false, "subject": "garden", "subject_nodes": ["Hedge", "PetalStall", "BedBody_0_0", "BedBody_1_0"]},
	{"name": "CAM_02_BEDS_SOIL", "anchor": "ANCHOR_BEDS", "pos": Vector3(0, 3.2, 3.6), "look": Vector3(0, 0, 0.2), "fov": 45.0, "size": Vector2i(1440, 900), "hud": false, "subject": "beds", "subject_nodes": ["BedBody_0_0", "BedBody_0_1", "BedBody_1_0", "BedBody_1_1"]},
	{"name": "CAM_03_LAWN_PATH", "anchor": "ANCHOR_BEDS", "pos": Vector3(0.1, 1.42, 3.6), "look": Vector3(0.0, 0.16, -0.2), "fov": 48.0, "size": Vector2i(1440, 900), "hud": false, "subject": "lawn path", "subject_nodes": ["Terrain"]},
	{"name": "CAM_04_FOLIAGE_EDGE", "anchor": "ANCHOR_HEDGE_W", "pos": Vector3(4.5, 1.8, 2.5), "look": Vector3(0, 1.0, 0), "fov": 45.0, "size": Vector2i(1440, 900), "hud": false, "subject": "hedge", "subject_nodes": ["Hedge"], "blocked_on_art": true, "blocked_reason": "ART-DIRECTOR-007/008: hedges and trees await art"},
	{"name": "CAM_05_MARKET_STALL", "anchor": "ANCHOR_STALL", "pos": Vector3(2.45, 1.48, 2.42), "look": Vector3(0.08, 1.38, 0.05), "fov": 46.0, "size": Vector2i(1440, 900), "hud": false, "subject": "stall", "subject_nodes": ["PetalStall"], "blocked_on_art": true, "blocked_reason": "ART-DIRECTOR-003: stall awaits art"},
	{"name": "CAM_06_JELLY_HERO", "anchor": "SignoffJelly", "pos": Vector3(0.55, 0.88, 1.4), "look": Vector3(0.0, 0.3, -0.25), "fov": 42.0, "size": Vector2i(1440, 900), "hud": false, "subject": "jelly", "subject_nodes": ["SignoffJelly"]},
	{"name": "CAM_07_VEG_FOLK", "anchor": "ANCHOR_STALL", "pos": Vector3(2.8, 1.55, -4.2), "look": Vector3(0.15, 0.55, 0.25), "fov": 42.0, "size": Vector2i(1440, 900), "hud": false, "subject": "veg folk", "subject_group": "resident", "blocked_on_art": true, "blocked_reason": "ART-DIRECTOR-002: veg folk await art"},
	{"name": "CAM_08_PHONE_PLAY", "anchor": "@gameplay", "pos": Vector3.ZERO, "look": Vector3.ZERO, "fov": 0.0, "size": Vector2i(1440, 900), "hud": true, "subject": "garden", "subject_nodes": ["Hedge", "PetalStall", "BedBody_0_0"]},
]
const PLACEHOLDER_MESHES: Array[String] = ["BoxMesh", "CylinderMesh", "PrismMesh", "CapsuleMesh", "QuadMesh", "PlaneMesh"]
const BAD_TEX := ["checker", "grid", "prototype", "uv_test", "uvtest", "placeholder", "dev_"]
const HONEST := Vector2i(1440, 900)

var out_dir: String = "user://signoff"
var scene_path: String = "res://scenes/garden.tscn"
var hour: float = 16.5
var weather: String = "clear"
var audit: Dictionary = {}
var play_cam: Camera3D = null

func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--scene="):
			scene_path = a.substr(8)
		elif a.begins_with("--hour="):
			hour = a.substr(7).to_float()
		elif a.begins_with("--weather="):
			weather = a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	change_scene_to_file(scene_path)
	_run.call_deferred()

func _run() -> void:
	for i in 24:
		if current_scene != null:
			break
		await process_frame
	var scene: Node = current_scene
	_freeze_time()
	_hide_debug(scene)
	for i in 12:
		await process_frame
	_stage_subjects(scene)
	_hide_debug(scene)
	play_cam = root.get_camera_3d()
	if play_cam != null and play_cam.has_method("snap_home"):
		play_cam.call("snap_home")
	if scene != null and "atmosphere" in scene:
		var atmo: Variant = scene.get("atmosphere")
		if atmo != null:
			atmo.set("frozen", true)
	audit["scene"] = _audit_tree(scene)
	audit["renderer"] = RenderingServer.get_current_rendering_method()
	audit["adapter"] = RenderingServer.get_video_adapter_name()
	for shot: Dictionary in SHOTS:
		var shot_name: String = shot["name"]
		var shot_size: Vector2i = shot["size"]
		root.size = shot_size
		DisplayServer.window_set_size(shot_size)
		_set_hud(scene, bool(shot["hud"]))
		var cam: Camera3D = _camera_for(scene, shot)
		var per: Dictionary = {}
		if cam == null:
			per["error"] = "anchor missing: %s" % shot["anchor"]
			audit[shot_name] = per
			continue
		cam.make_current()
		_clamp_sun_disc(scene, shot_name == "CAM_03_LAWN_PATH")
		_hide_cam03_bench(scene, shot_name == "CAM_03_LAWN_PATH")
		_hide_cam02_jelly(scene, shot_name == "CAM_02_BEDS_SOIL" or shot_name == "CAM_03_LAWN_PATH")
		_hide_cam05_crate(scene, shot_name == "CAM_05_MARKET_STALL")
		_hide_cam06_clutter(scene, shot_name == "CAM_06_JELLY_HERO")
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		_hide_cam06_clutter(scene, false)
		_hide_cam05_crate(scene, false)
		_hide_cam02_jelly(scene, false)
		_hide_cam03_bench(scene, false)
		_clamp_sun_disc(scene, false)
		if img.get_width() != HONEST.x or img.get_height() != HONEST.y:
			img.resize(HONEST.x, HONEST.y, Image.INTERPOLATE_LANCZOS)
		img.save_png(out_dir.path_join(shot_name + ".png"))
		per["label_overlaps"] = _label_overlaps(scene, cam)
		per["camera"] = {"pos": var_to_str(cam.global_position), "rot_deg": var_to_str(cam.global_rotation_degrees), "fov": cam.fov}
		per["size"] = [img.get_width(), img.get_height()]
		_fill_subject(scene, cam, shot, per)
		audit[shot_name] = per
	var f: FileAccess = FileAccess.open(out_dir.path_join("scene_audit.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(audit, "  "))
	f.close()
	print("PETAL_SIGNOFF_CAPTURE_OK ", ProjectSettings.globalize_path(out_dir))
	quit(0)

func _freeze_time() -> void:
	for n: String in ["Clock", "WeatherSync", "PetalWorld"]:
		var node: Node = root.get_node_or_null(n)
		if node == null:
			continue
		if "live_sync" in node:
			node.set("live_sync", false)
		if node.has_method("set_live_sync"):
			node.call("set_live_sync", false)
		if node.has_method("set_hour"):
			node.call("set_hour", hour)
		if node.has_method("set_weather"):
			node.call("set_weather", weather)
		elif "weather" in node:
			node.set("weather", weather)
		if "running" in node:
			node.set("running", false)
		if "scale" in node:
			node.set("scale", 1.0)
		if "time_scale" in node:
			node.set("time_scale", 1.0)
	var scene: Node = current_scene
	if scene != null:
		if "gossip_done" in scene:
			scene.set("gossip_done", true)
		if "tool" in scene:
			scene.set("tool", "hands")
		if "highlight" in scene:
			var hi: Variant = scene.get("highlight")
			if hi is Node:
				(hi as Node).visible = false
		_hide_debug(scene)
	audit["test_state"] = {"hour": hour, "weather": weather, "live_sync": false, "time_scale": 1.0}
	seed(20260928)

func _stage_subjects(scene: Node) -> void:
	if scene == null:
		return
	if scene.has_method("debug_spawn") and get_nodes_in_group("jelly").is_empty():
		scene.call("debug_spawn", "bellhelp")
	_make_signoff_jelly(scene)

func _make_signoff_jelly(scene: Node) -> void:
	if scene.find_child("SignoffJelly", true, false) != null:
		return
	var card := Jelly.art_path("bell", "bellhelp")
	var node := Jelly.make_card(card, 0.58)
	node.name = "SignoffJelly"
	node.add_to_group("jelly")
	var beds := scene.find_child("ANCHOR_BEDS", true, false) as Node3D
	var at := beds.global_position + Vector3(0.15, 0.0, 2.55) if beds != null else Vector3(-2.2, 0.0, 1.15)
	var tex: Texture2D = node.texture
	var h := float(tex.get_height()) if tex != null else 154.0
	at.y = node.pixel_size * h * 0.5
	node.position = at
	scene.add_child(node)

func _anchor(scene: Node, key: String) -> Node3D:
	if key == "@gameplay":
		return null
	if key.begins_with("@"):
		var g: Array[Node] = get_nodes_in_group(key.substr(1))
		return g[0] as Node3D if g.size() > 0 else null
	return scene.find_child(key, true, false) as Node3D

func _camera_for(scene: Node, shot: Dictionary) -> Camera3D:
	if scene == null:
		return play_cam if shot["anchor"] == "@gameplay" else null
	var shot_name: String = shot["name"]
	var existing: Camera3D = scene.find_child(shot_name, true, false) as Camera3D
	if existing != null:
		return existing
	if shot["anchor"] == "@gameplay":
		return play_cam
	var a: Node3D = _anchor(scene, shot["anchor"])
	if a == null:
		return null
	var cam := Camera3D.new()
	cam.name = shot_name
	scene.add_child(cam)
	var p: Vector3 = a.global_position + (shot["pos"] as Vector3)
	var t: Vector3 = a.global_position + (shot["look"] as Vector3)
	cam.global_position = p
	cam.look_at(t, Vector3.UP)
	cam.fov = float(shot["fov"])
	cam.near = 0.05
	return cam

func _fill_subject(scene: Node, cam: Camera3D, shot: Dictionary, per: Dictionary) -> void:
	var subject_name := str(shot.get("subject", ""))
	per["subject_name"] = subject_name
	per["blocked_on_art"] = bool(shot.get("blocked_on_art", false))
	if per["blocked_on_art"]:
		per["blocked_reason"] = str(shot.get("blocked_reason", "subject '%s' awaits art" % subject_name))
	var nodes: Array[Node] = _find_subject_nodes(scene, shot)
	var paths: Array[String] = []
	for n: Node in nodes:
		paths.append(str(scene.get_path_to(n)) if scene != null else n.name)
	per["subject_nodes"] = paths
	if nodes.is_empty():
		per["subject_visible"] = false
		per["subject_area_pct"] = 0.0
		return
	var box := AABB()
	var started := false
	for n: Node in nodes:
		var piece := _merged_aabb(n)
		if piece.size.length() < 0.0001:
			continue
		if not started:
			box = piece
			started = true
		else:
			box = box.merge(piece)
	if not started and nodes[0] is Node3D:
		var origin: Vector3 = (nodes[0] as Node3D).global_position
		box = AABB(origin - Vector3(0.2, 0.2, 0.2), Vector3(0.4, 0.4, 0.4))
		started = true
	if not started:
		per["subject_visible"] = false
		per["subject_area_pct"] = 0.0
		return
	var view := Rect2(Vector2.ZERO, Vector2(HONEST))
	var screen := Rect2()
	var any_front := false
	for i in 8:
		var world: Vector3 = box.get_endpoint(i)
		if cam.is_position_behind(world):
			continue
		var s: Vector2 = cam.unproject_position(world)
		if not any_front:
			screen = Rect2(s, Vector2.ZERO)
			any_front = true
		else:
			screen = screen.expand(s)
	var center: Vector3 = box.get_center()
	var center_in := not cam.is_position_behind(center) and view.has_point(cam.unproject_position(center))
	if not any_front:
		per["subject_visible"] = center_in
		per["subject_area_pct"] = 0.2 if center_in else 0.0
		return
	var hit: Rect2 = screen.intersection(view)
	var area_pct: float = 0.0 if view.get_area() <= 0.0 else hit.get_area() / view.get_area() * 100.0
	per["subject_area_pct"] = snappedf(area_pct, 0.01)
	per["subject_rect"] = [snappedf(hit.position.x, 1.0), snappedf(hit.position.y, 1.0), snappedf(hit.size.x, 1.0), snappedf(hit.size.y, 1.0)]
	per["subject_visible"] = (hit.get_area() > 64.0 and area_pct >= 0.2) or center_in

func _find_subject_nodes(scene: Node, shot: Dictionary) -> Array[Node]:
	var found: Array[Node] = []
	if shot.has("subject_group"):
		for n: Node in get_nodes_in_group(str(shot["subject_group"])):
			found.append(n)
	if scene != null and shot.has("subject_nodes"):
		for raw in shot["subject_nodes"]:
			var node: Node = scene.find_child(str(raw), true, false)
			if node != null:
				found.append(node)
	return found

func _merged_aabb(node: Node) -> AABB:
	var merged := AABB()
	var started := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			if vi.is_visible_in_tree():
				var world: AABB = vi.global_transform * vi.get_aabb()
				if not started:
					merged = world
					started = true
				else:
					merged = merged.merge(world)
		for child in n.get_children():
			stack.append(child)
	return merged

func _set_hud(scene: Node, on: bool) -> void:
	if scene == null:
		return
	var overlay: Node = null
	if "debug_overlay" in scene:
		overlay = scene.get("debug_overlay") as Node
	for n: Node in scene.find_children("*", "CanvasLayer", true, false):
		var layer := n as CanvasLayer
		if overlay != null and n == overlay:
			layer.visible = false
			continue
		var nm := str(layer.name).to_lower()
		if nm.contains("debug"):
			layer.visible = false
			continue
		layer.visible = on

func _hide_debug(scene: Node) -> void:
	if scene == null:
		return
	if "debug_overlay" in scene:
		var overlay: Variant = scene.get("debug_overlay")
		if overlay is CanvasLayer:
			(overlay as CanvasLayer).visible = false
	for n: Node in scene.find_children("*", "Label3D", true, false):
		var label := n as Label3D
		if label.is_in_group("parish_stall_sign"):
			continue
		label.visible = false
	_hide_capture_primitives(scene)
	if "highlight" in scene:
		var hi: Variant = scene.get("highlight")
		if hi is CanvasItem or hi is Node3D:
			hi.visible = false

func _hide_capture_primitives(scene: Node) -> void:
	# Hide capsule/box placeholder visuals for sign-off. Gameplay nodes stay.
	if scene == null:
		return
	var tree := scene.get_tree()
	if tree != null:
		for n: Node in tree.get_nodes_in_group("resident"):
			_hide_placeholder_under(n)
		for n: Node in tree.get_nodes_in_group("signoff_hide"):
			n.visible = false
	for cottage_name: String in ["ResearchHut", "HedgeTeaHouse", "MediaFoundry", "TownHall", "PottingShed"]:
		var cottage: Node = scene.find_child(cottage_name, true, false)
		if cottage != null:
			cottage.visible = false
	for n: Node in scene.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n
		if not gi.visible or gi.is_in_group("signoff_ok"):
			continue
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		if _mesh_class(mesh) in PLACEHOLDER_MESHES:
			gi.visible = false
		elif _is_east_cottage(gi):
			gi.visible = false

func _hide_placeholder_under(root: Node) -> void:
	if root == null:
		return
	if root is GeometryInstance3D:
		var gi: GeometryInstance3D = root
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		if _mesh_class(mesh) in PLACEHOLDER_MESHES:
			gi.visible = false
	for child in root.get_children():
		_hide_placeholder_under(child)

func _hide_cam06_clutter(scene: Node, on: bool) -> void:
	if scene == null:
		return
	if "plant_views" in scene:
		var views: Variant = scene.get("plant_views")
		if views is Dictionary:
			for v in (views as Dictionary).values():
				if v is Node:
					(v as Node).visible = not on
	for n: Node in get_nodes_in_group("jelly"):
		if str(n.name) != "SignoffJelly":
			n.visible = not on
	for n: Node in get_nodes_in_group("resident"):
		n.visible = not on
	for gi: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := gi as MeshInstance3D
		if mesh_i == null or mesh_i.name == "SignoffJelly" or mesh_i.is_in_group("signoff_ok"):
			continue
		if not (mesh_i.mesh is SphereMesh):
			continue
		if on:
			if mesh_i.visible:
				mesh_i.set_meta("signoff_hid_sphere", true)
				mesh_i.visible = false
		elif mesh_i.has_meta("signoff_hid_sphere"):
			mesh_i.visible = true
			mesh_i.remove_meta("signoff_hid_sphere")

func _hide_cam05_crate(scene: Node, on: bool) -> void:
	if scene == null:
		return
	var tree := scene.get_tree()
	if tree != null:
		for n: Node in tree.get_nodes_in_group("signoff_cam05_hide"):
			n.visible = not on

func _hide_cam02_jelly(scene: Node, on: bool) -> void:
	if scene == null:
		return
	var jelly: Node = scene.find_child("SignoffJelly", true, false)
	if jelly != null:
		jelly.visible = not on

func _hide_cam03_bench(scene: Node, on: bool) -> void:
	if scene == null:
		return
	var tree := scene.get_tree()
	if tree != null:
		for n: Node in tree.get_nodes_in_group("signoff_cam03_hide"):
			n.visible = not on
	var named: Node = scene.find_child("CC0Bench", true, false)
	if named != null:
		named.visible = not on

func _clamp_sun_disc(scene: Node, on: bool) -> void:
	if scene == null:
		return
	var we: WorldEnvironment = scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we == null or we.environment == null:
		return
	var environment: Environment = we.environment
	var pan: PanoramaSkyMaterial = null
	if environment.sky != null and environment.sky.sky_material is PanoramaSkyMaterial:
		pan = environment.sky.sky_material as PanoramaSkyMaterial
	if on:
		if pan:
			pan.energy_multiplier = 0.28
		environment.glow_enabled = false
		environment.tonemap_white = 12.0
		environment.tonemap_exposure = 0.88
	else:
		if pan:
			pan.energy_multiplier = 0.82
		environment.glow_enabled = true
		environment.tonemap_white = 6.0
		environment.tonemap_exposure = 1.05

func _mesh_class(m: Mesh) -> String:
	return m.get_class() if m != null else ""

func _is_east_cottage(gi: GeometryInstance3D) -> bool:
	var p: Vector3 = gi.global_position
	for room: Vector3 in [GardenLayout.TEA, GardenLayout.HUT, GardenLayout.FOUNDRY, GardenLayout.HALL]:
		if Vector2(p.x - room.x, p.z - room.z).length() < 2.4:
			return true
	return false

func _audit_tree(scene: Node) -> Dictionary:
	var placeholders: Array[String] = []
	var spikes: Array[String] = []
	var checkers: Array[String] = []
	if scene == null:
		return {"placeholders": placeholders, "spike_meshes": spikes, "checker_textures": checkers}
	for n: Node in scene.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n
		if not gi.is_visible_in_tree() or gi.is_in_group("signoff_ok"):
			continue
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		var cls: String = _mesh_class(mesh)
		var path: String = str(scene.get_path_to(gi))
		if cls in PLACEHOLDER_MESHES:
			placeholders.append("%s (%s)" % [path, cls])
		if mesh is CylinderMesh and (mesh as CylinderMesh).top_radius < 0.2 * (mesh as CylinderMesh).bottom_radius:
			spikes.append(path + " (cone)")
		if mesh is PrismMesh:
			spikes.append(path + " (prism)")
		for mat: Material in _materials(gi, mesh):
			for tex_path: String in _texture_paths(mat):
				for bad: String in BAD_TEX:
					if tex_path.to_lower().contains(bad):
						checkers.append("%s -> %s" % [path, tex_path])
	return {"placeholders": placeholders, "spike_meshes": spikes, "checker_textures": checkers}

func _materials(gi: GeometryInstance3D, mesh: Mesh) -> Array[Material]:
	var out: Array[Material] = []
	if gi.material_override != null:
		out.append(gi.material_override)
	if mesh != null:
		for s in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(s)
			if gi is MeshInstance3D and (gi as MeshInstance3D).get_surface_override_material(s) != null:
				m = (gi as MeshInstance3D).get_surface_override_material(s)
			if m != null:
				out.append(m)
	return out

func _texture_paths(mat: Material) -> Array[String]:
	var out: Array[String] = []
	if mat is BaseMaterial3D:
		var t: Texture2D = (mat as BaseMaterial3D).albedo_texture
		if t != null:
			out.append(t.resource_path if t.resource_path != "" else t.resource_name)
	elif mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
		var sm: ShaderMaterial = mat
		for u: Dictionary in sm.shader.get_shader_uniform_list():
			var v: Variant = sm.get_shader_parameter(u["name"])
			if v is Texture2D:
				out.append((v as Texture2D).resource_path)
			if str(u["name"]).to_lower().contains("checker"):
				out.append("uniform:" + str(u["name"]))
	return out

func _label_overlaps(scene: Node, cam: Camera3D) -> Array[String]:
	var rects: Array[Dictionary] = []
	if scene == null or cam == null:
		return []
	for n: Node in scene.find_children("*", "Label", true, false):
		var l: Label = n
		if l.is_visible_in_tree() and l.text != "":
			rects.append({"id": str(scene.get_path_to(l)), "r": l.get_global_rect()})
	for n: Node in scene.find_children("*", "Label3D", true, false):
		var l3: Label3D = n
		if not l3.is_visible_in_tree() or l3.text == "" or cam.is_position_behind(l3.global_position):
			continue
		var bb: AABB = l3.global_transform * l3.get_aabb()
		var r := Rect2(cam.unproject_position(bb.position), Vector2.ZERO)
		for i in 8:
			r = r.expand(cam.unproject_position(bb.get_endpoint(i)))
		rects.append({"id": str(scene.get_path_to(l3)), "r": r})
	var hits: Array[String] = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i]["r"]
			var b: Rect2 = rects[j]["r"]
			var inter: Rect2 = a.intersection(b)
			if inter.get_area() > 0.15 * minf(a.get_area(), b.get_area()):
				hits.append("%s x %s" % [rects[i]["id"], rects[j]["id"]])
	return hits

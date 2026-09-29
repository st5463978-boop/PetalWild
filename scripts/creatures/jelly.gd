class_name Jelly
extends Node3D

signal reacted(kind: String, jelly: Jelly)

var species_id := ""
var display_name := ""
var life := "curious"
var bond := 0.08
var mood := "content"
var tier := 1
var radius := 0.34
var held := false
var hold_target := Vector3.ZERO
var vel := Vector3.ZERO
var goal := Vector3.ZERO
var attract := Vector3.ZERO
var berth := Vector3.ZERO
var use_berth := false
var site_time := 0.0
var hunger := 1.0
var bite_wait := 2.0
var leaving := false
var squash := 1.0
var ripple := 0.0
var hop_wait := 0.4
var wants_sleep := false
var young := false
var reduce_motion := false
var mat: ShaderMaterial
var eye_l: Node3D
var eye_r: Node3D
var mouth: Node3D
var face_z := 0.0
var eye_scale := 1.0
var inspected := false
var poke_time := 0.0
var feel := "idle"
var recover_t := 0.0
var stretch := 0.0
var deform := JellyDeform.new()
var selected := false
var last_safe := Vector3.ZERO
var bound := true
var sample_pos: Array[Vector3] = []
var sample_ms: Array[int] = []
var body_root: Node3D
var halo: MeshInstance3D
var halo_mat: StandardMaterial3D
var feel_spring := JellyFeel.HOLD_SPRING
var feel_damp := JellyFeel.HOLD_DAMP
var feel_bounce := JellyFeel.RESTITUTION
var feel_stretch := JellyFeel.STRETCH_GAIN
var pet_time := 0.0
var nuzzled := false
var iris_color := Color(1.0, 1.0, 0.85)
var iris_mats: Array[StandardMaterial3D] = []
var art_card: Sprite3D
var icon_root: Node3D

func setup(definition: Dictionary) -> void:
	species_id = str(definition.get("id", ""))
	display_name = str(definition.get("name", species_id))
	radius = float(definition.get("radius", 0.34))
	life = "curious"
	hunger = 1.0
	_apply_tune(definition)
	add_to_group("jelly")
	_build(definition)
	var here := Vector3.ZERO
	if is_inside_tree():
		here = global_position
	attract = here
	goal = here
	last_safe = here

func hit_radius() -> float:
	var fit := _young_fit()
	return radius * fit * 1.65 + 0.2

func touch_radius() -> float:
	return radius * _young_fit() * 0.92

func set_select(on: bool, grabbed := false) -> void:
	selected = on or grabbed
	if halo == null:
		return
	halo.visible = selected and icon_root == null
	if halo_mat == null:
		return
	if grabbed:
		halo_mat.albedo_color = Color(1.0, 0.92, 0.45, 0.9)
		halo_mat.emission = Color(0.95, 0.82, 0.28)
		halo_mat.emission_energy_multiplier = 0.55
	elif is_hungry():
		halo_mat.albedo_color = Color(1.0, 0.72, 0.38, 0.85)
		halo_mat.emission = Color(0.95, 0.55, 0.2)
		halo_mat.emission_energy_multiplier = 0.42
	else:
		halo_mat.albedo_color = Color(0.85, 0.98, 0.7, 0.7)
		halo_mat.emission = Color(0.55, 0.85, 0.4)
		halo_mat.emission_energy_multiplier = 0.28

const ART_DIR := "res://assets/art/images/PETAL-08-101/"

static func art_path(shape: String, species_id: String = "") -> String:
	var key := "circle"
	match species_id:
		"bellhelp":
			key = "circle"
		"berrypatch":
			key = "cloud"
		"bulrush":
			key = "oblong"
		"reedic":
			key = "pill"
		"cirlark":
			key = "square"
		"grapling":
			key = "triangle"
		"dusknip":
			key = "hexagon"
		"pegapear":
			key = "teardrop"
		"gushorn":
			key = "hexagon"
		_:
			match shape:
				"long":
					key = "oblong"
				"flat":
					key = "pill"
				"stacked":
					key = "square"
				"lobes", "crown":
					key = "cloud"
				"pear", "droplet":
					key = "teardrop"
				_:
					key = "circle"
	return ART_DIR + key + ".png"

static func make_card(tex_path: String, height_m: float) -> Sprite3D:
	var sprite := Sprite3D.new()
	var img: Image = null
	var abs_path := ProjectSettings.globalize_path(tex_path)
	if FileAccess.file_exists(abs_path):
		img = Image.load_from_file(abs_path)
	if img != null:
		img.fix_alpha_edges()
		sprite.texture = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
	var tex: Texture2D = sprite.texture
	var h := float(tex.get_height()) if tex != null else 154.0
	sprite.pixel_size = height_m / maxf(h, 1.0)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.transparent = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.shaded = false
	sprite.double_sided = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.add_to_group("signoff_ok")
	return sprite

func _build(definition: Dictionary) -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/jelly.gdshader")
	mat.set_shader_parameter("deep_color", Color(str(definition.get("deep", "#3aaa66"))))
	mat.set_shader_parameter("lit_color", Color(str(definition.get("lit", "#e7ffd2"))))
	mat.set_shader_parameter("glow_color", Color(str(definition.get("glow", "#d6ff6a"))))
	mat.set_shader_parameter("wobble", float(definition.get("wobble", 0.5)))
	var root := Node3D.new()
	root.name = "Body"
	add_child(root)
	body_root = root
	_halo()
	var shape := str(definition.get("shape", "droplet"))
	face_z = -radius * 1.05
	var eye_y := _shape(root, shape)
	var organ_y := eye_y * 0.5
	if shape == "bell":
		organ_y = radius * 0.95
	_organ(root, definition, organ_y)
	_face(root, definition, eye_y)
	var card := art_path(shape, str(definition.get("id", "")))
	var card_abs := ProjectSettings.globalize_path(card)
	if FileAccess.file_exists(card_abs) or ResourceLoader.exists(card):
		art_card = make_card(card, maxf(radius * 1.7, 0.44))
		art_card.name = "Art"
		root.add_child(art_card)
	_icon_body(root, shape)
	_sync_presentation()

func _icon_body(root: Node3D, shape: String) -> void:
	icon_root = Node3D.new()
	icon_root.name = "Icon"
	root.add_child(icon_root)
	var body := MeshInstance3D.new()
	body.name = "IconBody"
	var sphere := SphereMesh.new()
	sphere.radius = radius * 0.92
	sphere.height = radius * 1.84
	sphere.radial_segments = 24
	sphere.rings = 16
	body.mesh = sphere
	var icon_mat := StandardMaterial3D.new()
	icon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	icon_mat.roughness = 0.38
	icon_mat.metallic = 0.0
	icon_mat.metallic_specular = 0.22
	var deep: Color = mat.get_shader_parameter("deep_color")
	icon_mat.albedo_color = deep
	body.material_override = icon_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match shape:
		"long":
			body.scale = Vector3(0.72, 1.35, 0.72)
		"flat":
			body.scale = Vector3(1.25, 0.62, 1.05)
		"stacked":
			body.scale = Vector3(1.05, 1.05, 1.05)
			var box := BoxMesh.new()
			box.size = Vector3(radius * 1.55, radius * 1.45, radius * 1.55)
			body.mesh = box
		"lobes", "crown":
			body.scale = Vector3(1.2, 0.92, 1.05)
		"pear":
			body.scale = Vector3(0.86, 1.2, 0.86)
		_:
			body.scale = Vector3.ONE
	body.position = Vector3(0.0, radius * body.scale.y, 0.0)
	icon_root.add_child(body)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(0.02, 0.02, 0.025)
	eye_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var eye_y := body.position.y + radius * 0.48 * body.scale.y
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.name = "IconEyeL" if side < 0.0 else "IconEyeR"
		var slab := BoxMesh.new()
		slab.size = Vector3(radius * 0.18, radius * 0.78, radius * 0.08)
		eye.mesh = slab
		eye.material_override = eye_mat
		eye.position = Vector3(side * radius * 0.32, eye_y, -radius * 0.98)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		icon_root.add_child(eye)

func _show_volume() -> bool:
	if art_card == null:
		return true
	if held or nuzzled or is_hungry():
		return true
	if feel != "idle":
		return true
	if deform.stretch > 0.04 or absf(squash - 1.0) > 0.08:
		return true
	if poke_time > 0.0:
		return true
	return false

func _sync_presentation() -> void:
	var show_body := _show_volume()
	if art_card != null:
		art_card.visible = not show_body
	if icon_root != null:
		icon_root.visible = show_body or art_card == null
	if halo != null and icon_root != null:
		halo.visible = false
	# The petal bell reads as a bush. The icon is the body the player holds.
	_set_procedural_visible(body_root, icon_root == null and (art_card == null or show_body))

func _set_procedural_visible(n: Node, on: bool) -> void:
	if n == null or n == art_card or n.name == "Icon":
		return
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visible = on
	for child in n.get_children():
		_set_procedural_visible(child, on)

func _shape(root: Node3D, shape: String) -> float:
	match shape:
		"bell":
			_bell(root)
			face_z = radius * 0.62
			eye_scale = 0.68
			return radius * 0.12
		"pear":
			_blob(root, Vector3(0, 0.32, 0), Vector3(0.95, 1.2, 0.95))
			_blob(root, Vector3(0, 0.72, 0), Vector3(0.36, 0.3, 0.36))
			return 0.5
		"long":
			_blob(root, Vector3(0, 0.5, 0), Vector3(0.58, 1.45, 0.58))
			return 0.78
		"flat":
			_blob(root, Vector3(0, 0.18, 0), Vector3(1.35, 0.4, 1.2))
			return 0.24
		"stacked":
			_blob(root, Vector3(0, 0.2, 0), Vector3(0.78, 0.55, 0.78))
			_blob(root, Vector3(0, 0.52, 0), Vector3(0.58, 0.46, 0.58))
			_blob(root, Vector3(0, 0.84, 0), Vector3(0.36, 0.32, 0.36))
			return 0.7
		"lobes":
			_blob(root, Vector3(0, 0.26, 0), Vector3(0.78, 0.64, 0.78))
			_blob(root, Vector3(0.28, 0.22, 0.08), Vector3(0.5, 0.44, 0.5))
			_blob(root, Vector3(-0.26, 0.2, 0.1), Vector3(0.48, 0.42, 0.48))
			_blob(root, Vector3(0.02, 0.24, -0.26), Vector3(0.46, 0.4, 0.46))
			return 0.32
		"crown":
			_blob(root, Vector3(0, 0.28, 0), Vector3(0.95, 0.75, 0.95))
			for i in 5:
				var angle := TAU * float(i) / 5.0
				_blob(root, Vector3(cos(angle) * 0.28, 0.58, sin(angle) * 0.28), Vector3(0.28, 0.38, 0.28))
			return 0.42
		_:
			_blob(root, Vector3(0, 0.32, 0), Vector3(0.82, 1.08, 0.82))
			return 0.46

func _bell(root: Node3D) -> void:
	_blob(root, Vector3(0, radius * 0.05, 0), Vector3(0.26, 0.1, 0.24))
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2, 1.35, 1.05, 0.46)
	# ponytail: the gap ring stays inside the cup so it does not glue the five lobes together.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 5.0, 1.9, 0.48, 0.28)
	# ponytail: wide short petals close the cup inside the tips. Raise reach if the center stays bare.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 10.0, 1.45, 0.62, 0.62, null, 0.0, 0.05)
	for i in 5:
		var angle := TAU * float(i) / 5.0 + 0.2
		_petal(root, angle, -0.05, 0.85, 0.42)
		_petal(root, angle, 0.25, 0.62, 0.32)
	# ponytail: lower whorl flares past the cup; raise drop if the two rims merge.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2, 0.42, 1.18, 0.42, null, radius * 0.35)
	# ponytail: third rim hangs between those tips; raise drop if it merges with the whorl above.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 5.0, 0.2, 1.28, 0.38, null, radius * 0.55)
	# ponytail: darker band under the tips; raise drop if it merges with the flared whorl.
	var band := StandardMaterial3D.new()
	band.albedo_color = Color("#1e5c30")
	band.roughness = 0.9
	band.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 10.0, 0.7, 1.05, 0.44, band, radius * 0.12, 0.4)
	# ponytail: gap tips reach past the five lobes; lower reach if they fuse into one rim.
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.2 + PI / 5.0, 1.6, 1.35, 0.28, null, -radius * 0.22, 0.1)
	for i in 3:
		var angle := TAU * float(i) / 3.0 + 0.4
		var stamen := MeshInstance3D.new()
		var bud := SphereMesh.new()
		bud.radius = radius * 0.07
		bud.height = radius * 0.18
		stamen.mesh = bud
		stamen.material_override = mat
		stamen.position = Vector3(cos(angle) * radius * 0.12, radius * 1.28, sin(angle) * radius * 0.12)
		root.add_child(stamen)
	var seed := MeshInstance3D.new()
	var seed_mesh := SphereMesh.new()
	seed_mesh.radius = radius * 0.08
	seed_mesh.height = radius * 0.14
	seed_mesh.radial_segments = 10
	seed_mesh.rings = 6
	seed.mesh = seed_mesh
	var seed_material := StandardMaterial3D.new()
	seed_material.albedo_color = Color("#8c6e28")
	seed_material.roughness = 0.92
	seed_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	seed.material_override = seed_material
	seed.position = Vector3(0.0, radius * 0.42, -radius * 0.02)
	root.add_child(seed)
	var throat_material := StandardMaterial3D.new()
	throat_material.albedo_color = Color("#163f24")
	throat_material.roughness = 0.86
	throat_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for i in 5:
		_petal(root, TAU * float(i) / 5.0 + 0.9, 2.6, 0.34, 0.42, throat_material)

func _petal(root: Node3D, angle: float, lift: float, reach: float, size: float, material: Material = null, drop: float = 0.0, droop: float = 1.0) -> void:
	var petal := MeshInstance3D.new()
	petal.mesh = _petal_mesh(droop)
	petal.material_override = mat if material == null else material
	var out := Vector3(cos(angle), lift, sin(angle)).normalized()
	var x_axis := Vector3.UP.cross(out).normalized()
	var y_axis := out.cross(x_axis).normalized()
	var rim := radius * 0.78 * reach
	petal.transform = Transform3D(Basis(x_axis, y_axis, out).scaled(Vector3(size, size, reach)), Vector3(cos(angle) * rim, radius * 0.1 - drop, sin(angle) * rim))
	root.add_child(petal)

func _petal_mesh(droop: float = 1.0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := radius * 2.2
	var steps := 8
	var prev: Array[Vector3] = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var z := t * length * (1.0 - 0.32 * t * t)
		var y := sin(t * PI) * radius * 0.32 - pow(maxf(t - 0.55, 0.0), 2.0) * radius * 2.1 * droop
		var w := radius * (0.14 + 0.72 * sin(t * PI))
		var cup := sin(t * PI) * radius * 0.55
		var rib := sin(t * PI) * radius * 0.28
		var row: Array[Vector3] = [
			Vector3(-w, y + cup, z),
			Vector3(-w * 0.42, y + cup * 0.08, z),
			Vector3(0.0, y + rib, z),
			Vector3(w * 0.42, y + cup * 0.08, z),
			Vector3(w, y + cup, z),
		]
		if i > 0:
			for k in row.size() - 1:
				_tri(tool, prev[k], prev[k + 1], row[k + 1])
				_tri(tool, prev[k], row[k + 1], row[k])
				_tri(tool, prev[k + 1], prev[k], row[k])
				_tri(tool, prev[k + 1], row[k], row[k + 1])
		prev = row
	tool.generate_normals()
	return tool.commit()

func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)

func _blob(root: Node3D, at: Vector3, squash_scale: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.scale = squash_scale
	root.add_child(node)
	return node

func _organ(root: Node3D, definition: Dictionary, height: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius * 0.28
	mesh.height = radius * 0.56
	mesh.radial_segments = 10
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	var glow := Color(str(definition.get("glow", "#d6ff6a")))
	material.albedo_color = glow
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = 0.7
	node.material_override = material
	node.position = Vector3(0, height, 0)
	root.add_child(node)

func _apply_tune(definition: Dictionary) -> void:
	var tuned: Dictionary = JellyFeel.tune(definition)
	feel_spring = float(tuned["spring"])
	feel_damp = float(tuned["damp"])
	feel_bounce = float(tuned["bounce"])
	feel_stretch = float(tuned["stretch"])

func is_hungry() -> bool:
	return JellyFeel.hungry(hunger, mood)

func shown_mood() -> String:
	if nuzzled and held:
		return "happy"
	if is_hungry() and mood != "panic" and mood != "dizzy" and mood != "annoyed":
		return "hungry"
	return mood

func _face(root: Node3D, definition: Dictionary, eye_y: float) -> void:
	iris_mats.clear()
	iris_color = Color(str(definition.get("eye", "#fff4c8")))
	var z := face_z if face_z != 0.0 else radius * 1.05
	var bell := str(definition.get("shape", "")) == "bell"
	var spread := radius * 0.2 if bell else minf(radius * 0.26, maxf(absf(z) * 0.38, radius * 0.12))
	eye_l = _eye(root, Vector3(-spread, eye_y, z), iris_color, true)
	eye_r = _eye(root, Vector3(spread, eye_y, z), iris_color, true)
	var mouth_y := radius * 0.05 if bell else eye_y - radius * 0.22
	var mouth_z := radius * 0.7 if bell else z
	mouth = _eye(root, Vector3(0, mouth_y, mouth_z), Color(str(definition.get("deep", "#1d6b38"))).darkened(0.15))
	mouth.scale = Vector3(0.7, 0.14, 0.2)

func face_point() -> Vector3:
	if mouth != null and is_instance_valid(mouth):
		return mouth.global_position
	if eye_l != null and is_instance_valid(eye_l):
		return eye_l.global_position
	return global_position + Vector3(0.0, radius * 0.45, face_z)

func poke() -> void:
	mood = "happy"
	bond = minf(1.0, bond + 0.04)
	ripple = 0.85
	poke_time = 0.7
	reacted.emit("poke", self)

func inspect_face() -> void:
	inspected = true
	tier = 0
	poke()

func clear_inspect() -> void:
	inspected = false

func snack() -> void:
	hunger = 1.0
	mood = "happy"
	bond = minf(1.0, bond + 0.05)
	ripple = 0.85
	bite_wait = 4.0
	poke_time = 0.55
	reacted.emit("snack", self)

func _eye(root: Node3D, at: Vector3, color: Color, keep_iris := false) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	root.add_child(pivot)
	var socket := MeshInstance3D.new()
	var socket_mesh := SphereMesh.new()
	socket_mesh.radius = radius * 0.14 * eye_scale
	socket_mesh.height = radius * 0.2 * eye_scale
	socket.mesh = socket_mesh
	var socket_material := StandardMaterial3D.new()
	socket_material.albedo_color = Color("#243024")
	socket_material.roughness = 0.8
	socket.material_override = socket_material
	socket.position = Vector3(0, 0, -radius * 0.02)
	pivot.add_child(socket)
	var mesh := SphereMesh.new()
	mesh.radius = radius * 0.1 * eye_scale
	mesh.height = radius * 0.16 * eye_scale
	mesh.radial_segments = 10
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.35
	material.roughness = 0.25
	node.material_override = material
	pivot.add_child(node)
	if keep_iris:
		iris_mats.append(material)
	var pupil := MeshInstance3D.new()
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = radius * 0.038
	pupil_mesh.height = radius * 0.06
	pupil.mesh = pupil_mesh
	var pupil_material := StandardMaterial3D.new()
	pupil_material.albedo_color = Color("#3c4a28")
	pupil.material_override = pupil_material
	pupil.position = Vector3(0, 0, radius * 0.1)
	pivot.add_child(pupil)
	return pivot

func grab(point: Vector3) -> void:
	held = true
	leaving = false
	hold_target = point
	mood = "playful"
	feel = "held"
	tier = 0
	recover_t = 0.0
	sample_pos.clear()
	sample_ms.clear()
	pet_time = 0.0
	nuzzled = false
	_note_sample(point)
	set_select(true, true)

func release() -> void:
	held = false
	vel = JellyFeel.throw_from_samples(sample_pos, sample_ms, vel)
	vel += deform.release_flick(hold_target - global_position)
	vel = JellyFeel.clamp_vel(vel)
	var speed := vel.length()
	var kind := JellyFeel.release_kind(speed)
	if kind == "throw":
		mood = "panic" if speed > JellyFeel.THROW_HARD else "dizzy"
		bond = maxf(0.0, bond - 0.08)
		ripple = 1.0
		feel = "air"
	elif kind == "drop":
		mood = "annoyed"
		bond = maxf(0.0, bond - 0.03)
		feel = "air"
	else:
		mood = "happy"
		bond = minf(1.0, bond + 0.06)
		vel.y = 2.6
		feel = "air"
	sample_pos.clear()
	sample_ms.clear()
	set_select(selected, false)
	reacted.emit(kind, self)

func _process(delta: float) -> void:
	if poke_time > 0.0:
		poke_time = maxf(0.0, poke_time - delta)
	if inspected:
		tier = 0
	if tier >= 3:
		visible = false
		_coast(delta)
	elif tier == 2:
		visible = true
		_coast(delta)
	else:
		visible = true
		_full(delta)

func _full(delta: float) -> void:
	if reduce_motion and not held:
		vel = Vector3.ZERO
		ripple = 0.0
		squash = 1.0
		stretch = 0.0
		deform.reset()
		feel = "idle"
		_apply_deform()
		if mat:
			mat.set_shader_parameter("ripple", 0.0)
			mat.set_shader_parameter("wobble", 0.0)
		_update_face()
		return
	ripple = move_toward(ripple, 0.0, delta * 1.8)
	squash = move_toward(squash, 1.0, delta * 3.2)
	if recover_t > 0.0 and not held:
		recover_t -= delta
		if recover_t <= 0.0:
			recover_t = 0.0
			feel = "idle"
			if mood == "dizzy" or mood == "panic" or mood == "annoyed":
				mood = "content"
	var heading_home := use_berth and goal.distance_to(berth) < 0.25
	if held:
		feel = "held"
		_note_sample(hold_target)
		var pull := hold_target - global_position
		if pull.length() > 2.5:
			mood = "annoyed"
			bond = maxf(0.0, bond - delta * 0.04)
	elif leaving:
		vel.x = 0.0
		vel.z = 0.0
		goal = GardenLayout.GATE
		var gate := GardenLayout.GATE - global_position
		gate.y = 0.0
		if gate.length() > 0.4:
			global_position += gate.normalized() * delta * 0.7
	elif heading_home:
		var home := berth - global_position
		home.y = 0.0
		if home.length() > 0.4:
			global_position += home.normalized() * delta * 0.55
	else:
		hop_wait -= delta
		var grounded := global_position.y <= _stand_y() + 0.04 and vel.y <= 0.4
		if (
			not wants_sleep
			and mood != "dizzy"
			and mood != "panic"
			and feel != "recover"
			and grounded
			and hop_wait <= 0.0
		):
			vel.y = randf_range(2.1, 3.3)
			hop_wait = randf_range(0.7, 1.5)
			var flat := goal - global_position
			flat.y = 0.0
			if flat.length() > 0.25:
				var hop := flat.normalized() * randf_range(0.5, 1.15)
				if species_id == "grapling":
					hop *= 0.45
				vel.x = hop.x
				vel.z = hop.z
		if global_position.distance_to(Vector3(goal.x, global_position.y, goal.z)) < 0.45:
			_pick_goal()
	var airborne := (not held) and global_position.y > _stand_y() + 0.05
	var steps := 1 if reduce_motion else JellyFeel.substeps(held, airborne, vel.length())
	var dt := delta / float(steps)
	var landed := false
	for _i in steps:
		if held:
			vel = JellyFeel.hold_follow(global_position, hold_target, vel, dt, feel_spring, feel_damp)
		elif not leaving and not heading_home:
			vel = JellyFeel.fall(vel, dt)
		global_position += vel * dt
		if not held:
			var floor_y := _stand_y()
			var landed_step: Dictionary = JellyFeel.land(global_position, vel, floor_y, dt, feel_bounce)
			global_position = landed_step["pos"]
			vel = landed_step["vel"]
			if bool(landed_step["hit"]):
				if bool(landed_step["bounced"]):
					squash = float(landed_step["squash"])
					ripple = maxf(ripple, float(landed_step["ripple"]))
					feel = "bounce"
					landed = true
				elif vel.length() < JellyFeel.RECOVER_TIME + 0.9 and feel == "bounce":
					feel = "recover"
					recover_t = JellyFeel.RECOVER_TIME
				elif feel == "air":
					feel = "idle"
		if not held and (feel == "air" or feel == "bounce"):
			var water_ok := species_id == "bulrush" or species_id == "reedic"
			var bumped: Dictionary = JellyFeel.bounce_prop(global_position, vel, touch_radius(), water_ok, feel_bounce)
			global_position = bumped["pos"]
			vel = bumped["vel"]
			if bool(bumped["hit"]):
				ripple = maxf(ripple, 0.45)
		if bound:
			global_position = JellyFeel.clamp_pos(global_position, last_safe)
		elif not global_position.is_finite():
			global_position = last_safe
		vel = JellyFeel.clamp_vel(vel)
	if landed:
		reacted.emit("land", self)
	if not held and global_position.y <= _stand_y() + 0.03 and vel.length() < 1.4:
		last_safe = global_position
	var pull_len := global_position.distance_to(hold_target) if held else 0.0
	stretch = JellyFeel.stretch_amount(pull_len, vel.length(), held, feel_stretch)
	var spring_pull: Vector3 = (hold_target - global_position) if held else vel
	deform.advance(delta, held, spring_pull, landed, not reduce_motion)
	if held:
		var pets: Dictionary = JellyFeel.pet_hold(pet_time, stretch, delta)
		pet_time = float(pets["pet_time"])
		if bool(pets["cancel"]):
			nuzzled = false
		elif bool(pets["nuzzle"]) and not nuzzled:
			nuzzled = true
			bond = minf(1.0, bond + 0.08)
			mood = "happy"
			ripple = maxf(ripple, 0.4)
			reacted.emit("nuzzle", self)
	_apply_deform()
	if not reduce_motion:
		rotation.z = sin(Time.get_ticks_msec() * 0.004) * 0.07
	else:
		rotation.z = 0.0
	if mat:
		mat.set_shader_parameter("ripple", 0.0 if reduce_motion else ripple)
		if reduce_motion:
			mat.set_shader_parameter("wobble", 0.0)
	_update_face()
	if not held and not leaving:
		site_time += delta

func _young_fit() -> float:
	if not young:
		return 1.0
	return lerpf(0.55, 1.0, clampf(site_time / 8.0, 0.0, 1.0))

func _apply_deform() -> void:
	var fit := _young_fit()
	scale = Vector3(fit, fit, fit)
	if body_root == null:
		body_root = get_node_or_null("Body") as Node3D
	if body_root == null:
		return
	var feel_scale := JellyFeel.body_scale(squash * (0.9 if is_hungry() and not held else 1.0), stretch)
	if deform.stretch > 0.01 or deform.lag.length() > 0.001:
		body_root.position = deform.lag
		body_root.basis = deform.basis_for(deform.axis, deform.stretch).scaled(feel_scale)
	else:
		body_root.position = Vector3.ZERO
		body_root.scale = feel_scale
	if held and is_inside_tree():
		var pull := hold_target - global_position
		pull.y = 0.0
		if pull.length() > 0.08 and deform.stretch <= 0.08:
			var lean := clampf(pull.length() * 0.12, 0.0, 0.35)
			body_root.rotation.z = clampf(-pull.x * lean, -0.4, 0.4)
			body_root.rotation.x = clampf(pull.z * lean, -0.4, 0.4)
		elif deform.stretch <= 0.08:
			body_root.rotation.x = 0.0
			body_root.rotation.z = 0.0
	elif feel == "dizzy" or mood == "dizzy":
		body_root.rotation.z = sin(Time.get_ticks_msec() * 0.012) * 0.22
	elif deform.stretch <= 0.08:
		body_root.rotation.x = move_toward(body_root.rotation.x, 0.0, 0.08)
		body_root.rotation.z = move_toward(body_root.rotation.z, 0.0, 0.08)
	if halo:
		halo.position.y = 0.03
		halo.scale = Vector3.ONE
	_sync_presentation()
	_face_icon()

func _face_icon() -> void:
	if icon_root == null or not icon_root.visible or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	var level := at
	level.y = icon_root.global_position.y
	at = level.lerp(at, 0.42)
	if at.distance_squared_to(icon_root.global_position) < 0.04:
		return
	icon_root.look_at(at, Vector3.UP)

func _halo() -> void:
	halo = MeshInstance3D.new()
	halo.name = "Halo"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.018
	ring.outer_radius = radius * 1.15
	ring.rings = 12
	ring.ring_segments = 16
	halo.mesh = ring
	halo.rotation.x = PI * 0.5
	halo.position.y = 0.03
	halo_mat = StandardMaterial3D.new()
	halo_mat.albedo_color = Color(0.85, 0.98, 0.7, 0.7)
	halo_mat.emission_enabled = true
	halo_mat.emission = Color(0.55, 0.85, 0.4)
	halo_mat.emission_energy_multiplier = 0.28
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	halo_mat.no_depth_test = true
	halo_mat.render_priority = 1
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.visible = false
	add_child(halo)

func _note_sample(point: Vector3) -> void:
	sample_pos.append(point)
	sample_ms.append(Time.get_ticks_msec())
	while sample_pos.size() > 8:
		sample_pos.remove_at(0)
		sample_ms.remove_at(0)

func _coast(delta: float) -> void:
	# ponytail: one home point; a room schedule if the district grows past the kit.
	var target := berth if use_berth else goal
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() > 0.4:
		var pace := 0.32 if species_id == "grapling" else 0.7
		global_position += flat.normalized() * delta * pace
	var along := target - global_position
	along.y = 0.0
	if not use_berth and along.length() < 0.5:
		_pick_goal()
	global_position.y = _stand_y()
	stretch = 0.0
	deform.reset()
	squash = 1.0
	_apply_deform()
	site_time += delta

func _stand_y() -> float:
	# ponytail: sit on the bowl; a swim if the body should go under.
	if held or leaving or use_berth or wants_sleep:
		return 0.0
	if species_id != "bulrush" and species_id != "reedic":
		return 0.0
	if GardenLayout.pond_distance(global_position.x, global_position.z) > GardenLayout.POND_RADIUS * 0.92:
		return 0.0
	var rim := GardenLayout.POND_RADIUS
	var pond := get_tree().get_first_node_in_group("parish_pond") as Node3D
	if pond != null:
		rim = float(pond.get_meta("rim", rim))
	return GardenLayout.pond_surface(global_position.x, global_position.z, rim) + 0.05

func _pick_goal() -> void:
	if leaving:
		goal = GardenLayout.GATE
		return
	if mood == "panic":
		goal = global_position + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
	elif wants_sleep:
		goal = attract
	else:
		goal = attract + Vector3(randf_range(-1.3, 1.3), 0, randf_range(-1.3, 1.3))
	goal.x = clampf(goal.x, -12.0, 11.0)
	goal.z = clampf(goal.z, -8.5, 6.5)

func _clamp_inside() -> void:
	global_position.x = clampf(global_position.x, -12.6, 11.6)
	global_position.z = clampf(global_position.z, -9.2, 7.2)

func _update_face() -> void:
	if eye_l == null:
		return
	if poke_time > 0.0:
		eye_l.scale.y = 0.12
		if eye_r:
			eye_r.scale.y = 1.05
		if mouth:
			mouth.scale = Vector3(0.7, 0.72, 0.2)
		_tint_iris(false)
		return
	var shut := 1.0
	var grin := mood == "happy" or mood == "playful" or nuzzled
	var hungry_look := (
		is_hungry()
		and mood != "panic"
		and mood != "dizzy"
		and not nuzzled
		and not (held and stretch > 0.22)
	)
	if wants_sleep or mood == "sleepy":
		shut = 0.18
		grin = false
		hungry_look = false
	elif mood == "dizzy":
		shut = 0.35
		grin = false
	elif mood == "annoyed" or mood == "panic":
		shut = 0.55
		grin = false
		hungry_look = false
	elif held and stretch > 0.28:
		shut = 0.62
		grin = true
		hungry_look = false
	elif hungry_look:
		shut = 0.42
		grin = false
	eye_l.scale.y = shut
	eye_r.scale.y = shut
	if mouth:
		if hungry_look:
			mouth.scale = Vector3(0.52, 0.08, 0.2)
		else:
			mouth.scale = Vector3(0.7, 0.55 if grin else 0.22, 0.2)
	_tint_iris(hungry_look)

func _tint_iris(hungry_look: bool) -> void:
	var tint := iris_color.lerp(Color(1.0, 0.58, 0.22), 0.58) if hungry_look else iris_color
	for iris in iris_mats:
		iris.albedo_color = tint
		iris.emission = tint

func to_state() -> Dictionary:
	return {
		"species": species_id,
		"life": life,
		"bond": bond,
		"mood": mood,
		"site_time": site_time,
		"hunger": hunger,
		"bite_wait": bite_wait,
		"leaving": leaving,
		"young": young,
		"position": [global_position.x, global_position.y, global_position.z],
	}

class_name DistrictBadges
extends Node3D
## District art: a flag billboard with its policy icons over every painted bed group,
## and a HUD strip for the Y policy cycle that lights the policies the active group has.
## Every icon is optional. Missing art falls back to text labels.

const SYNC_SECONDS := 0.25
const FLAG_LIFT := 1.7
const ICON_PIXEL := 0.0042

var districts: GardenDistricts
## Returns true when the policy strip should show (district tool or districts overlay).
var show_strip: Callable
var flag_root: Node3D
var strip: PanelContainer
var _strip_name: Label
var _strip_icons: HBoxContainer
var _flags: Dictionary = {}
var _digest := ""
var _wait := 0.0


func bind(source: GardenDistricts, strip_when: Callable = Callable()) -> void:
	name = "DistrictBadges"
	districts = source
	show_strip = strip_when
	flag_root = Node3D.new()
	flag_root.name = "Flags"
	add_child(flag_root)
	_build_strip()
	sync()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = SYNC_SECONDS
		sync()


func sync() -> void:
	if districts == null:
		return
	_sync_flags()
	_sync_strip()


## Flag node for a district, or null when it has no painted cells.
func flag_for(district_id: String) -> Node3D:
	return _flags.get(district_id) as Node3D


## Policy id -> TextureRect or Label in the HUD strip, in cycle order.
func strip_items() -> Dictionary:
	var out := {}
	if _strip_icons == null:
		return out
	for child in _strip_icons.get_children():
		out[str(child.get_meta("policy", ""))] = child
	return out


static func policy_icon(policy_id: String) -> Texture2D:
	return ArtKit.icon("policies", policy_id)


static func flag_icon() -> Texture2D:
	return ArtKit.icon("channels", "districts")


func _sync_flags() -> void:
	var live := {}
	for district_id in districts.ids():
		if districts.cell_count(district_id) <= 0:
			continue
		live[district_id] = true
		var policies := districts.policies_of(district_id)
		var key := "%s|%s|%s|%s" % [district_id, districts.name_of(district_id), ",".join(policies), str(districts.centroid(district_id))]
		var node: Node3D = _flags.get(district_id) as Node3D
		if node != null and str(node.get_meta("digest", "")) == key:
			continue
		if node != null:
			node.queue_free()
		node = _make_flag(district_id, policies)
		node.set_meta("digest", key)
		flag_root.add_child(node)
		_flags[district_id] = node
	for id_v in _flags.keys():
		if live.has(id_v):
			continue
		var stale: Node3D = _flags[id_v] as Node3D
		if stale != null:
			stale.queue_free()
		_flags.erase(id_v)


func _make_flag(district_id: String, policies: PackedStringArray) -> Node3D:
	var root := Node3D.new()
	root.name = "Flag_" + district_id
	var at := districts.centroid(district_id)
	root.position = Vector3(at.x, GardenLayout.height_at(at.x, at.z) + FLAG_LIFT, at.z)
	var flag := flag_icon()
	if flag != null:
		root.add_child(_billboard(flag, "Flag", Vector3.ZERO, ICON_PIXEL))
	var label := Label3D.new()
	label.name = "Name"
	label.text = districts.name_of(district_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.font_size = 40
	label.outline_size = 10
	label.modulate = ThemeKit.CREAM
	label.outline_modulate = ThemeKit.INK
	label.position = Vector3(0, -0.42, 0)
	label.no_depth_test = true
	root.add_child(label)
	var missing := PackedStringArray()
	var count := policies.size()
	for i in count:
		var policy_id := policies[i]
		var tex := policy_icon(policy_id)
		if tex == null:
			missing.append(districts.policy_name(policy_id))
			continue
		var x := (float(i) - float(count - 1) * 0.5) * 0.36
		var icon := _billboard(tex, "Policy_" + policy_id, Vector3(x, -0.72, 0), ICON_PIXEL * 0.6)
		icon.set_meta("policy", policy_id)
		root.add_child(icon)
	if not missing.is_empty():
		label.text += "\n" + ", ".join(missing)
	return root


func _billboard(tex: Texture2D, node_name: String, at: Vector3, pixel: float) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = node_name
	sprite.texture = tex
	sprite.pixel_size = pixel
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.position = at
	return sprite


func _build_strip() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PolicyHud"
	layer.layer = 11
	add_child(layer)
	strip = PanelContainer.new()
	strip.name = "PolicyStrip"
	strip.theme = ThemeKit.make_theme()
	strip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	strip.offset_left = 16
	strip.offset_top = 392
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.visible = false
	strip.add_theme_stylebox_override("panel", ThemeKit.panel())
	layer.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	strip.add_child(row)
	var flag := flag_icon()
	if flag != null:
		var badge := TextureRect.new()
		badge.texture = flag
		badge.custom_minimum_size = Vector2(36, 36)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(badge)
	_strip_name = Label.new()
	_strip_name.add_theme_color_override("font_color", ThemeKit.INK)
	row.add_child(_strip_name)
	_strip_icons = HBoxContainer.new()
	_strip_icons.add_theme_constant_override("separation", 6)
	row.add_child(_strip_icons)
	for policy_id in districts.policy_order():
		var tex := policy_icon(policy_id)
		var item: Control
		if tex != null:
			var rect := TextureRect.new()
			rect.texture = tex
			rect.custom_minimum_size = Vector2(36, 36)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item = rect
		else:
			var text := Label.new()
			text.text = districts.policy_name(policy_id)
			text.add_theme_color_override("font_color", ThemeKit.INK)
			item = text
		item.name = "Policy_" + policy_id
		item.tooltip_text = districts.policy_name(policy_id)
		item.set_meta("policy", policy_id)
		_strip_icons.add_child(item)


func _sync_strip() -> void:
	if strip == null:
		return
	var active := districts.active_id
	var want := active != "" and districts.cell_count(active) > 0
	if want and show_strip.is_valid():
		want = bool(show_strip.call())
	strip.visible = want
	if not want:
		return
	var on := districts.policies_of(active)
	var next := districts.next_policy()
	_strip_name.text = "%s  ·  Y: %s" % [districts.name_of(active), districts.policy_name(next)]
	for child in _strip_icons.get_children():
		var item := child as Control
		var policy_id := str(item.get_meta("policy", ""))
		var lit := on.has(policy_id)
		item.modulate = Color(1, 1, 1, 1.0 if lit else 0.32)
		item.set_meta("on", lit)

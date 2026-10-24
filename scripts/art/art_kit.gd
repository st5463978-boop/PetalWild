class_name ArtKit
extends RefCounted
## Data-driven lookup for the VC art (data/art_manifest.json).
## Every getter returns null / {} when an entry or file is missing, so callers keep
## their procedural placeholder. Set PETAL_PLACEHOLDER_ART=1 to force the placeholders.

const MANIFEST := "res://data/art_manifest.json"

static var _manifest: Dictionary = {}
static var _loaded := false
static var _textures: Dictionary = {}
static var _scenes: Dictionary = {}
static var _lumas: Dictionary = {}


static func enabled() -> bool:
	_ensure()
	if OS.get_environment("PETAL_PLACEHOLDER_ART") == "1":
		return false
	return bool(_manifest.get("enabled", false))


static func manifest() -> Dictionary:
	_ensure()
	return _manifest


static func section(name: String) -> Dictionary:
	_ensure()
	var found: Variant = _manifest.get(name, {})
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return found


static func entry(section_name: String, id: String) -> Dictionary:
	var found: Variant = section(section_name).get(id, {})
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return found


static func list(name: String) -> Array:
	_ensure()
	var found: Variant = _manifest.get(name, [])
	if typeof(found) != TYPE_ARRAY:
		return []
	return found


## Texture by explicit res:// path, or null when art is off or the file is missing.
static func texture_at(path: String) -> Texture2D:
	if not enabled() or path == "":
		return null
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_textures[path] = tex
	return tex


## Texture from a flat section such as "hud", "ground" or "beds".
static func texture(section_name: String, id: String) -> Texture2D:
	return texture_at(str(section(section_name).get(id, "")))


## HUD icon looked up through an alias table ("bars", "channels", "policies").
static func icon(alias_section: String, id: String) -> Texture2D:
	var key := str(section(alias_section).get(id, ""))
	if key == "":
		return null
	var tex := texture("hud", key)
	if tex == null:
		tex = texture("districts", key)
	return tex


## Overlay legend art for a channel: tier is "low", "mid", "high" or "legend".
## Channel ids map through "overlay_channels" when the names differ (blight -> moth).
static func overlay(channel_id: String, tier: String) -> Texture2D:
	if channel_id == "":
		return null
	var key := str(section("overlay_channels").get(channel_id, channel_id))
	return texture_at(str(entry("overlays", key).get(tier, "")))


## Legend strip cropped to its painted band (rows 23-41 of the 64 px source).
static func legend_strip(channel_id: String) -> Texture2D:
	var tex := overlay(channel_id, "legend")
	if tex == null:
		return null
	var size := tex.get_size()
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0.0, size.y * 0.36, size.x, size.y * 0.3)
	return atlas


static func sprite(section_name: String, id: String, key: String = "sprite") -> Texture2D:
	return texture_at(str(entry(section_name, id).get(key, "")))


## Instanced mesh for a species or service, scaled to the manifest height with its base on y=0.
## Returns null when there is no entry or the file cannot be loaded.
static func mesh_node(section_name: String, id: String) -> Node3D:
	if not enabled():
		return null
	var row := entry(section_name, id)
	var path := str(row.get("mesh", ""))
	if path == "":
		return null
	var packed: PackedScene = null
	if _scenes.has(path):
		packed = _scenes[path]
	else:
		if ResourceLoader.exists(path):
			packed = load(path) as PackedScene
		_scenes[path] = packed
	if packed == null:
		return null
	var holder := Node3D.new()
	holder.name = "Art_%s" % id
	var body := packed.instantiate() as Node3D
	if body == null:
		return null
	# meshes are baked to unit height, centred on x/z, base on y=0
	var height := float(row.get("height", 1.0))
	body.scale = Vector3.ONE * height
	body.rotation.y = deg_to_rad(float(row.get("yaw_deg", 0.0)))
	holder.add_child(body)
	return holder


## Average brightness of a texture (cached); used to keep tinted materials at their old value.
static func mean_luma(tex: Texture2D) -> float:
	if tex == null:
		return 1.0
	var key := tex.resource_path
	if _lumas.has(key):
		return _lumas[key]
	var image := tex.get_image()
	var luma := 0.5
	if image != null and not image.is_empty():
		image = image.duplicate()
		if image.is_compressed():
			image.decompress()
		image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		var c := image.get_pixel(0, 0)
		luma = maxf(0.08, c.r * 0.299 + c.g * 0.587 + c.b * 0.114)
	_lumas[key] = luma
	return luma


## Puts a ground or bed texture on a StandardMaterial3D and lifts the tint so the
## average colour matches the placeholder. Leaves the material alone if there is no art.
static func dress_material(material: StandardMaterial3D, tex: Texture2D, tint: Color, uv_scale: float = 1.0) -> void:
	if material == null:
		return
	if tex == null:
		material.albedo_texture = null
		material.albedo_color = tint
		return
	material.albedo_texture = tex
	material.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	var gain := 1.0 / mean_luma(tex)
	material.albedo_color = Color(minf(tint.r * gain, 1.0), minf(tint.g * gain, 1.0), minf(tint.b * gain, 1.0), tint.a)


## Soil lid texture for a plot, from the "soil_patches" block.
static func soil_texture(tilled: bool, moisture: float, chem: String = "") -> Texture2D:
	var rule := section("soil_patches")
	if rule.is_empty():
		return null
	var key := "grass"
	if chem == "nightloam":
		key = "nightloam"
	elif tilled and moisture >= float(rule.get("wet_above", 0.62)):
		key = "wet"
	elif tilled:
		key = "tilled"
	var name := str(rule.get(key, ""))
	var tex := texture("beds", name)
	if tex == null:
		tex = texture("ground", name)
	return tex


## Hooks the terrain shader's optional detail maps. No-op without art.
static func dress_terrain(material: ShaderMaterial) -> void:
	if material == null:
		return
	var rule := section("terrain")
	var grass := texture("ground", str(rule.get("grass", "")))
	if grass == null:
		return
	material.set_shader_parameter("detail_tex", grass)
	material.set_shader_parameter("detail_avg", mean_luma(grass))
	var soil := texture("ground", str(rule.get("soil", "")))
	if soil != null:
		material.set_shader_parameter("soil_tex", soil)
		material.set_shader_parameter("soil_avg", mean_luma(soil))
	material.set_shader_parameter("detail_scale", float(rule.get("scale", 0.3)))
	material.set_shader_parameter("detail_mix", float(rule.get("mix", 0.5)))


static func reload() -> void:
	_loaded = false
	_textures.clear()
	_scenes.clear()
	_lumas.clear()
	_ensure()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_manifest = {}
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(parsed) == TYPE_DICTIONARY:
		_manifest = parsed
	else:
		push_warning("art manifest is not an object; using placeholders")

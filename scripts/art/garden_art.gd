class_name GardenArt
extends Node3D
## Places VC art in the live garden: a few dressing props, a mesh for every stamped
## service, and billboard blight-moths over the cells the blight logic marks.
## Does nothing visible when the manifest is off or the files are missing.

const SYNC_SECONDS := 0.5

var services: ServiceField
## Anything with a `moths` array of {ix, iz} dicts (the live game passes ecology.blight).
var pests: Object
var dressing_root: Node3D
var service_root: Node3D
var moth_root: Node3D
var placed: Array[String] = []
var skipped: Array[String] = []
var _service_nodes: Dictionary = {}
var _moth_nodes: Dictionary = {}
var _wait := 0.0
var _time := 0.0


func bind(service_field: ServiceField, moth_source: Object) -> void:
	name = "GardenArt"
	services = service_field
	pests = moth_source
	dressing_root = _group("Dressing")
	service_root = _group("Services")
	moth_root = _group("Moths")
	if not ArtKit.enabled():
		return
	_place_dressing()
	sync()


func _process(delta: float) -> void:
	_time += delta
	_wait -= delta
	if _wait <= 0.0:
		_wait = SYNC_SECONDS
		sync()
	_flutter()


func sync() -> void:
	if not ArtKit.enabled():
		return
	_sync_services()
	_sync_moths()


## Keeps a dressing prop only on open lawn: off the path, out of the beds and the pond.
static func spot_is_clear(at: Vector3, footprint: float) -> bool:
	if GardenLayout.on_path(at.x, at.z):
		return false
	if GardenLayout.in_plots(at.x, at.z, footprint):
		return false
	if GardenLayout.pond_distance(at.x, at.z) < GardenLayout.POND_RADIUS + footprint:
		return false
	return true


func _place_dressing() -> void:
	for row_v in ArtKit.list("service_dressing"):
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_v
		var id := str(row.get("service", ""))
		var at := _vec(row.get("at", []))
		if not spot_is_clear(at, 0.35):
			skipped.append(id)
			continue
		var node := ArtKit.mesh_node("services", id)
		if node == null:
			skipped.append(id)
			continue
		node.position = Vector3(at.x, GardenLayout.height_at(at.x, at.z), at.z)
		node.rotation.y = deg_to_rad(float(row.get("yaw_deg", 0.0)))
		dressing_root.add_child(node)
		placed.append(id)


func _sync_services() -> void:
	if services == null:
		return
	var rule := ArtKit.section("stamped_services")
	var shrink := float(rule.get("scale", 0.8))
	for key_v in _service_nodes.keys():
		if not services.stamps.has(key_v):
			var gone: Node3D = _service_nodes[key_v]
			_service_nodes.erase(key_v)
			gone.queue_free()
	for key_v in services.stamps.keys():
		var key := str(key_v)
		var stamp: Dictionary = services.stamps[key_v]
		var center := GardenLayout.cell_center(int(stamp.get("x", 0)), int(stamp.get("z", 0)))
		var node: Node3D = _service_nodes.get(key)
		if node == null:
			node = ArtKit.mesh_node("services", base_id(key))
			if node == null:
				continue
			node.scale = Vector3.ONE * shrink
			service_root.add_child(node)
			_service_nodes[key] = node
		node.position = Vector3(center.x, GardenLayout.height_at(center.x, center.z) + float(rule.get("lift", 0.0)), center.z)


func _sync_moths() -> void:
	if pests == null:
		return
	var moths: Variant = pests.get("moths")
	if typeof(moths) != TYPE_ARRAY:
		return
	var rule := ArtKit.entry("pests", "blightmoth")
	var live: Dictionary = {}
	for moth_v in moths:
		if typeof(moth_v) != TYPE_DICTIONARY:
			continue
		var moth: Dictionary = moth_v
		var key := "%d,%d" % [int(moth.get("ix", 0)), int(moth.get("iz", 0))]
		live[key] = true
		if _moth_nodes.has(key):
			continue
		var tex := ArtKit.texture_at(str(rule.get("fly", rule.get("idle", ""))))
		if tex == null:
			return
		var sprite := Sprite3D.new()
		sprite.texture = tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.pixel_size = float(rule.get("size", 0.42)) / float(maxi(tex.get_width(), 1))
		var center := GardenLayout.cell_center(int(moth.get("ix", 0)), int(moth.get("iz", 0)))
		sprite.position = Vector3(center.x, float(rule.get("hover", 0.55)), center.z)
		sprite.set_meta("base_y", sprite.position.y)
		sprite.set_meta("phase", float(_moth_nodes.size()) * 1.7)
		moth_root.add_child(sprite)
		_moth_nodes[key] = sprite
	for key_v in _moth_nodes.keys():
		if not live.has(key_v):
			var gone: Node3D = _moth_nodes[key_v]
			_moth_nodes.erase(key_v)
			gone.queue_free()


func _flutter() -> void:
	for node_v in _moth_nodes.values():
		var sprite: Sprite3D = node_v
		var phase := float(sprite.get_meta("phase", 0.0))
		sprite.position.y = float(sprite.get_meta("base_y", 0.55)) + sin(_time * 3.1 + phase) * 0.06


func service_count() -> int:
	return _service_nodes.size()


func moth_count() -> int:
	return _moth_nodes.size()


static func base_id(service_id: String) -> String:
	var cut := service_id.find("#")
	if cut == -1:
		return service_id
	return service_id.substr(0, cut)


func _group(label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	add_child(node)
	return node


func _vec(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY:
		return Vector3.ZERO
	var items: Array = value
	if items.size() < 3:
		return Vector3.ZERO
	return Vector3(float(items[0]), float(items[1]), float(items[2]))

extends Node3D

@export var structures: Array[Structure] = []

var map:DataMap

var index:int = 0 # Index of structure being built

@export var selector:Node3D # The 'cursor'
@export var selector_container:Node3D # Node that holds a preview of the structure
@export var view_camera:Camera3D # Used for raycasting mouse
@export var gridmap:GridMap
@export var cash_display:Label

var plane:Plane # Used for raycasting mouse
var sfx: Node

func _ready():
	
	map = DataMap.new()
	plane = Plane(Vector3.UP, Vector3.ZERO)
	sfx = load("res://third_party/kenney_city_builder/scripts/audio.gd").new()
	add_child(sfx)
	
	# Create new MeshLibrary dynamically, can also be done in the editor
	# See: https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html
	
	var mesh_library = MeshLibrary.new()
	
	for structure in structures:
		
		var id = mesh_library.get_last_unused_item_id()
		
		mesh_library.create_item(id)
		var item_mesh := get_mesh(structure.model)
		if item_mesh == null:
			var box := BoxMesh.new()
			box.size = Vector3(0.9, 0.2, 0.9)
			item_mesh = box
		mesh_library.set_item_mesh(id, item_mesh)
		var piece_scale := structure.mesh_scale
		var basis := Basis.IDENTITY.scaled(Vector3(piece_scale, piece_scale, piece_scale))
		mesh_library.set_item_mesh_transform(id, Transform3D(basis, Vector3.ZERO))
		
	gridmap.mesh_library = mesh_library
	
	update_structure()
	update_cash()
	_load_sample()

func _process(delta):
	
	# Controls
	
	action_rotate() # Rotates selection 90 degrees
	action_structure_toggle() # Toggles between structures
	
	action_save() # Saving
	action_load() # Loading
	action_load_resources() # Loading from resources
	
	# Map position based on mouse
	
	var world_position = plane.intersects_ray(
		view_camera.project_ray_origin(get_viewport().get_mouse_position()),
		view_camera.project_ray_normal(get_viewport().get_mouse_position()))

	var gridmap_position = Vector3(round(world_position.x), 0, round(world_position.z))
	selector.position = lerp(selector.position, gridmap_position, min(delta * 40, 1.0))
	
	action_build(gridmap_position)
	action_demolish(gridmap_position)

# Retrieve the mesh from a PackedScene, used for dynamically creating a MeshLibrary

func get_mesh(packed_scene: PackedScene) -> Mesh:
	if packed_scene == null:
		return null
	var scene_state: SceneState = packed_scene.get_state()
	for i in range(scene_state.get_node_count()):
		if scene_state.get_node_type(i) == "MeshInstance3D":
			for j in scene_state.get_node_property_count(i):
				if scene_state.get_node_property_name(i, j) == "mesh":
					var prop_value: Variant = scene_state.get_node_property_value(i, j)
					if prop_value is Mesh:
						return (prop_value as Mesh).duplicate()
	var inst := packed_scene.instantiate()
	var found := _first_mesh(inst)
	var mesh: Mesh = null
	if found != null and found.mesh != null:
		mesh = found.mesh.duplicate()
	inst.free()
	return mesh

func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var hit := _first_mesh(child)
		if hit != null:
			return hit
	return null

# Build (place) a structure

func action_build(gridmap_position):
	if Input.is_action_just_pressed("build"):
		
		var previous_tile = gridmap.get_cell_item(gridmap_position)
		gridmap.set_cell_item(gridmap_position, index, gridmap.get_orthogonal_index_from_basis(selector.basis))
		
		if previous_tile != index:
			map.cash -= structures[index].price
			update_cash()
			
			sfx.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)

# Demolish (remove) a structure

func action_demolish(gridmap_position):
	if Input.is_action_just_pressed("demolish"):
		if gridmap.get_cell_item(gridmap_position) != -1:
			gridmap.set_cell_item(gridmap_position, -1)
			
			sfx.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)

# Rotates the 'cursor' 90 degrees

func action_rotate():
	if Input.is_action_just_pressed("rotate"):
		selector.rotate_y(deg_to_rad(90))
		
		sfx.play("sounds/rotate.ogg", -30)

# Toggle between structures to build

func action_structure_toggle():
	if Input.is_action_just_pressed("structure_next"):
		index = wrap(index + 1, 0, structures.size())
		sfx.play("sounds/toggle.ogg", -30)
	
	if Input.is_action_just_pressed("structure_previous"):
		index = wrap(index - 1, 0, structures.size())
		sfx.play("sounds/toggle.ogg", -30)

	update_structure()

# Update the structure visual in the 'cursor'

func update_structure():
	# Clear previous structure preview in selector
	for n in selector_container.get_children():
		selector_container.remove_child(n)
		n.queue_free()
		
	# Create new structure preview in selector
	var _model = structures[index].model.instantiate()
	selector_container.add_child(_model)
	_model.scale = Vector3.ONE * structures[index].mesh_scale
	_model.position.y += 0.25
	
func update_cash():
	cash_display.text = "$" + str(map.cash)

# Saving/load

func action_save():
	if Input.is_action_just_pressed("save"):
		print("Saving map...")
		
		map.structures.clear()
		for cell in gridmap.get_used_cells():
			
			var data_structure:DataStructure = DataStructure.new()
			
			data_structure.position = Vector2i(cell.x, cell.z)
			data_structure.orientation = gridmap.get_cell_item_orientation(cell)
			data_structure.structure = gridmap.get_cell_item(cell)
			
			map.structures.append(data_structure)
			
		ResourceSaver.save(map, "user://map.res")
	
func action_load():
	if Input.is_action_just_pressed("load"):
		print("Loading map...")
		
		gridmap.clear()
		
		map = ResourceLoader.load("user://map.res")
		if not map:
			map = DataMap.new()
		for cell in map.structures:
			gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)
			
		update_cash()

func action_load_resources():
	if Input.is_action_just_pressed("load_resources"):
		print("Loading map...")
		_load_sample()

# ponytail: JSON copy of the sample town. map.res stores the upstream res://scripts paths.
func _load_sample() -> void:
	var path := "res://third_party/kenney_city_builder/sample_map.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	gridmap.clear()
	map.cash = int(data.get("cash", map.cash))
	for cell in data.get("cells", []):
		gridmap.set_cell_item(Vector3i(int(cell["x"]), 0, int(cell["z"])), int(cell["s"]), int(cell["o"]))
	update_cash()

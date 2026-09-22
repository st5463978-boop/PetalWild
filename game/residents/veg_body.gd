extends Node3D

var person_id := ""
var family := "carrot"
var walking := false
var clock := 0.0
var left_leg: Node3D
var right_leg: Node3D
var speech: Label3D
var body: Node3D


func setup(spec: Dictionary) -> void:
	person_id = str(spec.get("id", ""))
	family = str(spec.get("family", "carrot"))
	body = Node3D.new()
	add_child(body)
	match family:
		"strawberry":
			_strawberry()
		"leek":
			_leek()
		_:
			_carrot()
	_limbs()
	var name_label := Label3D.new()
	name_label.text = str(spec.get("name", ""))
	name_label.font_size = 32
	name_label.position = Vector3(0, 1.55, 0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.modulate = Color(0.98, 0.95, 0.88)
	name_label.outline_size = 6
	add_child(name_label)
	speech = Label3D.new()
	speech.font_size = 26
	speech.position = Vector3(0, 1.9, 0)
	speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	speech.modulate = Color(1.0, 0.96, 0.86)
	speech.visible = false
	speech.width = 280.0
	add_child(speech)


func set_line(text: String) -> void:
	speech.text = text
	speech.visible = text != ""


func animate(delta: float) -> void:
	clock += delta
	var bob := sin(clock * (7.0 if walking else 2.0)) * (0.04 if walking else 0.015)
	body.position.y = bob
	if left_leg and walking:
		left_leg.rotation.x = sin(clock * 7.0) * 0.5
		right_leg.rotation.x = sin(clock * 7.0 + PI) * 0.5
	elif left_leg:
		left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, 0.15)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, 0.15)


func _carrot() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
	cone.bottom_radius = 0.22
	cone.height = 0.85
	_part(cone, Vector3(0, 0.62, 0), Color(0.92, 0.48, 0.16))
	_leaf(Vector3(-0.08, 1.12, 0), 0.4)
	_leaf(Vector3(0.1, 1.16, 0.02), -0.3)
	_scarf()


func _strawberry() -> void:
	var berry := SphereMesh.new()
	berry.radius = 0.28
	berry.height = 0.62
	_part(berry, Vector3(0, 0.62, 0), Color(0.86, 0.22, 0.32))
	for i in 8:
		var angle := float(i) / 8.0 * TAU
		var seed := SphereMesh.new()
		seed.radius = 0.025
		seed.height = 0.05
		_part(seed, Vector3(cos(angle) * 0.18, 0.55 + float(i % 3) * 0.08, sin(angle) * 0.16), Color(0.95, 0.82, 0.45))
	_leaf(Vector3(0, 1.0, 0), 0.2)
	_leaf(Vector3(0.12, 0.98, 0), -0.5)
	var apron := BoxMesh.new()
	apron.size = Vector3(0.32, 0.28, 0.08)
	_part(apron, Vector3(0, 0.48, 0.2), Color(0.93, 0.9, 0.82))


func _leek() -> void:
	for i in 4:
		var layer := CylinderMesh.new()
		layer.top_radius = 0.12 + float(i) * 0.015
		layer.bottom_radius = 0.13
		layer.height = 0.22
		var tint := Color(0.93, 0.92, 0.84).lerp(Color(0.35, 0.62, 0.28), float(i) / 3.0)
		_part(layer, Vector3(0, 0.35 + float(i) * 0.2, 0), tint)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.1
	ring.outer_radius = 0.14
	_part(ring, Vector3(0, 0.78, 0.08), Color(0.25, 0.32, 0.22))


func _limbs() -> void:
	var arm := CylinderMesh.new()
	arm.top_radius = 0.035
	arm.bottom_radius = 0.04
	arm.height = 0.28
	_part(arm, Vector3(-0.24, 0.62, 0), Color(0.93, 0.78, 0.62))
	_part(arm, Vector3(0.24, 0.62, 0), Color(0.93, 0.78, 0.62))
	var leg := CylinderMesh.new()
	leg.top_radius = 0.045
	leg.bottom_radius = 0.05
	leg.height = 0.22
	left_leg = _hinge(leg, Vector3(-0.08, 0.22, 0), Color(0.28, 0.2, 0.14))
	right_leg = _hinge(leg, Vector3(0.08, 0.22, 0), Color(0.28, 0.2, 0.14))
	var boot := SphereMesh.new()
	boot.radius = 0.06
	boot.height = 0.1
	_part(boot, Vector3(-0.08, 0.08, 0.03), Color(0.22, 0.16, 0.12))
	_part(boot, Vector3(0.08, 0.08, 0.03), Color(0.22, 0.16, 0.12))
	_eyes()


func _eyes() -> void:
	for side in [-1.0, 1.0]:
		var white := SphereMesh.new()
		white.radius = 0.045
		white.height = 0.09
		_part(white, Vector3(0.07 * side, 0.78, 0.2), Color(0.97, 0.95, 0.9))
		var iris := SphereMesh.new()
		iris.radius = 0.025
		iris.height = 0.05
		var iris_color := Color(0.25, 0.45, 0.28) if family == "leek" else Color(0.35, 0.2, 0.12)
		_part(iris, Vector3(0.075 * side, 0.77, 0.24), iris_color)
		var pupil := SphereMesh.new()
		pupil.radius = 0.012
		pupil.height = 0.024
		_part(pupil, Vector3(0.08 * side, 0.76, 0.26), Color(0.08, 0.06, 0.05))
	var smile := SphereMesh.new()
	smile.radius = 0.03
	smile.height = 0.05
	var mouth := _part(smile, Vector3(0, 0.68, 0.24), Color(0.55, 0.18, 0.2))
	mouth.scale = Vector3(1.8, 0.4, 0.4)


func _scarf() -> void:
	var scarf := BoxMesh.new()
	scarf.size = Vector3(0.26, 0.08, 0.12)
	_part(scarf, Vector3(0.02, 0.95, 0.08), Color(0.2, 0.38, 0.62))


func _leaf(pos: Vector3, yaw: float) -> void:
	var leaf := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.08
	leaf.mesh = mesh
	leaf.position = pos
	leaf.rotation.z = yaw
	leaf.scale = Vector3(1.4, 0.45, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.62, 0.22)
	mat.roughness = 0.6
	leaf.material_override = mat
	body.add_child(leaf)


func _hinge(mesh: Mesh, pos: Vector3, color: Color) -> Node3D:
	var hinge := Node3D.new()
	hinge.position = pos
	body.add_child(hinge)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = Vector3(0, -0.1, 0)
	part.material_override = _mat(color)
	hinge.add_child(part)
	return hinge


func _part(mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = _mat(color)
	body.add_child(node)
	return node


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.62
	return mat

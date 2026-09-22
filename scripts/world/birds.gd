class_name GardenBirds
extends Node3D

var bodies: Array[Node3D] = []
var left_wings: Array[MeshInstance3D] = []
var right_wings: Array[MeshInstance3D] = []
var perches: Array[Vector3] = []
var phase := 0.0

func build() -> void:
	perches = [
		Vector3(-4.4, 1.05, 5.05),
		Vector3(-11.0, 2.15, 3.5),
		Vector3(-1.4, 0.72, 3.55),
		Vector3(-5.4, 0.9, 4.35),
	]
	for i in perches.size():
		var bird := Node3D.new()
		add_child(bird)
		_body(bird)
		bird.position = perches[i]
		bodies.append(bird)

func tick(delta: float, frozen: bool, hour: float, weather: String) -> void:
	if not frozen:
		phase += delta
	var roost := hour >= 19.5 or weather == "rain"
	for i in bodies.size():
		if roost:
			bodies[i].position = perches[i]
			bodies[i].rotation = Vector3(0.15, 0.4 + float(i), 0.0)
			_flap(i, 0.2)
		else:
			var t := float(i) * TAU / float(bodies.size())
			if not frozen:
				t += phase * 0.35
			var at := Vector3(-2.2 + cos(t) * 5.2, 2.2 + sin(t * 2.0) * 0.2, -0.4 + sin(t) * 3.2)
			bodies[i].position = at
			bodies[i].rotation = Vector3(0.0, -t + PI * 0.5, sin(t) * 0.15)
			var flap := 0.35
			if not frozen:
				flap = sin(phase * 9.0 + float(i)) * 0.55
			_flap(i, flap)

func _flap(i: int, angle: float) -> void:
	left_wings[i].rotation.z = angle
	right_wings[i].rotation.z = -angle

func _body(bird: Node3D) -> void:
	var body_mat := _mat(Color("#6b3a28"), 0.82)
	var wing_mat := _mat(Color("#3d2818"), 0.88)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.32
	var torso := MeshInstance3D.new()
	torso.mesh = mesh
	torso.rotation_degrees = Vector3(0, 0, 90)
	torso.material_override = body_mat
	bird.add_child(torso)
	var beak := MeshInstance3D.new()
	var beak_mesh := BoxMesh.new()
	beak_mesh.size = Vector3(0.1, 0.03, 0.03)
	beak.mesh = beak_mesh
	beak.position = Vector3(0.18, 0.02, 0)
	beak.material_override = _mat(Color("#8a6238"), 0.7)
	bird.add_child(beak)
	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.12, 0.02, 0.08)
	tail.mesh = tail_mesh
	tail.position = Vector3(-0.16, 0.03, 0)
	tail.material_override = wing_mat
	bird.add_child(tail)
	left_wings.append(_wing(bird, 1.0, wing_mat))
	right_wings.append(_wing(bird, -1.0, wing_mat))

func _wing(bird: Node3D, side: float, material: Material) -> MeshInstance3D:
	var wing := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.02, 0.34)
	wing.mesh = box
	wing.position = Vector3(0.0, 0.05, 0.16 * side)
	wing.material_override = material
	bird.add_child(wing)
	return wing

func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# ponytail: rust and umber stay under this sun; raise if the birds go dull.
	material.albedo_color = color
	material.roughness = rough
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material

class_name GardenBees
extends Node3D

var bodies: Array[Node3D] = []
var homes: Array[Vector3] = []
var phase := 0.0

func build() -> void:
	var spots: Array[Vector3] = [
		Vector3(-6.4, 0.62, -3.6),
		Vector3(-4.6, 0.7, -2.8),
		Vector3(-1.6, 0.58, -4.4),
		Vector3(1.8, 0.66, -2.6),
		Vector3(4.2, 0.72, -0.8),
		Vector3(-5.2, 0.8, 1.4),
		Vector3(6.2, 0.64, 0.8),
		Vector3(-0.6, 0.6, 2.2),
	]
	for spot in spots:
		var bee := Node3D.new()
		add_child(bee)
		_body(bee)
		bee.position = spot
		bodies.append(bee)
		homes.append(spot)

func tick(delta: float, frozen: bool) -> void:
	if frozen:
		return
	phase += delta
	for i in bodies.size():
		var t := phase * 0.65 + float(i) * 1.7
		bodies[i].position = homes[i] + Vector3(sin(t) * 0.42, sin(t * 2.2) * 0.05, cos(t * 0.8) * 0.3)
		bodies[i].rotation.y = t

func _body(bee: Node3D) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.34
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.rotation_degrees = Vector3(0, 0, 90)
	var material := StandardMaterial3D.new()
	# ponytail: dark bodies so the bees stay under the sun; raise if they vanish.
	material.albedo_color = Color("#5a3a18")
	material.roughness = 0.84
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	node.material_override = material
	bee.add_child(node)
	var head := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.07
	ball.height = 0.14
	ball.radial_segments = 8
	ball.rings = 4
	head.mesh = ball
	head.position = Vector3(0.16, 0.02, 0)
	head.material_override = material
	bee.add_child(head)
	var band := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.1, 0.12)
	band.mesh = box
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#1c140c")
	dark.roughness = 0.9
	dark.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	band.material_override = dark
	bee.add_child(band)

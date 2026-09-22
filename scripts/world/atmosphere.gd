class_name Atmosphere
extends Node

var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var fill: DirectionalLight3D
var rain: CPUParticles3D
var sky_material: ProceduralSkyMaterial
var shafts: Array[MeshInstance3D] = []
var photosensitivity := false

func _build_shafts() -> void:
	for i in 7:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.55, 0.55, 16.0)
		var beam := MeshInstance3D.new()
		beam.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(1.0, 0.84, 0.52, 0.06)
		beam.material_override = material
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(-6.0 + float(i) * 2.0, float(i % 2) * 0.8 - 0.4, -9.0)
		beam.visible = false
		sun.add_child(beam)
		shafts.append(beam)

func build(parent: Node3D) -> void:
	world_environment = WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.82
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.ssao_enabled = true
	environment.ssao_radius = 1.15
	environment.ssao_intensity = 1.25
	environment.glow_enabled = true
	environment.glow_intensity = 0.32
	environment.glow_bloom = 0.08
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = 0.0045
	environment.fog_light_color = Color("f3d7b4")
	environment.fog_aerial_perspective = 0.45
	environment.fog_sky_affect = 0.35
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.12
	environment.adjustment_contrast = 1.04
	world_environment.environment = environment
	parent.add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_bias = 0.06
	parent.add_child(sun)
	_build_shafts()

	moon = DirectionalLight3D.new()
	moon.shadow_enabled = false
	parent.add_child(moon)

	fill = DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.light_color = Color("9eb8e6")
	parent.add_child(fill)

	rain = CPUParticles3D.new()
	rain.amount = 700
	rain.lifetime = 0.85
	rain.preprocess = 0.8
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(14, 0.4, 14)
	rain.direction = Vector3(0.15, -1, 0.05)
	rain.spread = 8.0
	rain.gravity = Vector3(0, -14, 0)
	rain.initial_velocity_min = 8.0
	rain.initial_velocity_max = 12.0
	var drop := BoxMesh.new()
	drop.size = Vector3(0.015, 0.18, 0.015)
	rain.mesh = drop
	var drop_material := StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.75, 0.84, 0.9, 0.45)
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain.material_override = drop_material
	rain.emitting = false
	parent.add_child(rain)

func apply(hour: float, weather: String, camera: Camera3D) -> void:
	var day := smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(18.5, 20.5, hour))
	var golden := 1.0 - clampf(absf(hour - 16.2) / 2.4, 0.0, 1.0)
	var night := 1.0 - day
	var sun_height := sin(deg_to_rad(clampf((hour - 6.0) / 12.0, 0.0, 1.0) * 180.0))
	sun.rotation_degrees = Vector3(-12.0 - sun_height * 58.0, -40.0 - hour * 2.0, 0)
	sun.light_energy = lerpf(0.05, 1.15, day) + golden * 0.12
	sun.light_color = Color("ffd2a4").lerp(Color("fff4dd"), 1.0 - golden)
	moon.rotation_degrees = Vector3(-35, 140, 0)
	moon.light_energy = 0.28 * night
	moon.light_color = Color("b9c8e8")
	fill.rotation_degrees = Vector3(-25, 150, 0)
	fill.light_energy = lerpf(0.08, 0.28, day)
	var environment := world_environment.environment
	environment.ambient_light_energy = lerpf(0.18, 0.5, day)
	environment.tonemap_exposure = 0.96 + golden * 0.06
	environment.fog_density = 0.006
	environment.fog_light_color = Color("f0d2b0")
	environment.glow_enabled = not photosensitivity
	if weather == "mist":
		environment.fog_density = 0.012
		environment.fog_light_color = Color("e7e0d4")
	elif weather == "rain":
		environment.fog_density = 0.008
		environment.fog_light_color = Color("c5d0d4")
		sun.light_energy *= 0.62
		environment.tonemap_exposure = 0.92
	elif weather == "golden":
		environment.fog_light_color = Color("f6d7ae")
	sky_material.sky_top_color = Color("7eadd4").lerp(Color("1c2438"), night)
	sky_material.sky_horizon_color = Color("f2c7a0").lerp(Color("3a4258"), night)
	sky_material.ground_horizon_color = Color("d9c49a")
	sky_material.ground_bottom_color = Color("6a8f48").lerp(Color("1d2a22"), night)
	sky_material.sun_angle_max = 32.0
	if camera:
		rain.global_position = camera.global_position + Vector3(0, 8.0, 0)
	rain.emitting = weather == "rain" and not photosensitivity
	var shafts_on := day > 0.45 and weather != "rain" and not photosensitivity
	for beam in shafts:
		beam.visible = shafts_on
		var tint := Color(1.0, 0.82, 0.48, 0.045 + golden * 0.04)
		var material := beam.material_override as StandardMaterial3D
		if material:
			material.albedo_color = tint

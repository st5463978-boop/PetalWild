class_name Atmosphere
extends Node

const GODRAY_CARDS_ENABLED := false
const GOLDEN_HOUR := 16.5

var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var fill: DirectionalLight3D
var rain: CPUParticles3D
var sky_material: ProceduralSkyMaterial
var shafts: Array[MeshInstance3D] = []
var photosensitivity := false

func _build_shafts(parent: Node3D) -> void:
	for i in 3:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.55, 0.55, 8.0)
		var beam := MeshInstance3D.new()
		beam.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(1.0, 0.9, 0.62, 0.04)
		beam.material_override = material
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(-8.2 + float(i) * 6.4, 3.4, 2.2)
		beam.rotation_degrees = Vector3(-62.0, 18.0, 0.0)
		beam.visible = false
		parent.add_child(beam)
		shafts.append(beam)

func build(parent: Node3D) -> void:
	var env_root := Node3D.new()
	env_root.name = "Environment"
	parent.add_child(env_root)

	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = QualityTier.make_environment()
	sky_material = world_environment.environment.sky.sky_material as ProceduralSkyMaterial
	env_root.add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	QualityTier.style_sun(sun)
	env_root.add_child(sun)

	fill = DirectionalLight3D.new()
	fill.name = "BounceFill"
	QualityTier.style_bounce(fill)
	env_root.add_child(fill)
	_build_shafts(env_root)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = Color("466177")
	moon.light_energy = 0.0
	moon.rotation_degrees = Vector3(-35, 140, 0)
	env_root.add_child(moon)

	rain = CPUParticles3D.new()
	rain.amount = 700 if QualityTier.tier != "c" else 160
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
	var environment := world_environment.environment
	if camera and camera.attributes == null:
		camera.attributes = QualityTier.make_camera_attributes()
	var identity := weather == "clear" and absf(hour - GOLDEN_HOUR) < 0.05
	if identity:
		_apply_identity(environment)
		_apply_fx(weather, camera, 1.0)
		return

	var day := smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(18.5, 20.5, hour))
	var night := 1.0 - day
	sun.rotation_degrees = _sun_rotation(hour)
	sun.light_color = _sun_color(hour, weather)
	sun.light_energy = _sun_energy(hour, weather)
	sun.shadow_opacity = _shadow_opacity(weather, day)
	moon.light_energy = 0.15 * night
	moon.light_color = Color("466177")
	fill.visible = QualityTier.uses_bounce_fill()
	fill.light_energy = QualityTier.BOUNCE_ENERGY * day
	fill.light_color = QualityTier.BOUNCE_COLOR
	environment.ambient_light_energy = lerpf(0.25, 0.6, day)
	environment.tonemap_exposure = QualityTier.EXPOSURE
	environment.fog_density = QualityTier.FOG_DENSITY
	environment.fog_light_color = QualityTier.FOG
	environment.glow_enabled = not photosensitivity
	sky_material.sky_top_color = QualityTier.SKY_TOP.lerp(Color("12272f"), night)
	sky_material.sky_horizon_color = QualityTier.SKY_HORIZON.lerp(Color("466177"), night)
	sky_material.ground_horizon_color = QualityTier.GROUND_HORIZON
	sky_material.ground_bottom_color = QualityTier.GROUND_BOTTOM.lerp(Color("1d2a22"), night)
	_apply_weather(environment, weather, day)
	_apply_fx(weather, camera, day)

func _apply_identity(environment: Environment) -> void:
	QualityTier.style_sun(sun)
	QualityTier.style_bounce(fill)
	moon.light_energy = 0.0
	environment.ambient_light_energy = 0.6
	environment.ambient_light_color = QualityTier.AMBIENT
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = QualityTier.EXPOSURE
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = QualityTier.SATURATION
	environment.adjustment_contrast = 1.05
	environment.fog_density = QualityTier.FOG_DENSITY
	environment.fog_light_color = QualityTier.FOG
	environment.glow_enabled = not photosensitivity
	sky_material.sky_top_color = QualityTier.SKY_TOP
	sky_material.sky_horizon_color = QualityTier.SKY_HORIZON
	sky_material.ground_horizon_color = QualityTier.GROUND_HORIZON
	sky_material.ground_bottom_color = QualityTier.GROUND_BOTTOM
	sky_material.sun_angle_max = 30.0

func _sun_rotation(hour: float) -> Vector3:
	var elev := 35.0
	var az := -45.0
	if hour < 6.0 or hour >= 20.5:
		elev = -8.0
		az = -120.0
	elif hour < GOLDEN_HOUR:
		var t := (hour - 6.0) / 10.5
		var noon := 1.0 - clampf(absf(hour - 12.0) / 6.0, 0.0, 1.0)
		elev = lerpf(8.0, 35.0, t) + noon * 18.0
		az = lerpf(50.0, -45.0, t)
	else:
		var t := clampf((hour - GOLDEN_HOUR) / 4.0, 0.0, 1.0)
		elev = lerpf(35.0, 4.0, t)
		az = lerpf(-45.0, -100.0, t)
	return Vector3(-elev, az, 0.0)

func _sun_color(hour: float, weather: String) -> Color:
	if weather == "rain":
		return Color("97a77b")
	if weather == "overcast" or weather == "mist":
		return Color("c4d2bd")
	if weather == "golden":
		return Color("c39042")
	var dusk := 1.0 - clampf(absf(hour - GOLDEN_HOUR) / 2.4, 0.0, 1.0)
	var dawn := 1.0 - clampf(absf(hour - 6.5) / 2.0, 0.0, 1.0)
	var color := QualityTier.SUN_COLOR
	color = color.lerp(Color("e4d7b8"), dawn * 0.65)
	color = color.lerp(Color("c39042"), dusk * 0.35)
	return color

func _sun_energy(hour: float, weather: String) -> float:
	var day := smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(18.5, 20.5, hour))
	var energy := lerpf(0.05, QualityTier.SUN_ENERGY, day)
	if weather == "rain":
		energy = 0.45
	elif weather == "overcast":
		energy = 0.7
	elif weather == "mist":
		energy *= 0.75
	elif weather == "golden":
		energy = clampf(energy * 0.7, 0.6, 0.9)
	return energy

func _shadow_opacity(weather: String, day: float) -> float:
	if weather == "rain":
		return 0.35
	if weather == "overcast" or weather == "mist":
		return 0.5
	return lerpf(0.4, 0.85, day)

func _apply_weather(environment: Environment, weather: String, day: float) -> void:
	if weather == "mist":
		environment.fog_density = 0.012
		environment.fog_light_color = Color("e7e0d4")
		sky_material.sky_horizon_color = Color("c4d2bd")
	elif weather == "rain":
		environment.fog_density = 0.015
		environment.fog_light_color = Color("c4d2bd")
		environment.tonemap_exposure = 1.1
		environment.ambient_light_energy = 1.0
		sky_material.sky_top_color = Color("97a77b")
		sky_material.sky_horizon_color = Color("c4d2bd")
	elif weather == "golden":
		environment.fog_density = 0.006
		environment.fog_light_color = Color("e4d7b8")
		environment.tonemap_exposure = 1.0
		sky_material.sky_top_color = Color("c39042")
		sky_material.sky_horizon_color = Color("e4d7b8")
	elif weather == "overcast":
		environment.fog_density = 0.008
		environment.fog_light_color = Color("c4d2bd")
		environment.tonemap_exposure = 1.05
		environment.ambient_light_energy = 0.9
		sky_material.sky_horizon_color = Color("c4d2bd")
	else:
		environment.ambient_light_energy = lerpf(0.25, 0.6, day)

func _apply_fx(weather: String, camera: Camera3D, day: float) -> void:
	if camera:
		rain.global_position = camera.global_position + Vector3(0, 8.0, 0)
	rain.emitting = weather == "rain" and not photosensitivity
	rain.visible = rain.emitting
	var shafts_on := GODRAY_CARDS_ENABLED and day > 0.45 and weather != "rain" and not photosensitivity
	for beam in shafts:
		beam.visible = shafts_on
		var tint := Color(1.0, 0.88, 0.58, 0.05)
		var material := beam.material_override as StandardMaterial3D
		if material:
			material.albedo_color = tint

extends Node

# VISUAL_TARGET v2 clear 16:30 baseline. Atmosphere lerps from these values.
# Art Director wins over ASTRA_PLAN on hexes (sun #e3ca82, sky #b7c7d2/#cfdbe1,
# ground #61661a/#343a12, bounce #b39a4d, sat 1.08).
const SUN_ROT := Vector3(-35.0, -45.0, 0.0)
const SUN_COLOR := Color("e3ca82")
const SUN_ENERGY := 1.6
const SUN_ANGULAR := 1.5
const BOUNCE_ROT := Vector3(35.0, 135.0, 0.0)
const BOUNCE_COLOR := Color("b39a4d")
const BOUNCE_ENERGY := 0.18
const SKY_TOP := Color("b7c7d2")
const SKY_HORIZON := Color("cfdbe1")
const GROUND_HORIZON := Color("61661a")
const GROUND_BOTTOM := Color("343a12")
const FOG := Color("cfdbe1")
const AMBIENT := Color("c9dee7")
const SATURATION := 1.08
const EXPOSURE := 0.95
const FOG_DENSITY := 0.004

var tier := "b"

func _ready() -> void:
	var method := RenderingServer.get_current_rendering_method()
	if method == "forward_plus":
		tier = "a"
	elif method == "mobile" or (method == "gl_compatibility" and OS.has_feature("mobile")):
		tier = "c"
	else:
		tier = "b"

func uses_bounce_fill() -> bool:
	return tier != "a"

func make_environment() -> Environment:
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = GROUND_HORIZON
	sky_mat.ground_bottom_color = GROUND_BOTTOM
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.15
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32 if tier != "a" else Sky.RADIANCE_SIZE_256
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.85
	environment.ambient_light_energy = 0.6
	environment.ambient_light_color = AMBIENT
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = EXPOSURE
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = SATURATION
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = FOG
	environment.fog_density = FOG_DENSITY
	environment.fog_aerial_perspective = 0.45
	environment.fog_sky_affect = 0.3
	environment.glow_enabled = true
	environment.glow_intensity = 0.4 if tier == "b" else (0.6 if tier == "a" else 0.3)
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	if tier == "a":
		environment.ssao_enabled = true
		environment.ssao_radius = 0.6
		environment.ssao_intensity = 1.8
		environment.ssil_enabled = true
		environment.ssil_radius = 3.0
		environment.ssil_intensity = 0.8
		environment.sdfgi_enabled = true
		environment.sdfgi_cascades = 4
		environment.sdfgi_min_cell_size = 0.15
		environment.sdfgi_use_occlusion = true
		environment.sdfgi_bounce_feedback = 0.4
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 0.008
		environment.volumetric_fog_albedo = SUN_COLOR
		environment.volumetric_fog_anisotropy = 0.6
		environment.volumetric_fog_length = 64.0
	else:
		environment.ssao_enabled = false
		environment.ssil_enabled = false
		environment.sdfgi_enabled = false
		environment.volumetric_fog_enabled = false
	return environment

func make_camera_attributes() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	if tier == "a":
		attributes.dof_blur_far_enabled = true
		attributes.dof_blur_amount = 0.06
	else:
		attributes.dof_blur_far_enabled = false
		attributes.dof_blur_near_enabled = false
	return attributes

func style_sun(light: DirectionalLight3D) -> void:
	light.rotation_degrees = SUN_ROT
	light.light_color = SUN_COLOR
	light.light_energy = SUN_ENERGY
	light.light_angular_distance = SUN_ANGULAR
	light.shadow_enabled = true
	light.shadow_blur = 1.5
	light.shadow_opacity = 0.85
	light.light_bake_mode = Light3D.BAKE_DYNAMIC
	if tier == "a":
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		light.directional_shadow_max_distance = 60.0
	else:
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		light.directional_shadow_max_distance = 30.0 if tier == "b" else 20.0
	light.shadow_bias = 0.06

func style_bounce(light: DirectionalLight3D) -> void:
	light.rotation_degrees = BOUNCE_ROT
	light.light_color = BOUNCE_COLOR
	light.light_energy = BOUNCE_ENERGY
	light.shadow_enabled = false
	light.light_specular = 0.0
	light.visible = uses_bounce_fill()

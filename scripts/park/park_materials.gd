class_name ParkMaterials
extends RefCounted

var lawn: ShaderMaterial
var soil: ShaderMaterial
var gravel: ShaderMaterial
var cobble: ShaderMaterial
var flag: ShaderMaterial
var rock: ShaderMaterial
var wood: StandardMaterial3D
var brick: StandardMaterial3D
var roof: StandardMaterial3D
var metal: StandardMaterial3D
var hedge: StandardMaterial3D
var glass: StandardMaterial3D
var water: ShaderMaterial
var foliage: ShaderMaterial
var lantern_glass: ShaderMaterial
var awning: StandardMaterial3D
var sand: ShaderMaterial
var bark: StandardMaterial3D

const PH := "res://assets/third_party/polyhaven/"
const GEN := "res://assets/park/generated/"


func load_all() -> void:
	lawn = _terrain(
		PH + "leafy_grass/leafy_grass_diff_1k.jpg",
		PH + "leafy_grass/leafy_grass_nor_gl_1k.jpg",
		PH + "leafy_grass/leafy_grass_arm_1k.jpg",
		Color("7aa832"),
		0.42,
		0.55
	)
	soil = _terrain(
		PH + "flower_scattered_dirt/flower_scattered_dirt_diff_1k.jpg",
		PH + "flower_scattered_dirt/flower_scattered_dirt_nor_gl_1k.jpg",
		PH + "flower_scattered_dirt/flower_scattered_dirt_arm_1k.jpg",
		Color("5c4330"),
		0.85,
		0.62
	)
	gravel = _terrain(
		PH + "gravel/gravel_diff_1k.jpg",
		PH + "gravel/gravel_nor_gl_1k.jpg",
		PH + "gravel/gravel_arm_1k.jpg",
		Color("f2dab6"),
		0.85,
		0.55
	)
	cobble = _terrain(
		PH + "cobblestone_floor_13/cobblestone_floor_13_diff_1k.jpg",
		PH + "cobblestone_floor_13/cobblestone_floor_13_nor_gl_1k.jpg",
		PH + "cobblestone_floor_13/cobblestone_floor_13_arm_1k.jpg",
		Color("c9b79b"),
		0.62,
		0.68
	)
	flag = _terrain(
		PH + "cobblestone_floor_13/cobblestone_floor_13_diff_1k.jpg",
		PH + "cobblestone_floor_13/cobblestone_floor_13_nor_gl_1k.jpg",
		PH + "cobblestone_floor_13/cobblestone_floor_13_arm_1k.jpg",
		Color("d4c4a4"),
		0.72,
		0.7
	)
	rock = _terrain(
		PH + "rocks_ground_02/rocks_ground_02_col_1k.jpg",
		PH + "rocks_ground_02/rocks_ground_02_nor_gl_1k.jpg",
		PH + "rocks_ground_02/rocks_ground_02_arm_1k.jpg",
		Color("b7a890"),
		0.7,
		0.75
	)
	sand = _terrain(
		PH + "flower_scattered_dirt/flower_scattered_dirt_diff_1k.jpg",
		PH + "flower_scattered_dirt/flower_scattered_dirt_nor_gl_1k.jpg",
		PH + "flower_scattered_dirt/flower_scattered_dirt_arm_1k.jpg",
		Color("c8a46a"),
		0.9,
		0.45
	)
	wood = _pbr(
		PH + "wood_planks/wood_planks_diff_1k.jpg",
		PH + "wood_planks/wood_planks_nor_gl_1k.jpg",
		PH + "wood_planks/wood_planks_arm_1k.jpg",
		Color("9f7f63"),
		0.7
	)
	brick = _pbr(
		PH + "brick_wall_001/brick_wall_001_diffuse_1k.jpg",
		PH + "brick_wall_001/brick_wall_001_nor_gl_1k.jpg",
		PH + "brick_wall_001/brick_wall_001_arm_1k.jpg",
		Color("c48a6a"),
		0.82
	)
	roof = _pbr(
		PH + "roof_09/roof_09_diff_1k.jpg",
		PH + "roof_09/roof_09_nor_gl_1k.jpg",
		PH + "roof_09/roof_09_arm_1k.jpg",
		Color("6e5344"),
		0.88
	)
	metal = _pbr(
		PH + "rusty_metal_02/rusty_metal_02_diff_1k.jpg",
		PH + "rusty_metal_02/rusty_metal_02_nor_gl_1k.jpg",
		PH + "rusty_metal_02/rusty_metal_02_arm_1k.jpg",
		Color("3a3c40"),
		0.45
	)
	metal.metallic = 0.55
	bark = _pbr(
		PH + "wood_planks/wood_planks_diff_1k.jpg",
		PH + "wood_planks/wood_planks_nor_gl_1k.jpg",
		PH + "wood_planks/wood_planks_arm_1k.jpg",
		Color("89613b"),
		0.92
	)
	hedge = StandardMaterial3D.new()
	hedge.albedo_color = Color("7eb445")
	hedge.roughness = 0.74
	hedge.vertex_color_use_as_albedo = true
	if ResourceLoader.exists(PH + "leafy_grass/leafy_grass_diff_1k.jpg"):
		hedge.albedo_texture = load(PH + "leafy_grass/leafy_grass_diff_1k.jpg")
		hedge.normal_enabled = true
		hedge.normal_texture = load(PH + "leafy_grass/leafy_grass_nor_gl_1k.jpg")
		hedge.normal_scale = 0.4
	hedge.uv1_scale = Vector3(1.8, 1.8, 1.8)
	glass = StandardMaterial3D.new()
	glass.albedo_color = Color(0.62, 0.78, 0.74, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic = 0.12
	glass.refraction_enabled = true
	glass.refraction_scale = 0.04
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	water = ShaderMaterial.new()
	water.shader = load("res://shaders/park_water.gdshader")
	foliage = ShaderMaterial.new()
	foliage.shader = load("res://shaders/park_foliage.gdshader")
	lantern_glass = ShaderMaterial.new()
	lantern_glass.shader = load("res://shaders/lantern_glass.gdshader")
	lantern_glass.set_shader_parameter("glow", 0.55)
	awning = StandardMaterial3D.new()
	awning.albedo_color = Color("f5dbb4")
	if ResourceLoader.exists(GEN + "awning_red_cream.png"):
		awning.albedo_texture = load(GEN + "awning_red_cream.png")
	awning.roughness = 0.9
	awning.uv1_scale = Vector3(1.8, 1.0, 1.8)
	awning.cull_mode = BaseMaterial3D.CULL_DISABLED


func _terrain(alb: String, nor: String, arm: String, tint: Color, uv_scale: float, nrm: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/park_terrain.gdshader")
	if ResourceLoader.exists(alb):
		material.set_shader_parameter("albedo_tex", load(alb))
	if ResourceLoader.exists(nor):
		material.set_shader_parameter("normal_tex", load(nor))
	if ResourceLoader.exists(arm):
		material.set_shader_parameter("arm_tex", load(arm))
	material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	material.set_shader_parameter("uv_scale", uv_scale)
	material.set_shader_parameter("normal_strength", nrm)
	return material


func _pbr(alb: String, nor: String, arm: String, tint: Color, rough: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = rough
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if ResourceLoader.exists(alb):
		material.albedo_texture = load(alb)
	if ResourceLoader.exists(nor):
		material.normal_enabled = true
		material.normal_texture = load(nor)
		material.normal_scale = 0.7
	if ResourceLoader.exists(arm):
		var arm_tex: Texture2D = load(arm)
		material.ao_enabled = true
		material.ao_texture = arm_tex
		material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.roughness_texture = arm_tex
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.uv1_scale = Vector3(1.4, 1.4, 1.4)
	return material


func tinted_brick(tint: Color) -> StandardMaterial3D:
	var material := brick.duplicate() as StandardMaterial3D
	material.albedo_color = tint
	return material


func tinted_wood(tint: Color) -> StandardMaterial3D:
	var material := wood.duplicate() as StandardMaterial3D
	material.albedo_color = tint
	return material


func solid(color: Color, rough: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.vertex_color_use_as_albedo = true
	return material

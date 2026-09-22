shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D opacity_tex : filter_linear_mipmap_anisotropic, repeat_disable;

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb;
	float cut = texture(opacity_tex, UV).r;
	ALPHA = cut;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ALBEDO = alb;
	ROUGHNESS = 0.74;
}

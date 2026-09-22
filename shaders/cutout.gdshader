shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D opacity_tex : filter_linear_mipmap_anisotropic, repeat_disable;

void fragment() {
	vec3 alb = texture(albedo_tex, UV).rgb;
	float cut = texture(opacity_tex, UV).r;
	ALPHA = cut;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	float peak = max(alb.r, max(alb.g, alb.b));
	// ponytail: cap atlas highlights under this sun; raise if the blooms go dull.
	float cap = peak > 0.38 ? 0.38 / peak : 1.0;
	ALBEDO = alb * cap;
	ROUGHNESS = 0.74;
}

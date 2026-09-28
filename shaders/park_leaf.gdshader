shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D opacity_tex : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool alpha_from_albedo = false;
uniform bool use_normal = true;
uniform float sway = 0.16;
uniform float wind = 1.25;
uniform vec3 tint : source_color = vec3(1.0);

void vertex() {
	float tip = COLOR.a;
	float phase = INSTANCE_CUSTOM.x * 6.28318 + NODE_POSITION_WORLD.x * 0.31 + NODE_POSITION_WORLD.z * 0.23;
	vec3 p = VERTEX;
	p.x += sin(TIME * wind + phase) * sway * tip;
	p.z += cos(TIME * wind * 0.77 + phase) * sway * 0.55 * tip;
	VERTEX = p;
}

void fragment() {
	vec4 sample = texture(albedo_tex, UV);
	float cut = alpha_from_albedo ? sample.a : texture(opacity_tex, UV).r;
	if (cut < 0.42) {
		discard;
	}
	vec3 col = sample.rgb * COLOR.rgb * tint;
	ALBEDO = col;
	ROUGHNESS = 0.62;
	SPECULAR = 0.18;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.55;
	}
	float back = pow(clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.3);
	EMISSION = col * back * 0.08;
}

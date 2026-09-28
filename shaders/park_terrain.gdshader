shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float uv_scale = 0.55;
uniform float normal_strength = 0.7;
uniform float wrap = 0.55;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * uv_scale;
	vec2 uv2 = world_pos.xz * uv_scale * 0.37 + vec2(0.13, 0.41);
	vec3 a = texture(albedo_tex, uv).rgb;
	vec3 b = texture(albedo_tex, uv2).rgb;
	vec3 alb = mix(a, b, 0.35) * tint * COLOR.rgb;
	vec4 arm = texture(arm_tex, uv);
	ALBEDO = alb;
	ROUGHNESS = clamp(arm.g, 0.35, 0.98);
	METALLIC = arm.b * 0.12;
	AO = arm.r;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	// wrap keeps lawn from going muddy on the shade side
	float ndl = clamp(dot(NORMAL, vec3(0.22, 0.94, 0.18)), 0.0, 1.0);
	EMISSION = alb * wrap * (1.0 - ndl) * 0.22;
}

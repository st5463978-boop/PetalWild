shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.07, 0.28, 0.32);
uniform vec3 shallow_color : source_color = vec3(0.28, 0.66, 0.58);
uniform vec3 sparkle_color : source_color = vec3(0.95, 0.88, 0.62);
uniform float wave_height = 0.028;
uniform float caustic_strength = 0.22;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform bool use_refraction = true;

varying vec3 world_pos;

void vertex() {
	vec3 p = VERTEX;
	float w1 = sin(p.x * 1.7 + TIME * 1.35) * wave_height;
	float w2 = cos(p.z * 2.15 + TIME * 1.05) * wave_height * 0.78;
	float w3 = sin((p.x + p.z) * 3.4 + TIME * 1.9) * wave_height * 0.42;
	p.y += w1 + w2 + w3;
	VERTEX = p;
	world_pos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	vec2 n_uv = world_pos.xz * 0.42;
	float n1 = sin(n_uv.x * 7.0 + TIME * 1.55) * cos(n_uv.y * 5.5 - TIME * 1.2);
	float n2 = sin((n_uv.x + n_uv.y) * 9.5 + TIME * 2.05);
	vec3 nrm = vec3(n1 * 0.22, 1.0, n2 * 0.18);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.35);
	vec3 water = mix(deep_color, shallow_color, clamp(fres * 0.85 + 0.12, 0.0, 1.0));
	vec3 col = water;
	if (use_refraction) {
		vec2 suv = SCREEN_UV + vec2(n1, n2) * 0.018;
		vec3 refr = texture(screen_texture, suv).rgb;
		col = mix(refr * 0.42 + water * 0.58, water, 0.28 + fres * 0.55);
	}
	float c1 = sin(world_pos.x * 10.0 + TIME * 1.65) * sin(world_pos.z * 8.4 - TIME * 1.25);
	float c2 = sin((world_pos.x - world_pos.z) * 13.0 + TIME * 2.3);
	float caustic = smoothstep(0.45, 0.92, c1 * 0.55 + c2 * 0.45);
	float spark = smoothstep(0.9, 1.0, sin(world_pos.x * 6.4 + TIME * 2.1) * sin(world_pos.z * 5.2 - TIME * 1.5));
	ALBEDO = col;
	ROUGHNESS = mix(0.05, 0.16, 1.0 - fres);
	METALLIC = 0.08;
	SPECULAR = 0.72;
	EMISSION = sparkle_color * spark * 0.28 + vec3(0.45, 0.72, 0.55) * caustic * caustic_strength + shallow_color * fres * 0.08;
	ALPHA = mix(0.78, 0.94, fres);
	NORMAL_MAP = vec3(n1 * 0.5 + 0.5, n2 * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 0.55;
}

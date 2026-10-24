shader_type spatial;

varying vec3 world_pos;

// Optional VC art detail maps. detail_mix = 0 (the default) keeps the placeholder look.
uniform sampler2D detail_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_avg = 1.0;
uniform float soil_avg = 1.0;
uniform float detail_scale = 0.3;
uniform float detail_mix = 0.0;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float fine = sin(world_pos.x * 17.0) * sin(world_pos.z * 15.0);
	float blot = sin(world_pos.x * 2.1 + world_pos.z * 1.6);
	float moss = smoothstep(0.35, 0.95, blot * 0.5 + 0.5);
	vec3 col = base * (0.86 + 0.18 * fine);
	float soil = smoothstep(0.0, 0.08, base.r - base.g);
	col = mix(col, col * vec3(0.72, 1.08, 0.68), moss * 0.28 * (1.0 - soil));
	float furrow = sin(world_pos.x * 9.0);
	col = mix(col, col * 0.86, soil * (0.5 - furrow * 0.5) * 0.35);
	if (detail_mix > 0.0) {
		vec2 uv = world_pos.xz * detail_scale;
		vec3 grass_texel = texture(detail_tex, uv).rgb;
		vec3 soil_texel = texture(soil_tex, uv * 1.4).rgb;
		float grass_l = dot(grass_texel, vec3(0.299, 0.587, 0.114)) / max(detail_avg, 0.05);
		float soil_l = dot(soil_texel, vec3(0.299, 0.587, 0.114)) / max(soil_avg, 0.05);
		float detail = clamp(mix(grass_l, soil_l, soil), 0.45, 1.7);
		col = mix(col, col * detail, detail_mix);
	}
	ALBEDO = col;
	ROUGHNESS = 0.94;
}

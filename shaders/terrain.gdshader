shader_type spatial;

varying vec3 world_pos;

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
	ALBEDO = col;
	ROUGHNESS = 0.94;
}

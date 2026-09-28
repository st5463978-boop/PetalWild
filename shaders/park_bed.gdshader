shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Painted sediment. Not a photo scan. Piñata bed: saturated, toy-scale, readable under clear water.
uniform vec3 shore_sand : source_color = vec3(0.98, 0.74, 0.28);
uniform vec3 moss : source_color = vec3(0.20, 0.82, 0.26);
uniform vec3 bowl : source_color = vec3(0.10, 0.66, 0.48);
uniform vec3 gold : source_color = vec3(1.0, 0.84, 0.22);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * 0.55;
	float n = sin(uv.x * 2.4 + 0.4) * cos(uv.y * 2.1);
	float n2 = sin(uv.x * 6.5 + uv.y * 4.2);
	float peb = sin(uv.x * 14.0) * sin(uv.y * 11.0);
	float depth = clamp(-world_pos.y / 0.48, 0.0, 1.0);
	vec3 col = mix(shore_sand, moss, smoothstep(-0.15, 0.75, n));
	col = mix(col, bowl, smoothstep(0.25, 1.0, depth));
	col = mix(col, gold, smoothstep(0.55, 0.95, n2) * 0.35 * (1.0 - depth * 0.4));
	col *= 0.92 + peb * 0.08;
	ALBEDO = col;
	ROUGHNESS = mix(0.72, 0.9, depth);
	SPECULAR = 0.12;
	float caustic = sin(world_pos.x * 9.0 + TIME * 1.1) * sin(world_pos.z * 7.4 - TIME * 0.85);
	EMISSION = gold * smoothstep(0.4, 0.9, caustic) * 0.28 * (1.0 - depth * 0.2);
}

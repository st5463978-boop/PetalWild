shader_type spatial;
render_mode cull_disabled;

varying vec3 world_pos;
varying float up;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up = NORMAL.y;
	vec3 p = VERTEX;
	float lump = sin(world_pos.x * 3.1) * cos(world_pos.z * 2.7);
	float lump2 = sin(world_pos.x * 8.5 + world_pos.z * 6.4);
	if (up > 0.12) {
		p += NORMAL * (lump * 0.16 + lump2 * 0.05);
		p.y += abs(lump) * up * 0.08;
	}
	VERTEX = p;
}

void fragment() {
	float broad = sin(world_pos.x * 9.0 + world_pos.y * 4.0) * sin(world_pos.z * 8.0);
	float fine = sin(world_pos.x * 22.0 + world_pos.y * 15.0 + world_pos.z * 11.0);
	vec3 deep = vec3(0.09, 0.28, 0.12);
	vec3 mid = vec3(0.24, 0.48, 0.18);
	vec3 sun = vec3(0.66, 0.78, 0.32);
	vec3 col = mix(deep, mid, broad * 0.5 + 0.5);
	col = mix(col, sun, clamp(up, 0.0, 1.0) * (0.28 + fine * 0.12));
	ALBEDO = col;
	ROUGHNESS = 0.84;
	SPECULAR = 0.15;
}

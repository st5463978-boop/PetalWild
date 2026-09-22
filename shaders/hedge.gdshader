shader_type spatial;
render_mode cull_disabled;

varying vec3 world_pos;
varying float up;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up = NORMAL.y;
	vec3 p = VERTEX;
	float lump = sin(world_pos.x * 6.4) * cos(world_pos.z * 5.2) * sin(world_pos.y * 7.5);
	p += NORMAL * lump * 0.16;
	float tuft = sin(world_pos.x * 17.0 + world_pos.y * 11.0);
	if (up > 0.15) {
		p += NORMAL * tuft * 0.1;
	}
	VERTEX = p;
}

void fragment() {
	float broad = sin(world_pos.x * 9.0 + world_pos.y * 4.0) * sin(world_pos.z * 8.0);
	float fine = sin(world_pos.x * 22.0 + world_pos.y * 15.0 + world_pos.z * 11.0);
	vec3 deep = vec3(0.05, 0.18, 0.07);
	vec3 mid = vec3(0.13, 0.34, 0.11);
	vec3 sun = vec3(0.42, 0.58, 0.2);
	vec3 col = mix(deep, mid, broad * 0.5 + 0.5);
	col = mix(col, sun, clamp(up, 0.0, 1.0) * (0.28 + fine * 0.12));
	ALBEDO = col;
	ROUGHNESS = 0.84;
	SPECULAR = 0.15;
}

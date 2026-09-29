shader_type spatial;
render_mode cull_disabled;

varying float tip;

void vertex() {
	tip = 1.0 - UV.y;
	vec3 p = VERTEX;
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float sway = sin(TIME * 1.7 + phase) * tip * 0.16;
	p.x += sway;
	p.z += cos(TIME * 1.3 + phase) * tip * 0.05;
	VERTEX = p;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 col = COLOR.rgb;
	float shade = clamp(abs(dot(NORMAL, vec3(0.25, 0.9, 0.2))), 0.0, 1.0);
	ALBEDO = col * (0.55 + 0.45 * shade);
	ROUGHNESS = 0.9;
	EMISSION = vec3(0.0);
}

void light() {
	float ndot = max(abs(dot(NORMAL, LIGHT)), 0.28);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ndot;
}

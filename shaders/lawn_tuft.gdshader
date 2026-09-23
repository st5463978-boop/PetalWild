shader_type spatial;
render_mode cull_disabled, specular_disabled;

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
	vec3 col = COLOR.rgb;
	float shade = clamp(dot(NORMAL, vec3(0.25, 0.9, 0.2)), 0.0, 1.0);
	// ponytail: same shade as the hedge cards; 0.72 is the night delta, drop it if the lawn goes black.
	ALBEDO = col * (0.48 + 0.36 * shade) * 0.72;
	ROUGHNESS = 1.0;
}

void light() {
	float ndot = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 lit = ALBEDO * LIGHT_COLOR * ATTENUATION * ndot;
	DIFFUSE_LIGHT += min(lit, vec3(0.2));
}

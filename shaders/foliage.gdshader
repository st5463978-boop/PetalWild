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
	vec3 col = COLOR.rgb;
	float shade = clamp(dot(NORMAL, vec3(0.25, 0.9, 0.2)), 0.0, 1.0);
	ALBEDO = col * (0.5 + 0.62 * shade);
	ROUGHNESS = 0.78;
	EMISSION = col * tip * 0.04;
}

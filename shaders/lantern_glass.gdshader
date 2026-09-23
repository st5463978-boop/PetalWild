shader_type spatial;
render_mode specular_disabled;

uniform float glow = 0.22;

void fragment() {
	// ponytail: the glass clips to 255 under this sun; raise glow if the night lamp goes out.
	vec3 glass = vec3(0.38, 0.18, 0.06);
	ALBEDO = glass;
	EMISSION = glass * glow;
	ROUGHNESS = 1.0;
}

void light() {
	float ndot = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 lit = ALBEDO * LIGHT_COLOR * ATTENUATION * ndot;
	DIFFUSE_LIGHT += min(lit, vec3(0.14));
}

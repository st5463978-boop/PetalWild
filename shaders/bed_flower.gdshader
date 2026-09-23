shader_type spatial;
render_mode cull_disabled, specular_disabled;

varying vec3 petal;

void vertex() {
	petal = COLOR.rgb;
}

void fragment() {
	ALBEDO = petal * 0.55;
	ROUGHNESS = 1.0;
}

void light() {
	float ndot = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 lit = ALBEDO * LIGHT_COLOR * ATTENUATION * ndot;
	DIFFUSE_LIGHT += min(lit, vec3(0.2));
}

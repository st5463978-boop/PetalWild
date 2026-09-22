shader_type spatial;
render_mode cull_disabled;

uniform vec4 leaf_a : source_color = vec4(0.15, 0.38, 0.14, 1.0);
uniform vec4 leaf_b : source_color = vec4(0.46, 0.66, 0.22, 1.0);
uniform float wind = 0.06;

void vertex() {
	float sway = sin(TIME * 1.35 + VERTEX.x * 0.55 + VERTEX.z * 0.4) * wind;
	VERTEX.x += sway * (1.0 + VERTEX.y);
	VERTEX.z += cos(TIME * 1.1 + VERTEX.z) * wind * 0.6;
}

void fragment() {
	ALBEDO = mix(leaf_a.rgb, leaf_b.rgb, clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0));
	ROUGHNESS = 0.82;
}

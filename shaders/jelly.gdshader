shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.08, 0.35, 0.22, 1.0);
uniform vec4 lit_color : source_color = vec4(0.55, 0.9, 0.45, 1.0);
uniform vec4 rim_color : source_color = vec4(0.9, 1.0, 0.75, 1.0);
uniform float wobble = 0.06;
uniform float impact = 0.0;
uniform vec3 push = vec3(0.0, 0.0, 0.0);

void vertex() {
	float n = sin(TIME * 3.2 + VERTEX.y * 9.0 + VERTEX.x * 5.0) * wobble;
	VERTEX += NORMAL * n;
	VERTEX += push * impact * (VERTEX.y + 0.15);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.1);
	float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(deep_color.rgb, lit_color.rgb, up);
	col = mix(col, rim_color.rgb, fres * 0.55);
	ALBEDO = col;
	ROUGHNESS = mix(0.16, 0.42, fres);
	SPECULAR = 0.55;
	EMISSION = col * 0.12;
	RIM = 0.35;
	RIM_TINT = 0.55;
}

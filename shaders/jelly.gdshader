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
	float height = clamp(VERTEX.y * 2.2 + 0.15, 0.0, 1.0);
	vec3 col = mix(deep_color.rgb, lit_color.rgb, fres * 0.55 + height * 0.35);
	float bubble = smoothstep(0.9, 1.0, sin(VERTEX.x * 34.0 + TIME) * sin(VERTEX.y * 28.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.22, fres);
	SPECULAR = 0.28;
	EMISSION = glow_color.rgb * (fres * 0.12 + bubble * 0.16 + height * 0.05);
}

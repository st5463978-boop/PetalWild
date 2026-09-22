shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.2, 0.7, 0.4, 1.0);
uniform vec4 lit_color : source_color = vec4(0.9, 1.0, 0.8, 1.0);
uniform vec4 glow_color : source_color = vec4(0.8, 1.0, 0.4, 1.0);
uniform float wobble = 0.5;
uniform float ripple = 0.0;

void vertex() {
	vec3 p = VERTEX;
	float n = sin(p.y * 9.0 + TIME * 2.3) * sin(p.x * 8.0 + TIME * 1.6);
	p += NORMAL * n * 0.04 * wobble;
	p += NORMAL * sin(TIME * 7.0) * ripple * 0.05;
	VERTEX = p;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.6);
	float core = pow(facing, 1.35);
	float height = clamp(VERTEX.y * 2.2 + 0.15, 0.0, 1.0);
	vec3 col = mix(deep_color.rgb * 0.62, lit_color.rgb, rim * 0.28 + height * 0.22);
	col = mix(col, deep_color.rgb * 0.45, core * 0.5);
	float bubble = smoothstep(0.92, 1.0, sin(VERTEX.x * 34.0 + TIME) * sin(VERTEX.y * 28.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.78, 0.58, rim);
	SPECULAR = 0.08;
	EMISSION = glow_color.rgb * (rim * 0.08 + bubble * 0.1 + core * 0.06);
}

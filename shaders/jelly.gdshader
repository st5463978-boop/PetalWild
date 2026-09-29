shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.2, 0.7, 0.4, 1.0);
uniform vec4 lit_color : source_color = vec4(0.9, 1.0, 0.8, 1.0);
uniform vec4 glow_color : source_color = vec4(0.8, 1.0, 0.4, 1.0);
uniform float wobble = 0.5;
uniform float ripple = 0.0;
uniform vec3 stretch_dir = vec3(0.0, 1.0, 0.0);
uniform float stretch = 0.0;

void vertex() {
	vec3 p = VERTEX;
	float n = sin(p.y * 9.0 + TIME * 2.3) * sin(p.x * 8.0 + TIME * 1.6);
	p += NORMAL * n * 0.04 * wobble;
	p += NORMAL * sin(TIME * 7.0) * ripple * 0.05;
	float along = dot(p, stretch_dir);
	p += NORMAL * sin(TIME * 6.0 + along * 11.0) * stretch * 0.06;
	VERTEX = p;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.2);
	float height = clamp(VERTEX.y * 2.2 + 0.15, 0.0, 1.0);
	vec3 col = mix(deep_color.rgb * 0.82, deep_color.rgb, height);
	col = mix(col, lit_color.rgb, height * 0.1 + rim * 0.05);
	float bubble = smoothstep(0.94, 1.0, sin(VERTEX.x * 34.0 + TIME) * sin(VERTEX.y * 28.0));
	ALBEDO = col;
	ROUGHNESS = 0.94;
	SPECULAR = 0.02;
	EMISSION = glow_color.rgb * bubble * 0.03;
}

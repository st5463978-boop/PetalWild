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
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.65);
	vec3 col = mix(deep_color.rgb, lit_color.rgb, fres);
	float bubble = smoothstep(0.86, 1.0, sin(VERTEX.x * 28.0 + TIME * 1.2) * sin(VERTEX.y * 24.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.32, 0.06, fres);
	SPECULAR = 0.5;
	EMISSION = glow_color.rgb * (fres * 0.22 + bubble * 0.18);
}

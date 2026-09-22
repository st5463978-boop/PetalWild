shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.04, 0.22, 0.2, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.42, 0.75, 0.58, 1.0);

void vertex() {
	VERTEX.y += sin(TIME * 1.5 + VERTEX.x * 0.85 + VERTEX.z * 0.65) * 0.035;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.1);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, fres);
	ALPHA = mix(0.82, 0.42, fres);
	ROUGHNESS = 0.16;
	EMISSION = ALBEDO * 0.05;
}

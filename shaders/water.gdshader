shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.08, 0.32, 0.3, 1.0);
uniform vec4 lit_color : source_color = vec4(0.55, 0.82, 0.72, 1.0);

void vertex() {
	VERTEX.y += sin(TIME * 1.3 + VERTEX.x * 1.7 + VERTEX.z * 1.1) * 0.035;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	ALBEDO = mix(deep_color.rgb, lit_color.rgb, fres);
	ROUGHNESS = mix(0.05, 0.28, fres);
	SPECULAR = 0.7;
	ALPHA = mix(0.78, 0.45, fres);
	EMISSION = lit_color.rgb * 0.04;
}

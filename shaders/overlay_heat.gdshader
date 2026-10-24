shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform vec4 low_color : source_color = vec4(0.11, 0.14, 0.1, 0.35);
uniform vec4 high_color : source_color = vec4(0.12, 0.54, 0.27, 0.9);
uniform float amount = 0.0;

void fragment() {
	float t = clamp(amount, 0.0, 1.0);
	vec4 col = mix(low_color, high_color, t);
	ALBEDO = col.rgb;
	ALPHA = col.a;
}

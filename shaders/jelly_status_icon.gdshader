shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec4 neon_color : source_color = vec4(0.25, 0.66, 1.0, 1.0);
uniform float energy : hint_range(0.0, 16.0) = 5.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform int glow_mode : hint_range(0, 1) = 0;

void fragment() {
	float mask = 1.0;
	if (glow_mode == 1) {
		vec2 p = UV - vec2(0.5);
		float d = length(p) * 2.0;
		mask = clamp(1.0 - d, 0.0, 1.0);
		mask *= mask;
	}
	float a = neon_color.a * fade * mask;
	vec3 hdr = neon_color.rgb * energy;
	ALBEDO = hdr;
	EMISSION = hdr;
	ALPHA = clamp(a, 0.0, 1.0);
}

shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(0.28, 0.48, 0.18);
uniform float gain = 1.0;

void fragment() {
	vec4 texel = texture(tex, UV);
	if (texel.a < 0.4) {
		discard;
	}
	vec3 leaf = mix(texel.rgb, COLOR.rgb, 0.42);
	ALBEDO = mix(leaf, tint, 0.16) * gain;
	ROUGHNESS = 0.86;
	SPECULAR = 0.06;
}

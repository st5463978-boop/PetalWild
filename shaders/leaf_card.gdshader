shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(0.28, 0.48, 0.18);
uniform float gain = 1.0;

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 texel = texture(tex, UV);
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	vec3 leaf = mix(texel.rgb, COLOR.rgb, 0.42);
	ALBEDO = mix(leaf, tint, 0.16) * gain;
	ROUGHNESS = 0.86;
	SPECULAR = 0.06;
}

void light() {
	float ndot = max(abs(dot(NORMAL, LIGHT)), 0.22);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ndot;
}

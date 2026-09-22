shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind = 0.035;

void vertex() {
	float height = max(VERTEX.y, 0.0);
	float sway = sin(TIME * 1.25 + VERTEX.x * 0.85 + VERTEX.z * 0.55) * wind;
	VERTEX.x += sway * height;
	VERTEX.z += cos(TIME * 0.95 + VERTEX.z * 0.7) * wind * 0.55 * height;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	if (tex.a < 0.4) {
		discard;
	}
	ALBEDO = tex.rgb;
	ROUGHNESS = 0.74;
}

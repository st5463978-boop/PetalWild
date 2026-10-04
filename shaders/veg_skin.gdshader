shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Cast > Veggie folk. Photoreal vegetable skin at toy scale.
// Not the jelly shader: no transmission, no glassy alpha.
uniform vec4 skin_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform float roughness = 0.42;
uniform float sss_strength = 0.35;

void vertex() {
	float breath = sin(TIME * 1.6 + VERTEX.y * 6.0) * 0.004;
	VERTEX += NORMAL * breath;
}

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb * skin_tint.rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	// OpenGL 3 drops SSS. A soft key wrap keeps the vegetable round.
	float wrap = pow(clamp(dot(NORMAL, normalize(vec3(-0.35, 0.82, 0.45))), 0.0, 1.0), 0.65);
	ALBEDO = tex * mix(0.78, 1.06, wrap);
	ROUGHNESS = mix(roughness + 0.08, roughness * 0.75, wrap);
	SPECULAR = 0.34;
	SSS_STRENGTH = sss_strength;
	SSS_TRANSMITTANCE_COLOR = vec4(tex, 1.0);
	SSS_TRANSMITTANCE_DEPTH = 0.08;
	EMISSION = tex * rim * 0.08 + tex * wrap * 0.03;
}

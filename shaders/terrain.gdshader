shader_type spatial;

uniform sampler2D grass_tex : source_color, hint_default_white;
uniform sampler2D dirt_tex : source_color, hint_default_white;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * 0.22;
	vec3 grass = texture(grass_tex, uv).rgb;
	vec3 dirt = texture(dirt_tex, uv * 0.9).rgb;
	vec3 base = COLOR.rgb;
	float soil = smoothstep(0.0, 0.08, base.r - base.g);
	vec3 col = mix(grass * base * 1.12, dirt * base * 1.2, soil);
	ALBEDO = col;
	ROUGHNESS = 0.92;
}

shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rgh_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 1.2;
uniform float nrm_strength = 0.5;

varying vec3 world_pos;
varying float height_mask;

vec3 triplanar_col(sampler2D tex, vec3 pos, vec3 n) {
	vec3 b = abs(n);
	b = max(b - vec3(0.2), vec3(0.0));
	b /= max(b.x + b.y + b.z, 0.001);
	vec3 cx = texture(tex, pos.yz / tile_m).rgb;
	vec3 cy = texture(tex, pos.xz / tile_m).rgb;
	vec3 cz = texture(tex, pos.xy / tile_m).rgb;
	return cx * b.x + cy * b.y + cz * b.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height_mask = COLOR.b;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 col = triplanar_col(albedo_tex, world_pos, n);
	float h = clamp(height_mask, 0.0, 1.0);
	// Dark olive bases, quieter crown. Keep the pillow value, drop the lime.
	vec3 base_mul = vec3(0.10, 0.24, 0.09);
	vec3 top_mul = vec3(0.50, 0.58, 0.32);
	col *= mix(base_mul, top_mul, mix(0.38, 1.0, h));
	col = mix(col, vec3(0.34, 0.42, 0.18), h * h * 0.10);
	vec3 nn = triplanar_col(nrm_tex, world_pos, n) * 2.0 - 1.0;
	NORMAL = normalize(n + vec3(nn.x, nn.y, 0.0) * nrm_strength);
	ALBEDO = col;
	ROUGHNESS = 0.84;
	SPECULAR = 0.14;
	BACKLIGHT = vec3(0.12, 0.20, 0.08);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2) * 0.05;
	float top = smoothstep(0.6, 1.0, NORMAL.y);
	EMISSION = vec3(0.62, 0.58, 0.42) * rim * (1.0 + top * 0.4);
}

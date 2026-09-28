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
	vec3 base_mul = vec3(0.043, 0.365, 0.071);
	col *= mix(base_mul, vec3(1.0), mix(0.55, 1.0, h));
	col = mix(col, vec3(0.435, 0.800, 0.220), h * h * 0.16);
	vec3 nn = triplanar_col(nrm_tex, world_pos, n) * 2.0 - 1.0;
	NORMAL = normalize(n + vec3(nn.x, nn.y, 0.0) * nrm_strength);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.18;
	BACKLIGHT = vec3(0.19, 0.31, 0.08);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2) * 0.08;
	float top = smoothstep(0.6, 1.0, NORMAL.y);
	EMISSION = vec3(0.808, 0.898, 0.992) * rim * (1.0 + top);
}

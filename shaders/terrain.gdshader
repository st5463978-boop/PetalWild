shader_type spatial;
render_mode cull_back;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clover_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D flagstone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D splat_tex : source_color, filter_linear;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D flag_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 splat_origin_size = vec4(-13.6, -9.9, 26.4, 17.8);

varying vec3 world_pos;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec2 uv_g = uv / 2.0;
	vec3 grass_a = texture(grass_tex, uv_g).rgb;
	vec2 uv_b = vec2(uv_g.x * 0.7986 - uv_g.y * 0.6018, uv_g.x * 0.6018 + uv_g.y * 0.7986) * 0.37;
	vec3 grass_b = texture(grass_tex, uv_b).rgb;
	vec3 grass = mix(grass_a, grass_b, 0.5);
	float clover_m = step(0.75, vnoise(uv / 3.0));
	grass = mix(grass, texture(clover_tex, uv / 2.0).rgb, clover_m * 0.28);
	float macro = mix(0.94, 1.06, vnoise(uv / 5.4));
	grass *= macro;
	vec2 splat_uv = (uv - splat_origin_size.xy) / splat_origin_size.zw;
	vec3 splat = texture(splat_tex, splat_uv).rgb;
	vec3 flag = texture(flagstone_tex, uv / 1.5).rgb * vec3(0.78, 0.74, 0.68);
	vec3 dirt = texture(dirt_tex, uv / 2.0).rgb;
	vec3 grav = texture(gravel_tex, uv).rgb * vec3(0.86, 0.82, 0.74);
	float luma = dot(flag, vec3(0.3, 0.5, 0.2));
	float moss_amt = (1.0 - smoothstep(0.35, 0.55, luma)) * splat.r;
	flag = mix(flag, vec3(0.45, 0.45, 0.27), moss_amt * 0.45);
	vec3 col = grass;
	col = mix(col, flag, clamp(splat.r, 0.0, 1.0));
	col = mix(col, dirt, clamp(splat.g, 0.0, 1.0));
	col = mix(col, grav, clamp(splat.b, 0.0, 1.0));
	vec3 gn = texture(grass_nrm, uv_g).rgb * 2.0 - 1.0;
	vec3 fn = texture(flag_nrm, uv / 1.5).rgb * 2.0 - 1.0;
	vec3 nrm = mix(gn, fn, splat.r);
	nrm = mix(nrm, vec3(0.0, 0.0, 1.0), splat.g);
	NORMAL_MAP = nrm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.3, 0.55, splat.r);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.75, splat.r);
	SPECULAR = 0.25;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4) * 0.02;
	EMISSION = vec3(0.72, 0.62, 0.48) * rim;
}

shader_type spatial;
render_mode cull_back;

uniform sampler2D soil_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mulch_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tilled_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cell_state : filter_nearest;
uniform vec2 plot_origin = vec2(-7.4, -5.4);
uniform vec2 plot_size = vec2(4.6, 3.44);
uniform vec2 cells = vec2(5.0, 4.0);
uniform float cell_w = 0.92;
uniform float cell_d = 0.86;

varying vec3 world_pos;
varying vec2 local_xz;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_xz = world_pos.xz - plot_origin;
	vec2 cell_uv = clamp(local_xz / plot_size, vec2(0.0), vec2(0.999));
	vec4 st = texture(cell_state, cell_uv);
	float tri = abs(fract(local_xz.y / 0.3) * 2.0 - 1.0);
	// ponytail: 5 cm ridges plus a full tilled normal read as a pale slab under this sun.
	VERTEX.y += st.r * 0.018 * tri;
}

void fragment() {
	float lip = COLOR.g;
	vec3 soil = texture(soil_tex, world_pos.xz).rgb;
	vec3 mulch = texture(mulch_tex, world_pos.xz / 0.6).rgb;
	vec2 cell_uv = clamp(local_xz / plot_size, vec2(0.0), vec2(0.999));
	vec4 st = texture(cell_state, cell_uv);
	vec3 soil_n = texture(soil_nrm, world_pos.xz).rgb;
	vec3 till_n = texture(tilled_nrm, world_pos.xz).rgb;
	vec3 nrm = mix(soil_n, mix(soil_n, till_n, 0.35), st.r);
	vec3 col = mix(soil, mulch, lip);
	col *= mix(1.0, 0.82, st.g);
	vec2 cell_frac = fract(local_xz / vec2(cell_w, cell_d));
	float seam = 1.0 - smoothstep(0.0, 0.015 / cell_w, min(min(cell_frac.x, 1.0 - cell_frac.x), min(cell_frac.y, 1.0 - cell_frac.y)));
	if (lip < 0.5) {
		col *= mix(1.0, 0.6, seam);
	}
	col *= mix(0.55, 1.0, COLOR.r);
	ALBEDO = col;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = mix(0.7, 0.45, st.r);
	ROUGHNESS = mix(mix(0.92, 0.78, st.g), 0.85, lip);
	SPECULAR = mix(0.12, 0.22, lip);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4) * 0.04;
	EMISSION = vec3(0.89, 0.78, 0.48) * rim;
}

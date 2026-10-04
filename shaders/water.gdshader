shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

varying vec3 world_pos;

void vertex() {
	vec3 p = VERTEX;
	float wave = sin(p.x * 1.6 + TIME * 1.35) * 0.018 + cos(p.z * 2.0 + TIME * 1.05) * 0.014;
	p.y += wave;
	VERTEX = p;
	world_pos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	vec2 center = vec2(8.0, -2.5);
	float dist = distance(world_pos.xz, center);
	float depth = smoothstep(0.35, 3.5, dist);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	vec3 deep = vec3(0.03, 0.15, 0.17);
	vec3 shoal = vec3(0.2, 0.46, 0.4);
	vec3 lit = vec3(0.74, 0.9, 0.74);
	vec3 col = mix(deep, shoal, depth);
	col = mix(col, lit, fres * 0.35);
	float spark = smoothstep(0.96, 1.0, sin(world_pos.x * 9.0 + TIME * 1.7) * sin(world_pos.z * 7.0 - TIME * 1.2));
	ALBEDO = col;
	ROUGHNESS = mix(0.38, 0.5, depth);
	SPECULAR = 0.28;
	EMISSION = vec3(0.9, 0.84, 0.6) * spark * 0.08 + lit * fres * 0.04;
	ALPHA = mix(0.9, 0.82, fres);
}

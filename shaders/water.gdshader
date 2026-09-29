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
	// High cameras barely catch the rim, so the bowl itself has to read as water.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	vec3 deep = vec3(0.10, 0.42, 0.50);
	vec3 lit = vec3(0.58, 0.84, 0.78);
	vec3 col = mix(deep, lit, 0.4 + fres * 0.55);
	float spark = smoothstep(0.94, 1.0, sin(world_pos.x * 6.0 + TIME * 1.6) * sin(world_pos.z * 4.8 - TIME * 1.2));
	ALBEDO = col;
	ROUGHNESS = 0.16;
	SPECULAR = 0.42;
	EMISSION = vec3(0.72, 0.9, 0.82) * spark * 0.22;
	ALPHA = 0.92;
}

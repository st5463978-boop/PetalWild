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
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.1);
	vec3 deep = vec3(0.07, 0.28, 0.27);
	vec3 lit = vec3(0.62, 0.84, 0.68);
	vec3 col = mix(deep, lit, fres);
	float spark = smoothstep(0.93, 1.0, sin(world_pos.x * 7.0 + TIME * 2.0) * sin(world_pos.z * 5.5 - TIME * 1.4));
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.55;
	EMISSION = vec3(0.95, 0.82, 0.5) * spark * 0.4 + vec3(0.35, 0.7, 0.55) * fres * 0.1;
	ALPHA = 0.86;
}

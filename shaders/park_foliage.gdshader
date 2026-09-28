shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float sway = 0.14;
uniform float speed = 1.55;
uniform vec3 backlight : source_color = vec3(0.51, 0.66, 0.20);
uniform float wrap = 0.32;

varying float tip;
varying vec3 world_pos;

void vertex() {
	tip = COLOR.a;
	float phase = INSTANCE_CUSTOM.x * 6.2831 + NODE_POSITION_WORLD.x * 0.37 + NODE_POSITION_WORLD.z * 0.21;
	vec3 p = VERTEX;
	p.x += sin(TIME * speed + phase) * sway * tip;
	p.z += cos(TIME * speed * 0.78 + phase) * sway * 0.45 * tip;
	VERTEX = p;
	world_pos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	float ndl = clamp(dot(NORMAL, vec3(0.2, 0.92, 0.18)) + wrap, 0.0, 1.0);
	ALBEDO = col * (0.55 + 0.45 * ndl);
	ROUGHNESS = 0.72;
	SPECULAR = 0.22;
	float back = pow(clamp(1.0 - abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.4);
	EMISSION = backlight * back * 0.22 + col * 0.04;
}

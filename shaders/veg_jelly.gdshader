shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.96, 0.38, 0.07, 1.0);
uniform vec4 shallow_color : source_color = vec4(1.0, 0.74, 0.38, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.92, 0.70, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform float rim_power = 2.1;
uniform float transmission = 0.32;
uniform float glow = 0.22;
uniform float wobble_amount = 0.012;
uniform vec3 move_velocity = vec3(0.0);
uniform float jiggle_scale = 0.012;

void vertex() {
	float speed = min(length(move_velocity), 2.4);
	float idle = sin(TIME * 2.6 + VERTEX.y * 6.0 + VERTEX.x * 3.0);
	float jiggle = sin(TIME * 7.0 + VERTEX.y * 8.0);
	vec3 lag = vec3(-move_velocity.x, speed * 0.08, -move_velocity.z) * jiggle_scale;
	float height = clamp(VERTEX.y * 0.55, 0.0, 0.7);
	VERTEX += NORMAL * idle * wobble_amount * (0.25 + height);
	VERTEX += lag * jiggle * height;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	float backlit = pow(clamp(-dot(NORMAL, VIEW), 0.0, 1.0), 1.35);
	float height = clamp(VERTEX.y * 0.7 + 0.2, 0.0, 1.0);
	vec3 tex = texture(albedo_tex, UV).rgb;
	vec3 body = mix(deep_color.rgb, shallow_color.rgb, height * 0.5 + rim * 0.4);
	body *= tex;
	ALBEDO = body;
	ROUGHNESS = mix(0.28, 0.07, rim);
	SPECULAR = 0.55;
	METALLIC = 0.0;
	EMISSION = rim_color.rgb * rim * glow + shallow_color.rgb * backlit * transmission + body * 0.06;
	ALPHA = mix(0.86, 0.96, facing);
}

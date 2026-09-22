shader_type canvas_item;

void fragment() {
	vec2 uv = UV;
	vec3 zenith = vec3(0.42, 0.66, 0.78);
	vec3 horizon = vec3(0.97, 0.78, 0.55);
	vec3 sky = mix(horizon, zenith, smoothstep(0.05, 0.72, uv.y));
	float sun = smoothstep(0.22, 0.0, length(uv - vec2(0.74, 0.62)));
	sky = mix(sky, vec3(1.0, 0.95, 0.82), sun);
	float hedge = 0.30 + sin(uv.x * 26.0) * 0.012 + sin(uv.x * 8.0) * 0.028;
	float hedge_mask = smoothstep(hedge, hedge - 0.015, uv.y);
	float gate = smoothstep(0.18, 0.0, abs(uv.x - 0.5));
	hedge_mask *= 1.0 - gate * smoothstep(0.22, 0.34, uv.y);
	vec3 leaf = vec3(0.09, 0.28, 0.13);
	vec3 ground = vec3(0.24, 0.42, 0.18);
	float ground_mask = smoothstep(0.34, 0.28, uv.y);
	vec3 col = mix(sky, ground, ground_mask);
	col = mix(col, leaf, hedge_mask);
	COLOR = vec4(col, 1.0);
}

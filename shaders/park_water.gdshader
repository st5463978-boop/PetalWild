shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// v1 sheet from docs/water/WATER_PLAN.md: low roughness, dual normals, emissive glints, Fresnel sky.
// The painted bed is a separate mesh. Environment SSR stays off.
uniform vec3 shallow_tint : source_color = vec3(0.42, 0.62, 0.48);
uniform vec3 sky_tint : source_color = vec3(0.96, 0.72, 0.38);
uniform float fresnel_power = 3.6;
uniform float normal_strength = 0.34;
uniform float sparkle_power = 96.0;
uniform float sparkle_intensity = 3.2;
uniform vec3 sun_dir_world = vec3(0.42, 0.48, 0.28);

varying vec3 world_pos;

void vertex() {
	vec3 p = VERTEX;
	p.y += sin(p.x * 1.7 + TIME * 0.85) * 0.004 + cos(p.z * 2.1 + TIME * 0.65) * 0.0035;
	VERTEX = p;
	world_pos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	vec2 uv_a = world_pos.xz * 0.55 + vec2(TIME * 0.028, TIME * 0.016);
	vec2 uv_b = world_pos.xz * 0.91 + vec2(-TIME * 0.02, TIME * 0.033);
	float n1 = sin(uv_a.x * 8.0) * cos(uv_a.y * 6.4);
	float n2 = sin(uv_b.x * 12.0 + uv_b.y * 5.0);
	vec3 map_n = normalize(vec3(n1 * normal_strength, n2 * normal_strength, 1.0));
	NORMAL = normalize(TANGENT * map_n.x + BINORMAL * map_n.y + NORMAL * map_n.z);

	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 l_world = normalize(sun_dir_world);
	vec3 h_world = normalize(l_world + v_world);
	float ndv = clamp(dot(n_world, v_world), 0.0, 1.0);
	float fres = pow(1.0 - ndv, fresnel_power);
	float spec = pow(clamp(dot(n_world, h_world), 0.0, 1.0), sparkle_power);
	float mask = sin(world_pos.x * 18.0 + TIME * 1.4) * sin(world_pos.z * 15.0 - TIME * 1.1);
	float glint = spec * smoothstep(0.86, 0.995, mask);

	ALBEDO = mix(shallow_tint, sky_tint, fres);
	ROUGHNESS = mix(0.04, 0.18, 1.0 - fres);
	SPECULAR = 0.9;
	METALLIC = 0.0;
	EMISSION = vec3(1.0, 0.95, 0.7) * glint * sparkle_intensity;
	ALPHA = mix(0.04, 0.66, fres);
}

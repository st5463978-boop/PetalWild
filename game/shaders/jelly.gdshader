shader_type spatial;

uniform vec4 deep_color : source_color = vec4(0.2, 0.55, 0.25, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.85, 0.95, 0.45, 1.0);
uniform float impact = 0.0;
uniform float wobble = 0.035;

void vertex() {
	float wave = sin(TIME * 3.4 + VERTEX.y * 9.0 + VERTEX.x * 4.0) * wobble;
	float squash = impact * 0.16;
	VERTEX += NORMAL * wave;
	VERTEX.y -= squash;
	VERTEX.x *= 1.0 + squash;
	VERTEX.z *= 1.0 + squash;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.7);
	vec3 body = mix(deep_color.rgb, shallow_color.rgb, fres);
	ALBEDO = body;
	ROUGHNESS = mix(0.48, 0.1, fres);
	EMISSION = body * fres * 0.18;
}

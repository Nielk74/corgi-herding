shader_type spatial;
render_mode cull_disabled;

uniform float wind_strength : hint_range(0.0, 1.0) = 0.35;

void vertex() {
	// Per-instance phase, coherent broad gusts, and a pinned root. One GPU
	// material animates the patches; no per-blade process callback or timer.
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float tip = clamp(VERTEX.y / 0.28, 0.0, 1.0);
	float gust = sin(TIME * 1.35 + base.x * 0.10 + base.z * 0.07);
	float flutter = sin(TIME * 2.3 + INSTANCE_CUSTOM.x) * 0.2;
	VERTEX.x += (gust + flutter) * tip * tip * 0.10 * wind_strength;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.96;
}

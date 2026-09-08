shader_type spatial;
render_mode cull_disabled, shadows_disabled, diffuse_burley, specular_disabled;

// One opaque pass over the existing, triangle-clipped lake. These slow changes
// suggest a little wind on the surface; there are no reflections or extra layers.
uniform float ripple_strength : hint_range(0.0, 0.025) = 0.018;
varying vec2 water_position;

void vertex() {
	water_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

vec3 linear_color(vec3 color) {
	return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)),
		step(vec3(0.04045), color));
}

void fragment() {
	vec2 p = water_position;
	float first = dot(p, vec2(0.31, 2.35)) - TIME * 0.36 + sin(p.x * 0.13) * 0.65;
	float second = dot(p, vec2(-0.47, 1.57)) + TIME * 0.19;
	float ripple = sin(first) * 0.65 + sin(second) * 0.35;
	// The existing water vertices encode sandy shallows. Keep their edge calm
	// and let the tiny modulation appear only as the water becomes deeper blue.
	float depth_weight = smoothstep(0.055, 0.20, COLOR.b - COLOR.r);
	vec3 color = COLOR.rgb * (1.0 + ripple * ripple_strength * depth_weight);
	// Compatibility converts final albedo itself; linear renderers do not.
	ALBEDO = OUTPUT_IS_SRGB ? color : linear_color(color);
	vec3 world_normal = normalize(vec3(cos(second) * 0.003, 1.0,
		cos(first) * 0.018 + cos(second) * 0.005));
	world_normal = normalize(mix(vec3(0.0, 1.0, 0.0), world_normal, depth_weight));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

// Two world-space quads suggest scattered sunlight. Ordinary depth testing
// hides them behind terrain; there is no ray march or volumetric light solver.
uniform vec4 shaft_color : source_color = vec4(1.0, 0.90, 0.72, 1.0);
uniform float opacity : hint_range(0.0, 0.15) = 0.04;

void fragment() {
	float lateral = abs(UV.x - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.12, 1.0, lateral);
	float ends = smoothstep(0.0, 0.22, UV.y) * (1.0 - smoothstep(0.70, 1.0, UV.y));
	float drift = 0.94 + 0.06 * sin(TIME * 0.35 + UV.y * 2.0);
	ALBEDO = shaft_color.rgb;
	ALPHA = edge * edge * ends * opacity * drift;
}

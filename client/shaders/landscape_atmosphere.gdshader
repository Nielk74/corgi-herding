shader_type spatial;
// Private visual study. One screen pass, no radiance-cubemap updates or depth writes.
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D screen_color : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform bool clouds_enabled = false;
uniform bool blur_enabled = false;
uniform float drift_time = 0.0;
uniform float desert_warmth = 0.0;
uniform float cloud_scale = 1.7;
uniform vec4 actor_rects[14];
uniform int actor_count = 0;
uniform float blur_radius_pixels : hint_range(0.0, 2.0) = 1.35;

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec4 h = fract(sin(vec4(dot(cell, vec2(127.1, 311.7)),
		dot(cell + vec2(1.0, 0.0), vec2(127.1, 311.7)),
		dot(cell + vec2(0.0, 1.0), vec2(127.1, 311.7)),
		dot(cell + vec2(1.0), vec2(127.1, 311.7)))) * 43758.5453);
	return mix(mix(h.x, h.y, f.x), mix(h.z, h.w, f.x), f.y);
}

float cloud_field(vec2 p) {
	float result = 0.0;
	float weight = 0.5333333;
	for (int i = 0; i < 4; i++) {
		result += value_noise(p) * weight;
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(13.2, 7.1);
		weight *= 0.5;
	}
	return result;
}

vec3 view_position(vec2 uv, float depth, mat4 inverse_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

bool protected_pixel(vec2 uv) {
	for (int i = 0; i < 14; i++) {
		if (i >= actor_count) { break; }
		vec4 r = actor_rects[i];
		if (uv.x >= r.x && uv.y >= r.y && uv.x <= r.z && uv.y <= r.w) { return true; }
	}
	return false;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float depth = textureLod(scene_depth, uv, 0.0).r;
	vec3 view = view_position(uv, depth, INV_PROJECTION_MATRIX);
	float distance = -view.z;
	// Also protect anti-aliased animal/sky edges whose resolved depth is sky.
	if (protected_pixel(uv)) { discard; }
	bool sky_pixel = depth < 0.0000001;
	if (sky_pixel && clouds_enabled) {
		// MSAA's resolved depth may choose sky at the edge of an opaque pine
		// or ridge. Leave a tiny neighborhood untouched, including the original
		// per-sample coverage, instead of painting cloud color over that edge.
		vec2 pixel = 1.5 / VIEWPORT_SIZE;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				if (x == 0 && y == 0) { continue; }
				vec2 neighbor = clamp(uv + vec2(float(x), float(y)) * pixel, vec2(0.0), vec2(1.0));
				if (textureLod(scene_depth, neighbor, 0.0).r >= 0.0000001) { discard; }
			}
		}
	}
	bool soft_pixel = blur_enabled && distance > 110.0;
	// Leave protected/near MSAA samples untouched, rather than replacing them
	// with a resolved color copy that would alter sharp silhouette edges.
	if (!(clouds_enabled && sky_pixel) && !soft_pixel) { discard; }
	vec3 original = textureLod(screen_color, uv, 0.0).rgb;
	vec3 color = original;
	// Only distant scenery. Reject samples across foreground/depth boundaries,
	// and conservatively protect every projected animal/herder silhouette.
	if (soft_pixel) {
		float amount = smoothstep(110.0, 240.0, distance);
		vec2 pixel = 1.0 / VIEWPORT_SIZE;
		vec3 sum = original * 4.0;
		float weights = 4.0;
		for (int i = 0; i < 4; i++) {
			vec2 direction = i == 0 ? vec2(1.0, 0.0) : (i == 1 ? vec2(-1.0, 0.0) : (i == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
			vec2 sample_uv = clamp(uv + direction * pixel * min(blur_radius_pixels, 2.0) * amount, pixel * 0.5, vec2(1.0) - pixel * 0.5);
			float sample_depth = textureLod(scene_depth, sample_uv, 0.0).r;
			float sample_distance = -view_position(sample_uv, sample_depth, INV_PROJECTION_MATRIX).z;
			if (sample_distance > 110.0 && abs(sample_distance - distance) < max(8.0, distance * 0.08) && !protected_pixel(sample_uv)) {
				sum += textureLod(screen_color, sample_uv, 0.0).rgb;
				weights += 1.0;
			}
		}
		color = mix(original, sum / weights, amount * 0.7);
	}
	// Clouds decorate only pixels with no geometry. The existing sky still
	// supplies stable ambient lighting; clouds cannot repaint mountains/actors.
	if (clouds_enabled && sky_pixel) {
		vec3 direction = normalize(mat3(INV_VIEW_MATRIX) * view);
		float above_horizon = smoothstep(0.025, 0.13, direction.y);
		vec2 plane = direction.xz / max(direction.y + 0.12, 0.13);
		vec2 travel = vec2(drift_time * 0.003, drift_time * 0.0008);
		float cloud = cloud_field(plane * cloud_scale + vec2(4.7, 8.3) + travel);
		float veil = smoothstep(0.50, 0.66, cloud) * above_horizon * 0.98;
		vec3 horizon = mix(vec3(0.79, 0.84, 0.86), vec3(0.91, 0.81, 0.68), desert_warmth);
		float glow = pow(1.0 - clamp(direction.y * 2.1, 0.0, 1.0), 3.0) * 0.38;
		color = mix(color, horizon, glow);
		vec3 shade = mix(vec3(0.68, 0.75, 0.79), vec3(0.80, 0.76, 0.70), desert_warmth);
		vec3 lit = mix(vec3(0.96, 0.96, 0.92), vec3(1.0, 0.93, 0.81), desert_warmth);
		vec3 cloud_color = mix(shade, lit, smoothstep(0.47, 0.73, cloud));
		color = mix(color, cloud_color, veil);
	}
	ALBEDO = color;
	ALPHA = 1.0;
}

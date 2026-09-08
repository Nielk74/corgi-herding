shader_type spatial;
// Studio surface experiment: real CC0 albedo/normal/roughness data and raster
// sunlight. No baked GI, displacement, screen-space reflection or ray tracing.
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_roughness : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap, repeat_enable;
uniform vec3 ground_tint : source_color = vec3(0.78, 1.0, 0.72);
uniform vec3 stone_tint : source_color = vec3(0.88, 0.91, 0.93);
uniform bool snow_enabled = true;
varying vec3 world_position;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float soft_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x), mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), f.x), f.y);
}
vec3 triplanar_color(sampler2D source, vec3 p, vec3 weights) {
	return texture(source, p.zy).rgb * weights.x + texture(source, p.xz).rgb * weights.y + texture(source, p.xy).rgb * weights.z;
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec3 n = normalize(world_normal);
	vec3 weights = pow(abs(n), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	vec2 p = world_position.xz;
	vec2 rotated = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
	float macro = soft_noise(p * 0.025);
	vec3 grass = mix(texture(ground_albedo, p * 0.24).rgb, texture(ground_albedo, rotated * 0.071 + vec2(11.3, 7.8)).rgb, 0.42);
	grass *= ground_tint * mix(0.83, 1.12, macro);
	vec3 stone = triplanar_color(rock_albedo, world_position * 0.15, weights) * stone_tint;
	float rock = smoothstep(0.15, 0.42, 1.0 - n.y + (macro - 0.5) * 0.08);
	// The alpine vegetation line follows elevation and broken local exposure,
	// rather than leaving bright grass on every upward-facing summit triangle.
	float alpine_rock = snow_enabled ? smoothstep(42.0, 66.0, world_position.y + macro * 12.0) : 0.0;
	rock = max(rock, alpine_rock);
	ALBEDO = mix(grass, stone, rock);
	float wear = clamp(1.0 - COLOR.a, 0.0, 1.0);
	vec3 tread = mix(vec3(0.28, 0.23, 0.16), stone * vec3(0.75, 0.68, 0.55), 0.55);
	ALBEDO = mix(ALBEDO, tread * mix(0.91, 1.06, macro), wear * 0.84);
	float grass_rough = texture(ground_roughness, p * 0.24).r;
	float stone_rough = triplanar_color(rock_roughness, world_position * 0.15, weights).r;
	ROUGHNESS = clamp(mix(grass_rough, stone_rough, rock), 0.68, 1.0);
	// Height-independent tangent perturbations keep the sampled mesh silhouette
	// and picking untouched. Rock detail uses the dominant world-plane axes.
	vec2 grass_bump = texture(ground_normal, p * 0.24).rg * 2.0 - 1.0;
	vec2 bx = texture(rock_normal, world_position.zy * 0.15).rg * 2.0 - 1.0;
	vec2 by = texture(rock_normal, world_position.xz * 0.15).rg * 2.0 - 1.0;
	vec2 bz = texture(rock_normal, world_position.xy * 0.15).rg * 2.0 - 1.0;
	vec3 rock_bump = vec3(0.0, bx.y, bx.x) * weights.x + vec3(by.x, 0.0, by.y) * weights.y + vec3(bz.x, bz.y, 0.0) * weights.z;
	vec3 bump = mix(vec3(grass_bump.x, 0.0, grass_bump.y), rock_bump, rock) * 0.22;
	bump -= n * dot(bump, n);
	float snow_breakup = soft_noise(p * 0.095 + vec2(21.7, 4.3));
	float snow = snow_enabled ? smoothstep(63.0, 85.0, world_position.y + macro * 12.0 + snow_breakup * 5.0) * smoothstep(0.26, 0.66, n.y) : 0.0;
	ALBEDO = mix(ALBEDO, vec3(0.63, 0.69, 0.71) * mix(0.94, 1.0, snow_breakup), snow);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + bump * (1.0 - snow * 0.7)), 0.0)).xyz);
	SPECULAR = 0.25;
}

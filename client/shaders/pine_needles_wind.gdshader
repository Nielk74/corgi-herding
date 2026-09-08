shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Standalone candidate: no caller/cooked material is changed automatically.
// COLOR already includes the MultiMesh instance tint. This conversion matches
// Godot 4.6 StandardMaterial3D's vertex_color_is_srgb generation.
// https://github.com/godotengine/godot/blob/4.6.3-stable/scene/resources/material.cpp#L1138-L1147
uniform vec4 needle_tint : source_color = vec4(0.3882352941, 0.4784313725, 0.3372549020, 1.0);
uniform float needle_roughness = 0.96;
uniform float needle_specular = 0.5;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wind_time = 0.0;

void vertex() {
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
			COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
	if (wind_strength > 0.0) {
		vec3 direction = vec3(0.8, 0.0, 0.6);
		// Divide by the actual transformed direction length, not an assumed
		// tree scale. Thus horizontal displacement is <= 0.08 world units.
		float direction_scale = length(mat3(MODEL_MATRIX) * direction);
		float phase = dot(MODEL_MATRIX[3].xz, vec2(0.37, 0.19));
		float wave = 0.72 * sin(wind_time * 0.63 + phase)
			+ 0.28 * sin(wind_time * 0.91 + phase * 1.7);
		float u = clamp((VERTEX.y - 1.7) / 3.8, 0.0, 1.0);
		float weight = u * u * (3.0 - 2.0 * u);
		float derivative = 6.0 * u * (1.0 - u) / 3.8;
		if (direction_scale > 0.000001) {
			float shear = 0.08 * clamp(wind_strength, 0.0, 1.0) * wave / direction_scale;
			VERTEX += direction * shear * weight;
			// Inverse-transpose Jacobian for p' = p + direction * f(p.y).
			// direction.y == 0 makes its determinant exactly one.
			NORMAL.y -= dot(NORMAL, direction) * shear * derivative;
			NORMAL = normalize(NORMAL);
		}
	}
}

void fragment() {
	ALBEDO = needle_tint.rgb * COLOR.rgb;
	ROUGHNESS = needle_roughness;
	SPECULAR = needle_specular;
	METALLIC = 0.0;
}

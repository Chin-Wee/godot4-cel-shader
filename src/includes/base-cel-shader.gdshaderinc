global uniform sampler2D diffuse_curve: repeat_disable;
global uniform float specular_smoothness;
global uniform float fresnel_smoothness;
uniform float ndotl_dither_strength: hint_range(0.0, 0.1, 0.001) = 0.03;
varying vec2 NDTL_DITHER_POSITION;

group_uniforms DiffuseRamp;
uniform int diffuse_ramp_mode: hint_enum("Texture", "Two Tone", "Smoothed Two Tone") = 0;
uniform float diffuse_ramp_threshold: hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform float diffuse_ramp_smoothing: hint_range(0.001, 0.5, 0.001) = 0.08;
group_uniforms;

float bayer4x4(vec2 screen_position) {
	int x = int(screen_position.x) % 4;
	int y = int(screen_position.y) % 4;
	int rank = (((x ^ y) & 1) << 3) | ((y & 1) << 2) | ((x ^ y) & 2) | (y >> 1);
	return (float(rank) + 0.5) / 16.0;
}

float diffuse_sample(vec3 light, vec3 normal) {
	float ndotl = dot(light, normal);
	ndotl += (bayer4x4(NDTL_DITHER_POSITION) - 0.5) * ndotl_dither_strength;
	if (diffuse_ramp_mode == 1) {
		return step(diffuse_ramp_threshold, ndotl);
	}
	if (diffuse_ramp_mode == 2) {
		float half_width = diffuse_ramp_smoothing * 0.5;
		return smoothstep(
				diffuse_ramp_threshold - half_width,
				diffuse_ramp_threshold + half_width,
				ndotl
		);
	}
	return texture(diffuse_curve, vec2(ndotl, 0.0)).r;
}

float is_lit(vec3 light, vec3 normal, float attenuation) {
	return attenuation * diffuse_sample(light, normal);
}

vec3 diffuse_light(
		vec3 albedo,
		vec3 light_color,
		vec3 light,
		vec3 normal,
		float attenuation
) {
	return albedo * light_color * is_lit(light, normal, attenuation);
}

vec3 specular_light(
		vec3 light_color,
		vec3 specular_color,
		float specular_strength,
		vec3 normal,
		vec3 view,
		vec3 light,
		float attenuation
) {
	vec3 half = normalize(view + light);
	float gloss = pow(2.0, 8.0 * (1.0 - specular_strength));
	float intensity = pow(dot(normal, half), gloss * gloss);
	return light_color
			* specular_color
			* is_lit(light, normal, attenuation)
			* smoothstep(
					0.05,
					0.05 + specular_smoothness,
					intensity
			);
}

vec3 fresnel_light(
		vec3 light_color,
		vec3 fresnel_color,
		float fresnel_strength,
		vec3 normal,
		vec3 view,
		vec3 light,
		float attenuation
) {
	float fresnel_dot = 1.0 - dot(normal, view);
	float fresnel_threshold = pow((1.0 - fresnel_strength), dot(light, normal));
	return light_color
			* fresnel_color
			* is_lit(light, normal, attenuation)
			* smoothstep(
					fresnel_threshold - fresnel_smoothness / 2.0,
					fresnel_threshold + fresnel_smoothness / 2.0,
					fresnel_dot
			);
}

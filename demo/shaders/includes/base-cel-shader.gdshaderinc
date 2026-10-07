global uniform sampler2D diffuse_curve: repeat_disable;

 float diffuse_sample(vec3 light, vec3 normal) {
	return texture(diffuse_curve, vec2(dot(light, normal), 0)
	).r;
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
		float specular_exponent,
		float specular_smoothness,
		vec3 normal,
		vec3 view,
		vec3 light,
		float attenuation
) {
	vec3 half = normalize(view + light);
	float intensity = pow(max(dot(normal, half), 0.0), specular_exponent);
	return light_color
			* specular_color
			* specular_strength
			* is_lit(light, normal, attenuation)
			* smoothstep(
					0.05,
					0.05 + specular_smoothness,
					intensity
			);
}

float fresnel_factor(vec3 normal, vec3 view, float power) {
	return pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), power);
}

shader_type spatial;
render_mode cull_disabled;

#include "includes/base-cel-shader.gdshaderinc"

uniform float wind_speed = 0.05;
uniform float wind_strength = 2.0;
// How big, in world space, is the noise texture
// wind will tile every wind_texture_tile_size
uniform float wind_texture_tile_size = 20.0;
uniform float wind_vertical_strength = 0.3;
uniform vec2 wind_horizontal_direction = vec2(1.0, 0.5);

uniform sampler2D color_ramp : source_color;
// we need a tiling noise here!
uniform sampler2D wind_noise : hint_default_black;

uniform vec3 character_position;
uniform float character_radius = 3.0;
uniform sampler2D character_distance_falloff_curve : hint_default_black;
uniform float character_push_strength = 1.0;

varying float debug_wind;

void vertex() {
	vec3 world_vert = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec2 normalized_wind_direction = normalize(wind_horizontal_direction);
	vec2 world_uv = world_vert.xz / wind_texture_tile_size + normalized_wind_direction * TIME * wind_speed;
	// we displace only the top part of the mesh
	// note that this means that the mesh needs to have UV in a way that the bottom of UV space
	// is at the top of the mesh
	float displacement_affect = (1.0 - UV.y);
	float wind_noise_intensity = (textureLod(wind_noise, world_uv, 0.0).r - 0.5);

	// We convert the direction of the wind into vertex space from world space
	// if we used it directly in vertex space, rotated blades of grass wouldn't behave properly
	vec2 vert_space_horizontal_dir =
			(inverse(MODEL_MATRIX) * vec4(wind_horizontal_direction, 0.0, 0.0)).xy;

	vert_space_horizontal_dir = normalize(vert_space_horizontal_dir);

	vec3 bump_wind = vec3(
		wind_noise_intensity * vert_space_horizontal_dir.x,
		1.0 - wind_noise_intensity,
		wind_noise_intensity * vert_space_horizontal_dir.y);

	bump_wind = normalize(bump_wind);

	bump_wind *= vec3(wind_strength, wind_vertical_strength, wind_strength);

	VERTEX += bump_wind * displacement_affect;

	// BOTW-style proximity bending: one moving character field, evaluated on the GPU.
	vec3 dir_to_character = character_position - MODEL_MATRIX[3].xyz;
	float distance_to_character = length(dir_to_character);
	float falloff = 1.0 - smoothstep(0.0, max(character_radius, 0.001), distance_to_character);
	dir_to_character.y = 0.0;
	vec3 push_direction = -dir_to_character / max(length(dir_to_character), 0.001);
	float falloff_curve = textureLod(character_distance_falloff_curve, vec2(falloff), 0.0).x;
	vec3 world_push = push_direction * falloff_curve * character_push_strength;
	// Keep bend distance in world units across differently scaled and rotated blades.
	VERTEX += (inverse(MODEL_MATRIX) * vec4(world_push, 0.0)).xyz * displacement_affect;

}

void fragment() {
	NDTL_DITHER_POSITION = FRAGCOORD.xy;
	ALBEDO = texture(color_ramp, vec2(1.0 - UV.y, 0)).rgb ;
}

void light() {
	DIFFUSE_LIGHT += diffuse_light(ALBEDO, LIGHT_COLOR, LIGHT, NORMAL, ATTENUATION);
}

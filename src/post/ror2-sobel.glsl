#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;
layout(set = 0, binding = 2) uniform sampler2D normal_texture;

layout(push_constant, std430) uniform Params {
	vec4 edge_settings; // threshold, depth weight, normal weight, pixel radius
	vec4 screen_size; // width, height, padding, padding
	vec4 outline_color;
} params;

float sample_depth(ivec2 pixel, ivec2 size) {
	return texelFetch(depth_texture, clamp(pixel, ivec2(0), size - 1), 0).r;
}

vec3 sample_normal(ivec2 pixel, ivec2 size) {
	// Forward+ uses a best-fit encoding; decode and normalize as in Godot's compatibility conversion.
	vec3 decoded_normal = texelFetch(normal_texture, clamp(pixel, ivec2(0), size - 1), 0).rgb * 2.0 - 1.0;
	float normal_length_squared = dot(decoded_normal, decoded_normal);
	return normal_length_squared > 0.000001 ? decoded_normal * inversesqrt(normal_length_squared) : vec3(0.0);
}

float depth_sobel(ivec2 pixel, ivec2 size, int radius) {
	ivec2 left = ivec2(-radius, 0);
	ivec2 right = ivec2(radius, 0);
	ivec2 top = ivec2(0, -radius);
	ivec2 bottom = ivec2(0, radius);
	ivec2 top_left = ivec2(-radius, -radius);
	ivec2 top_right = ivec2(radius, -radius);
	ivec2 bottom_left = ivec2(-radius, radius);
	ivec2 bottom_right = ivec2(radius, radius);

	float gx = -sample_depth(pixel + top_left, size) + sample_depth(pixel + top_right, size)
		- 2.0 * sample_depth(pixel + left, size) + 2.0 * sample_depth(pixel + right, size)
		- sample_depth(pixel + bottom_left, size) + sample_depth(pixel + bottom_right, size);
	float gy = -sample_depth(pixel + top_left, size) - 2.0 * sample_depth(pixel + top, size)
		- sample_depth(pixel + top_right, size) + sample_depth(pixel + bottom_left, size)
		+ 2.0 * sample_depth(pixel + bottom, size) + sample_depth(pixel + bottom_right, size);
	return length(vec2(gx, gy)) * 0.25;
}

float normal_sobel(ivec2 pixel, ivec2 size, int radius) {
	ivec2 left = ivec2(-radius, 0);
	ivec2 right = ivec2(radius, 0);
	ivec2 top = ivec2(0, -radius);
	ivec2 bottom = ivec2(0, radius);
	ivec2 top_left = ivec2(-radius, -radius);
	ivec2 top_right = ivec2(radius, -radius);
	ivec2 bottom_left = ivec2(-radius, radius);
	ivec2 bottom_right = ivec2(radius, radius);

	vec3 gx = -sample_normal(pixel + top_left, size) + sample_normal(pixel + top_right, size)
		- 2.0 * sample_normal(pixel + left, size) + 2.0 * sample_normal(pixel + right, size)
		- sample_normal(pixel + bottom_left, size) + sample_normal(pixel + bottom_right, size);
	vec3 gy = -sample_normal(pixel + top_left, size) - 2.0 * sample_normal(pixel + top, size)
		- sample_normal(pixel + top_right, size) + sample_normal(pixel + bottom_left, size)
		+ 2.0 * sample_normal(pixel + bottom, size) + sample_normal(pixel + bottom_right, size);
	return sqrt(dot(gx, gx) + dot(gy, gy)) * 0.25;
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.screen_size.xy);
	if (pixel.x >= size.x || pixel.y >= size.y) {
		return;
	}

	int radius = max(1, int(round(params.edge_settings.w)));
	float depth_edge = depth_sobel(pixel, size, radius) * params.edge_settings.y;
	float normal_edge = normal_sobel(pixel, size, radius) * params.edge_settings.z;
	float edge = step(params.edge_settings.x, depth_edge + normal_edge);

	vec4 color = imageLoad(color_image, pixel);
	color.rgb = mix(color.rgb, params.outline_color.rgb, edge * params.outline_color.a);
	imageStore(color_image, pixel, color);
}

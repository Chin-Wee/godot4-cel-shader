// Shared material implementation for the existing Risk of Rain 2 reference.
// The small .gdshader wrappers select the supported material features.
#if USE_ALPHA
render_mode depth_draw_always;
#endif

#include "base-cel-shader.gdshaderinc"

#if USE_EMISSION
#include "emission.gdshaderinc"
#endif

#if USE_REFLECTIONS
#include "reflections.gdshaderinc"
#endif

#if USE_NORMAL_MAP
#include "normal-map.gdshaderinc"
#endif

#if USE_OCCLUSION
#include "occlusion.gdshaderinc"
#endif

#if USE_HEIGHT_MAP
#include "height-map.gdshaderinc"
#endif

#if USE_ANISOTROPY
#include "anisotropy.gdshaderinc"
#endif

#if USE_BACKLIGHT
#include "backlight.gdshaderinc"
#endif

#if USE_REFRACTION
#include "refraction.gdshaderinc"
#elif !USE_REFRACTION && USE_ALPHA
#include "transparency.gdshaderinc"
#endif

group_uniforms BaseProperties;
#if USE_ALPHA_CUTOFF
uniform float alpha_cutoff: hint_range(0.0, 1.0) = 0.5;
#endif
uniform vec4 color: source_color = vec4(0.7, 0.12, 0.86, 1.0);
uniform sampler2D base_texture: source_color;
#if USE_COLOR_SATURATION
uniform float color_saturation: hint_range(0.0, 1.0) = 0.35;
#endif
#if USE_PAINT_VARIATION
uniform float paint_variation: hint_range(0.0, 0.4) = 0.06;
#endif
uniform vec4 specular: source_color = vec4(0.3, 0.3, 0.3, 0.5);
uniform sampler2D specular_texture: hint_default_white;
uniform float specular_strength: hint_range(0.0, 1.0) = 1.0;
uniform float specular_exponent: hint_range(1.0, 512.0) = 256.0;
uniform float specular_smoothness: hint_range(0.0, 1.0) = 0.05;
uniform vec4 fresnel: source_color = vec4(0.2, 0.2, 0.2, 0.3);
uniform sampler2D fresnel_texture: hint_default_white;
uniform bool enable_fresnel_emission = false;
uniform sampler2D fresnel_ramp: source_color, hint_default_white;
uniform float fresnel_power: hint_range(0.1, 10.0) = 5.0;
uniform float fresnel_boost: hint_range(0.0, 8.0) = 1.0;
group_uniforms;

varying vec3 SPECULAR_COLOR;
varying float SPECULAR_STRENGTH;

varying vec2 base_uv;

group_uniforms Tiling;
uniform vec2 uv_scale = vec2(1,1);
uniform vec2 uv_offset = vec2(0,0);
group_uniforms;

#if USE_PAINT_VARIATION
// ponytail: procedural strokes stay synthetic; use an authored brush map for hand-painted marks.
float paint_hash(vec3 cell) {
	return fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float paint_noise(vec3 position) {
	vec3 cell = floor(position);
	vec3 blend = fract(position);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float x0 = mix(paint_hash(cell), paint_hash(cell + vec3(1.0, 0.0, 0.0)), blend.x);
	float x1 = mix(paint_hash(cell + vec3(0.0, 1.0, 0.0)), paint_hash(cell + vec3(1.0, 1.0, 0.0)), blend.x);
	float x2 = mix(paint_hash(cell + vec3(0.0, 0.0, 1.0)), paint_hash(cell + vec3(1.0, 0.0, 1.0)), blend.x);
	float x3 = mix(paint_hash(cell + vec3(0.0, 1.0, 1.0)), paint_hash(cell + vec3(1.0, 1.0, 1.0)), blend.x);
	return mix(mix(x0, x1, blend.y), mix(x2, x3, blend.y), blend.z);
}
#endif

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
	#if !USE_HEIGHT_MAP
		base_uv = UV;
	#endif
}

void fragment() {
	NDTL_DITHER_POSITION = FRAGCOORD.xy;
#if USE_HEIGHT_MAP
	base_uv = height_map_fragment(UV, VERTEX, TANGENT, BINORMAL, NORMAL);
#endif

#if USE_COLOR_SATURATION
	vec3 albedo = color.rgb * texture(base_texture, base_uv).rgb;
	float luminance = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(vec3(luminance), albedo, color_saturation);
#if USE_PAINT_VARIATION
	if (paint_variation > 0.0) {
		vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 projection_weights = pow(abs(world_normal), vec3(4.0));
		projection_weights /= dot(projection_weights, vec3(1.0));
		float brush_strokes =
				paint_noise(vec3(world_position.zy * vec2(8.0, 1.8), 0.0)) * projection_weights.x +
				paint_noise(vec3(world_position.xz * vec2(8.0, 1.8), 0.0)) * projection_weights.y +
				paint_noise(vec3(world_position.xy * vec2(8.0, 1.8), 0.0)) * projection_weights.z;
		brush_strokes = smoothstep(0.22, 0.78, brush_strokes);
		float pigment = mix(paint_noise(world_position * 1.2), brush_strokes, 0.75);
		float pigment_shift = (pigment - 0.5) * paint_variation * 2.0;
		albedo *= vec3(1.0 + pigment_shift, 1.0 + pigment_shift * 0.35, 1.0 - pigment_shift * 0.25);
	}
#endif
	ALBEDO = albedo;
#endif

#if USE_ALPHA
	float alpha = color.a * texture(base_texture, base_uv).a;
	ALBEDO *= alpha;
#elif USE_ALPHA_CUTOFF
	ALPHA = color.a * texture(base_texture, base_uv).a;
	ALPHA_SCISSOR_THRESHOLD = color.a * texture(base_texture, base_uv).a;
#endif

#if USE_REFRACTION && USE_ALPHA
	EMISSION += refraction_fragment(alpha, NORMAL, SCREEN_UV, FRAGCOORD.z);
#elif !USE_REFRACTION && USE_ALPHA
	EMISSION += transparency_fragment(alpha, SCREEN_UV);
#endif

	SPECULAR_COLOR = specular.rgb * texture(specular_texture, base_uv).rgb;
	SPECULAR_STRENGTH = specular.a * texture(specular_texture, base_uv).a;

#if USE_EMISSION
	EMISSION += emission_fragment(base_uv);
#endif

#if USE_REFLECTIONS
	Surface surf = reflections_fragment(UV);
	METALLIC = surf.metallic;
	ROUGHNESS = surf.roughness;
#endif

#if USE_NORMAL_MAP
	NormalData normal = normal_map_fragment(base_uv, NORMAL, TANGENT, BINORMAL);
	NORMAL = normal.vector;
	NORMAL_MAP = normal.map;
	NORMAL_MAP_DEPTH = normal.depth;
#endif

#if USE_OCCLUSION
	OcclusionData occlusion = occlusion_fragment(base_uv);
	AO = occlusion.ao;
	AO_LIGHT_AFFECT = occlusion.ao_light_affect;
#endif

#if USE_ANISOTROPY
	AnisotropyData aniso = anisotropy_fragment(UV);
	ANISOTROPY_DIR = aniso.direction;
	ANISOTROPY_RATIO = aniso.ratio;
#endif

#if USE_BACKLIGHT
	BACKLIGHT = backlight_fragment(base_uv);
#endif

	if (enable_fresnel_emission) {
		vec4 fresnel_mask = texture(fresnel_texture, base_uv);
		float fresnel_term = fresnel_factor(NORMAL, VIEW, fresnel_power);
		vec3 fresnel_ramp_color = texture(fresnel_ramp, vec2(fresnel_term, 0.0)).rgb;
		EMISSION += fresnel_term * fresnel.rgb * fresnel_mask.rgb * fresnel.a * fresnel_mask.a * fresnel_boost * fresnel_ramp_color;
	}

#if !USE_COLOR_SATURATION
	ALBEDO = color.rgb * texture(base_texture, base_uv).rgb;
#endif
}

void light() {
#if USE_BACKLIGHT
	DIFFUSE_LIGHT += backlight_diffuse(
			ALBEDO,
			LIGHT_COLOR,
			LIGHT,
			NORMAL,
			ATTENUATION,
			BACKLIGHT
	);
#else
	DIFFUSE_LIGHT += diffuse_light(
			ALBEDO,
			LIGHT_COLOR,
			LIGHT,
			NORMAL,
			ATTENUATION
	);
#endif

#if USE_ANISOTROPY
	SPECULAR_LIGHT += anisotropy_specular(
			LIGHT_COLOR,
			SPECULAR_COLOR,
			SPECULAR_STRENGTH * specular_strength,
			specular_exponent,
			specular_smoothness,
			NORMAL,
			VIEW,
			LIGHT,
			ATTENUATION,
			UV,
			ANISOTROPY_DIR,
			ANISOTROPY_RATIO
	);
#else
	SPECULAR_LIGHT += specular_light(
			LIGHT_COLOR,
			SPECULAR_COLOR,
			SPECULAR_STRENGTH * specular_strength,
			specular_exponent,
			specular_smoothness,
			NORMAL,
			VIEW,
			LIGHT,
			ATTENUATION
	);
#endif
}

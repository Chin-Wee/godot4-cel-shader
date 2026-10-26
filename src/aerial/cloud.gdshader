shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
#include "../includes/base-cel-shader.gdshaderinc"
#include "atmosphere.gdshaderinc"
uniform vec4 cloud_light: source_color = vec4(1.0, 0.62, 0.38, 1.0);
uniform vec4 cloud_shadow: source_color = vec4(0.22, 0.17, 0.29, 1.0);
uniform vec4 cloud_transmission: source_color = vec4(1.0, 0.29, 0.065, 1.0);
uniform vec4 cloud_lining: source_color = vec4(1.0, 0.91, 0.66, 1.0);
uniform float cloud_scattering_strength = 1.0;
uniform float cloud_bank_glow_strength = 0.7;
uniform float cloud_edge_strength = 1.0;
uniform float storm = 0.0;
uniform float cloud_shade_noise_scale = 0.009;
uniform float cloud_shade_noise_strength = 0.18;
uniform float cloud_band_smoothing = 0.025;
varying float cloud_shade_variation;
varying float cloud_height;
// DELIVERY MUST COMPLETE is the production visual reference; its cloud source is unpublished.
// Coarse value noise moves the band boundary rather than texturing the lit surface.
float cloud_hash(vec3 cell) {
 return fract(sin(dot(cell,vec3(127.1,311.7,74.7)))*43758.5453);
}
float cloud_shade_noise(vec3 point) {
 vec3 cell = floor(point);
 vec3 f = fract(point);
 f = f*f*(3.0-2.0*f);
 return mix(mix(mix(cloud_hash(cell),cloud_hash(cell+vec3(1,0,0)),f.x),
                mix(cloud_hash(cell+vec3(0,1,0)),cloud_hash(cell+vec3(1,1,0)),f.x),f.y),
            mix(mix(cloud_hash(cell+vec3(0,0,1)),cloud_hash(cell+vec3(1,0,1)),f.x),
                mix(cloud_hash(cell+vec3(0,1,1)),cloud_hash(cell+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() {
 cloud_height = VERTEX.y;
 aerial_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 aerial_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 NDTL_DITHER_POSITION = FRAGCOORD.xy;
 cloud_shade_variation = (cloud_shade_noise(aerial_world_position*cloud_shade_noise_scale)-0.5)*cloud_shade_noise_strength;
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 vec3 world_normal = normalize(aerial_world_normal);
 vec3 sun = aerial_sun_vector();
 vec3 eye_ray = aerial_view_direction(CAMERA_POSITION_WORLD);
 ALBEDO = cloud_light.rgb * (1.0 - haze) * mix(1.0, 0.4, storm);
 EMISSION = (mix(cloud_shadow.rgb, cloud_shadow.rgb * 0.4, storm) * 0.85 + aerial_surface_fill(world_normal)*0.1) * (1.0 - haze) + aerial_haze_tint(CAMERA_POSITION_WORLD) * haze;
 float sun_edge = smoothstep(-0.2,0.6,dot(world_normal,sun));
 float edge = fresnel_factor(NORMAL,VIEW,1.5);
 float crown = smoothstep(-0.15,0.85,cloud_height);
 // A separate broad glow field sits below the sun, rather than following its glare radius.
 vec2 eye_horizontal = eye_ray.xz*inversesqrt(max(dot(eye_ray.xz,eye_ray.xz),0.0001));
 vec2 sun_horizontal = sun.xz*inversesqrt(max(dot(sun.xz,sun.xz),0.0001));
 float bank_glow = pow(max(dot(eye_horizontal,sun_horizontal),0.0),12.0)
                 * exp(-pow((eye_ray.y-(sun.y-0.1))*5.0,2.0));
 float forward_scatter = pow(max(dot(eye_ray,sun),0.0),9.0);
 // ponytail: edge/crown estimate optical thickness; a density volume is needed for physical self-shadowing.
 float optical_thickness = mix(1.9,0.35,edge)*mix(1.2,0.7,crown);
 float transmission = exp(-optical_thickness*1.3);
 vec3 internal_light = mix(cloud_transmission.rgb*0.35,cloud_light.rgb,transmission);
 float scattering = forward_scatter*(0.25+0.75*transmission);
 EMISSION += internal_light*scattering*cloud_scattering_strength*(1.0-storm)*(1.0-haze);
 EMISSION += cloud_transmission.rgb*bank_glow*cloud_bank_glow_strength*(0.28+0.72*transmission)*(1.0-storm)*(1.0-haze);
 float lining = smoothstep(0.45-crown*0.12,0.82-crown*0.05,edge)*sun_edge;
 EMISSION += cloud_lining.rgb*lining*cloud_edge_strength*(0.25+0.75*bank_glow)*(1.0-storm)*(1.0-haze);
}
void light() {
 // Three broad planes share the material family's screen-space Bayer threshold.
 float shade = dot(LIGHT,NORMAL) + cloud_shade_variation
             + (bayer4x4(NDTL_DITHER_POSITION)-0.5)*ndotl_dither_strength;
 float width = max(cloud_band_smoothing,0.001)*0.5;
 float mid = smoothstep(0.05-width,0.05+width,shade);
 float bright = smoothstep(0.55-width,0.55+width,shade);
 DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * (mid*0.28+bright*0.37);
}

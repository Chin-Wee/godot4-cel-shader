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
varying float cloud_height;
void vertex() {
 cloud_height = VERTEX.y;
 aerial_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 aerial_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 NDTL_DITHER_POSITION = FRAGCOORD.xy;
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 vec3 world_normal = normalize(aerial_world_normal);
 vec3 sun = aerial_sun_vector();
 vec3 eye_ray = aerial_view_direction(CAMERA_POSITION_WORLD);
 ALBEDO = cloud_light.rgb * (1.0 - haze) * mix(1.0, 0.4, storm);
 float base_fill = mix(0.65,1.0,smoothstep(-0.35,0.6,cloud_height));
 EMISSION = (mix(cloud_shadow.rgb, cloud_shadow.rgb * 0.4, storm) * base_fill + aerial_surface_fill(world_normal)*0.1) * (1.0 - haze) + aerial_haze_tint(CAMERA_POSITION_WORLD) * haze;
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
 DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * is_lit(LIGHT, NORMAL, ATTENUATION) * 0.65;
}

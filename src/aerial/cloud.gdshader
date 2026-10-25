shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
#include "../includes/base-cel-shader.gdshaderinc"
#include "atmosphere.gdshaderinc"
uniform vec4 cloud_light: source_color = vec4(1.0, 0.62, 0.38, 1.0);
uniform vec4 cloud_shadow: source_color = vec4(0.22, 0.17, 0.29, 1.0);
uniform float storm = 0.0;
uniform vec3 sun_direction = vec3(-0.5,0.22,-0.84);
varying float cloud_height;
void vertex() {
 cloud_height = VERTEX.y;
 aerial_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 aerial_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 NDTL_DITHER_POSITION = FRAGCOORD.xy;
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 ALBEDO = cloud_light.rgb * (1.0 - haze) * mix(1.0, 0.4, storm);
 float base_fill = mix(0.65,1.0,smoothstep(-0.35,0.6,cloud_height));
 EMISSION = mix(cloud_shadow.rgb, cloud_shadow.rgb * 0.4, storm) * base_fill * (1.0 - haze) + haze_color.rgb * haze;
 float sun_edge = smoothstep(-0.2,0.6,dot(aerial_world_normal,normalize(sun_direction)));
 EMISSION += cloud_light.rgb * fresnel_factor(NORMAL, VIEW, 3.0) * sun_edge * 0.22 * (1.0 - haze);
 // Art-directed transmission through sunward crowns, not a volumetric solve.
 vec3 eye_ray = normalize(aerial_world_position-CAMERA_POSITION_WORLD);
 float forward_scatter = pow(max(dot(eye_ray,normalize(sun_direction)),0.0),18.0);
 float crown = smoothstep(-0.15,0.85,cloud_height);
 EMISSION += cloud_light.rgb * forward_scatter * (crown*0.22+fresnel_factor(NORMAL,VIEW,1.5)*0.55) * (1.0-storm) * (1.0-haze);
}
void light() {
 DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * is_lit(LIGHT, NORMAL, ATTENUATION) * 0.8;
}

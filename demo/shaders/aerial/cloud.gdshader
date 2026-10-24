shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
#include "../includes/base-cel-shader.gdshaderinc"
#include "atmosphere.gdshaderinc"
uniform vec4 cloud_light: source_color = vec4(1.0, 0.62, 0.38, 1.0);
uniform vec4 cloud_shadow: source_color = vec4(0.22, 0.17, 0.29, 1.0);
uniform float storm = 0.0;
void vertex() {
 aerial_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 aerial_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 NDTL_DITHER_POSITION = FRAGCOORD.xy;
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 ALBEDO = cloud_light.rgb * (1.0 - haze) * mix(1.0, 0.4, storm);
 EMISSION = mix(cloud_shadow.rgb, cloud_shadow.rgb * 0.4, storm) * (1.0 - haze) + haze_color.rgb * haze;
 EMISSION += cloud_light.rgb * fresnel_factor(NORMAL, VIEW, 4.0) * 0.08 * (1.0 - haze);
}
void light() {
 DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * is_lit(LIGHT, NORMAL, ATTENUATION) * 0.65;
}

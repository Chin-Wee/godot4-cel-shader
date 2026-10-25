shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
#include "../includes/base-cel-shader.gdshaderinc"
#include "atmosphere.gdshaderinc"
uniform vec4 rock_color: source_color = vec4(0.43, 0.20, 0.17, 1.0);
uniform vec4 cap_color: source_color = vec4(0.53, 0.31, 0.27, 1.0);
uniform vec4 valley_color: source_color = vec4(0.025, 0.095, 0.19, 1.0);
uniform float terrain_rim = 0.07;
void vertex() {
 aerial_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 aerial_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 NDTL_DITHER_POSITION = FRAGCOORD.xy;
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 float height = smoothstep(0.0, 260.0, aerial_world_position.y);
 float cap = smoothstep(0.62, 0.95, aerial_world_normal.y);
 vec3 base = mix(valley_color.rgb, rock_color.rgb, smoothstep(8.0, 90.0, aerial_world_position.y));
 base = mix(base, cap_color.rgb, cap * height);
 // Broad strata only: no small texture detail competing with the canyon silhouette.
 base *= mix(0.94, 1.0, step(0.24, fract(aerial_world_position.y / 65.0)));
 ALBEDO = base * (1.0 - haze);
 float rim = fresnel_factor(NORMAL, VIEW, 5.0) * terrain_rim;
 EMISSION = (mix(valley_color.rgb,base * 0.25,0.2) + rim * cap_color.rgb) * (1.0 - haze) + haze_color.rgb * haze;
}
void light() {
 DIFFUSE_LIGHT += diffuse_light(ALBEDO, LIGHT_COLOR, LIGHT, NORMAL, ATTENUATION);
}

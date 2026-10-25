shader_type spatial;
render_mode ambient_light_disabled;
#include "../includes/base-cel-shader.gdshaderinc"
#include "atmosphere.gdshaderinc"
uniform vec4 body_color: source_color = vec4(0.88, 0.29, 0.045, 1.0);
uniform vec4 underside_color: source_color = vec4(0.055, 0.075, 0.105, 1.0);
uniform vec4 shadow_color: source_color = vec4(0.08, 0.11, 0.18, 1.0);
uniform vec4 rim_color: source_color = vec4(1.0, 0.76, 0.39, 1.0);
uniform float shadow_fill = 0.65;
uniform float rim_strength = 0.7;
uniform float rim_power = 4.0;
uniform float highlight_mask: hint_range(0.0, 1.0) = 0.0;
uniform float orientation_bias: hint_range(0.0, 1.0) = 0.8;
uniform float panel_strength: hint_range(0.0,1.0) = 0.8;
uniform vec4 panel_color: source_color = vec4(0.9,0.56,0.17,1.0);
varying vec3 local_position;
varying vec3 local_normal;
void vertex() {
 aerial_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 aerial_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
 local_normal = NORMAL;
 local_position = VERTEX;
}
void fragment() {
 NDTL_DITHER_POSITION = FRAGCOORD.xy;
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 vec3 base = mix(underside_color.rgb, body_color.rgb, mix(1.0, smoothstep(-0.35, 0.4, local_normal.y), orientation_bias));
 float wing_panel = step(9.0,abs(local_position.x)) * step(4.0,local_position.z) * step(local_position.z,11.0) * step(0.3,local_normal.y);
 base = mix(base,panel_color.rgb,wing_panel * panel_strength);
 ALBEDO = base * (1.0 - haze);
 float rim_term = fresnel_factor(NORMAL, VIEW, rim_power);
 float rim = smoothstep(0.25,0.7,rim_term);
 float stipple = step(bayer4x4(FRAGCOORD.xy/1.5),rim_term);
 rim = max(rim,stipple * 0.25);
 float panel_fill = 0.12+0.24*max(smoothstep(0.2,0.8,local_normal.y),step(7.0,local_position.y));
 EMISSION = (base * panel_fill + shadow_color.rgb * shadow_fill + rim * rim_color.rgb * rim_strength) * (1.0 - haze) + haze_color.rgb * haze;
 ROUGHNESS = 1.0;
}
void light() {
 DIFFUSE_LIGHT += diffuse_light(ALBEDO, LIGHT_COLOR, LIGHT, NORMAL, ATTENUATION);
 SPECULAR_LIGHT += specular_light(LIGHT_COLOR, vec3(1.0, 0.83, 0.58), highlight_mask, 160.0, 0.03, NORMAL, VIEW, LIGHT, ATTENUATION);
}

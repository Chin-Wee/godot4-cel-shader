shader_type spatial;
render_mode unshaded, cull_disabled;
#include "../includes/base-cel-shader.gdshaderinc"
#include "atmosphere.gdshaderinc"
uniform sampler2D color_ramp: source_color;
uniform sampler2D depth_texture: hint_depth_texture, repeat_disable, filter_nearest;
uniform float effect_time = 0.0;
uniform float lifetime = 12.0;
uniform float normalized_age = 0.0;
uniform bool instance_age = false;
uniform float expansion = 0.0;
uniform float emission_strength = 0.0;
uniform float soft_intersection = 0.0;
uniform bool graphic_fire = false;
uniform float vfx_rim = 0.08;
varying vec3 effect_local_position;
varying float age;
void vertex() {
 effect_local_position = VERTEX;
 age = instance_age ? (effect_time - INSTANCE_CUSTOM.r) / lifetime : normalized_age;
 VERTEX *= 1.0 + clamp(age,0.0,1.0) * expansion;
 aerial_world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 aerial_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 if (age < 0.0 || age >= 1.0) { discard; }
 float fade = 1.0 - smoothstep(0.65,1.0,age);
 if (soft_intersection > 0.0) {
  float depth = textureLod(depth_texture,SCREEN_UV,0.0).r;
  vec4 scene_position = INV_PROJECTION_MATRIX * vec4(SCREEN_UV*2.0-1.0,depth,1.0);
  float separation = -scene_position.z / scene_position.w + VERTEX.z;
  fade *= clamp(separation / soft_intersection,0.0,1.0);
 }
 if (fade < bayer4x4(FRAGCOORD.xy)) { discard; }
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 vec3 color = texture(color_ramp,vec2(clamp(age,0.0,1.0),0.5)).rgb;
 if (graphic_fire) {
  float mass = sin(effect_local_position.x * 3.0 + sin(effect_local_position.y * 4.0) + effect_local_position.z * 2.0 + age * 9.0);
  color = mix(color * vec3(1.0,0.4,0.05),vec3(1.0,0.98,0.5),smoothstep(-0.12,0.12,mass));
 }
 float lighting = mix(0.45,1.0,smoothstep(-0.15,0.15,dot(aerial_world_normal,normalize(vec3(-0.5,0.6,-0.8)))));
 // Unshaded materials use ALBEDO directly, including the HDR emissive contribution.
 ALBEDO = mix(color * (lighting + emission_strength) + color * fresnel_factor(NORMAL,VIEW,4.0) * vfx_rim,haze_color.rgb,haze);
}

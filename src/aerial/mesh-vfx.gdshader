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
uniform vec3 wind_velocity = vec3(0.08,0.12,0.0);
uniform float wind_curl = 0.08;
uniform float emission_strength = 0.0;
uniform float soft_intersection = 0.0;
uniform bool graphic_fire = false;
uniform float shape_seed = 0.0;
uniform float vfx_rim = 0.08;
// Opt-in trail geometry; zero preserves explosions and other mesh VFX.
uniform int trail_style = 0; // 1: faceted chunk, 2: camera-facing path ribbon.
uniform int trail_profile = 0; // 1: wide vapor, 2: fine/emissive core.
uniform float trail_roll_speed = 0.0;
uniform float trail_opacity = 1.0;
uniform float trail_smoke_delay = 0.0; // Seconds before missile exhaust condenses into opaque smoke.
uniform vec4 trail_tint: source_color = vec4(1.0);
varying float trail_active;
varying vec3 effect_local_position;
varying float age;
void vertex() {
 effect_local_position = VERTEX;
 age = instance_age ? (effect_time - INSTANCE_CUSTOM.r) / lifetime : normalized_age;
 trail_active = instance_age ? INSTANCE_CUSTOM.a : 1.0;
 float growth = 1.0+clamp(age,0.0,1.0)*expansion;
 if (trail_style == 1) {
  growth *= 1.0+sin(INSTANCE_CUSTOM.g*17.0+max(effect_time-INSTANCE_CUSTOM.r,0.0)*3.0)*0.045*smoothstep(0.0,0.2,max(effect_time-INSTANCE_CUSTOM.r,0.0));
  float turn = sin(INSTANCE_CUSTOM.g*10.681)*max(effect_time-INSTANCE_CUSTOM.r,0.0)*trail_roll_speed;
  mat2 roll = mat2(vec2(cos(turn),sin(turn)),vec2(-sin(turn),cos(turn)));
  VERTEX.xy = roll*VERTEX.xy*growth;
  float length_growth = 1.0+clamp(age,0.0,1.0)*0.15;
  NORMAL = normalize(vec3(roll*NORMAL.xy/growth,NORMAL.z/length_growth));
  VERTEX.z *= length_growth;
 } else if (trail_style == 2 && INSTANCE_CUSTOM.b > 0.0 && trail_active > 0.0) {
  vec3 tangent = normalize(MODEL_MATRIX[2].xyz);
  vec3 side = cross(tangent,CAMERA_POSITION_WORLD-MODEL_MATRIX[3].xyz);
  side = dot(side,side) > 0.000001 ? normalize(side) : INV_VIEW_MATRIX[0].xyz;
  vec3 ribbon_position = side*VERTEX.x*length(MODEL_MATRIX[0].xyz)*growth
                       +tangent*VERTEX.z*length(MODEL_MATRIX[2].xyz);
  VERTEX = inverse(mat3(MODEL_MATRIX))*ribbon_position;
  NORMAL = normalize(transpose(mat3(MODEL_MATRIX))*normalize(cross(side,tangent)));
 } else { VERTEX *= growth; }
 if (instance_age) {
  float seconds = max(effect_time-INSTANCE_CUSTOM.r,0.0);
  float phase = INSTANCE_CUSTOM.g*6.283185;
  vec3 curl = vec3(sin(phase+seconds*0.6),sin(phase*2.0+seconds*0.3),cos(phase+seconds*0.4));
  // Oriented, stretched trail instances still drift in shared world-space wind.
  // Unused slots have zero scale and no radius; do not invert their matrices.
  if (INSTANCE_CUSTOM.b > 0.0) {
   VERTEX += inverse(mat3(MODEL_MATRIX))*(wind_velocity+curl*wind_curl)*seconds;
  }
 }
 aerial_world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 aerial_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 if (age < 0.0 || age >= 1.0 || trail_active < 0.5) { discard; }
 float fade = (1.0-smoothstep(0.65,1.0,age))*trail_opacity;
 // The narrow HDR burn must remain visible before opaque smoke forms around it.
 // Keep depth testing: world geometry still occludes every trail layer.
 if (trail_smoke_delay > 0.0) {
  if (age*lifetime <= trail_smoke_delay) { discard; }
  fade *= smoothstep(trail_smoke_delay,trail_smoke_delay+0.18,age*lifetime);
 }
 if (trail_style == 2) {
  vec2 p = UV*2.0-1.0;
  if (trail_profile == 1) {
   // Broad dithered density around the geometric core, never soft-alpha smoke.
   float density = 1.0-smoothstep(0.25,1.0,dot(p,p));
   fade *= density;
  } else { fade *= 1.0-smoothstep(0.55,1.0,abs(p.x)); }
 }
 if (soft_intersection > 0.0) {
  float depth = textureLod(depth_texture,SCREEN_UV,0.0).r;
  vec4 scene_position = INV_PROJECTION_MATRIX * vec4(SCREEN_UV*2.0-1.0,depth,1.0);
  float separation = -scene_position.z / scene_position.w + VERTEX.z;
  fade *= clamp(separation / soft_intersection,0.0,1.0);
 }
 if (trail_style > 0) {
  fade *= 1.0-smoothstep(haze_start+haze_distance*0.4,haze_start+haze_distance*0.8,length(aerial_world_position-CAMERA_POSITION_WORLD));
 }
 if (fade < bayer4x4(FRAGCOORD.xy)) { discard; }
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 vec3 color = texture(color_ramp,vec2(clamp(age,0.0,1.0),0.5)).rgb;
 if (graphic_fire) {
  vec3 p = effect_local_position*5.0+shape_seed*vec3(9.0,17.0,6.0)+age*vec3(0.0,3.0,-1.0);
  vec3 warp = sin(p.yzx*1.4+cos(p.zxy));
  float mass = dot(sin(p+warp*0.8),vec3(0.45,0.35,0.2));
  float heat = 1.0-smoothstep(0.3,0.85,age);
  vec3 orange = mix(color*0.4,color*vec3(1.0,0.3,0.02),heat);
  vec3 core = mix(color,vec3(1.0,0.95,0.24),heat);
  color = mix(orange,core,smoothstep(-0.08,0.12,mass));
 }
 color *= COLOR.rgb*trail_tint.rgb;
 float ndl = dot(aerial_world_normal,aerial_sun_vector());
 float lighting = mix(0.45,1.0,smoothstep(-0.15,0.15,ndl));
 if (trail_style > 0) {
  lighting = mix(0.32,0.67,smoothstep(0.02,0.06,ndl));
  lighting = mix(lighting,1.0,smoothstep(0.55,0.59,ndl));
 }
 // Unshaded materials use ALBEDO directly, including the HDR emissive contribution.
 ALBEDO = mix(color * (lighting + emission_strength) + color * fresnel_factor(NORMAL,VIEW,4.0) * vfx_rim,aerial_haze_tint(CAMERA_POSITION_WORLD),haze);
}

shader_type spatial;
render_mode unshaded, cull_back;
#include "../includes/base-cel-shader.gdshaderinc"
#include "atmosphere.gdshaderinc"

// KSP2's exhaust breakdown and the supplied Stylized_BOTW_Fire are the references.
// Coordinates belong to the nozzle: Z=0 at its exit, Z=1 at the plume tip.
uniform sampler2D flow_noise: repeat_enable, filter_linear;
uniform float flow_phase = 0.0;
instance uniform float phase_offset = 0.0;
uniform float throttle: hint_range(0.0, 1.0) = 1.0;
uniform float twist = 1.2;
uniform float flow_density = 0.08;
uniform float turbulence: hint_range(0.0, 0.16, 0.01) = 0.14;
uniform float emission_strength = 2.5;
uniform vec4 core_color: source_color = vec4(1.0, 0.85, 0.65, 1.0);
uniform vec4 plume_color: source_color = vec4(1.0, 0.035, 0.23, 1.0);
uniform vec4 hot_color: source_color = vec4(1.0, 0.22, 0.44, 1.0);
uniform vec4 rim_color: source_color = vec4(0.5, 0.06, 0.65, 1.0);
varying vec3 plume_position;
varying float plume_length;

void vertex() {
 plume_position = VERTEX;
 // Shape masks stay normalized; flow uses nozzle-local meters, including parent scale.
 plume_length = length(MODEL_MATRIX[2].xyz);
 // Only the tail moves. Nonuniform node/aircraft scale applies afterward.
 float flow_z = VERTEX.z*plume_length*flow_density-flow_phase+phase_offset;
 vec2 bend = vec2(textureLod(flow_noise,vec2(flow_z,0.2),0.0).r,
                  textureLod(flow_noise,vec2(flow_z,0.7),0.0).r)-0.5;
 float beat = (flow_phase+phase_offset)*6.283185;
 float side_phase = VERTEX.x*2.0+VERTEX.y*3.0;
 vec2 shake = vec2(sin(beat*3.0+side_phase),cos(beat*5.0+side_phase));
 float tail_weight = VERTEX.z*VERTEX.z;
 VERTEX.xy += (shake*0.75+bend*0.5)*clamp(turbulence,0.0,0.16)*tail_weight;
 VERTEX.z += sin(beat*4.0+side_phase)*0.025*tail_weight;
 aerial_world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
 if (throttle <= 0.001) { discard; }
 float axial = clamp(plume_position.z,0.0,1.0);
 float angle = dot(plume_position.xy,plume_position.xy) > 0.000001 ? atan(plume_position.y,plume_position.x)/6.283185 : 0.0;
 vec2 uv = vec2(angle+axial*twist,axial*plume_length*flow_density-flow_phase+phase_offset);
 float warp = texture(flow_noise,uv*vec2(1.0,0.6)+vec2(0.3,0.7)).r-0.5;
 float noise = texture(flow_noise,uv+vec2(warp*0.28,0.0)).r;
 float wisps = texture(flow_noise,uv*vec2(2.0,0.65)+vec2(0.4,-flow_phase*0.3)).r;
 // Multiplication erodes the tail; adding alpha masks would saturate coverage.
 float tail = smoothstep(0.6,1.0,axial);
 float coverage = (1.0-smoothstep(0.65,1.0,axial))*mix(1.0,noise*wisps*2.0,tail);
 if (coverage < 0.22) { discard; }
 float cells = pow(0.5+0.5*cos(axial*25.13274),10.0);
 float heat = (1.0-smoothstep(0.0,0.22,axial))*0.85+noise*0.15+cells*mix(0.8,0.35,axial);
 // Coarse fields move only the boundaries between flat cel colors.
 vec3 color = mix(plume_color.rgb,hot_color.rgb,step(0.58,heat));
 color = mix(color,core_color.rgb,step(0.95,heat));
 color = mix(color,rim_color.rgb,step(0.7,fresnel_factor(NORMAL,VIEW,3.0)));
 float haze = aerial_haze(CAMERA_POSITION_WORLD);
 float gain = (0.5+emission_strength*throttle)*mix(1.0,0.6,step(0.7,axial));
 ALBEDO = mix(color*gain,haze_color.rgb,haze);
}

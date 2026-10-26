// One aerial palette shared by aircraft, terrain, clouds and VFX.
uniform vec4 haze_color: source_color = vec4(0.30, 0.27, 0.40, 1.0);
uniform vec4 haze_sun_color: source_color = vec4(0.88, 0.43, 0.27, 1.0);
uniform float haze_sun_strength: hint_range(0.0, 1.0) = 0.8;
uniform vec4 sky_fill_color: source_color = vec4(0.14, 0.22, 0.38, 1.0);
uniform float sky_fill_strength: hint_range(0.0, 1.0) = 0.3;
uniform float haze_start = 1300.0;
uniform float haze_distance = 6500.0;
uniform vec3 sun_direction = vec3(-0.5,0.22,-0.84);
varying vec3 aerial_world_position;
varying vec3 aerial_world_normal;
float aerial_haze(vec3 camera_position) {
 float distance_fraction = max(length(aerial_world_position - camera_position) - haze_start, 0.0) / haze_distance;
 return 1.0 - exp(-distance_fraction * 1.8);
}
vec3 aerial_sun_vector() {
 return sun_direction * inversesqrt(max(dot(sun_direction,sun_direction),0.0001));
}
vec3 aerial_view_direction(vec3 camera_position) {
 vec3 ray = aerial_world_position-camera_position;
 return ray * inversesqrt(max(dot(ray,ray),0.0001));
}
vec3 aerial_haze_tint(vec3 camera_position) {
 vec3 ray = aerial_view_direction(camera_position);
 float forward = pow(max(dot(ray,aerial_sun_vector()),0.0),8.0);
 float horizon = exp(-abs(ray.y)*2.0);
 return mix(haze_color.rgb,haze_sun_color.rgb,clamp(forward*haze_sun_strength*(0.6+0.4*horizon),0.0,1.0));
}
vec3 aerial_surface_fill(vec3 world_normal) {
 vec3 sun = aerial_sun_vector();
 vec3 reflected_direction = normalize(vec3(sun.x,-0.2,sun.z));
 float sky = 0.25+0.75*max(world_normal.y,0.0);
 float warm = smoothstep(-0.2,0.8,dot(world_normal,reflected_direction));
 return sky_fill_color.rgb*sky_fill_strength*sky
      + haze_sun_color.rgb*sky_fill_strength*haze_sun_strength*warm*0.28;
}

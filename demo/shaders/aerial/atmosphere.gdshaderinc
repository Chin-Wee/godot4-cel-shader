// One aerial palette shared by aircraft, terrain, clouds and VFX.
uniform vec4 haze_color: source_color = vec4(0.54, 0.34, 0.39, 1.0);
uniform float haze_start = 1300.0;
uniform float haze_distance = 6500.0;
uniform vec3 sun_direction = vec3(-0.5,0.22,-0.84);
varying vec3 aerial_world_position;
varying vec3 aerial_world_normal;
float aerial_haze(vec3 camera_position) {
 float distance_fraction = max(length(aerial_world_position - camera_position) - haze_start, 0.0) / haze_distance;
 return 1.0 - exp(-distance_fraction * 1.8);
}

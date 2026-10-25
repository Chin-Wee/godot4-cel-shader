shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture: hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 sun_uv = vec2(0.3,0.25);
uniform float sun_visible = 1.0;
uniform float corona_strength = 0.45;
uniform float shaft_strength = 0.22;
uniform float flare_strength = 0.12;
uniform float rain_strength = 0.0;
uniform float weather_time = 0.0;
uniform float post_strength = 1.0;
float drop_hash(vec2 cell) {
 return fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
}
vec3 solar_ghost(vec2 point, vec2 axis) {
 vec2 red = point-axis*0.35;
 vec2 blue = point+axis*0.35;
 vec3 lobes = exp(-vec3(dot(red,red),dot(point,point),dot(blue,blue))*3.0);
 float halo = exp(-pow(length(point)-0.8,2.0)*32.0);
 return lobes+vec3(0.05,0.1,0.15)*halo;
}
void fragment() {
 vec2 uv = SCREEN_UV;
 vec2 grid = uv*vec2(28.0,9.0);
 grid.y += weather_time*(1.5+drop_hash(vec2(floor(grid.x),17.0))*3.0);
 vec2 cell = floor(grid);
 float seed = drop_hash(cell);
 vec2 center = vec2(0.15+seed*0.7,0.15+drop_hash(cell+3.0)*0.7);
 vec2 drop = fract(grid)-center;
 float mask = (1.0-smoothstep(0.12,0.27,length(drop*vec2(5.0+seed*5.0,0.5+seed*0.5))))*step(0.55,drop_hash(cell+11.0));
 vec2 distortion = vec2(drop.x*4.0,drop.y*0.25)*mask*0.024*rain_strength;
 vec3 original = textureLod(screen_texture,uv,0.0).rgb;
 vec3 color = textureLod(screen_texture,uv+distortion,0.0).rgb;
 // Lightshaft visual reference: Crysis. Standard radial screen sampling.
 // The source mask is the resolved frame; this is not volumetric shadow tracing.
 float solar_visibility = 0.0;
 // ponytail: luminance estimates occlusion; use a depth mask if white geometry must suppress flares.
 if (sun_visible > 0.0 && sun_uv.x >= 0.0 && sun_uv.x <= 1.0 && sun_uv.y >= 0.0 && sun_uv.y <= 1.0) {
  vec3 source = textureLod(screen_texture,sun_uv,1.0).rgb;
  solar_visibility = smoothstep(0.65,0.92,dot(source,vec3(0.2126,0.7152,0.0722)))*sun_visible;
 }
 if (solar_visibility > 0.0) {
  vec2 delta = (sun_uv-uv)*0.97/12.0;
  vec2 sample_uv = uv;
  float rays = 0.0;
  for (int i=0;i<12;i++) {
   sample_uv += delta;
   vec3 sample_color = textureLod(screen_texture,sample_uv,2.0).rgb;
   rays += max(dot(sample_color,vec3(0.2126,0.7152,0.0722))-0.58,0.0)*(1.0-float(i)/16.0);
  }
  color += vec3(1.0,0.82,0.55)*rays*shaft_strength*solar_visibility;
  float aspect = SCREEN_PIXEL_SIZE.y/SCREEN_PIXEL_SIZE.x;
  vec2 aspect_scale = vec2(aspect,1.0);
  vec2 ray = (uv-sun_uv)*aspect_scale;
  float radius = length(ray);
  float angle = atan(ray.y,ray.x);
  float corona = exp(-radius*16.0)*(0.24+0.12*pow(abs(sin(angle*4.0)),12.0));
  color += vec3(1.0,0.68,0.32)*corona*solar_visibility*corona_strength;
  // DELIVERY MUST COMPLETE's supplied sunset image is the optical flare reference.
  // Resolved-source masking keeps the analytic ghosts from shining through clouds.
  vec2 axis = vec2(0.5)-sun_uv;
  vec2 direction = axis*aspect_scale/max(length(axis*aspect_scale),0.001);
  vec3 ghosts = solar_ghost((uv-(sun_uv-axis*0.6))*aspect_scale/0.07,direction)*0.65;
  ghosts += solar_ghost((uv-(sun_uv+axis*2.4))*aspect_scale/0.065,direction);
  color += ghosts*flare_strength*solar_visibility*smoothstep(0.03,0.18,length(axis));
 }
 color += mask*rain_strength*0.025;
 COLOR = vec4(mix(original,color,post_strength),1.0);
}

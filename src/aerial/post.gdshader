shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture: hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D solar_visibility_texture: repeat_disable, filter_nearest;
uniform bool use_depth_occlusion = false;
uniform vec2 sun_uv = vec2(0.3,0.25);
uniform float sun_visible = 1.0;
uniform float corona_strength = 0.45;
uniform float glare_strength = 0.9;
uniform float starburst_strength = 0.45;
uniform float streak_strength = 0.35;
uniform float ring_strength = 0.055;
uniform float flare_strength = 0.4;
uniform float veil_strength = 0.45;
uniform float rain_strength = 0.0;
uniform float weather_time = 0.0;
uniform float post_strength = 1.0;
float drop_hash(vec2 cell) {
 return fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
}
vec3 spectral_ghost(vec2 point, vec2 axis) {
 if (dot(point,point) > 5.0) { return vec3(0.0); }
 vec3 color = vec3(0.0);
 // Six overlapping wavelength lobes create dispersion, rather than RGB fringes.
 for (int i=0;i<6;i++) {
  float wavelength = float(i)/5.0;
  vec3 hue = abs(fract(vec3(0.78*(1.0-wavelength))+vec3(0.0,0.666667,0.333333))*6.0-3.0);
  vec3 spectrum = clamp(hue-1.0,0.0,1.0);
  vec2 offset = point-axis*(wavelength-0.5)*1.3;
  color += spectrum*exp(-dot(offset,offset)*3.0);
 }
 return color*0.55;
}
vec3 iris_ring(vec2 point, float radius) {
 float ring_distance = length(point);
 if (abs(ring_distance-radius) > 0.12) { return vec3(0.0); }
 vec3 split_radius = vec3(radius+0.018,radius,radius-0.012);
 vec3 edge = (vec3(ring_distance)-split_radius)/0.026;
 return exp(-edge*edge)*vec3(0.45,0.85,0.75);
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
 // These are camera optics; world-space scattering and cloud shadows are separate.
 float solar_visibility = 0.0;
 if (sun_visible > 0.0 && sun_uv.x >= 0.0 && sun_uv.x <= 1.0 && sun_uv.y >= 0.0 && sun_uv.y <= 1.0) {
  if (use_depth_occlusion) {
   solar_visibility = clamp(textureLod(solar_visibility_texture,vec2(0.5),0.0).r,0.0,1.0)*clamp(sun_visible,0.0,1.0);
  } else {
   // ponytail: standalone captures use luminance; the scene supplies GPU depth visibility.
   vec3 source = textureLod(screen_texture,sun_uv,1.0).rgb;
   solar_visibility = smoothstep(0.65,0.92,dot(source,vec3(0.2126,0.7152,0.0722)))*clamp(sun_visible,0.0,1.0);
  }
 }
 if (solar_visibility > 0.0) {
  float aspect = SCREEN_PIXEL_SIZE.y/SCREEN_PIXEL_SIZE.x;
  vec2 aspect_scale = vec2(aspect,1.0);
  vec2 ray = (uv-sun_uv)*aspect_scale;
  float radius = length(ray);
  float angle = radius > 0.00001 ? atan(ray.y,ray.x) : 0.0;
  float horizontal = exp(-abs(ray.x)*1.6);
  float thin = exp(-pow(ray.y/0.002,2.0));
  float medium = exp(-pow(ray.y/0.017,2.0));
  float broad = exp(-pow(ray.y/0.055,2.0));
  // Veiling glare lifts dark values and reduces local contrast before bright glare.
  float veil = (exp(-radius*5.0)*0.65+broad*horizontal*0.08)*veil_strength*solar_visibility;
  color = mix(color,mix(vec3(0.78,0.48,0.36),color,0.45),clamp(veil,0.0,0.8));
  float white_core = exp(-pow(radius/0.018,2.0))*2.0;
  float warm_envelope = exp(-pow(radius/0.05,2.0))*0.3;
  color += (vec3(1.0)*white_core+vec3(1.0,0.88,0.65)*warm_envelope)*glare_strength*solar_visibility;
  // A low-frequency atmospheric halo remains broader than the clipped glare mass.
  float corona = exp(-radius*6.0)*0.16;
  color += mix(vec3(1.0,0.34,0.18),vec3(1.0,0.78,0.48),exp(-radius*10.0))*corona*corona_strength*solar_visibility;
  float spikes = pow(abs(cos(angle*4.0)),40.0)*exp(-radius*10.5)*smoothstep(0.009,0.025,radius);
  spikes += exp(-pow(ray.x/0.012,2.0))*exp(-abs(ray.y)*13.0)*0.35;
  color += vec3(1.0,0.88,0.66)*spikes*starburst_strength*0.65*solar_visibility;
  color += vec3(1.0,0.85,0.68)*(thin*0.6+medium*0.16+broad*0.065)*horizontal*streak_strength*solar_visibility;
  // DELIVERY MUST COMPLETE's supplied sunset is the visual reference for these optics.
  vec2 axis = vec2(0.5)-sun_uv;
  vec2 direction = axis*aspect_scale/max(length(axis*aspect_scale),0.001);
  vec3 ghosts = spectral_ghost((uv-(sun_uv-axis*0.6))*aspect_scale/0.075,direction)*0.8;
  ghosts += spectral_ghost((uv-(sun_uv+axis*2.4))*aspect_scale/0.065,direction)*1.55;
  ghosts += spectral_ghost((uv-(sun_uv+axis*0.65))*aspect_scale/0.11,direction)*0.08;
  ghosts += spectral_ghost((uv-(sun_uv+axis*1.35))*aspect_scale/0.055,direction)*0.12;
  ghosts += spectral_ghost((uv-(sun_uv+axis*1.85))*aspect_scale/0.035,direction)*0.07;
  color += ghosts*flare_strength*solar_visibility*smoothstep(0.03,0.18,length(axis));
  vec3 rings = iris_ring((uv-(sun_uv+axis*0.34))*aspect_scale,0.69);
  rings += iris_ring((uv-(sun_uv+axis*0.55))*aspect_scale,0.83)*0.35;
  color += rings*ring_strength*solar_visibility;
 }
 color += mask*rain_strength*0.025;
 COLOR = vec4(mix(original,color,post_strength),1.0);
}

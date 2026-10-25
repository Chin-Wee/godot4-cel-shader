shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture: hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 sun_uv = vec2(0.3,0.25);
uniform float sun_visible = 1.0;
uniform float glow_strength = 0.45;
uniform float shaft_strength = 0.12;
uniform float rain_strength = 0.0;
uniform float weather_time = 0.0;
uniform float post_strength = 1.0;
float drop_hash(vec2 cell) {
 return fract(sin(dot(cell,vec2(127.1,311.7)))*43758.5453);
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
 vec3 wide = textureLod(screen_texture,uv,4.0).rgb;
 vec3 narrow = textureLod(screen_texture,uv,2.0).rgb;
 vec3 glow = max(wide-vec3(0.55),vec3(0.0))*0.65 + max(narrow-vec3(0.7),vec3(0.0))*0.35;
 color += glow*glow_strength;
 // Lightshaft visual reference: Crysis. Standard radial screen sampling.
 // The source mask is the resolved frame; this is not volumetric shadow tracing.
 vec2 delta = (sun_uv-uv)*0.75/8.0;
 vec2 sample_uv = uv;
 float rays = 0.0;
 if (sun_visible > 0.0) {
 for (int i=0;i<8;i++) {
  sample_uv += delta;
  vec3 sample_color = textureLod(screen_texture,sample_uv,2.0).rgb;
  rays += max(dot(sample_color,vec3(0.2126,0.7152,0.0722))-0.68,0.0)*(1.0-float(i)/11.0);
 }
 }
 color += vec3(1.0,0.72,0.4)*rays*shaft_strength*sun_visible;
 float aspect = SCREEN_PIXEL_SIZE.y/SCREEN_PIXEL_SIZE.x;
 vec2 ray = (uv-sun_uv)*vec2(aspect,1.0);
 float radius = length(ray);
 float angle = atan(ray.y,ray.x);
 float corona = exp(-radius*24.0)*(0.32+0.12*pow(abs(sin(angle*4.0)),12.0));
 color += vec3(1.0,0.68,0.32)*corona*sun_visible*glow_strength;
 color += mask*rain_strength*0.025;
 COLOR = vec4(mix(original,color,post_strength),1.0);
}

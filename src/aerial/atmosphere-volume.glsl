#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(std430,set=0,binding=0) readonly buffer Frame {
 mat4 inverse_projection;
 mat4 camera_to_world;
 mat4 world_to_cloud;
 vec4 sun_direction;
 vec4 shadow_x;
 vec4 shadow_y;
 vec4 shadow_bounds;
 vec4 light_color;
 vec4 ambient_color; // linear ambient RGB, native luminance multiplier
 vec4 settings; // density, height scale, max distance, strength
 vec4 controls; // bank count, shadow strength, solar uv
 vec4 sizes; // full and quarter resolution
} frame;
#ifdef PASS_SHADOW
struct Bank { mat4 inverse_transform; vec4 lobe_range; };
layout(std430,set=0,binding=1) readonly buffer Clouds { Bank banks[18]; vec4 lobes[64]; } clouds;
layout(rgba16f,set=0,binding=3) uniform writeonly image2D shadow_image;
vec2 sphere_interval(vec3 origin,vec3 direction,vec4 lobe) {
 vec3 delta=origin-lobe.xyz;
 float a=dot(direction,direction);
 float b=dot(delta,direction);
 float c=dot(delta,delta)-(lobe.w+0.035)*(lobe.w+0.035);
 float discriminant=b*b-a*c;
 if(discriminant<=0.0) return vec2(1.0,-1.0);
 return (-b+vec2(-1.0,1.0)*sqrt(discriminant))/a;
}
vec2 clipped_interval(vec3 origin,vec3 direction,vec4 lobe,bool lower) {
 vec3 o=origin,d=direction;
 if(lower) { o.y=-0.38+(o.y+0.38)/0.23; d.y/=0.23; }
 vec2 interval=sphere_interval(o,d,lobe);
 if(abs(direction.y)<0.000001) {
  if((origin.y< -0.38)!=lower) return vec2(1.0,-1.0);
 } else {
  float boundary=(-0.38-origin.y)/direction.y;
  if((direction.y>0.0)==lower) interval.y=min(interval.y,boundary);
  else interval.x=max(interval.x,boundary);
 }
 return interval;
}
void main() {
 ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);
 ivec2 size=imageSize(shadow_image);
 if(any(greaterThanEqual(pixel,size))) return;
 vec2 uv=(vec2(pixel)+0.5)/vec2(size);
 vec2 plane=frame.shadow_bounds.xy+uv*frame.shadow_bounds.zw;
 vec3 origin=frame.shadow_x.xyz*plane.x+frame.shadow_y.xyz*plane.y;
 vec3 direction=normalize(cross(frame.shadow_x.xyz,frame.shadow_y.xyz));
 // ponytail: broad lobe intervals match the cloud banks; tiny radial crest noise
 // and internal cavities are intentionally below this 256px shadow field resolution.
 float front=-60000.0,back=60000.0,optical_depth=0.0;
 for(int index=0;index<int(frame.controls.x);index++) {
  Bank bank=clouds.banks[index];
  vec3 o=(bank.inverse_transform*vec4(origin,1.0)).xyz;
  vec3 d=(bank.inverse_transform*vec4(direction,0.0)).xyz;
  float entry=60000.0,exit=-60000.0;
  for(int j=0;j<int(bank.lobe_range.y);j++) {
   vec4 lobe=clouds.lobes[int(bank.lobe_range.x)+j];
   for(int region=0;region<2;region++) {
    vec2 interval=clipped_interval(o,d,lobe,region==1);
    if(interval.y>interval.x) { entry=min(entry,interval.x); exit=max(exit,interval.y); }
   }
  }
  if(exit>entry) {
   front=max(front,exit); back=min(back,entry);
   optical_depth+=(exit-entry)*0.018;
  }
 }
 imageStore(shadow_image,pixel,vec4(front,back,min(optical_depth,40.0),1.0));
}
#else
#ifdef DEPTH_MULTISAMPLED
layout(set=0,binding=2) uniform sampler2DMS depth_texture;
float depth_at(ivec2 pixel) {
 float depth=0.0;
 for(int sample_index=0;sample_index<DEPTH_SAMPLES;sample_index++) depth=max(depth,texelFetch(depth_texture,pixel,sample_index).r);
 return depth;
}
#else
layout(set=0,binding=2) uniform sampler2D depth_texture;
float depth_at(ivec2 pixel) { return texelFetch(depth_texture,pixel,0).r; }
#endif
#ifdef PASS_SOLAR
layout(r16f,set=0,binding=6) uniform writeonly image2D solar_image;
void main() {
 if(any(notEqual(ivec2(gl_GlobalInvocationID.xy),ivec2(0)))) return;
 vec2 uv=frame.controls.zw;
 float visibility=0.0;
 if(frame.sun_direction.w>0.0 && all(greaterThanEqual(uv,vec2(0))) && all(lessThanEqual(uv,vec2(1)))) {
  ivec2 size=ivec2(frame.sizes.xy);
  float radius=max(1.0,frame.sizes.y*0.008);
  for(int y=-2;y<=2;y++) for(int x=-2;x<=2;x++) {
   ivec2 pixel=ivec2(uv*vec2(size)+vec2(x,y)*radius*0.5);
   pixel=clamp(pixel,ivec2(0),size-1);
   visibility+=depth_at(pixel)<=0.0000001 ? 1.0:0.0;
  }
  visibility/=25.0;
 }
 imageStore(solar_image,ivec2(0),vec4(visibility));
}
#else
layout(rgba16f,set=0,binding=3) uniform readonly image2D shadow_image;
layout(rgba16f,set=0,binding=4) uniform writeonly image2D scattering_image;
layout(r32f,set=0,binding=5) uniform writeonly image2D distance_image;
float cloud_visibility(vec3 point) {
 vec3 local=(frame.world_to_cloud*vec4(point,1.0)).xyz;
 vec2 plane=vec2(dot(local,frame.shadow_x.xyz),dot(local,frame.shadow_y.xyz));
 vec2 uv=(plane-frame.shadow_bounds.xy)/frame.shadow_bounds.zw;
 if(any(lessThan(uv,vec2(0))) || any(greaterThan(uv,vec2(1)))) return 1.0;
 vec2 texel=uv*vec2(imageSize(shadow_image))-0.5;
 ivec2 base=ivec2(floor(texel));
 vec2 fraction=fract(texel);
 float visibility=0.0;
 float depth=dot(local,normalize(cross(frame.shadow_x.xyz,frame.shadow_y.xyz)));
 for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
  ivec2 coord=clamp(base+ivec2(x,y),ivec2(0),imageSize(shadow_image)-1);
  vec3 data=imageLoad(shadow_image,coord).rgb;
  float remaining=data.z>0.0 ? clamp((data.x-depth)/max(data.x-data.y,1.0),0.0,1.0):0.0;
  float weight=(x==0 ? 1.0-fraction.x:fraction.x)*(y==0 ? 1.0-fraction.y:fraction.y);
  visibility+=exp(-data.z*remaining)*weight;
 }
 return mix(1.0,visibility,frame.controls.y);
}
void main() {
 ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);
 ivec2 size=imageSize(scattering_image);
 if(any(greaterThanEqual(pixel,size))) return;
 ivec2 full_size=ivec2(frame.sizes.xy);
 // Conservative reverse-Z depth prevents low-resolution fog leaking over foreground edges.
 float depth=0.0;
 for(int y=0;y<4;y++) for(int x=0;x<4;x++) depth=max(depth,depth_at(min(pixel*4+ivec2(x,y),full_size-1)));
 vec2 uv=(vec2(pixel)+0.5)/vec2(size);
 vec4 view=frame.inverse_projection*vec4(uv*2.0-1.0,depth,1.0);
 float distance=depth>0.0000001 ? min(length(view.xyz/max(abs(view.w),0.000001)),frame.settings.z):frame.settings.z;
 imageStore(distance_image,pixel,vec4(distance));
 vec4 far_point=frame.inverse_projection*vec4(uv*2.0-1.0,0.0,1.0);
 vec3 direction=normalize(mat3(frame.camera_to_world)*normalize(far_point.xyz));
 vec3 origin=frame.camera_to_world[3].xyz;
 float cosine=dot(direction,normalize(frame.sun_direction.xyz));
 float g=0.62;
 float phase=(1.0-g*g)/pow(max(1.0+g*g-2.0*g*cosine,0.02),1.5);
 phase=min(phase,5.0)*0.07957747; // Henyey-Greenstein normalization: 1/(4*pi).
 float step_length=distance/24.0;
 vec3 radiance=vec3(0.0);
 float transmittance=1.0;
 for(int step_index=0;step_index<24;step_index++) {
  float along=(float(step_index)+0.5)*step_length;
  vec3 point=origin+direction*along;
  float density=frame.settings.x*exp(-max(point.y,0.0)/max(frame.settings.y,1.0));
  density*=smoothstep(80.0,300.0,along);
  float extinction=1.0-exp(-density*step_length*frame.settings.w);
  vec3 sunlight=frame.light_color.rgb*frame.light_color.w*phase*cloud_visibility(point)*frame.sun_direction.w;
  radiance+=transmittance*extinction*(frame.ambient_color.rgb+sunlight);
  transmittance*=1.0-extinction;
 }
 imageStore(scattering_image,pixel,vec4(radiance/frame.ambient_color.w,transmittance));
}
#endif
#endif

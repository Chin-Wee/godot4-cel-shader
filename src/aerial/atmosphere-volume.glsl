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
struct Bank { mat4 inverse_transform; vec4 variant; };
layout(std430,set=0,binding=1) readonly buffer Clouds {
 vec4 field_min;
 vec4 field_extent;
 vec4 field_size; // xyz samples per variant, w variant count
 Bank banks[18];
} clouds;
layout(set=0,binding=7) uniform sampler3D density_texture;
layout(rgba16f,set=0,binding=3) uniform writeonly image2D shadow_image;
vec2 box_interval(vec3 origin,vec3 direction) {
 float entry=-60000.0,exit=60000.0;
 vec3 high=clouds.field_min.xyz+clouds.field_extent.xyz;
 for(int axis=0;axis<3;axis++) {
  if(abs(direction[axis])<0.000001) {
   if(origin[axis]<clouds.field_min[axis] || origin[axis]>high[axis]) return vec2(1,-1);
  } else {
   vec2 slab=(vec2(clouds.field_min[axis],high[axis])-origin[axis])/direction[axis];
   entry=max(entry,min(slab.x,slab.y));
   exit=min(exit,max(slab.x,slab.y));
  }
 }
 return vec2(entry,exit);
}
float sampled_density(vec3 point,float variant) {
 vec3 grid=(point-clouds.field_min.xyz)/clouds.field_extent.xyz*(clouds.field_size.xyz-1.0);
 // Variant grids are stacked along Z. Texel centers preserve the CPU's x-fast
 // trilinear interpolation without filtering across neighboring variants.
 vec3 atlas_size=clouds.field_size.xyz*vec3(1,1,clouds.field_size.w);
 vec3 uv=(grid+vec3(0.5,0.5,0.5+variant*clouds.field_size.z))/atlas_size;
 return smoothstep(0.0,0.14,textureLod(density_texture,uv,0.0).r);
}
void main() {
 ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);
 ivec2 size=imageSize(shadow_image);
 if(any(greaterThanEqual(pixel,size))) return;
 vec2 uv=(vec2(pixel)+0.5)/vec2(size);
 vec2 plane=frame.shadow_bounds.xy+uv*frame.shadow_bounds.zw;
 vec3 origin=frame.shadow_x.xyz*plane.x+frame.shadow_y.xyz*plane.y;
 vec3 direction=normalize(cross(frame.shadow_x.xyz,frame.shadow_y.xyz));
 float front=-60000.0,back=60000.0,optical_depth=0.0;
 for(int index=0;index<int(frame.controls.x);index++) {
  Bank bank=clouds.banks[index];
  vec3 o=(bank.inverse_transform*vec4(origin,1.0)).xyz;
  vec3 d=(bank.inverse_transform*vec4(direction,0.0)).xyz;
  vec2 interval=box_interval(o,d);
  if(interval.y<=interval.x) continue;
  float step_length=(interval.y-interval.x)/32.0;
  for(int sample_index=0;sample_index<32;sample_index++) {
   float along=interval.x+(float(sample_index)+0.5)*step_length;
   float density=sampled_density(o+d*along,bank.variant.x);
   if(density>0.0001) {
    front=max(front,along+step_length*0.5);
    back=min(back,along-step_length*0.5);
    optical_depth+=density*step_length*0.018;
   }
  }
 }
 // ponytail: the integrated column honors grid cavities and overhangs; only the
 // distribution of shadow within that column is approximated by front/back depth.
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
 float g=0.72;
 float phase=(1.0-g*g)/pow(max(1.0+g*g-2.0*g*cosine,0.02),1.5);
 phase=min(phase,8.0)*0.07957747; // Henyey-Greenstein normalization: 1/(4*pi).
 float step_length=distance/24.0;
 vec3 radiance=vec3(0.0);
 float transmittance=1.0;
 for(int step_index=0;step_index<24;step_index++) {
  float along=(float(step_index)+0.5)*step_length;
  vec3 point=origin+direction*along;
  float density=frame.settings.x*exp(-max(point.y,0.0)/max(frame.settings.y,1.0));
  density*=smoothstep(450.0,1600.0,along);
  float extinction=1.0-exp(-density*step_length*frame.settings.w);
  vec3 sunlight=frame.light_color.rgb*frame.light_color.w*phase*cloud_visibility(point)*frame.sun_direction.w;
  radiance+=transmittance*extinction*(frame.ambient_color.rgb+sunlight);
  transmittance*=1.0-extinction;
 }
 imageStore(scattering_image,pixel,vec4(radiance/frame.ambient_color.w,transmittance));
}
#endif
#endif

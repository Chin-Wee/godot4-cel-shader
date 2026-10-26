#[vertex]
#version 450
void main() {
 vec2 point=vec2((gl_VertexIndex<<1)&2,gl_VertexIndex&2);
 gl_Position=vec4(point*2.0-1.0,0.0,1.0);
}
#[fragment]
#version 450
layout(std430,set=0,binding=0) readonly buffer Frame {
 mat4 inverse_projection; mat4 camera_to_world; mat4 world_to_cloud;
 vec4 sun_direction; vec4 shadow_x; vec4 shadow_y; vec4 shadow_bounds;
 vec4 light_color; vec4 ambient_color; vec4 settings; vec4 controls; vec4 sizes;
} frame;
#ifdef DEPTH_MULTISAMPLED
layout(set=0,binding=2) uniform sampler2DMS depth_texture;
float depth_at(ivec2 pixel) {
 float depth=0.0;
 for(int index=0;index<DEPTH_SAMPLES;index++) depth=max(depth,texelFetch(depth_texture,pixel,index).r);
 return depth;
}
#else
layout(set=0,binding=2) uniform sampler2D depth_texture;
float depth_at(ivec2 pixel) { return texelFetch(depth_texture,pixel,0).r; }
#endif
layout(set=0,binding=4) uniform sampler2D scattering_texture;
layout(set=0,binding=5) uniform sampler2D distance_texture;
layout(location=0) out vec4 out_color;
void main() {
 vec2 uv=gl_FragCoord.xy/frame.sizes.xy;
 float depth=depth_at(ivec2(gl_FragCoord.xy));
 vec4 view=frame.inverse_projection*vec4(uv*2.0-1.0,depth,1.0);
 float distance=depth>0.0000001 ? min(length(view.xyz/max(abs(view.w),0.000001)),frame.settings.z):frame.settings.z;
 vec2 texel=uv*frame.sizes.zw-0.5;
 ivec2 base=ivec2(floor(texel));
 vec2 fraction=fract(texel);
 vec4 fog=vec4(0.0);
 float weights=0.0;
 for(int y=0;y<2;y++) for(int x=0;x<2;x++) {
  ivec2 coord=clamp(base+ivec2(x,y),ivec2(0),ivec2(frame.sizes.zw)-1);
  float low_distance=texelFetch(distance_texture,coord,0).r;
  float weight=(x==0 ? 1.0-fraction.x:fraction.x)*(y==0 ? 1.0-fraction.y:fraction.y);
  weight*=exp(-abs(low_distance-distance)/max(15.0,distance*0.04));
  fog+=texelFetch(scattering_texture,coord,0)*weight;
  weights+=weight;
 }
 // No matching depth neighbor means an edge: preserve the foreground instead of a fog halo.
 out_color=weights>0.00001 ? fog/weights:vec4(0,0,0,1);
}

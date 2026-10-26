shader_type sky;
uniform vec4 zenith_color: source_color = vec4(0.20, 0.13, 0.24, 1.0);
uniform vec4 horizon_color: source_color = vec4(0.69, 0.36, 0.32, 1.0);
uniform vec4 sun_color: source_color = vec4(1.0, 0.78, 0.48, 1.0);
uniform vec3 sun_direction = vec3(-0.5, 0.22, -0.84);
uniform float solar_core_energy = 18.0;
uniform float solar_angular_radius = 0.006;
uniform float halo_strength = 1.0;
uniform float horizon_scatter_strength = 0.35;
void sky() {
 float up = smoothstep(0.0, 0.5, EYEDIR.y);
 vec3 color = mix(horizon_color.rgb, zenith_color.rgb, up);
 vec3 direction = normalize(EYEDIR);
 float sun_alignment = clamp(dot(direction,normalize(sun_direction)),-1.0,1.0);
 float angular_radius = max(solar_angular_radius,0.0001);
 float disk = smoothstep(cos(angular_radius),cos(angular_radius*0.75),sun_alignment);
 float angle = acos(sun_alignment);
 float glare = exp(-pow(angle/0.034,2.0))*0.7;
 float inner_halo = pow(max(sun_alignment,0.0),48.0)*0.16;
 float outer_halo = pow(max(sun_alignment,0.0),7.0)*0.08;
 // The warm horizon field illuminates the sun-facing air, not the entire sky.
 float horizon = exp(-abs(direction.y-0.045)*7.0)*pow(max(sun_alignment,0.0),7.0);
 color += sun_color.rgb*(disk*solar_core_energy+(glare+inner_halo+outer_halo)*halo_strength);
 color += vec3(1.0,0.34,0.12)*horizon*horizon_scatter_strength;
 COLOR = color;
}

shader_type sky;
uniform vec4 zenith_color: source_color = vec4(0.20, 0.13, 0.24, 1.0);
uniform vec4 horizon_color: source_color = vec4(0.69, 0.36, 0.32, 1.0);
uniform vec4 sun_color: source_color = vec4(1.0, 0.78, 0.48, 1.0);
uniform vec3 sun_direction = vec3(-0.5, 0.22, -0.84);
void sky() {
 float up = smoothstep(0.0, 0.5, EYEDIR.y);
 vec3 color = mix(horizon_color.rgb, zenith_color.rgb, up);
 float sun_alignment = dot(normalize(EYEDIR), normalize(sun_direction));
 float disk = smoothstep(0.99925, 0.9994, sun_alignment);
 float glow = pow(max(sun_alignment, 0.0), 72.0);
 color += sun_color.rgb * (glow * 0.12 + disk * 3.0);
 COLOR = color;
}

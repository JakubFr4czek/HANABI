shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

uniform vec3 shadow_color : source_color = vec3(0.17, 0.035, 0.30);
uniform float opacity : hint_range(0.0, 1.0) = 0.42;
uniform float phase = 0.0;

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.4);
	float bands = 0.5 + 0.5 * sin((VERTEX.y + VERTEX.x * 0.35) * 9.0 - TIME * 1.7 + phase);
	vec3 col = shadow_color * (0.62 + bands * 0.20) + vec3(0.32, 0.10, 0.55) * fresnel * 0.25;
	ALBEDO = col;
	EMISSION = col * fresnel * 0.18;
	ALPHA = opacity * (0.34 + fresnel * 0.46);
}

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

uniform vec3 shadow_color : source_color = vec3(0.17, 0.035, 0.30);
uniform float opacity : hint_range(0.0, 1.0) = 0.42;
uniform float phase = 0.0;

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.4);
	float bands = 0.5 + 0.5 * sin((VERTEX.y + VERTEX.x * 0.35) * 9.0 - TIME * 1.7 + phase);
	// Liquid glass: a faint light streak circles the dome, caught by the rim.
	float sheen_pos = fract(VERTEX.x * 0.22 - VERTEX.y * 0.13 + TIME * 0.12 + phase * 0.16);
	float sheen = pow(max(0.0, 1.0 - abs(sheen_pos * 2.0 - 1.0) * 3.0), 2.0);
	vec3 col = shadow_color * (0.62 + bands * 0.20) + vec3(0.32, 0.10, 0.55) * fresnel * 0.25;
	col += vec3(0.45, 0.20, 0.70) * sheen * (0.10 + fresnel * 0.35);
	ALBEDO = col;
	EMISSION = col * fresnel * 0.18 + vec3(0.45, 0.20, 0.70) * sheen * fresnel * 0.12;
	ALPHA = opacity * (0.34 + fresnel * 0.46);
}

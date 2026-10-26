shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Full-view red vignette when the player is hurt (drawn as a clip-space quad,
// so it covers each eye in VR). Only visible while it is fading out, and a
// faint pulse stays at the edges while health is low.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float low_health : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.45, 0.0, 0.02);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float edge = smoothstep(0.35, 1.25, r);
	float pulse = low_health * (0.55 + 0.45 * sin(TIME * 4.0)) * 0.45;
	ALBEDO = tint;
	ALPHA = clamp(edge * (intensity * 0.85 + pulse), 0.0, 0.9);
}

shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Distant branching storm lightning bolt shader (GDD §9):
// "Lightning: branching bolts with a bright core and a glow, plus a brief
// scene-wide flash. Bolts are mesh and shader, not particles."

uniform vec3 core_color : source_color = vec3(0.90, 0.96, 1.0);
uniform vec3 glow_color : source_color = vec3(0.24, 0.62, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	// UV.x is across the bolt ribbon (0..1, center at 0.5); UV.y is along the bolt (0 = top, 1 = bottom).
	float x = abs(UV.x - 0.5) * 2.0;
	float core = exp(-x * x * 22.0);
	float corona = exp(-x * x * 3.8);
	float tip_fade = smoothstep(0.0, 0.06, UV.y) * (1.0 - smoothstep(0.88, 1.0, UV.y));

	vec3 col = (core_color * core * 3.6 + glow_color * corona * 1.6) * intensity * tip_fade;
	ALBEDO = col;
	ALPHA = clamp((core + corona * 0.65) * intensity * tip_fade, 0.0, 1.0);
}

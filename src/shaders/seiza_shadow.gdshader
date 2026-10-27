shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Cross-legged meditation silhouette on the wet stone (GDD §9 run intro).
uniform float shadow_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float torso = 1.0 - smoothstep(0.22, 0.34, length(p * vec2(0.85, 1.0)));
	float lap_l = 1.0 - smoothstep(0.10, 0.18, length(p - vec2(-0.34, 0.08)));
	float lap_r = 1.0 - smoothstep(0.10, 0.18, length(p - vec2(0.34, 0.08)));
	float knees = max(lap_l, lap_r) * smoothstep(0.05, 0.18, abs(p.y + 0.02));
	float shape = clamp(torso * 0.55 + knees * 0.95, 0.0, 1.0);
	if (shape < 0.02) {
		discard;
	}
	vec3 col = vec3(0.02, 0.015, 0.04);
	ALBEDO = col;
	ALPHA = shape * shadow_strength * 0.88;
}

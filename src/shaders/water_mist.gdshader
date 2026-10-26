shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Low-cost drifting surface mist layer for Dojo of the Storm (Quest 3 Compatibility safe).
// Renders a soft band of mist hovering just above the water around the platform rim,
// around the Sakura trunk and Torii pillars, and fading seamlessly into the deep world fog.

uniform vec4 mist_color : source_color = vec4(0.056, 0.044, 0.125, 1.0);
uniform vec4 fog_color : source_color = vec4(0.032, 0.026, 0.072, 1.0);
uniform vec4 sakura_tint : source_color = vec4(0.46, 0.12, 0.34, 1.0);
uniform vec4 lightning_tint : source_color = vec4(0.45, 0.65, 1.0, 1.0);
uniform float mist_opacity : hint_range(0.0, 1.0) = 0.44;
uniform float inner_clear_radius : hint_range(2.0, 12.0) = 5.15;
uniform float outer_fade_radius : hint_range(10.0, 40.0) = 16.5;
uniform vec2 drift_velocity = vec2(0.18, -0.11);
uniform float lightning_flash : hint_range(0.0, 2.0) = 0.0;

varying vec3 v_world_pos;

float mist_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(v_world_pos.xz);
	// Keep the stone platform floor clear while letting mist curl right up to the platform rim
	float inner_mask = smoothstep(inner_clear_radius - 0.25, inner_clear_radius + 1.85, r);
	float outer_mask = 1.0 - smoothstep(outer_fade_radius * 0.58, outer_fade_radius, r);

	vec2 p1 = v_world_pos.xz * 0.28 + TIME * drift_velocity;
	vec2 p2 = v_world_pos.xz * 0.55 - TIME * drift_velocity.yx * 0.75;
	float n1 = mist_noise(p1);
	float n2 = mist_noise(p2);
	float wisps = smoothstep(0.24, 0.82, n1 * 0.62 + n2 * 0.38);

	// Extra mist plumes hugging the platform rim, Sakura trunk, and Giant Torii base
	float rim_bank = exp(-max(r - 5.30, 0.0) * 0.45) * 0.48;
	float d_torii = length((v_world_pos.xz - vec2(0.0, -10.5)) * vec2(0.45, 0.85));
	float torii_bank = exp(-d_torii * 0.28) * 0.55;

	// Subtle pink scatter near the western Sakura tree
	float d_sakura = length(v_world_pos.xz - vec2(-9.2, -4.6));
	float sakura_scatter = exp(-d_sakura * 0.18);

	vec3 near_col = mix(mist_color.rgb, sakura_tint.rgb, sakura_scatter * 0.36);
	// Blend mist color toward the deep world fog color with radial distance so there is no horizon band
	float dist_blend = smoothstep(8.5, outer_fade_radius, r);
	vec3 col = mix(near_col, fog_color.rgb, dist_blend);
	// Lightning flash briefly illuminates the mist banks across the water
	col += lightning_tint.rgb * (lightning_flash * (0.24 + 0.22 * wisps));

	float density = clamp((wisps * 0.78 + rim_bank + torii_bank) * inner_mask * outer_mask, 0.0, 1.0);
	float alpha = density * mist_opacity * (1.0 + lightning_flash * 0.28);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.72);
}

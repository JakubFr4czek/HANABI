shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Diegetic radial gauge ring for the katana tsuba (XP) and wrist charm (HP & XP).

uniform float fill_ratio : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fill_color : source_color = vec3(0.35, 0.88, 1.0);
uniform vec3 track_color : source_color = vec3(0.14, 0.18, 0.28);
uniform float inner_radius : hint_range(0.1, 0.9) = 0.66;
uniform float outer_radius : hint_range(0.2, 0.99) = 0.92;
uniform float glow_boost : hint_range(0.5, 4.0) = 2.15;
uniform int segments = 12;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r < inner_radius - 0.03 || r > outer_radius + 0.03) {
		discard;
	}
	float band = smoothstep(inner_radius - 0.02, inner_radius + 0.015, r)
		* (1.0 - smoothstep(outer_radius - 0.015, outer_radius + 0.02, r));

	// Thin inner/outer gold-spirit rim lines so the track reads even at low XP
	float rim_line = (1.0 - smoothstep(0.0, 0.018, abs(r - inner_radius)))
		+ (1.0 - smoothstep(0.0, 0.018, abs(r - outer_radius)));

	// Angle from top (0..1 clockwise)
	float ang = fract((atan(p.x, -p.y) / (2.0 * PI)) + 1.0);
	float filled = 1.0 - smoothstep(fill_ratio - 0.008, fill_ratio + 0.008, ang);
	if (fill_ratio <= 0.001) {
		filled = 0.0;
	}

	// Subtle segment notches
	float seg_f = float(max(segments, 1));
	float notch = smoothstep(0.02, 0.055, abs(fract(ang * seg_f) - 0.5));
	float pulse = 0.92 + 0.08 * sin(TIME * 3.5);

	vec3 col = mix(track_color + fill_color * (rim_line * 0.35), fill_color * glow_boost * pulse, filled) * (0.78 + 0.22 * notch);
	float alpha = band * mix(0.62, 0.98, filled) * (0.68 + 0.32 * notch);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.98);
}

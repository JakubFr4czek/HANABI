shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Traditional Japanese Ofuda (paper talisman) shader:
// - Chamfered top shoulders like authentic shrine ofuda
// - Dark indigo-charcoal washi paper with subtle vertical fiber grain
// - Double vermilion/accent border seal with corner knots, hanko stamp, and central enso ring
// - Supports clean diagonal split + white-hot glowing blade cut seam when sliced in half

uniform vec3 paper_color : source_color = vec3(0.036, 0.038, 0.064);
uniform vec3 accent_color : source_color = vec3(1.0, 0.32, 0.24);
uniform vec3 gold_color : source_color = vec3(0.84, 0.72, 0.46);
uniform float glow_strength : hint_range(0.5, 3.0) = 1.65;
uniform float opacity : hint_range(0.0, 1.0) = 0.97;
// 0 = whole talisman, 1 = upper half (after cut), 2 = lower half (after cut)
uniform int half_mode = 0;
uniform float cut_slope = 0.18;

float box_border(vec2 p, vec2 b, float thickness) {
	vec2 d = abs(p) - b;
	float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	return 1.0 - smoothstep(thickness * 0.5, thickness, abs(dist));
}

float ring_line(vec2 p, float r, float thickness) {
	return 1.0 - smoothstep(thickness * 0.5, thickness, abs(length(p) - r));
}

void fragment() {
	// p in [-1, 1], y = -1 is top, y = +1 is bottom
	vec2 p = (UV - 0.5) * 2.0;

	// Traditional chamfered top corners of an ofuda
	if (abs(p.x) - p.y > 1.72) {
		discard;
	}

	float cut_line = p.y - p.x * cut_slope;
	float cut_seam = 0.0;
	if (half_mode == 1) {
		if (cut_line > 0.0) discard;
		cut_seam = 1.0 - smoothstep(0.0, 0.085, abs(cut_line));
	} else if (half_mode == 2) {
		if (cut_line <= 0.0) discard;
		cut_seam = 1.0 - smoothstep(0.0, 0.085, abs(cut_line));
	}

	// Subtle vertical washi paper fiber texture + warm inner gradient
	float fiber = sin(UV.x * 190.0) * 0.5 + sin(UV.y * 45.0 + UV.x * 30.0) * 0.5;
	float center_lift = 1.0 - smoothstep(0.0, 0.95, length(p * vec2(0.85, 0.65)));
	vec3 base = paper_color * (0.94 + 0.06 * fiber) + accent_color * (center_lift * 0.045);

	// Outer and inner border frames
	float outer_b = box_border(p, vec2(0.88, 0.92), 0.028);
	float inner_b = box_border(p, vec2(0.80, 0.85), 0.015);

	// Corner lattice accents
	float corner = box_border(abs(p) - vec2(0.68, 0.73), vec2(0.10, 0.10), 0.015);

	// Central enso/seal ring behind the Kanji (upper-middle, p.y around -0.22)
	vec2 kanji_p = vec2(p.x, (p.y + 0.22) * 2.1);
	float seal_ring = ring_line(kanji_p, 0.48, 0.024) + ring_line(kanji_p, 0.39, 0.013) * 0.65;

	// Vermilion hanko seal stamp at bottom center
	float hanko = box_border(p - vec2(0.0, 0.72), vec2(0.11, 0.055), 0.016);

	// Horizontal divider below the Kanji
	float divider = (1.0 - smoothstep(0.008, 0.016, abs(p.y - 0.14))) * step(abs(p.x), 0.68);

	float pulse = 0.90 + 0.10 * sin(TIME * 3.2);
	float rim_glow = smoothstep(0.75, 0.98, max(abs(p.x), abs(p.y)));

	vec3 ink_pattern = accent_color * glow_strength * pulse * (outer_b + seal_ring * 0.95 + hanko * 0.85 + rim_glow * 0.25)
		+ gold_color * 1.05 * (inner_b + corner * 0.70 + divider * 0.85);

	vec3 seam_col = mix(accent_color * 3.6, vec3(2.4, 2.1, 1.7), pow(cut_seam, 2.2)) * cut_seam;
	ALBEDO = base + ink_pattern + seam_col;
	ALPHA = opacity;
}

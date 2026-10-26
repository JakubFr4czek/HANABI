shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Four-part spawn seal on the arena floor: 桜 (Sakura) 雷 (Storm) 墨 (Ink) 影 (Shadow).
// Each quadrant has its own elemental accent color and brightens when that element is active.

uniform vec3 sakura_color : source_color = vec3(1.0, 0.22, 0.58);
uniform vec3 storm_color : source_color = vec3(0.28, 0.72, 1.0);
uniform vec3 ink_color : source_color = vec3(0.42, 0.50, 0.68);
uniform vec3 shadow_color : source_color = vec3(0.62, 0.26, 1.0);
uniform int active_element_index = -1; // -1 = none (balanced), 0 = sakura, 1 = storm, 2 = ink, 3 = shadow

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}

	float angle = atan(p.y, p.x); // -PI..PI
	// 4 quadrants rotated by 45 deg so each quadrant sits cleanly at N, E, S, W:
	// East (0): Sakura 桜, North (1): Storm 雷, West (2): Ink 墨, South (3): Shadow 影
	int quad = 0;
	if (abs(p.x) > abs(p.y)) {
		quad = (p.x >= 0.0) ? 0 : 2;
	} else {
		quad = (p.y < 0.0) ? 1 : 3;
	}

	vec3 elem_col = sakura_color;
	if (quad == 1) elem_col = storm_color;
	else if (quad == 2) elem_col = ink_color;
	else if (quad == 3) elem_col = shadow_color;

	float active_boost = (active_element_index == quad) ? 2.2 : ((active_element_index < 0) ? 1.15 : 0.55);
	float pulse = 0.88 + 0.12 * sin(TIME * 2.0 + float(quad) * 1.57);

	// Gap along the 4 diagonal dividers between quadrants.
	float diag_dist = min(abs(p.x - p.y), abs(p.x + p.y)) * 0.7071;
	float gap_mask = smoothstep(0.015, 0.032, diag_dist);

	// Outer double ring, quadrant arc band, and inner sacred lotus/compass geometry.
	float outer_ring = (1.0 - smoothstep(0.008, 0.022, abs(r - 0.94))) + (1.0 - smoothstep(0.006, 0.018, abs(r - 0.86))) * 0.7;
	float mid_ring = (1.0 - smoothstep(0.008, 0.020, abs(r - 0.52))) * gap_mask;
	float inner_ring = 1.0 - smoothstep(0.008, 0.020, abs(r - 0.24));

	// 8-fold inner star / petal motif.
	float star_r = 0.24 + 0.14 * abs(cos(angle * 2.0));
	float star_line = (1.0 - smoothstep(0.008, 0.022, abs(r - star_r))) * gap_mask;

	// Soft elemental fill inside each quadrant's glyph zone (r in 0.52..0.86).
	float band_fill = smoothstep(0.52, 0.56, r) * (1.0 - smoothstep(0.82, 0.86, r)) * gap_mask * 0.16;

	// Diagonal divider ticks.
	float divider_line = (1.0 - smoothstep(0.004, 0.012, diag_dist)) * step(0.24, r) * step(r, 0.94) * 0.45;

	float pattern = clamp((outer_ring + mid_ring + inner_ring + star_line) * gap_mask + band_fill + divider_line, 0.0, 1.0);
	vec3 col = elem_col * (0.35 + 1.35 * pattern) * active_boost * pulse;

	ALBEDO = col;
	ALPHA = clamp(pattern * (0.45 + 0.35 * active_boost), 0.0, 0.92);
}

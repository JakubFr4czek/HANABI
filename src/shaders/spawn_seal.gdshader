shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Four-part spawn seal on the arena floor: 桜 (Sakura) 雷 (Storm) 墨 (Ink) 影 (Shadow).
// At rest it is a dim, wet silver inlay in the stone; only the active
// element's quadrant lights up in its neon color (a single focal accent).

global uniform float storm_flash;

uniform vec3 inlay_color : source_color = vec3(0.16, 0.17, 0.22);
uniform vec3 sakura_color : source_color = vec3(1.0, 0.22, 0.58);
uniform vec3 storm_color : source_color = vec3(0.28, 0.72, 1.0);
uniform vec3 ink_color : source_color = vec3(0.42, 0.50, 0.68);
uniform vec3 shadow_color : source_color = vec3(0.62, 0.26, 1.0);
uniform int active_element_index = -1; // -1 = none, 0 = sakura, 1 = storm, 2 = ink, 3 = shadow

float line(float d, float w) {
	return 1.0 - smoothstep(w * 0.5, w, d);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float angle = atan(p.y, p.x);
	// East (0): Sakura 桜, North (1): Storm 雷, West (2): Ink 墨, South (3): Shadow 影
	int quad = abs(p.x) > abs(p.y) ? (p.x >= 0.0 ? 0 : 2) : (p.y < 0.0 ? 1 : 3);
	vec3 elem = quad == 0 ? sakura_color : (quad == 1 ? storm_color : (quad == 2 ? ink_color : shadow_color));

	float diag = min(abs(p.x - p.y), abs(p.x + p.y)) * 0.7071;
	float gap = smoothstep(0.012, 0.026, diag);
	float star_r = 0.24 + 0.14 * abs(cos(angle * 2.0));
	float pattern = clamp(
		(line(abs(r - 0.94), 0.018) + line(abs(r - 0.87), 0.012) * 0.7
		+ line(abs(r - 0.52), 0.014) + line(abs(r - 0.24), 0.014) + line(abs(r - star_r), 0.014)) * gap
		+ line(diag, 0.008) * step(0.24, r) * step(r, 0.94) * 0.5, 0.0, 1.0);

	bool active = active_element_index == quad;
	float pulse = 0.85 + 0.15 * sin(TIME * 1.6);
	float fill = active ? smoothstep(0.52, 0.6, r) * (1.0 - smoothstep(0.8, 0.87, r)) * gap * 0.12 : 0.0;
	vec3 col = active ? elem * (1.6 * pattern + fill * 2.0) * pulse : inlay_color * pattern * (1.0 + storm_flash * 1.5);
	ALBEDO = col;
	ALPHA = clamp(active ? pattern * 0.95 + fill : pattern * 0.7, 0.0, 0.95);
}

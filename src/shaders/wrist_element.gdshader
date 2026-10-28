shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// The element strip of the wrist plate (E3): one quad that draws the element
// crest (ring = the imbue time left, clockwise from 12 o'clock) and the two
// ability pips for the A and B buttons (ring = how far each has recharged, a
// full bright ring = ready), each on a dark inkstone disc. The kanji are Label3D
// nodes on top. Units are metres in the strip's own plane (y points down).

uniform vec2 size = vec2(0.1, 0.034);
uniform vec2 crest_center = vec2(-0.0355, 0.0);
uniform float crest_outer = 0.0140;
uniform float crest_inner = 0.0106;
uniform vec2 pip1_center = vec2(0.020, 0.0);
uniform vec2 pip2_center = vec2(0.041, 0.0);
uniform float pip_outer = 0.0085;
uniform float pip_inner = 0.0066;

uniform vec3 color : source_color = vec3(0.6, 0.6, 0.65);
// 1 with an element on the blade, 0 on plain steel (everything dims to a track).
uniform float lit : hint_range(0.0, 1.0) = 0.0;
uniform float crest_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float pip1_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float pip2_ratio : hint_range(0.0, 1.0) = 0.0;
// 1 in the last seconds: the crest beats at 3 Hz in step with the blade.
uniform float warn : hint_range(0.0, 1.0) = 0.0;
uniform float left = 0.0;
// 1 -> 0 right after an imbue.
uniform float flash : hint_range(0.0, 1.0) = 0.0;

float ring(vec2 p, vec2 c, float ri, float ro, float aa) {
	float r = length(p - c);
	return smoothstep(ri - aa, ri + aa, r) * (1.0 - smoothstep(ro - aa, ro + aa, r));
}

float disc(vec2 p, vec2 c, float ro, float aa) {
	return 1.0 - smoothstep(ro - aa, ro + aa, length(p - c));
}

// 1 where the clockwise angle from 12 o'clock is below ratio.
float sweep(vec2 p, vec2 c, float ratio) {
	if (ratio >= 0.999) {
		return 1.0;
	}
	vec2 d = p - c;
	float ang = fract(atan(d.x, -d.y) / TAU + 1.0);
	return (1.0 - smoothstep(ratio - 0.007, ratio + 0.007, ang)) * step(0.001, ratio);
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	float aa = max(fwidth(p.x) * 0.8, 0.00006);

	float back = max(disc(p, crest_center, crest_outer + 0.0006, aa),
		max(disc(p, pip1_center, pip_outer + 0.0006, aa), disc(p, pip2_center, pip_outer + 0.0006, aa)));
	vec3 col = vec3(0.012, 0.011, 0.018);
	float a = back * 0.82;

	vec3 base = mix(vec3(0.5, 0.47, 0.55), color, lit);
	vec3 track = base * mix(0.38, 0.2, lit);
	float pulse = mix(1.0, 0.35 + 0.65 * (0.5 + 0.5 * sin(18.8496 * left)), warn);
	vec3 on = base * (1.5 + flash * 2.0) * pulse;

	float cband = ring(p, crest_center, crest_inner, crest_outer, aa);
	float cfill = sweep(p, crest_center, crest_ratio) * lit;
	col = mix(col, mix(track, on, cfill), cband);
	a = max(a, cband * mix(0.7, 1.0, cfill));

	for (int i = 0; i < 2; i++) {
		vec2 c = i == 0 ? pip1_center : pip2_center;
		float ratio = i == 0 ? pip1_ratio : pip2_ratio;
		float band = ring(p, c, pip_inner, pip_outer, aa);
		float fill = sweep(p, c, ratio) * lit;
		float ready = step(0.999, ratio) * lit;
		vec3 pip_on = base * mix(1.25, 1.9, ready);
		col = mix(col, mix(track, pip_on, fill), band);
		a = max(a, band * mix(0.7, 1.0, fill));
	}

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.98);
}

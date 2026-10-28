shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled, shadows_disabled;

// The wrist readout (D14), one quad in the bracer's own plane (metres, "up" is +y):
// - the HP ring: a thin arc from 12 o'clock whose length is the health share, round
//   at both ends, coloured by the health (the script picks the colour);
// - the kcal fire inside the ring: noise flame in red, orange and yellow, lit by its
//   own colours only (no light). The white figure is a Label3D on top of it;
// - a hairline arc outside the ring for the time left on the imbued element.
// Everything else in the quad is alpha 0, so the plate has no panel behind it.

uniform vec2 size = vec2(0.06, 0.06);
uniform float ring_radius = 0.0170;
uniform float ring_width = 0.0042;
uniform float element_radius = 0.0236;
uniform float element_width = 0.0014;
uniform float flame_radius = 0.0136;

uniform vec3 hp_color : source_color = vec3(0.36, 0.84, 0.72);
uniform float hp_fill : hint_range(0.0, 1.0) = 1.0;
// 1 below the critical share: the ring breathes gently.
uniform float hp_pulse : hint_range(0.0, 1.0) = 0.0;

uniform vec3 element_color : source_color = vec3(0.8, 0.8, 0.8);
uniform float element_fill : hint_range(0.0, 1.0) = 0.0;
uniform float element_on : hint_range(0.0, 1.0) = 0.0;

uniform vec3 flame_edge : source_color = vec3(0.5, 0.05, 0.02);
uniform vec3 flame_mid : source_color = vec3(0.78, 0.18, 0.04);
uniform vec3 flame_core : source_color = vec3(1.0, 0.66, 0.2);
// 1 at rest, brighter for a moment on a level-up.
uniform float flame_gain : hint_range(0.0, 3.0) = 1.0;

// Parry and level-up glow on the ring (0..1).
uniform float glow : hint_range(0.0, 1.0) = 0.0;
// The gesture fade (0 hidden .. 1 shown).
uniform float presence : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.03 + 7.1) + 0.15 * vnoise(p * 4.1 - 3.7);
}

// 1 inside a band of half-width halfw around the signed distance d (anti-aliased).
float band(float d, float halfw, float aa) {
	return 1.0 - smoothstep(halfw - aa, halfw + aa, abs(d));
}

float disc(vec2 q, vec2 c, float r, float aa) {
	return 1.0 - smoothstep(r - aa, r + aa, length(q - c));
}

// Clockwise share of the circle measured from 12 o'clock, 0..1.
float clock_share(vec2 q) {
	return fract(atan(q.x, q.y) / TAU);
}

// An arc from 12 o'clock over `share` of the circle, with round caps at both ends.
float arc(vec2 q, float radius, float width, float share, float aa) {
	if (share <= 0.0005) {
		return 0.0;
	}
	float dshare = aa / (TAU * radius);
	float sweep = 1.0 - smoothstep(share - dshare, share + dshare, clock_share(q));
	float body = band(length(q) - radius, width * 0.5, aa) * sweep;
	float start_cap = disc(q, vec2(0.0, radius), width * 0.5, aa);
	float end_cap = disc(q, vec2(sin(share * TAU), cos(share * TAU)) * radius, width * 0.5, aa);
	return max(body, max(start_cap, end_cap));
}

// Source-over composite of one layer onto (col, a).
void over(inout vec3 col, inout float a, vec3 layer, float layer_a) {
	float out_a = layer_a + a * (1.0 - layer_a);
	if (out_a > 0.0001) {
		col = (layer * layer_a + col * a * (1.0 - layer_a)) / out_a;
	}
	a = out_a;
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 q = vec2(p.x, -p.y);
	float aa = max(fwidth(q.x) * 0.9, 0.00006);
	float r = length(q);

	vec3 col = vec3(0.0);
	float a = 0.0;

	// The fire: a noise tongue that rises and flickers, inside the ring.
	vec2 f = q / flame_radius;
	float fy = (f.y + 0.85) / 1.75;
	float n = fbm(vec2(f.x * 2.6, fy * 2.2 - TIME * 1.9));
	float half_w = mix(0.62, 0.04, pow(clamp(fy, 0.0, 1.0), 0.75)) * (0.8 + 0.45 * n);
	float lean = (n - 0.5) * 0.4 * clamp(fy, 0.0, 1.0);
	float dx = abs(f.x - lean) - half_w;
	float tongue = (1.0 - smoothstep(-0.06, 0.05, dx)) * smoothstep(-0.02, 0.06, fy) * (1.0 - smoothstep(0.9, 1.02, fy));
	float inner = clamp(-dx / max(half_w, 0.05), 0.0, 1.0);
	vec3 fire = mix(flame_edge, flame_mid, smoothstep(0.0, 0.55, inner));
	fire = mix(fire, flame_core, smoothstep(0.55, 1.0, inner) * (1.0 - smoothstep(0.1, 0.35, fy)));
	over(col, a, fire, clamp(tongue * 0.92 * flame_gain * (0.85 + 0.15 * n), 0.0, 1.0));

	// The ring: a muted track, the health arc over it, pulsing when critical.
	float pulse = 1.0 - hp_pulse * 0.1 * (1.0 - sin(TIME * 4.2));
	float track = band(r - ring_radius, ring_width * 0.5, aa) * 0.26;
	over(col, a, vec3(0.55, 0.56, 0.6), track);
	float hp_mask = arc(q, ring_radius, ring_width, hp_fill, aa);
	over(col, a, hp_color * pulse * (1.0 + glow * 0.5), hp_mask * 0.96);

	// The element's time left, on its own hairline outside the ring.
	float el = arc(q, element_radius, element_width, element_fill, aa) * element_on;
	over(col, a, element_color, el * 0.95);

	// A soft halo of the health colour, stronger after a parry or a level-up.
	float halo = exp(-pow((r - ring_radius) / 0.0062, 2.0)) * (0.08 + 0.3 * glow);
	over(col, a, hp_color, halo * step(0.001, hp_fill));

	ALBEDO = col;
	ALPHA = clamp(a * presence, 0.0, 1.0);
}

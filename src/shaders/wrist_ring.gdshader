shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled, shadows_disabled;

// The wrist readout (D14, D22), one quad in the bracer's own plane (metres, "up" is +y):
// - the HP ring: a thin arc from 12 o'clock whose length is the health share, round
//   at both ends, coloured by the health (the script picks the colour);
// - inside the ring, nothing: the kcal figure is a Label3D over a clear centre;
// - a hairline arc outside the ring for the time left on the imbued element;
// - three elemental charge orbs over the ring's top-right, in the order they were taken
//   (oldest first): an empty orb is a dim grey outline, a filled one takes its element's
//   colour with a soft glow. The script sets each slot's rgb colour and fill (a: 0 or 1).
// Everything else in the quad is alpha 0, so the plate has no panel behind it.

uniform vec2 size = vec2(0.06, 0.06);
uniform float ring_radius = 0.0170;
uniform float ring_width = 0.0042;
uniform float element_radius = 0.0236;
uniform float element_width = 0.0014;

uniform vec3 hp_color : source_color = vec3(0.36, 0.84, 0.72);
uniform float hp_fill : hint_range(0.0, 1.0) = 1.0;
// 1 below the critical share: the ring breathes gently.
uniform float hp_pulse : hint_range(0.0, 1.0) = 0.0;

uniform vec3 element_color : source_color = vec3(0.8, 0.8, 0.8);
uniform float element_fill : hint_range(0.0, 1.0) = 0.0;
uniform float element_on : hint_range(0.0, 1.0) = 0.0;

// The three charge orbs: centre radius, orb radius, and the clockwise angles (rad from 12 o'clock).
uniform float charge_radius = 0.0277;
uniform float charge_size = 0.0019;
uniform vec3 charge_angles = vec3(0.17, 0.61, 1.05);
// Slot colour (rgb, source colour) and fill (a: 1 = charged, 0 = empty), oldest charge first.
uniform vec4 charge_0 : source_color = vec4(0.3, 0.3, 0.34, 0.0);
uniform vec4 charge_1 : source_color = vec4(0.3, 0.3, 0.34, 0.0);
uniform vec4 charge_2 : source_color = vec4(0.3, 0.3, 0.34, 0.0);

// Parry and level-up glow on the ring (0..1).
uniform float glow : hint_range(0.0, 1.0) = 0.0;
// The gesture fade (0 hidden .. 1 shown).
uniform float presence : hint_range(0.0, 1.0) = 0.0;

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

// One charge orb at angle `ang`: an empty outline, or a filled disc with a soft glow.
void charge_orb(inout vec3 col, inout float a, vec2 q, float ang, vec4 slot, float aa) {
	vec2 c = vec2(sin(ang), cos(ang)) * charge_radius;
	float d = length(q - c);
	if (slot.a > 0.5) {
		float halo = exp(-pow((d - charge_size) / (charge_size * 1.6), 2.0)) * 0.35;
		over(col, a, slot.rgb, halo);
		// A little brighter toward the centre, so the orb reads as a bead, not a flat dot.
		vec3 bead = slot.rgb * (0.78 + 0.35 * (1.0 - clamp(d / charge_size, 0.0, 1.0)));
		over(col, a, bead, disc(q, c, charge_size, aa));
	} else {
		over(col, a, slot.rgb, band(d - charge_size * 0.8, charge_size * 0.12, aa) * 0.6);
	}
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 q = vec2(p.x, -p.y);
	float aa = max(fwidth(q.x) * 0.9, 0.00006);
	float r = length(q);

	vec3 col = vec3(0.0);
	float a = 0.0;

	// The ring: a muted track, the health arc over it, pulsing when critical.
	float pulse = 1.0 - hp_pulse * 0.1 * (1.0 - sin(TIME * 4.2));
	float track = band(r - ring_radius, ring_width * 0.5, aa) * 0.26;
	over(col, a, vec3(0.55, 0.56, 0.6), track);
	float hp_mask = arc(q, ring_radius, ring_width, hp_fill, aa);
	over(col, a, hp_color * pulse * (1.0 + glow * 0.5), hp_mask * 0.96);

	// The element's time left, on its own hairline outside the ring.
	float el = arc(q, element_radius, element_width, element_fill, aa) * element_on;
	over(col, a, element_color, el * 0.95);

	// The three charges, oldest first.
	charge_orb(col, a, q, charge_angles.x, charge_0, aa);
	charge_orb(col, a, q, charge_angles.y, charge_1, aa);
	charge_orb(col, a, q, charge_angles.z, charge_2, aa);

	// A soft halo of the health colour, stronger after a parry or a level-up.
	float halo = exp(-pow((r - ring_radius) / 0.0062, 2.0)) * (0.08 + 0.3 * glow);
	over(col, a, hp_color, halo * step(0.001, hp_fill));

	ALBEDO = col;
	ALPHA = clamp(a * presence, 0.0, 1.0);
}

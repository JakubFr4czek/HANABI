shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// Rim light of an imbued blade (E4): a second pass over the katana mesh, only
// the blade part, swollen a little (mostly in thickness) and drawn
// with a fresnel falloff. It is *mixed* over the scene, not added: an additive
// colour washes out to pastel white against the pale fog. Seen from behind, from the guard or edge-on, the thin
// steel still carries a soft glowing outline (light on the edge); face-on it
// is nearly invisible, so the steel texture and the edge light of
// katana_steel.gdshader keep the show. Same imbue clock as the steel pass:
// the guard-to-tip sweep, the drain on expiry and the 3 Hz warning.
// Blade = mesh-local Y > 0.014 (see katana_steel.gdshader).

uniform vec3 rim_color : source_color = vec3(1.0, 0.32, 0.74);
// 0 = off (the pass is removed from the blade then).
uniform float rim_strength : hint_range(0.0, 3.0) = 0.0;
uniform float rim_sweep = 2.0;
uniform float rim_warn : hint_range(0.0, 1.0) = 0.0;
uniform float rim_left = 0.0;
uniform float thickness_scale = 2.8;
uniform float width_scale = 1.4;

varying float v_blade;
varying float v_bt;

void vertex() {
	v_blade = smoothstep(0.012, 0.02, VERTEX.y);
	v_bt = clamp((VERTEX.y - 0.02) / 0.67, 0.0, 1.0);
	// The blade curves toward its spine; swell around its own centre line.
	float centre = 0.115 * pow(max(VERTEX.y - 0.22, 0.0), 2.0);
	VERTEX.z *= mix(1.0, thickness_scale, v_blade);
	VERTEX.x = centre + (VERTEX.x - centre) * mix(1.0, width_scale, v_blade);
}

void fragment() {
	if (v_blade < 0.5) {
		discard;
	}
	float reach = 1.0 - smoothstep(rim_sweep - 0.14, rim_sweep, v_bt);
	float pulse = mix(1.0, 0.30 + 0.70 * (0.5 + 0.5 * sin(18.8496 * rim_left)), rim_warn);
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float a = rim_strength * reach * pulse * (0.035 + 0.965 * f);
	ALBEDO = rim_color;
	ALPHA = clamp(a * 0.8, 0.0, 0.8);
}

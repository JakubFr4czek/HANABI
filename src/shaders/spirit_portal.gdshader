shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// The spirit gate the katana is drawn out of in the intro: a dark, slowly
// swirling well with a bright rim, opening and closing with [open].

uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.78, 0.62, 1.0);
uniform vec3 core_color : source_color = vec3(0.05, 0.04, 0.12);
uniform vec3 swirl_color : source_color = vec3(0.42, 0.36, 0.9);

void fragment() {
	if (open <= 0.001) {
		discard;
	}
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p) / open;
	if (r > 1.08) {
		discard;
	}
	float ang = atan(p.y, p.x);
	// Spiral arms turning inward.
	float swirl = sin(ang * 4.0 + r * 10.0 - TIME * 2.6) * 0.5 + 0.5;
	swirl *= smoothstep(0.05, 0.8, r);
	float rim = smoothstep(0.78, 0.97, r) * (1.0 - smoothstep(0.97, 1.06, r));
	float flicker = 0.85 + 0.15 * sin(TIME * 7.0 + ang * 3.0);
	vec3 inner = mix(core_color, swirl_color, swirl * 0.55);
	vec3 col = mix(inner, rim_color * 2.6 * flicker, rim);
	ALBEDO = col;
	// Dark well inside, soft at the centre so the world shows faintly through.
	float a = mix(0.82, 0.95, swirl) * smoothstep(0.0, 0.25, r * 1.6 + 0.1);
	ALPHA = clamp(max(a * (1.0 - rim), rim), 0.0, 1.0) * smoothstep(1.08, 0.98, r);
}

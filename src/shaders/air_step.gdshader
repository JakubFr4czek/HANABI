shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// A step on the air during the intro descent: where the foot lands a soft
// glowing print flares and a ripple ring runs outward, as if the air were
// still water. Lies flat (quad rotated into XZ); UV.y runs along the foot.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 step_color : source_color = vec3(0.62, 0.78, 1.0);
uniform float intensity = 1.6;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// The print: an oval under the sole, brightest as the foot lands.
	vec2 sole = p * vec2(3.6, 2.2);
	float print = exp(-dot(sole, sole) * 1.6) * (1.0 - smoothstep(0.0, 0.55, progress));
	// The ripple: a thin ring expanding from the print and thinning out.
	float r = length(p * vec2(1.0, 0.85));
	float ring_r = mix(0.12, 0.92, sqrt(progress));
	float ring_w = mix(0.05, 0.12, progress);
	float ring = (1.0 - smoothstep(0.0, ring_w, abs(r - ring_r))) * (1.0 - progress);
	// A second, fainter echo ring behind it.
	float echo_r = mix(0.04, 0.6, progress);
	float echo = (1.0 - smoothstep(0.0, ring_w * 0.8, abs(r - echo_r))) * (1.0 - progress) * 0.35;
	float a = (print * 0.9 + ring + echo) * smoothstep(1.0, 0.85, r);
	ALBEDO = step_color * intensity * a;
	ALPHA = clamp(a, 0.0, 1.0);
}

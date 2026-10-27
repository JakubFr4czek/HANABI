shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

// Hitodama (floating soul flame): teardrop spirit flame with elongated upper
// wisp, bright inner pearl core, and soft halo falloff.

uniform vec3 soul_color : source_color = vec3(0.38, 0.86, 1.0);
uniform float intensity : hint_range(0.2, 4.0) = 1.1;
uniform float phase = 0.0;

varying float v_height;

void vertex() {
	v_height = clamp(VERTEX.y * 7.5, -1.0, 1.0);
	float top = max(0.0, VERTEX.y);
	// Taper and stretch the upper half into a classic Hitodama flame tail.
	float taper = 1.0 - top * 4.2;
	VERTEX.xz *= clamp(taper, 0.14, 1.0);
	VERTEX.y += top * 1.25;
	VERTEX.x += sin(TIME * 5.8 + phase + VERTEX.y * 14.0) * top * 0.24;
	VERTEX.z += cos(TIME * 4.9 + phase * 1.3 + VERTEX.y * 14.0) * top * 0.24;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float core = pow(ndv, 2.8) * (1.0 - smoothstep(0.15, 0.95, v_height) * 0.55);
	float halo = pow(ndv, 1.15) * (1.0 - smoothstep(0.55, 1.0, v_height) * 0.45);
	float pulse = 0.90 + 0.10 * sin(TIME * 6.5 + phase);
	vec3 col = mix(soul_color, vec3(1.0, 0.98, 1.0), clamp(core * 0.85, 0.0, 1.0)) * intensity * pulse;
	ALBEDO = col;
	ALPHA = clamp(halo * 0.95 + core * 0.65, 0.0, 1.0);
}

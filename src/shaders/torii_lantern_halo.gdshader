shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

// Lantern light of a Torii gate that reads through the milk fog (E3): a soft
// halo, a hot core, and a thin vertical shaft of light so a gate is a *line* in
// the mist, not just another round blob. Mixed (not added) over the pale fog:
// an additive colour washes out to white on a bright background, a mix keeps its
// hue, and a dark ink-blue can even be darker than the fog. One quad, no lights.
uniform vec4 glow_color : source_color = vec4(1.0, 0.32, 0.74, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.9, 1.0);
// 0 = dormant (spent gate), 1 = awake, above 1 = the flare as the gate is crossed.
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float phase = 0.0;
// Radius of the round halo and half extents of the quad, in metres.
uniform float halo_radius = 1.0;
uniform vec2 half_size = vec2(1.2, 2.6);
uniform float shaft_width = 0.17;

varying float v_dist;

void vertex() {
	// Cylindrical (Y-up) camera-facing billboard.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]
	);
	v_dist = length(MODEL_MATRIX[3].xyz - INV_VIEW_MATRIX[3].xyz);
	// Past ~9 m the glow grows with distance so a far gate keeps its apparent
	// size in the fog (a fixed 2 m halo shrinks to a speck at 28 m).
	VERTEX.xy *= clamp(v_dist / 12.0, 1.0, 1.6);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * half_size;
	float breathe = 0.92 + 0.08 * sin(TIME * 1.3 + phase);
	float d = length(p) / halo_radius;
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	float core = pow(clamp(1.0 - d * 2.4, 0.0, 1.0), 2.0);
	float shaft = exp(-pow(p.x / shaft_width, 2.0)) * pow(clamp(1.0 - abs(p.y) / half_size.y, 0.0, 1.0), 1.5);
	// Up close the gate is its own light: keep the shaft and glare gentle.
	float far_k = smoothstep(3.0, 13.0, v_dist);
	float a = (halo * mix(0.5, 1.0, far_k) + shaft * 0.6 * far_k) * intensity * breathe;
	a += core * 0.4 * intensity;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = mix(glow_color.rgb, core_color.rgb, clamp(core * intensity, 0.0, 1.0) * 0.8);
	// Past ~18 m the glow thins a little more: the trunks and crowns in front of it
	// read through the milk, and the far gates stay a light rather than a blob.
	float far_thin = mix(1.0, 0.72, smoothstep(18.0, 36.0, v_dist));
	ALPHA = clamp(a * far_thin, 0.0, 0.5);
}

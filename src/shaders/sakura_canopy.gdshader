shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Restrained, high-depth sakura canopy blossom shader (GDD §9):
// Shapes each crossed quad into a cluster of 4 notched 5-petal sakura blossoms
// with alpha discard so the canopy has a delicate, lacy silhouette with sky gaps.
// Deep wine-magenta interior for depth, crisp Fresnel/rim glow on petal edges,
// and only rare bright neon-pink accent blossoms (~8% via INSTANCE_CUSTOM.y).

uniform vec3 deep_petal_color : source_color = vec3(0.14, 0.018, 0.085);
uniform vec3 mid_petal_color : source_color = vec3(0.48, 0.07, 0.28);
uniform vec3 rim_neon_color : source_color = vec3(1.0, 0.26, 0.64);
uniform vec3 accent_neon_color : source_color = vec3(1.0, 0.56, 0.85);
uniform vec3 iridescence_color : source_color = vec3(0.46, 0.34, 0.96);

varying vec4 v_custom;
varying vec3 v_world_pos;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	// Gentle organic rustle in the storm breeze per cluster.
	float phase = v_custom.x * 19.3 + TIME * 1.45;
	float flutter = 0.022 + 0.015 * v_custom.z;
	VERTEX.x += sin(phase + VERTEX.y * 4.0) * flutter;
	VERTEX.z += cos(phase * 0.85 + VERTEX.x * 4.0) * flutter;
	VERTEX.y += sin(phase * 1.3 + UV.x * 3.14) * (flutter * 0.55);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float petal_lobe(vec2 p, float angle_offset) {
	float a = atan(p.y, p.x) + angle_offset;
	float r = length(p);
	// 5-petal sakura flower with characteristic V-notches at the tip of each petal.
	float sector = mod(a + 3.14159265, 1.25663706) - 0.62831853; // 2*PI / 5
	float cos5 = cos(sector * 2.5);
	float notch = exp(-abs(sector) * 14.0) * 0.14;
	float target_r = (0.36 + 0.56 * pow(max(cos5, 0.0), 0.62)) - notch;
	return target_r - r;
}

void fragment() {
	// Each quad contains a small sprig of 4 sakura blossoms at different offsets/scales
	// so the canopy looks like lacy twig-clusters of tiny petals with sky gaps between them.
	vec2 uv_centered = (UV - vec2(0.5)) * 2.05;
	float seed = v_custom.x * 6.28318;

	vec2 p1 = (uv_centered - vec2(-0.22, 0.18)) * 1.25;
	vec2 p2 = (uv_centered - vec2(0.24, 0.12)) * 1.35;
	vec2 p3 = (uv_centered - vec2(-0.08, -0.22)) * 1.30;
	vec2 p4 = (uv_centered - vec2(0.22, -0.26)) * 1.48;

	float d1 = petal_lobe(p1, seed);
	float d2 = petal_lobe(p2, seed + 1.1);
	float d3 = petal_lobe(p3, seed + 2.3);
	float d4 = petal_lobe(p4, seed + 3.7);

	float d = max(max(d1, d2), max(d3, d4));
	if (d < 0.0) {
		discard;
	}

	// Distance from the nearest petal edge (0 at outer edge, ~0.55 at flower core).
	float edge_factor = 1.0 - smoothstep(0.0, 0.25, d);
	float core_factor = smoothstep(0.22, 0.52, d);

	float r_min = min(min(length(p1), length(p2)), min(length(p3), length(p4)));
	float stamen_dots = smoothstep(0.16, 0.04, r_min) * step(0.62, sin(atan(uv_centered.y, uv_centered.x) * 15.0 + seed));

	// INSTANCE_CUSTOM:
	// .x = random seed (0..1)
	// .y = accent weight (0..1, > 0.87 means rare bright neon accent cluster)
	// .z = canopy exposure / outer-shell factor (0 = deep interior shadow, 1 = outer crown tip)
	// .w = height factor (0 = lower drooping bough, 1 = high crown)
	float exposure = clamp(v_custom.z, 0.0, 1.0);
	float is_accent = smoothstep(0.86, 0.96, v_custom.y);

	float ndotv = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - clamp(ndotv, 0.0, 1.0), 2.2);
	float rim = clamp(edge_factor * 0.76 + fresnel * 0.68, 0.0, 1.0);

	// Base albedo stays dark wine/plum in the interior and rich magenta on outer twigs.
	vec3 base_col = mix(deep_petal_color, mid_petal_color, exposure * 0.78 + 0.22 * (1.0 - core_factor));
	base_col = mix(base_col, rim_neon_color * 0.88, rim * 0.58);

	// Restrained emission: deep interior stays dark; petal edges get a crisp Fresnel/rim
	// neon line; only ~10% of clusters flare as bright sakura accents.
	vec3 edge_glow_col = mix(rim_neon_color, iridescence_color, fresnel * 0.26);
	float base_emit = mix(0.03, 0.24, exposure);
	float rim_emit = pow(rim, 1.55) * mix(0.36, 1.08, exposure);
	float accent_emit = is_accent * (0.62 + 0.92 * rim);

	vec3 emission = base_col * base_emit
		+ edge_glow_col * rim_emit
		+ accent_neon_color * (accent_emit + stamen_dots * 0.50 * exposure);

	ALBEDO = base_col;
	EMISSION = emission;
	ROUGHNESS = 0.30;
	METALLIC = 0.05;
}

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Wet dark-stone disc platform floating in the Dojo of the Storm (GDD §9).
// Carved concentric dojo rings, radial slab joints, damp mirror sheen, and
// soft baked-style sakura canopy bounce on the western rim under the overhanging boughs.

uniform vec3 stone_base : source_color = vec3(0.075, 0.08, 0.11);
uniform vec3 stone_dark : source_color = vec3(0.04, 0.045, 0.065);
uniform vec3 ring_glow_color : source_color = vec3(0.18, 0.16, 0.30);
uniform vec3 sakura_tint : source_color = vec3(0.76, 0.14, 0.44);
uniform vec3 lightning_tint : source_color = vec3(0.35, 0.68, 1.0);
uniform float lightning_flash : hint_range(0.0, 2.0) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_local_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(234.56, 789.01));
	p += dot(p, p + 33.33);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_normal = NORMAL;
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float r = length(xz);
	float angle = atan(xz.y, xz.x);

	float n_coarse = noise2(xz * 1.4);
	float n_fine = noise2(xz * 6.5);
	float grain = n_coarse * 0.65 + n_fine * 0.35;

	// Concentric stone rings at r = 1.72, 3.65, 4.95 m + 16 radial slab joints outside the center seal.
	float ring1 = 1.0 - smoothstep(0.012, 0.032, abs(r - 1.72));
	float ring2 = 1.0 - smoothstep(0.015, 0.038, abs(r - 3.65));
	float ring3 = 1.0 - smoothstep(0.02, 0.045, abs(r - 4.95));
	float radial_spoke = (1.0 - smoothstep(0.012, 0.028, abs(sin(angle * 8.0)) * r)) * step(1.72, r) * step(r, 4.95);
	float groove = clamp(ring1 + ring2 + ring3 + radial_spoke * 0.65, 0.0, 1.0);

	vec3 col = mix(stone_dark, stone_base, grain);
	col = mix(col, stone_dark * 0.55, groove * 0.7);

	// Dampness / wet puddles on the top surface of the disc.
	float top_mask = smoothstep(0.5, 0.9, v_local_normal.y);
	float puddle = smoothstep(0.48, 0.75, n_coarse) * top_mask;
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 4.0) * (0.35 + 0.65 * puddle);

	// Soft magenta canopy bounce on the western/north-western edge of the stone disc
	// where the monumental off-platform sakura tree's boughs reach across the water.
	vec2 sakura_delta = (xz - vec2(-4.2, -2.2)) / vec2(3.2, 2.8);
	float sakura_pool = exp(-dot(sakura_delta, sakura_delta) * 1.25) * top_mask;
	float dappled = 0.55 + 0.45 * smoothstep(0.3, 0.7, n_fine);
	float sakura_bounce = sakura_pool * dappled * (0.45 + 0.55 * puddle);

	vec3 wet_refl = vec3(0.05, 0.04, 0.11) * fresnel;
	wet_refl += sakura_tint * sakura_bounce * (0.15 + 0.22 * fresnel);
	wet_refl += ring_glow_color * (ring1 * 0.45 + ring2 * 0.25 + ring3 * 0.35);
	wet_refl += lightning_tint * lightning_flash * (0.12 + 0.28 * fresnel);

	ALBEDO = col;
	EMISSION = wet_refl;
	ROUGHNESS = mix(0.68, 0.16, puddle);
	METALLIC = 0.12;
}

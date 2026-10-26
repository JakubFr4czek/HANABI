shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Endless still water-mirror surrounding the floating stone disc (GDD §9).
// Fakes sky, torii, sakura canopy, and lightning reflections in the material (no SSR)
// for Quest 3 / Compatibility renderer performance.

uniform vec3 deep_water_color : source_color = vec3(0.012, 0.016, 0.036);
uniform vec3 sky_zenith_color : source_color = vec3(0.04, 0.025, 0.095);
uniform vec3 sky_horizon_color : source_color = vec3(0.035, 0.04, 0.10);
uniform vec3 torii_reflection_color : source_color = vec3(0.42, 0.05, 0.06);
uniform vec3 sakura_reflection_color : source_color = vec3(0.76, 0.14, 0.44);
uniform vec3 lightning_color : source_color = vec3(0.35, 0.68, 1.0);
uniform float lightning_flash : hint_range(0.0, 2.0) = 0.0;
uniform float platform_radius = 5.25;

varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
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
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float dist = length(xz);

	// Gentle ripples on the water mirror + faint concentric rings around the stone disc & sakura trunk.
	float n1 = noise2(xz * 1.8 + vec2(TIME * 0.08, -TIME * 0.06));
	float n2 = noise2(xz * 4.2 - vec2(TIME * 0.11, TIME * 0.09));
	float edge_dist = max(dist - platform_radius, 0.0);
	float ring_ripple = sin(edge_dist * 9.0 - TIME * 1.4) * exp(-edge_dist * 0.35);

	vec2 grad = vec2(n1 - 0.5, n2 - 0.5) * 0.035 + normalize(xz + vec2(1e-4)) * ring_ripple * 0.015;
	vec3 ripple_normal = normalize(vec3(grad.x, 1.0, grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(ripple_normal, 0.0)).xyz);

	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.16 + 0.84 * pow(1.0 - ndotv, 4.0);

	// Faked sky reflection with drifting cloud modulation.
	float cloud_mod = smoothstep(0.25, 0.75, n1 * 0.6 + n2 * 0.4);
	vec3 refl = mix(sky_horizon_color, sky_zenith_color, clamp(ndotv * 1.4, 0.0, 1.0));
	refl += vec3(0.045, 0.03, 0.09) * cloud_mod;

	// Mirrored crimson silhouette glow below the giant torii behind the mannequin (z ~ -10.5).
	vec2 torii_delta = (xz - vec2(0.0, -10.5)) / vec2(4.2, 5.5);
	float torii_pool = exp(-dot(torii_delta, torii_delta) * 1.8) * (0.65 + 0.35 * sin(xz.x * 3.0 + n1 * 2.5));
	refl += torii_reflection_color * torii_pool * 0.45;

	// Mirrored dappled magenta-pink reflection below the monumental sakura canopy in the water (around (-7.8, -3.8)).
	vec2 sakura_delta = (xz - vec2(-7.8, -3.8)) / vec2(5.8, 4.8);
	float ripple_shimmer = 0.52 + 0.48 * sin(xz.x * 3.8 + xz.y * 3.2 + n2 * 4.2);
	float sakura_pool = exp(-dot(sakura_delta, sakura_delta) * 1.25) * ripple_shimmer;
	refl += sakura_reflection_color * sakura_pool * 0.56;

	// Lightning reflection streak across the water mirror.
	float bolt_streak = exp(-pow((xz.x + 2.5) * 0.14, 2.0)) * smoothstep(-2.0, -35.0, xz.y);
	refl += lightning_color * lightning_flash * (0.28 + 0.65 * bolt_streak);

	// Subtle white-violet shore ring right where the stone platform meets the water.
	float shore_foam = exp(-edge_dist * 4.5) * smoothstep(0.0, 0.08, edge_dist);
	refl += vec3(0.16, 0.14, 0.28) * shore_foam * 0.4;

	// Distance fade into the dark horizon fog.
	float horizon_fade = smoothstep(25.0, 95.0, dist);
	vec3 water = mix(deep_water_color, refl, fresnel);
	water = mix(water, sky_horizon_color + lightning_color * lightning_flash * 0.12, horizon_fade);

	ALBEDO = water * 0.35;
	EMISSION = water * 0.85;
	ROUGHNESS = 0.08;
	METALLIC = 0.15;
}

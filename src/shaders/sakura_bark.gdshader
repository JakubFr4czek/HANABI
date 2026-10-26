shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Dark, almost-black gnarled sakura bark shader with subtle wet rim and
// baked-like warm magenta canopy bounce from above (GDD §9).

uniform vec3 bark_dark : source_color = vec3(0.014, 0.011, 0.022);
uniform vec3 bark_crevice : source_color = vec3(0.032, 0.022, 0.048);
uniform vec3 canopy_bounce_color : source_color = vec3(0.75, 0.14, 0.44);
uniform vec3 storm_rim_color : source_color = vec3(0.18, 0.24, 0.45);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_custom;

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
	v_custom = INSTANCE_CUSTOM;
	// Subtle sway in high thin twigs only (v_custom.x stores branch height tier 0..1).
	float sway = smoothstep(0.45, 1.0, v_custom.x) * 0.022;
	VERTEX.x += sin(TIME * 1.15 + VERTEX.y * 2.0 + v_custom.y * 6.28) * sway;
	VERTEX.z += cos(TIME * 0.95 + VERTEX.x * 2.0 + v_custom.y * 6.28) * sway * 0.8;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Gnarled vertical/spiral bark ridges.
	vec2 bark_uv = vec2(UV.x * 9.0 + v_world_pos.y * 0.8, v_world_pos.y * 2.6);
	float n1 = noise2(bark_uv);
	float n2 = noise2(bark_uv * 2.7 + vec2(3.1, 1.7));
	float ridge = smoothstep(0.25, 0.78, n1 * 0.65 + n2 * 0.35);

	vec3 base_col = mix(bark_dark, bark_crevice, ridge);

	// Soft magenta bounce from the blossom canopy onto upper/inner bark surfaces
	// + subtle water-mirror bounce near the roots.
	float height_under_canopy = smoothstep(1.2, 5.8, v_world_pos.y) * (1.0 - smoothstep(8.2, 10.5, v_world_pos.y));
	float up_facing = clamp(v_world_normal.y * 0.65 + 0.35, 0.0, 1.0);
	float root_glow = exp(-max(v_world_pos.y, 0.0) * 1.4) * 0.35;
	float canopy_bounce = (height_under_canopy * up_facing * 0.65 + root_glow) * (0.65 + 0.35 * ridge);

	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 3.2);

	ALBEDO = base_col;
	EMISSION = canopy_bounce_color * canopy_bounce * 0.28 + storm_rim_color * fresnel * 0.08;
	ROUGHNESS = mix(0.86, 0.58, fresnel);
	METALLIC = 0.05;
}

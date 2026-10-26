shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx, fog_disabled;

// Dojo of the Storm — Real-time Water Shader (Quest 3 Compatibility safe).
// Features:
// 1. Summed Gerstner/sine vertex displacement (dampened under the stone platform).
// 2. Dual scrolling normal maps in crossing directions + procedural capillary wave normals.
// 3. Concentric ripples around the stone platform rim, torii pillars, sakura trunk, and raindrops.
// 4. True Schlick Fresnel: dark/translucent abyssal depth when looking down near the platform edge,
//    sky/neon reflection at grazing angles.
// 5. Normal-distorted equirectangular baked storm sky panorama + ray-projected reflections of
//    the Sakura tree, Giant Torii, and lightning bolts broken into liquid wave facets.

uniform vec4 deep_water_color : source_color = vec4(0.005, 0.007, 0.020, 1.0);
uniform vec4 shallow_edge_color : source_color = vec4(0.014, 0.022, 0.052, 1.0);
uniform vec4 abyss_edge_color : source_color = vec4(0.002, 0.003, 0.009, 1.0);
uniform vec4 horizon_sky_color : source_color = vec4(0.058, 0.042, 0.135, 1.0);
uniform vec4 zenith_sky_color : source_color = vec4(0.015, 0.010, 0.040, 1.0);
uniform vec4 sakura_reflection_color : source_color = vec4(0.96, 0.22, 0.58, 1.0);
uniform vec4 torii_reflection_color : source_color = vec4(0.90, 0.16, 0.08, 1.0);
uniform vec4 lightning_reflection_color : source_color = vec4(0.45, 0.65, 1.0, 1.0);
uniform vec4 fog_color : source_color = vec4(0.032, 0.026, 0.072, 1.0);

uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_panorama : source_color, filter_linear_mipmap, repeat_enable;

uniform vec2 normal_scroll_a = vec2(0.032, 0.021);
uniform vec2 normal_scroll_b = vec2(-0.026, 0.035);
uniform float normal_tile_a : hint_range(0.02, 1.0) = 0.28;
uniform float normal_tile_b : hint_range(0.02, 1.0) = 0.48;
uniform float normal_strength : hint_range(0.0, 1.5) = 0.72;

uniform float wave_speed : hint_range(0.0, 4.0) = 1.30;
uniform float wave_height : hint_range(0.0, 0.25) = 0.062;
uniform float wave_chop : hint_range(0.0, 1.0) = 0.42;
uniform float fresnel_power : hint_range(1.0, 8.0) = 3.8;
uniform float fresnel_bias : hint_range(0.0, 0.3) = 0.02;
uniform float platform_radius : hint_range(1.0, 15.0) = 5.25;
uniform float rain_ripple_intensity : hint_range(0.0, 1.5) = 0.95;

uniform float lightning_flash : hint_range(0.0, 2.0) = 0.0;
uniform vec2 lightning_dir = vec2(-0.35, -0.94);

varying vec3 v_world_pos;
varying float v_wave_height;
varying vec2 v_gerstner_slope;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Expanding raindrop ripple ring in a tiled cell
vec3 rain_ripple_cell(vec2 p, float t, float seed_shift) {
	vec2 cell = floor(p);
	float h1 = hash21(cell + vec2(seed_shift, 0.0));
	float h2 = hash21(cell + vec2(19.3, 71.7 + seed_shift));
	vec2 center = cell + vec2(0.20 + 0.60 * h1, 0.20 + 0.60 * h2);
	vec2 d = p - center;
	float dist = length(d);
	float phase = fract(t * (0.58 + 0.32 * h1) + h2);
	float radius = phase * 0.88;
	float ring_dist = dist - radius;
	// Double-ring packet per raindrop impact
	float env = exp(-abs(ring_dist) * 16.0) * pow(1.0 - phase, 1.35) * smoothstep(0.015, 0.08, radius);
	float wave = sin(ring_dist * 54.0);
	float d_wave = cos(ring_dist * 54.0) * env;
	float crest = pow(max(0.0, wave), 2.0) * env;
	vec2 dir = d / max(dist, 0.001);
	return vec3(dir * d_wave, crest);
}

vec3 sample_rain_ripples(vec2 world_xz, float t) {
	vec3 r1 = rain_ripple_cell(world_xz * 1.25, t, 0.0);
	vec3 r2 = rain_ripple_cell((world_xz + vec2(2.3, -1.7)) * 0.85, t * 0.88 + 0.41, 13.7);
	vec3 r3 = rain_ripple_cell((world_xz + vec2(-4.1, 3.2)) * 1.65, t * 1.12 + 0.73, 29.1);
	return r1 * 0.55 + r2 * 0.48 + r3 * 0.42;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r = length(world_pos.xz);
	// Dampen vertex displacement right under the stone disc so it never pokes through the floor,
	// ramping up smoothly right past the platform rim (r > 5.05 m).
	float open_water = smoothstep(platform_radius - 0.30, platform_radius + 1.15, r) * (1.0 - smoothstep(32.0, 65.0, r));
	float t = TIME * wave_speed;

	// 4 crossing Gerstner-style wave trains
	vec2 d1 = normalize(vec2(0.84, 0.54));
	vec2 d2 = normalize(vec2(-0.62, 0.78));
	vec2 d3 = normalize(vec2(-0.36, -0.93));
	vec2 d4 = normalize(vec2(0.95, -0.31));

	float p1 = dot(world_pos.xz, d1) * 1.65 + t * 1.55;
	float p2 = dot(world_pos.xz, d2) * 2.55 - t * 1.90;
	float p3 = dot(world_pos.xz, d3) * 3.85 + t * 2.35;
	float p4 = dot(world_pos.xz, d4) * 5.60 - t * 2.85;

	float h = (
		sin(p1) * 0.44 +
		sin(p2) * 0.30 +
		sin(p3) * 0.16 +
		sin(p4) * 0.10
	) * wave_height * open_water;

	vec2 horiz_disp = (
		d1 * cos(p1) * 0.40 +
		d2 * cos(p2) * 0.25 +
		d3 * cos(p3) * 0.12
	) * (wave_height * wave_chop * open_water);

	vec2 slope = (
		d1 * (cos(p1) * 1.65 * 0.44) +
		d2 * (cos(p2) * 2.55 * 0.30) +
		d3 * (cos(p3) * 3.85 * 0.16) +
		d4 * (cos(p4) * 5.60 * 0.10)
	) * wave_height * open_water;

	VERTEX.y += h;
	VERTEX.xz += horiz_disp;

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wave_height = h;
	v_gerstner_slope = slope;
}

vec2 dir_to_equirect_uv(vec3 dir) {
	vec3 d = normalize(dir);
	float u = atan(d.x, -d.z) / (2.0 * PI) + 0.5;
	float v = acos(clamp(d.y, -1.0, 1.0)) / PI;
	return vec2(u, v);
}

// Helper for obstacle ring ripples (torii pillars, sakura trunk)
void add_obstacle_ripple(vec2 world_xz, vec2 center, float radius, float freq, float falloff, float t, inout vec2 ripple_grad, inout float ripple_crest) {
	vec2 d = world_xz - center;
	float dist = max(length(d) - radius, 0.0);
	float env = exp(-dist * falloff) * smoothstep(0.0, 0.05, dist);
	float phase = dist * freq - t * 3.4;
	ripple_grad += (d / max(length(d), 0.001)) * cos(phase) * env;
	ripple_crest += pow(max(0.0, sin(phase)), 2.5) * env;
}

void fragment() {
	vec3 world_pos = v_world_pos;
	float r = length(world_pos.xz);
	float t = TIME * wave_speed;

	// 1. Dual scrolling normal map layers moving in crossing directions
	vec2 uv_a = world_pos.xz * normal_tile_a + TIME * normal_scroll_a;
	vec2 uv_b = vec2(
		world_pos.x * 0.866 - world_pos.z * 0.500,
		world_pos.x * 0.500 + world_pos.z * 0.866
	) * normal_tile_b + TIME * normal_scroll_b;

	vec3 n_a = texture(normal_map_a, uv_a).rgb * 2.0 - 1.0;
	vec3 n_b = texture(normal_map_b, uv_b).rgb * 2.0 - 1.0;

	// Multi-scale wave normal synthesis: broad normal maps + sharp crossing capillary wavelets
	vec2 n_tex = (n_a.xy * 1.45 + n_b.xy * 1.35);
	vec2 w_dir1 = vec2(0.92, 0.39);
	vec2 w_dir2 = vec2(-0.76, 0.65);
	vec2 w_dir3 = vec2(0.28, -0.96);
	float w1 = cos(dot(world_pos.xz, w_dir1) * 5.8 + t * 2.8 + n_a.x * 2.2);
	float w2 = cos(dot(world_pos.xz, w_dir2) * 8.4 - t * 3.3 + n_b.y * 2.2);
	float w3 = cos(dot(world_pos.xz, w_dir3) * 13.5 + t * 4.1);
	vec2 n_cap = (w_dir1 * w1 * 0.45 + w_dir2 * w2 * 0.35 + w_dir3 * w3 * 0.22);

	// 2. Shore ripples lapping around the stone platform rim (r = 5.25 m)
	float edge_dist = max(r - platform_radius, 0.0);
	vec2 radial_dir = world_pos.xz / max(r, 0.001);
	float shore_env = exp(-edge_dist * 0.72) * smoothstep(0.0, 0.06, edge_dist);
	float shore_phase = edge_dist * 12.5 - t * 2.9 + (n_a.x + n_b.y) * 1.8;
	float shore_wave = cos(shore_phase) * shore_env;
	float shore_crest = pow(max(0.0, sin(shore_phase)), 3.5) * shore_env;
	// Immediate meniscus/foam line hugging the wet stone rim (0..18 cm from platform edge)
	float rim_meniscus = exp(-edge_dist * 11.0) * (0.65 + 0.35 * sin(atan(world_pos.z, world_pos.x) * 18.0 + t * 2.0));

	// 3. Concentric ripples around Giant Torii pillars, sunken torii, and Sakura trunk
	vec2 pillar_grad = vec2(0.0);
	float pillar_crest = 0.0;
	add_obstacle_ripple(world_pos.xz, vec2(-3.2, -10.5), 0.38, 14.0, 0.85, t, pillar_grad, pillar_crest);
	add_obstacle_ripple(world_pos.xz, vec2( 3.2, -10.5), 0.38, 14.0, 0.85, t, pillar_grad, pillar_crest);
	add_obstacle_ripple(world_pos.xz, vec2(-9.2,  -4.6), 0.68, 11.0, 0.68, t, pillar_grad, pillar_crest);
	add_obstacle_ripple(world_pos.xz, vec2(-5.4, -12.4), 0.30, 13.0, 0.90, t, pillar_grad, pillar_crest);
	add_obstacle_ripple(world_pos.xz, vec2( 5.8, -13.2), 0.30, 13.0, 0.90, t, pillar_grad, pillar_crest);

	// 4. Raindrop ripple rings across the water
	float rain_fade = 1.0 - smoothstep(11.0, 20.0, r);
	vec3 rain_rip = sample_rain_ripples(world_pos.xz, TIME * 0.95) * (rain_ripple_intensity * rain_fade);

	// Total normal slope perturbation in world space
	vec2 total_slope =
		v_gerstner_slope * 3.2 +
		(n_tex * 0.65 + n_cap * 0.55) * normal_strength +
		radial_dir * (shore_wave * 0.34) +
		pillar_grad * 0.32 +
		rain_rip.xy * 0.38;

	vec3 world_normal = normalize(vec3(-total_slope.x, 1.0, -total_slope.y));

	// Camera distance and true view vector
	vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view_vec = cam_pos - world_pos;
	float cam_dist = length(view_vec);
	vec3 world_view = view_vec / max(cam_dist, 0.001);

	// 5. True Schlick Fresnel:
	// Steep downward view near the platform rim -> low Fresnel -> dark translucent depth.
	// Grazing angles further out -> high Fresnel -> strong storm sky & neon reflection.
	float ndotv = clamp(dot(world_normal, world_view), 0.0, 1.0);
	float flat_ndotv = clamp(world_view.y, 0.0, 1.0);
	float fresnel = clamp(fresnel_bias + (1.0 - fresnel_bias) * pow(1.0 - ndotv, fresnel_power), 0.0, 1.0);
	// Suppress reflection when looking down into the water near the platform edge so the dark depth reads clearly
	float near_rim_depth_view = exp(-edge_dist * 0.48) * smoothstep(0.14, 0.48, flat_ndotv);
	fresnel *= mix(1.0, 0.18, near_rim_depth_view);

	// 6. Dark water depth & submerged platform drop-off shelf near the rim
	vec2 refracted_xz = world_pos.xz + total_slope * 0.28;
	float refracted_edge = max(length(refracted_xz) - platform_radius, 0.0);
	// Underwater stone shelf extending ~0.75 m past the rim before dropping into the dark abyss
	float submerged_shelf = exp(-refracted_edge * 2.4) * (0.6 + 0.4 * n_a.x);
	float shallow_band = exp(-edge_dist * 0.45);
	float abyss_trench = smoothstep(0.25, 1.2, edge_dist) * exp(-edge_dist * 0.45);

	vec3 water_body = mix(deep_water_color.rgb, shallow_edge_color.rgb, shallow_band * 0.65);
	water_body = mix(water_body, vec3(0.032, 0.038, 0.068), submerged_shelf * 0.58);
	water_body = mix(water_body, abyss_edge_color.rgb, abyss_trench * 0.78);

	// 7. Reflected ray distorted by the dual normal maps & waves
	vec3 refl_dir = reflect(-world_view, world_normal);
	refl_dir.y = max(refl_dir.y, 0.015);
	vec3 warped_refl_dir = normalize(vec3(
		refl_dir.x - total_slope.x * 0.85,
		max(0.02, refl_dir.y + abs(total_slope.x + total_slope.y) * 0.14),
		refl_dir.z - total_slope.y * 0.85
	));
	vec2 sky_uv = dir_to_equirect_uv(warped_refl_dir);
	vec3 baked_sky = textureLod(sky_panorama, sky_uv, 1.0).rgb;
	float sky_elev = clamp(warped_refl_dir.y, 0.0, 1.0);
	vec3 analytic_sky = mix(horizon_sky_color.rgb, zenith_sky_color.rgb, pow(sky_elev, 0.55));
	vec3 sky_refl = mix(analytic_sky, baked_sky, 0.84);

	// Wave-facet contrast: wave slopes tilted toward the camera catch sky/neon glints,
	// while back-slopes and troughs remain deep dark indigo
	float facet_tilt = dot(total_slope, normalize(world_view.xz + vec2(0.0001)));
	float wave_facet = smoothstep(-0.22, 0.24, facet_tilt + v_wave_height * 3.5);
	sky_refl *= mix(0.38, 1.55, wave_facet);

	// 8. Ray-projected Sakura Tree reflection (-9.2, y, -4.6) distorted by wave normals:
	// Project the normal-perturbed reflection ray onto the vertical plane of the Sakura tree.
	vec2 sakura_center = vec2(-9.2, -4.6);
	vec2 to_sakura = sakura_center - world_pos.xz;
	float dist_to_sakura = length(to_sakura);
	vec2 sakura_dir = to_sakura / max(dist_to_sakura, 0.001);
	float ray_toward_sakura = max(0.0, dot(normalize(warped_refl_dir.xz + vec2(0.0001)), sakura_dir));
	vec3 sakura_hit = world_pos + warped_refl_dir * min(dist_to_sakura, 18.0);
	// Radial distance in the virtual vertical reflection plane to the blossom canopy (centered at y = 4.6)
	float canopy_horiz = length(sakura_hit.xz - sakura_center);
	float canopy_vert = abs(sakura_hit.y - 4.4);
	// Blossom cluster noise in the reflected image so it reads as broken petal clusters, not a flat gradient
	float cluster_pattern = 0.5 + 0.5 * sin(sakura_hit.x * 2.8 + sakura_hit.y * 3.4) * cos(sakura_hit.z * 2.6 - sakura_hit.y * 2.9);
	float sakura_canopy_mask = exp(-canopy_horiz * 0.28) * exp(-canopy_vert * 0.36) * pow(ray_toward_sakura, 2.2);
	float sakura_shatter = smoothstep(0.18, 0.82, wave_facet * 0.65 + cluster_pattern * 0.55);
	float sakura_refl = sakura_canopy_mask * sakura_shatter * (1.0 - smoothstep(14.0, 24.0, dist_to_sakura));
	sky_refl += sakura_reflection_color.rgb * sakura_refl * 1.35;

	// 9. Ray-projected Giant Torii reflection (x in [-4.2, 4.2], z = -10.5) distorted by wave normals:
	if (world_pos.z > -10.5 && warped_refl_dir.z < -0.05) {
		float t_torii = clamp((-10.5 - world_pos.z) / warped_refl_dir.z, 0.0, 26.0);
		vec3 torii_hit = world_pos + warped_refl_dir * t_torii;
		float pillar_l = exp(-abs(torii_hit.x - (-3.2)) * 2.2) * smoothstep(0.0, 0.6, torii_hit.y) * (1.0 - smoothstep(6.2, 7.8, torii_hit.y));
		float pillar_r = exp(-abs(torii_hit.x - ( 3.2)) * 2.2) * smoothstep(0.0, 0.6, torii_hit.y) * (1.0 - smoothstep(6.2, 7.8, torii_hit.y));
		float crossbeam = exp(-abs(torii_hit.y - 5.8) * 1.4) * (1.0 - smoothstep(3.8, 5.2, abs(torii_hit.x)));
		float torii_mask = clamp(pillar_l + pillar_r + crossbeam * 0.9, 0.0, 1.2) * exp(-t_torii * 0.09);
		sky_refl += torii_reflection_color.rgb * torii_mask * mix(0.35, 1.45, wave_facet) * 0.85;
	}

	// 10. Silent storm lightning reflection streak across the wave facets
	vec2 refl_xz_dir = normalize(warped_refl_dir.xz + vec2(0.0001));
	float bolt_align = pow(max(0.0, dot(refl_xz_dir, normalize(lightning_dir))), 6.0);
	vec3 flash_refl = lightning_reflection_color.rgb * lightning_flash * (0.28 + 1.15 * bolt_align * mix(0.35, 1.45, wave_facet));
	sky_refl += flash_refl;

	// 11. Crisp shoreline, pillar, and raindrop crest highlights
	float ripple_highlights = (
		rim_meniscus * 0.55 +
		shore_crest * 0.72 +
		pillar_crest * 0.68 +
		rain_rip.z * 0.85
	) * (1.0 - smoothstep(12.0, 19.5, cam_dist));
	vec3 crest_tint = mix(vec3(0.26, 0.24, 0.48), sakura_reflection_color.rgb * 0.65, exp(-dist_to_sakura * 0.15));

	// Combine dark water depth and Fresnel-weighted reflection
	vec3 surface_color = mix(water_body, sky_refl, fresnel) + crest_tint * ripple_highlights;

	// 12. Atmospheric depth fog matching WorldEnvironment & StormSkyDome:
	// Starts at 6.0 m and reaches full opacity right behind the Torii (~19.5 m) so everything
	// beyond the Torii dissolves into the dark violet-navy storm haze with zero horizon line.
	float depth_fog = pow(smoothstep(6.0, 19.5, cam_dist), 0.92);
	float radial_fog = smoothstep(12.5, 20.5, r);
	float fog_factor = clamp(max(depth_fog, radial_fog), 0.0, 1.0);
	vec3 active_fog_color = fog_color.rgb + lightning_reflection_color.rgb * (lightning_flash * 0.14);

	// Fade diffuse/specular lighting to 0 as fog_factor -> 1 and drive EMISSION to active_fog_color
	// so the distant fogged water matches the unshaded sky dome horizon to the exact RGB value.
	float clear_vis = 1.0 - fog_factor;
	ALBEDO = surface_color * clear_vis;
	METALLIC = mix(0.08, 0.48, fresnel) * clear_vis;
	ROUGHNESS = mix(mix(0.24, 0.05, fresnel), 1.0, fog_factor);
	SPECULAR = 0.78 * clear_vis;
	NORMAL = (VIEW_MATRIX * vec4(world_normal, 0.0)).xyz;
	vec3 water_emission = sky_refl * (fresnel * 0.48) + crest_tint * (ripple_highlights * 0.68) + flash_refl * 0.55;
	EMISSION = mix(water_emission, active_fog_color, fog_factor);
}

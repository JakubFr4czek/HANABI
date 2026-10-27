shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// Endless black water mirror under the rain (Dojo of the Storm, GDD §9).
// Unshaded on purpose: everything is computed here (no light passes on Quest).
// - Almost still surface: a slow, faint swell plus raindrop rings.
// - Fresnel: near-black depth looking down, the sky at grazing angles.
// - Reflection: baked storm panorama, a glittering moon path, and the giant
//   torii as a dark silhouette in the mirror. No SSR, no reflection probes.
// - Lightning brightens the reflected sky toward the strike.

#include "res://src/shaders/rain_ripples.gdshaderinc"

global uniform vec3 moon_direction;
global uniform float storm_flash;
global uniform vec2 storm_flash_dir;
global uniform float intro_ripple_radius;
global uniform float intro_ripple_gain;

uniform vec3 deep_color : source_color = vec3(0.012, 0.014, 0.026);
uniform vec3 moon_color : source_color = vec3(0.8, 0.86, 1.0);
uniform vec3 lightning_tint : source_color = vec3(0.55, 0.72, 1.0);

uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_panorama : source_color, filter_linear_mipmap, repeat_enable;

uniform float swell_strength : hint_range(0.0, 0.5) = 0.09;
uniform float rain_strength : hint_range(0.0, 1.0) = 0.5;
uniform float platform_radius = 5.25;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 equirect_uv(vec3 d) {
	return vec2(atan(d.x, -d.z) / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
}

void fragment() {
	vec3 p = v_world_pos;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = cam - p;
	float cam_dist = length(to_cam);
	vec3 v = to_cam / cam_dist;

	// Slow broad swell from two crossing normal maps.
	vec2 na = texture(normal_map_a, p.xz * 0.045 + TIME * vec2(0.004, 0.003)).xy * 2.0 - 1.0;
	vec2 nb = texture(normal_map_b, p.xz * 0.11 - TIME * vec2(0.003, 0.005)).xy * 2.0 - 1.0;
	vec2 slope = (na * 0.6 + nb * 0.4) * swell_strength;

	// Rain rings, fading out with distance (they would only shimmer far away).
	vec3 rr = rain_ripples(p.xz, TIME * 1.4) * (1.0 - smoothstep(4.0, 14.0, cam_dist));
	slope += rr.xy * rain_strength;
	// A thin ring of disturbed water hugging the stone rim.
	float edge = max(length(p.xz) - platform_radius, 0.0);
	slope += normalize(p.xz) * sin(edge * 40.0 - TIME * 2.2) * exp(-edge * 6.0) * 0.08;

	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	vec3 r = reflect(-v, n);
	r.y = max(r.y, 0.005);
	vec3 refl = textureLod(sky_panorama, equirect_uv(r), 0.5).rgb;

	// Moon path: the sharp highlight smeared by the ripples into a glitter road.
	vec3 md = normalize(moon_direction);
	float m = max(dot(r, md), 0.0);
	refl += moon_color * (pow(m, 1800.0) * 40.0 + pow(m, 180.0) * 1.2 + pow(m, 24.0) * 0.06);

	// The giant torii (pillars at x = ±3.2, beams near y = 5.6–7, plane z = -10.5) as a dark reflection.
	if (p.z > -10.5 && r.z < -0.02) {
		float t = (-10.5 - p.z) / r.z;
		vec3 hit = p + r * t;
		float pillar = (1.0 - smoothstep(0.3, 0.45, abs(abs(hit.x) - 3.2))) * step(hit.y, 6.6);
		float beam = (1.0 - smoothstep(0.25, 0.4, abs(hit.y - 6.75))) * step(abs(hit.x), 5.1)
			+ (1.0 - smoothstep(0.15, 0.25, abs(hit.y - 5.6))) * step(abs(hit.x), 3.6);
		refl *= 1.0 - clamp(pillar + beam, 0.0, 1.0) * 0.85;
	}

	// Lightning: the reflected sky lights up toward the strike.
	float align = pow(max(dot(normalize(r.xz + vec2(1e-5)), normalize(storm_flash_dir)), 0.0), 4.0);
	refl += lightning_tint * storm_flash * (0.05 + 0.5 * align) * smoothstep(0.0, 0.3, r.y + 0.1);

	vec3 col = mix(deep_color, refl, fresnel);
	// Raindrop crowns catch a little light close to the viewer.
	col += vec3(0.1, 0.11, 0.16) * rr.z * (1.0 + storm_flash * 2.0);
	float intro_r = length(v_world_pos.xz);
	float intro_ring = smoothstep(0.65, 0.0, abs(intro_r - intro_ripple_radius)) * intro_ripple_gain;
	col += lightning_tint * intro_ring * (0.25 + storm_flash * 0.35);
	ALBEDO = col;
}

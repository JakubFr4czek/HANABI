shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

// Deep violet-to-navy storm sky dome for the Dojo of the Storm (GDD §9).
// Works identically on Quest (Compatibility) and PCVR (Mobile).

uniform vec3 zenith_color : source_color = vec3(0.035, 0.02, 0.085);
uniform vec3 mid_sky_color : source_color = vec3(0.055, 0.04, 0.13);
uniform vec3 horizon_color : source_color = vec3(0.025, 0.04, 0.095);
uniform vec3 cloud_tint : source_color = vec3(0.14, 0.09, 0.26);
uniform vec3 lightning_tint : source_color = vec3(0.35, 0.68, 1.0);
uniform float lightning_flash : hint_range(0.0, 2.0) = 0.0;
uniform vec2 lightning_dir_xz = vec2(-0.25, -0.96);

varying vec3 v_local_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = rot * p * 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	vec3 dir = normalize(v_local_pos);
	float h = clamp(dir.y, 0.0, 1.0);

	// Base gradient: deep violet zenith fading to dark navy near the horizon.
	vec3 sky = mix(horizon_color, mid_sky_color, smoothstep(0.0, 0.28, h));
	sky = mix(sky, zenith_color, smoothstep(0.22, 0.85, h));

	// Slow drifting storm clouds projected onto the upper hemisphere.
	vec2 cloud_uv = dir.xz / (h + 0.18) * 1.35;
	float c1 = fbm(cloud_uv + vec2(TIME * 0.012, -TIME * 0.008));
	float c2 = fbm(cloud_uv * 1.8 - vec2(TIME * 0.009, TIME * 0.014) + 4.7);
	float clouds = smoothstep(0.38, 0.78, c1 * 0.65 + c2 * 0.35) * smoothstep(0.01, 0.18, h);

	vec3 cloud_col = cloud_tint * (0.45 + 0.55 * c2);
	sky = mix(sky, cloud_col, clouds * 0.65);

	// Distant silent lightning illumination inside the clouds.
	vec2 h_dir = normalize(dir.xz + vec2(1e-5));
	vec2 l_dir = normalize(lightning_dir_xz);
	float dir_align = smoothstep(0.2, 0.98, dot(h_dir, l_dir));
	float height_band = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.35, 0.85, h));
	float cloud_glow = (0.35 + 0.65 * clouds) * (0.25 + 0.75 * dir_align * height_band);
	sky += lightning_tint * lightning_flash * cloud_glow * 0.65;

	// Subtle horizon mist blend so the water mirror and sky meet seamlessly.
	float horizon_mist = exp(-abs(dir.y) * 14.0);
	sky = mix(sky, vec3(0.045, 0.035, 0.09) + lightning_tint * lightning_flash * 0.12, horizon_mist * 0.65);

	ALBEDO = sky;
}

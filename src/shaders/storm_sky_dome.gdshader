shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

// Visible storm sky for the Dojo of the Storm (GDD §9): near-black zenith,
// slow cloud bands, a cold moon veiled by the clouds, and lightning lighting the
// cloud undersides from inside. The horizon is locked to the world fog color so
// the water and the sky melt into one haze. Same on Quest (Compatibility) and PC.
//
// P1b: the only clouds in the run are this shader. It runs on the SkyDome sphere
// (r = 125 m, Arena/SkyDome in scenes/training_arena.tscn, inherited by run.tscn). The
// Environment sky (storm_sky.gdshader) has no clouds. The fog is uniform. Crowns are
// opaque depth-writing geometry (forest_diffuse: depth_draw_opaque + ALPHA_SCISSOR), so
// the deck can only show above or between them. The cloud base is therefore set in
// elevation (cloud_base_deg), not as a height band.

global uniform vec3 moon_direction;
global uniform vec4 storm_fog_color;
global uniform float storm_flash;
global uniform vec2 storm_flash_dir;

// Elevation (degrees) of the cloud deck's lower edge. Below it there are no clouds at all,
// only the fog haze and zenith dark. P1b: the forest crowns reach up to ~70 degrees as seen
// from the paths (tests/forest_world_test.gd, cloud base check), so the deck sits above them.
uniform float cloud_base_deg : hint_range(0.0, 89.0) = 75.0;
uniform vec3 zenith_color : source_color = vec3(0.012, 0.012, 0.03);
uniform vec3 cloud_dark : source_color = vec3(0.025, 0.024, 0.05);
uniform vec3 cloud_lit : source_color = vec3(0.30, 0.31, 0.42);
uniform vec3 moon_color : source_color = vec3(0.78, 0.84, 1.0);
uniform vec3 lightning_tint : source_color = vec3(0.55, 0.72, 1.0);

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
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
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
	vec3 fog = storm_fog_color.rgb;

	vec3 sky = mix(fog, zenith_color, smoothstep(0.02, 0.5, h));

	// Cloud deck projected on a plane, drifting slowly. The deck starts at cloud_base_deg,
	// above every crown seen from the paths, and thins toward the zenith, so the clouds
	// stay high, soft and far. The UV scale is raised so the cap keeps the same cloud size.
	float base_h = sin(radians(cloud_base_deg));
	vec2 cloud_uv = dir.xz / (h + 0.25) * 4.0;
	float c1 = fbm(cloud_uv + vec2(TIME * 0.004, -TIME * 0.003));
	float c2 = fbm(cloud_uv * 2.3 - vec2(TIME * 0.003, TIME * 0.005) + 4.7);
	float altitude = smoothstep(base_h, base_h + 0.06, h) * (1.0 - smoothstep(0.8, 1.0, h) * 0.6);
	float density = smoothstep(0.38, 0.8, c1 * 0.7 + c2 * 0.3) * altitude;
	float thickness = c2;

	// Moon: a sharp disc and a wide halo, dimmed where clouds pass in front.
	vec3 md = normalize(moon_direction);
	float m = max(dot(dir, md), 0.0);
	float veil = mix(1.0, 0.25, density);
	vec3 moon = moon_color * (smoothstep(0.99955, 0.99975, m) * 5.0 * mix(1.0, 0.35, density) + pow(m, 120.0) * 0.6 * veil + pow(m, 10.0) * 0.07);

	// Clouds near the moon get a silver lining; the rest stay as dark masses.
	float moon_near = pow(m, 14.0);
	vec3 cloud_col = mix(cloud_dark, cloud_lit, moon_near * (1.0 - thickness) * 0.9);
	sky = mix(sky, cloud_col, density * 0.6);
	sky += moon;

	// Lightning lights the clouds from inside, strongest toward the strike.
	vec2 l_dir = normalize(storm_flash_dir);
	float align = smoothstep(0.1, 0.95, dot(normalize(dir.xz + vec2(1e-5)), l_dir));
	float band = smoothstep(0.03, 0.14, h) * (1.0 - smoothstep(0.35, 0.8, h));
	sky += lightning_tint * storm_flash * (0.08 + density * (0.15 + 0.85 * align * band) * (0.6 + 0.8 * thickness));

	// The lowest band is exactly the fog color, so there is no horizon line. The
	// haze is deep enough that the sky melts into the fog behind the tree line.
	float horizon = 1.0 - smoothstep(0.0, 0.18, h);
	sky = mix(sky, fog + lightning_tint * storm_flash * 0.06, horizon);
	ALBEDO = sky;
}

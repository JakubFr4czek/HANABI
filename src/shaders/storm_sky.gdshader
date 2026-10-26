shader_type sky;

// Static storm sky used only for reflections and radiance (the visible sky is
// StormSkyDome). No TIME, so the radiance is rendered once, not every frame.

global uniform vec3 moon_direction;
global uniform vec4 storm_fog_color;

uniform vec3 zenith_color : source_color = vec3(0.012, 0.012, 0.03);
uniform vec3 moon_color : source_color = vec3(0.78, 0.84, 1.0);
uniform vec3 water_color : source_color = vec3(0.004, 0.005, 0.012);

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 fog = storm_fog_color.rgb;
	vec3 col = mix(fog, zenith_color, smoothstep(0.02, 0.55, d.y));
	// Below the horizon: the dark water mirror.
	col = mix(col, mix(fog * 0.5, water_color, smoothstep(0.0, 0.25, -d.y)), step(d.y, 0.0));
	float m = max(dot(d, normalize(moon_direction)), 0.0);
	col += moon_color * (pow(m, 900.0) * 12.0 + pow(m, 60.0) * 0.5 + pow(m, 8.0) * 0.08) * step(0.0, d.y);
	COLOR = col;
}

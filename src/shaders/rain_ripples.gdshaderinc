// Expanding raindrop rings on a flat wet surface (water, puddles).
// Returns (slope.xy, crest) in world XZ; add slope to the surface normal.

float rr_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 rr_cell(vec2 p, float t, float seed) {
	vec2 cell = floor(p);
	float h1 = rr_hash(cell + vec2(seed, 0.0));
	float h2 = rr_hash(cell + vec2(19.3, 71.7 + seed));
	vec2 center = cell + vec2(0.2 + 0.6 * h1, 0.2 + 0.6 * h2);
	vec2 d = p - center;
	float dist = length(d);
	float phase = fract(t * (0.9 + 0.5 * h1) + h2);
	float ring = dist - phase * 0.45;
	float env = exp(-abs(ring) * 28.0) * (1.0 - phase) * (1.0 - phase) * smoothstep(0.0, 0.04, phase);
	float slope = cos(ring * 70.0) * env;
	return vec3(d / max(dist, 0.001) * slope, max(0.0, sin(ring * 70.0)) * env);
}

vec3 rain_ripples(vec2 world_xz, float t) {
	return rr_cell(world_xz * 2.2, t, 0.0) * 0.6
		+ rr_cell((world_xz + vec2(2.3, -1.7)) * 3.1, t * 1.13 + 0.41, 13.7) * 0.45
		+ rr_cell((world_xz + vec2(-4.1, 3.2)) * 4.3, t * 0.87 + 0.73, 29.1) * 0.35;
}

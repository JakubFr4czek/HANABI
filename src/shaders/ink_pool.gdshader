shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 ink_color : source_color = vec3(0.012, 0.014, 0.028);
uniform vec3 edge_color : source_color = vec3(0.33, 0.42, 0.74);
uniform float age = 0.0;
uniform float lifetime = 7.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float n = noise(p * 3.2 + vec2(TIME * 0.055, -TIME * 0.035));
	float r = length(p * vec2(1.0, 0.86));
	float boundary = 0.78 + (n - 0.5) * 0.22;
	float body = 1.0 - smoothstep(boundary - 0.08, boundary, r);
	float rim = (1.0 - smoothstep(0.025, 0.085, abs(r - boundary))) * body;
	float wash_in = smoothstep(0.0, 0.24, age);
	float wash_out = 1.0 - smoothstep(max(lifetime - 1.2, 0.0), lifetime, age);
	float life = wash_in * wash_out;
	float oily = pow(max(0.0, 1.0 - abs(dot(NORMAL, VIEW))), 3.0);
	vec3 col = ink_color * (0.78 + n * 0.24) + edge_color * (rim * 0.62 + oily * 0.14);
	ALBEDO = col;
	EMISSION = edge_color * (rim * 0.34 + oily * 0.08);
	ALPHA = body * life * (0.82 + rim * 0.16);
}

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Drifting surface mist for the Dojo of the Storm (Quest 3 Compatibility safe).
// A soft band of moonlit mist above the water around the platform rim and the
// torii base, fading into the world fog color with distance.

global uniform vec4 storm_fog_color;
global uniform float storm_flash;

uniform vec3 mist_color : source_color = vec3(0.2, 0.2, 0.3);
uniform vec3 lightning_tint : source_color = vec3(0.55, 0.72, 1.0);
uniform float mist_opacity : hint_range(0.0, 1.0) = 0.44;
uniform float inner_clear_radius : hint_range(2.0, 12.0) = 5.15;
uniform float outer_fade_radius : hint_range(10.0, 40.0) = 16.5;
uniform vec2 drift_velocity = vec2(0.12, -0.07);

varying vec3 v_world_pos;

float mist_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float r = length(v_world_pos.xz);
	float inner_mask = smoothstep(inner_clear_radius - 0.25, inner_clear_radius + 1.85, r);
	float outer_mask = 1.0 - smoothstep(outer_fade_radius * 0.58, outer_fade_radius, r);

	float n1 = mist_noise(v_world_pos.xz * 0.22 + TIME * drift_velocity);
	float n2 = mist_noise(v_world_pos.xz * 0.5 - TIME * drift_velocity.yx * 0.75);
	float wisps = smoothstep(0.3, 0.85, n1 * 0.62 + n2 * 0.38);

	float rim_bank = exp(-max(r - 5.3, 0.0) * 0.45) * 0.4;
	float d_torii = length((v_world_pos.xz - vec2(0.0, -10.5)) * vec2(0.45, 0.85));
	float torii_bank = exp(-d_torii * 0.28) * 0.5;

	vec3 col = mix(mist_color, storm_fog_color.rgb, smoothstep(8.5, outer_fade_radius, r));
	col += lightning_tint * storm_flash * (0.2 + 0.25 * wisps);

	float density = clamp((wisps * 0.78 + rim_bank + torii_bank) * inner_mask * outer_mask, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = clamp(density * mist_opacity * (1.0 + storm_flash * 0.3), 0.0, 0.7);
}

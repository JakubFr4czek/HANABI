shader_type spatial;
// Glowing yōkai eyes seen through the run's milk fog: one camera-facing quad
// drawing both eyes (one draw call per enemy), laid out along the head's
// lateral axis. Each point's world size never drops below min_angle × distance,
// so far off the pair is one faint spark that grows and splits as it closes.
// Mixed (not added) so the red stays saturated over pale fog; the HDR core
// crosses the glow threshold and blooms. Fog is ignored on purpose.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 glow_color : source_color = vec3(1.0, 0.26, 0.1);
uniform float base_size = 0.05;
uniform float min_angle = 0.0085;
uniform float eye_sep = 0.088;
uniform float intensity = 2.2;
instance uniform float glow = 1.0;  // >1 brightens (wind-up tell), 0 hides

varying vec2 v_m;        // fragment position in metres within the quad
varying float v_size;    // radius of one eye point
varying float v_half_sep;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float dist = length(center.xyz);
	float size = max(base_size, dist * min_angle);
	vec2 lat = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
	float lat_len = length(lat);
	vec2 ax = lat_len > 1e-4 ? lat / lat_len : vec2(1.0, 0.0);
	vec2 ay = vec2(-ax.y, ax.x);
	float half_sep = 0.5 * eye_sep * min(lat_len, 1.0);
	float half_w = size + half_sep;
	// Sit just in front of the mask so the head never hides its own eyes.
	center.xyz -= normalize(center.xyz) * 0.06;
	center.xy += ax * VERTEX.x * 2.0 * half_w + ay * VERTEX.y * 2.0 * size;
	POSITION = PROJECTION_MATRIX * center;
	v_m = vec2(VERTEX.x * 2.0 * half_w, VERTEX.y * 2.0 * size);
	v_size = size;
	v_half_sep = half_sep;
}

void fragment() {
	float r1 = length(v_m - vec2(v_half_sep, 0.0)) / v_size;
	float r2 = length(v_m + vec2(v_half_sep, 0.0)) / v_size;
	float core = exp(-r1 * r1 * 14.0) + exp(-r2 * r2 * 14.0);
	float halo = (exp(-r1 * r1 * 3.0) + exp(-r2 * r2 * 3.0)) * 0.3;
	ALBEDO = glow_color * intensity * max(glow, 1.0) * (1.0 + min(core, 1.0) * 1.5);
	ALPHA = clamp(core * 1.3 + halo, 0.0, 1.0) * clamp(glow, 0.0, 1.0);
}

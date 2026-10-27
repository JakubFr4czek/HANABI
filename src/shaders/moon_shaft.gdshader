shader_type spatial;
// Moonlight falling through gaps in the cedar canopy into the run's milk fog.
// A quad billboarded around its own axis (instance Y = axis × length, X =
// width), additive, faded by camera distance instead of scene fog (fog on an
// additive pass would only brighten it), and faded out right in front of the
// eyes so walking through a shaft never washes the view out.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

global uniform float storm_flash;

uniform vec3 shaft_color : source_color = vec3(0.72, 0.8, 1.0);
uniform float intensity = 0.55;
uniform float near_fade = 2.2;
uniform float far_start = 7.0;
uniform float far_end = 12.5;

varying vec2 v_uv;
varying float v_fade;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 axis_full = MODEL_MATRIX[1].xyz;
	float len = length(axis_full);
	vec3 axis = axis_full / max(len, 1e-4);
	float width = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - base;
	vec3 side = normalize(cross(axis, to_cam));
	vec3 world = base + axis * len * VERTEX.y + side * width * VERTEX.x;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	v_uv = vec2(VERTEX.x + 0.5, VERTEX.y);
	// Distance from the camera to the nearest point on the shaft.
	vec3 rel = CAMERA_POSITION_WORLD - base;
	vec3 closest = base + axis * clamp(dot(rel, axis), 0.0, len);
	float d = distance(CAMERA_POSITION_WORLD, closest);
	v_fade = smoothstep(0.6, near_fade, d) * (1.0 - smoothstep(far_start, far_end, d));
}

void fragment() {
	float across = sin(v_uv.x * PI);
	across *= across;
	// Bright under the canopy gap, thinning toward the forest floor.
	float along = smoothstep(0.0, 0.18, v_uv.y) * (1.0 - smoothstep(0.82, 1.0, v_uv.y));
	along *= mix(0.55, 1.0, v_uv.y);
	float shimmer = 0.85 + 0.15 * sin(TIME * 0.7 + v_uv.y * 6.0 + v_uv.x * 3.0);
	ALBEDO = shaft_color * across * along * shimmer * v_fade * intensity * (1.0 + storm_flash * 2.0);
}

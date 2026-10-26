shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Rain streaks, splashes and blade drips (particles). Billboards rotate only
// around world Y so streaks stay vertical; they fade with distance (fog is
// disabled because additive fog would brighten them) and flare on lightning.

global uniform float storm_flash;
global uniform vec4 storm_fog_color;

uniform vec3 tint : source_color = vec3(0.62, 0.68, 0.86);
uniform float intensity = 0.22;
uniform float flash_boost = 1.8;
uniform float fade_distance = 9.0;
uniform float near_fade = 0.35;

varying float v_dist;

void vertex() {
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	to_cam.y = 0.0;
	to_cam = length(to_cam) > 0.0001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(up, to_cam));
	mat4 bb = mat4(
		vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(to_cam * length(MODEL_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = sin(UV.y * PI);
	float mask = across * across * along;
	float fade = (1.0 - smoothstep(fade_distance * 0.45, fade_distance, v_dist)) * smoothstep(near_fade, near_fade * 2.5, v_dist);
	vec3 col = mix(tint, storm_fog_color.rgb * 3.0, 0.25) * (1.0 + storm_flash * flash_boost);
	ALBEDO = col * intensity;
	ALPHA = mask * fade * COLOR.a;
}

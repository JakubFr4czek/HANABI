shader_type spatial;
// Forest props in the milk fog: diffuse only. No specular lobe, so moonlight
// wraps the form and then disappears into the fog instead of sheening like plastic.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled;

global uniform vec4 storm_fog_color;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
// Daylight photo, cooled so it sits in the night fog.
uniform vec3 night_tint : source_color = vec3(0.82, 0.86, 0.84);
uniform float albedo_gain = 1.0;
uniform float normal_depth = 0.55;

void fragment() {
	vec3 tex = texture(albedo_texture, UV).rgb;
	// The atlas paints blossoms on black. The black is the gap between leaves,
	// not bark, so it is cut away and the crown stays a cloud instead of a solid cone.
	float cover = max(tex.r, max(tex.g, tex.b));
	ALPHA = cover;
	ALPHA_SCISSOR_THRESHOLD = 0.05;
	vec3 alb = tex * night_tint * albedo_gain;
	ALBEDO = alb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Bark grooves and leaf clumps catch the moon on the diffuse lobe only.
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float open_sky = clamp(wn.y * 0.45 + 0.5, 0.0, 1.0);
	// Shadowed bark takes a little of the fog, so a trunk fades into the air.
	EMISSION = storm_fog_color.rgb * 0.05 * (0.65 + 0.35 * open_sky);
}

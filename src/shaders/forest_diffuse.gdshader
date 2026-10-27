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
uniform vec3 foliage_color : source_color = vec3(0.30, 0.36, 0.32);

void fragment() {
	// UV.x above 1 is the root flare: bark at the trunk, soil at the tip.
	float root = step(1.5, UV.x);
	float along = clamp(UV.x - 2.0, 0.0, 1.0);
	vec3 bark = vec3(0.18, 0.13, 0.10);
	vec3 soil = vec3(0.22, 0.24, 0.16);
	vec3 alb_root = mix(bark, soil, smoothstep(0.08, 0.85, along));
	float grain = fract(sin(dot(UV, vec2(12.9898, 78.233))) * 43758.5453);
	alb_root *= mix(0.84, 1.06, grain);
	alb_root *= mix(1.0, 0.8, smoothstep(0.72, 1.0, along));
	alb_root *= night_tint;

	vec3 tex = texture(albedo_texture, UV).rgb;
	// The atlas paints blossoms on black. The black is the gap between leaves,
	// not bark, so it is cut away and the crown stays a cloud instead of a solid cone.
	float cover = max(tex.r, max(tex.g, tex.b));
	vec3 alb = tex * night_tint * albedo_gain;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float open_sky = clamp(wn.y * 0.45 + 0.5, 0.0, 1.0);

	// UV.y above 1.5 is a solid foliage clump (the rebuilt crown): a muted
	// leaf mass, per-vertex shade in UV.x, darker on its underside.
	float leaf = step(1.5, UV.y);
	vec3 alb_leaf = foliage_color * mix(0.78, 1.12, UV.x) * mix(0.55, 1.0, open_sky);
	alb = mix(alb, alb_leaf, leaf);

	ALBEDO = mix(alb, alb_root, root);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Bark grooves and leaf clumps catch the moon on the diffuse lobe only.
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - root) * (1.0 - leaf);
	// Canopy gaps cut away; the root flare and foliage clumps are solid.
	ALPHA = mix(cover, 1.0, max(root, leaf));
	ALPHA_SCISSOR_THRESHOLD = 0.05;
	// Shadowed bark takes a little of the fog, so a trunk fades into the air.
	EMISSION = storm_fog_color.rgb * 0.05 * (0.65 + 0.35 * open_sky);
}

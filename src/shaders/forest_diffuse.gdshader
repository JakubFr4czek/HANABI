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
// Level of detail cross-fade (D6): 0 is the full crown, which dissolves out
// across lod_band (metres from the camera), 1 is the far crown, which dissolves
// in over the same band. The dither is an ordered pattern on the screen, so the
// fade has no popping edge and does not shimmer while the camera stands still.
uniform float lod_far = 0.0;
// Height haze (N4): crowns fade into the fog colour above height_haze_low, fully at height_haze_high.
uniform float height_haze_low = 8.0;
uniform float height_haze_high = 22.0;
uniform float height_haze = 0.0;
// Distance haze (N4, from the profile): trunks start to take the mist at distance_haze_start,
// fully at distance_haze_end, at most distance_haze_max. Later start = darker trunks against the mist.
uniform float distance_haze_start = 14.0;
uniform float distance_haze_end = 40.0;
uniform float distance_haze_max = 0.5;
uniform vec2 lod_band = vec2(9.0, 11.0);
// The far crown's trunk is a plain bark colour: the atlas sample at its UV is pale.
uniform vec3 far_bark_color : source_color = vec3(0.16, 0.12, 0.10);
// Cherry atlas: black between the blossoms is a gap, so it is cut away.
// Alpha-cut level of the canopy gaps: the cherry atlas is black between blossoms (0.05);
// a scanned crown's navy card background sits below 0.3 and its leaves above.
uniform float cut_level = 0.05;
// Leaf cards with their own alpha (ferns, RGBA atlases) cut out on the alpha channel.
// Off by default: the cherry atlas has no alpha and is cut out on its brightness.
uniform bool alpha_from_texture = false;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float interleaved_gradient(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float in_band = smoothstep(lod_band.x, lod_band.y, dist);
	float lod_alpha = mix(1.0 - in_band, in_band, lod_far);
	float dither = interleaved_gradient(FRAGCOORD.xy);
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

	vec4 texel = texture(albedo_texture, UV);
	vec3 tex = texel.rgb;
	// The atlas paints blossoms on black. The black is the gap between leaves,
	// not bark, so it is cut away and the crown stays a cloud instead of a solid cone.
	float cover = alpha_from_texture ? texel.a : max(tex.r, max(tex.g, tex.b));
	vec3 alb = tex * night_tint * albedo_gain;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float open_sky = clamp(wn.y * 0.45 + 0.5, 0.0, 1.0);

	// UV.y above 1.5 is a solid foliage clump (the rebuilt crown): a muted
	// leaf mass, per-vertex shade in UV.x, darker on its underside.
	float leaf = step(1.5, UV.y);
	vec3 alb_leaf = foliage_color * mix(0.78, 1.12, UV.x) * mix(0.55, 1.0, open_sky);
	alb = mix(alb, alb_leaf, leaf);

	// Distance haze: the crowns lose their dark body into the milk before the fog takes them.
	float haze = smoothstep(distance_haze_start, distance_haze_end, distance(world_pos, CAMERA_POSITION_WORLD)) * distance_haze_max;
	vec3 body = mix(alb, alb_root, root);
	if (lod_far > 0.5 && leaf < 0.5) {
		body = far_bark_color * night_tint * mix(0.84, 1.06, grain);
	}
	float high_haze = smoothstep(height_haze_low, height_haze_high, world_pos.y) * height_haze;
	ALBEDO = mix(body, storm_fog_color.rgb, max(haze, high_haze));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Bark grooves and leaf clumps catch the moon on the diffuse lobe only.
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - root) * (1.0 - leaf);
	// Canopy gaps cut away; the root flare and foliage clumps are solid.
	ALPHA = mix(cover, 1.0, max(root, leaf)) * lod_alpha;
	// Inside the band the scissor is the dither; outside it stays the usual cut-out.
	bool fading = lod_alpha > 0.0 && lod_alpha < 1.0;
	ALPHA_SCISSOR_THRESHOLD = fading ? dither : cut_level;
	// Shadowed bark takes a little of the fog, so a trunk fades into the air.
	EMISSION = storm_fog_color.rgb * 0.05 * (0.65 + 0.35 * open_sky);
}

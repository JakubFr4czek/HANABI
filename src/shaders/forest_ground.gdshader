shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

#include "res://src/shaders/atmosphere.gdshaderinc"
// Run forest floor: cedar-needle soil, patches of grass on the flats and stones
// on slopes / in scattered beds (Poly Haven CC0, 1K). World-space planar mapping
// (the terrain has no UVs); diffuse + normal only to stay cheap on Quest.

global uniform vec4 storm_fog_color;

uniform sampler2D soil_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// Moss (Moss002, ambientCG CC0): dense green cover on the slopes and in damp patches (D5).
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float moss_tile = 3.0;
uniform vec3 moss_tint : source_color = vec3(0.9, 1.0, 0.92);
// How much of the free ground the moss may take, and how it breaks up.
uniform float moss_slope_share : hint_range(0.0, 1.0) = 0.55;
uniform float moss_patch_share : hint_range(0.0, 1.0) = 0.9;
uniform float soil_tile = 2.6;
uniform float grass_tile = 2.2;
uniform float stone_tile = 3.2;
// Daylight scans dimmed and cooled to the moonlit night.
uniform vec3 night_tint : source_color = vec3(0.5, 0.52, 0.6);
uniform float normal_strength = 0.9;
uniform float roughness_dry : hint_range(0.0, 1.0) = 0.9;
uniform float roughness_wet : hint_range(0.0, 1.0) = 0.5;
uniform float wetness : hint_range(0.0, 1.0) = 0.6;
uniform float fog_fade_start = 60.0;
// Atmosphere of the floor (N4): the same layers as the crowns, set from WorldGenProfile.
uniform float distance_haze_start = 8.0;
uniform float distance_haze_end = 40.0;
uniform float distance_haze_max = 0.8;
uniform float low_mist_amount = 0.35;
uniform float low_mist_height = 3.0;
uniform vec3 haze_far_color : source_color = vec3(0.16, 0.30, 0.36);
uniform float fog_fade_end = 70.0;
// Unlit moon/fog bounce so the forest floor is not a black void at night.
uniform float ambient_fill = 0.0;
// Kept for callers that set it; the scans carry their own cavities.
uniform float fill = 1.35;
uniform float cavity_ao : hint_range(0.0, 1.0) = 0.0;
// Footpath material (its own texture, never mixed with the layers above).
uniform sampler2D path_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float path_tile = 2.2;
// Warm, lit packed earth: brighter than the dark duff beside the trail.
uniform vec3 path_tint : source_color = vec3(1.0, 0.9, 0.76);
// Lifts the trail above the dark duff beside it (about 40% more luminance).
uniform float path_gain = 1.5;
// Edge of the trail, drawn from the distance to the centre line (vertex colour G, metres ÷ path_encode).
// The vertex R weight is a 1 m lattice ramp: its edge stepped like the grid, so it is not used for the edge.
uniform float path_half = 1.0;
uniform float path_encode = 4.0;
// Width jitter of the edge, metres: a ragged, hand-trodden border, not a drawn line.
uniform float path_edge_noise = 0.22;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Planar XZ mapping: tangent along +X, binormal along +Z (chunks are unrotated).
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 p = v_world_pos.xz;
	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float broad = vnoise(p * 0.11) * 0.7 + vnoise(p * 0.37) * 0.3;
	float beds = vnoise(p * 0.52 + 17.0);
	// Footpaths (vertex colour R, ForestWorld._build_terrain_mesh). The strip is
	// its own material: no stone, grass or soil mixes into it. The edge is soft
	// and noisy, so it never reads as a drawn line.
	// Sharp edge: a little noise only, so the border is ragged but still a border.
	// Distance to the centre line (metres), read from G: a smooth field, so the edge is a curve.
	float path_d = COLOR.g * path_encode;
	// Smooth trail weight (1 on the trail, 0 off it), then the noisy edge: the noise is in metres.
	float path_w = 1.0 - smoothstep(path_half * 0.75, path_half * 1.2, path_d);
	float path_w_edge = 1.0 - smoothstep(path_half * 0.75, path_half * 1.2,
		path_d + (vnoise(p * 0.9) - 0.5) * path_edge_noise);
	float trail = smoothstep(0.42, 0.58, path_w_edge);
	// Flat stones just outside the border (a band about 0.5 m wide), rare: only the
	// noisiest spots of the band get one.
	float beside = smoothstep(0.0, 0.3, path_w) * (1.0 - smoothstep(0.3, 0.6, path_w));
	float kerb = beside * smoothstep(0.7, 0.8, vnoise(p * 1.9 + 3.0));
	float free = clamp(1.0 - trail - kerb, 0.0, 1.0);
	float w_stone = clamp(smoothstep(0.07, 0.19, slope) + smoothstep(0.74, 0.86, beds) * 0.85, 0.0, 1.0) * free;
	// Moss takes the slopes and the damp patches, before the grass and soil share the rest.
	float patches = vnoise(p * 0.23 + 5.0);
	float w_moss = clamp(smoothstep(0.05, 0.2, slope) * moss_slope_share + smoothstep(0.42, 0.62, patches) * moss_patch_share, 0.0, 1.0)
		* max(free - w_stone, 0.0);
	float w_grass = smoothstep(0.44, 0.6, broad) * max(free - w_stone - w_moss, 0.0);
	float w_soil = max(free - w_stone - w_moss - w_grass, 0.0);

	// A second, tighter sample so needles and grit stay visible at the feet.
	vec3 soil = mix(texture(soil_albedo, p / soil_tile).rgb,
		texture(soil_albedo, p / (soil_tile * 0.42) + vec2(2.0, 5.0)).rgb, 0.42);
	vec3 grass = mix(texture(grass_albedo, p / grass_tile).rgb,
		texture(grass_albedo, p / (grass_tile * 0.45) + vec2(8.0, 1.0)).rgb, 0.38);
	vec3 stone = texture(stone_albedo, p / stone_tile).rgb;
	vec3 moss = mix(texture(moss_albedo, p / moss_tile).rgb,
		texture(moss_albedo, p / (moss_tile * 0.4) + vec2(4.0, 9.0)).rgb, 0.4);
	// Packed earth of the trail; a coarser second sample breaks the tiling.
	vec3 path = mix(texture(path_albedo, p / path_tile).rgb,
		texture(path_albedo, p / (path_tile * 0.4) + vec2(3.0, 7.0)).rgb, 0.35) * path_tint * path_gain;
	vec3 flat_stone = texture(stone_albedo, p / (stone_tile * 0.6)).rgb * vec3(0.9, 0.92, 0.96) * 1.1;
	vec3 nrm = texture(moss_normal, p / moss_tile).rgb * w_moss
		+ texture(soil_normal, p / soil_tile).rgb * w_soil
		+ texture(grass_normal, p / grass_tile).rgb * w_grass
		+ texture(stone_normal, p / stone_tile).rgb * w_stone
		+ texture(path_normal, p / path_tile).rgb * trail;
	// Soil stays brown, grass stays green, stone stays cool. One grey tint
	// was turning the whole floor into a single sheet.
	vec3 alb = moss * moss_tint * w_moss
		+ soil * vec3(0.58, 0.50, 0.44) * w_soil
		+ grass * vec3(0.42, 0.52, 0.40) * w_grass
		+ stone * vec3(0.50, 0.52, 0.54) * w_stone
		+ path * trail
		+ flat_stone * kerb;
	float litter = vnoise(p * 1.65 + 4.0);
	float damp = vnoise(p * 0.27 + 11.0);
	alb *= mix(0.74, 1.08, litter);
	alb *= mix(0.82, 1.0, damp);
	// Grooves in the scan sit a little darker, like pockets of wet needles.
	alb *= mix(0.8, 1.04, smoothstep(0.32, 0.68, nrm.g));
	alb *= mix(vec3(1.0), night_tint * 1.65, 0.28);
	float radial = length(v_world_pos.xz - CAMERA_POSITION_WORLD.xz);
	float fog_mix = smoothstep(fog_fade_start, fog_fade_end, radial);
	float haze = mist_amount(radial, v_world_pos.y, distance_haze_start, distance_haze_end, distance_haze_max,
		low_mist_amount, low_mist_height);
	vec3 haze_col = mix(storm_fog_color.rgb, haze_far_color, smoothstep(15.0, 40.0, radial));
	// Mist is added as emission (below), not mixed into the albedo: the albedo is lit by the dark
	// night ambient, so a mixed-in mist would be lit dark too.
	if (fog_mix > 0.985) {
		discard;
	}
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength;
	// Rain pools in the soil, less on stone tops.
	float wet = wetness * (1.0 - w_stone * 0.4);
	ROUGHNESS = mix(roughness_dry, roughness_wet, wet);
	METALLIC = 0.0;
	// Shadowed soil takes the fog's color, not a lit copy of the daylight scan.
	EMISSION = mix(alb, storm_fog_color.rgb, 0.4) * ambient_fill * (1.0 - fog_mix) + haze_col * haze;
	ALBEDO = alb * (1.0 - haze);
}

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
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
uniform float fog_fade_end = 70.0;
// Unlit moon/fog bounce so the forest floor is not a black void at night.
uniform float ambient_fill = 0.0;
// Kept for callers that set it; the scans carry their own cavities.
uniform float fill = 1.35;
uniform float cavity_ao : hint_range(0.0, 1.0) = 0.0;

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
	float w_stone = clamp(smoothstep(0.07, 0.19, slope) + smoothstep(0.74, 0.86, beds) * 0.85, 0.0, 1.0);
	float w_grass = smoothstep(0.44, 0.6, broad) * (1.0 - w_stone);
	float w_soil = max(1.0 - w_stone - w_grass, 0.0);

	vec3 alb = texture(soil_albedo, p / soil_tile).rgb * w_soil
		+ texture(grass_albedo, p / grass_tile).rgb * w_grass
		+ texture(stone_albedo, p / stone_tile).rgb * w_stone;
	vec3 nrm = texture(soil_normal, p / soil_tile).rgb * w_soil
		+ texture(grass_normal, p / grass_tile).rgb * w_grass
		+ texture(stone_normal, p / stone_tile).rgb * w_stone;

	alb *= night_tint;
	float radial = length(v_world_pos.xz - CAMERA_POSITION_WORLD.xz);
	float fog_mix = smoothstep(fog_fade_start, fog_fade_end, radial);
	if (fog_mix > 0.985) {
		discard;
	}
	ALBEDO = alb;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength;
	// Rain pools in the soil, less on stone tops.
	float wet = wetness * (1.0 - w_stone * 0.4);
	ROUGHNESS = mix(roughness_dry, roughness_wet, wet);
	METALLIC = 0.0;
	EMISSION = mix(alb, storm_fog_color.rgb, 0.3) * ambient_fill * (1.0 - fog_mix);
}

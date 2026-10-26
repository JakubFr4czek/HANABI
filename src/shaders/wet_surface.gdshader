shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Rain-soaked surface for props (lacquered wood, stone, wood): darker and
// glossier where wet, with slow rain streaks running down in world space, a
// darker band at the water line, and optional fine wood grain.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec3 base_color : source_color = vec3(0.3, 0.05, 0.05);
uniform float roughness_dry : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_wet : hint_range(0.0, 1.0) = 0.12;
uniform float wetness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float streak_scale = 9.0;
uniform float waterline_y = 0.35;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.0;
uniform float grain_scale = 30.0;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.0;
// Cheap stand-in for a soft fill light (moonlit fog bounce), so backlit
// gameplay-critical props stay readable without an extra light pass.
uniform float fill = 0.0;
// 0..1, flashes the surface (e.g. a hit on the training dummy).
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.55, 0.6);
// Optional PBR maps from scanned assets. With orm_mode > 0 roughness_dry and
// metallic scale the texture: 1 = glTF metal/rough (G, B), 2 = ARM (R = AO too).
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.0;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform int orm_mode : hint_range(0, 2) = 0;
uniform vec3 emission_tint : source_color = vec3(0.0);

varying vec3 v_world_pos;
varying vec3 v_local_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(234.56, 789.01));
	p += dot(p, p + 33.33);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_pos = VERTEX;
}

void fragment() {
	vec3 wp = v_world_pos;
	vec3 tex = texture(albedo_texture, UV).rgb;
	vec3 col = base_color * tex;
	float rough_dry = roughness_dry;
	float metal = metallic;
	if (orm_mode > 0) {
		vec3 orm = texture(orm_texture, UV).rgb;
		rough_dry *= orm.g;
		metal *= orm.b;
		if (orm_mode == 2) {
			AO = orm.r;
		}
	}
	if (normal_depth > 0.0) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}

	// Vertical rain streaks: thin columns, stretched along Y, crawling down.
	float column = noise2(vec2((wp.x + wp.z) * streak_scale, 0.5));
	float run = noise2(vec2((wp.x + wp.z) * streak_scale * 0.5, wp.y * 1.6 + TIME * 0.08));
	float streak = smoothstep(0.55, 0.9, column) * smoothstep(0.35, 0.7, run);
	float wet = clamp(wetness * (0.7 + 0.3 * noise2(wp.xy * 2.0 + wp.zy)) + streak * 0.5, 0.0, 1.0);

	// Wood grain along the local up axis.
	float grain = noise2(vec2(v_local_pos.x * grain_scale + v_local_pos.z * grain_scale * 0.6, v_local_pos.y * 2.0));
	col *= mix(1.0, 0.65 + 0.5 * grain, grain_amount);

	// Grime and soaked band just above the water line.
	float waterline = 1.0 - smoothstep(waterline_y - 0.1, waterline_y + 0.45, wp.y);
	col *= mix(1.0, 0.45, waterline);

	col *= mix(1.0, 0.55, wet);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * rim_amount;

	ALBEDO = col;
	ROUGHNESS = mix(rough_dry, min(roughness_wet, rough_dry), wet * (1.0 - waterline * 0.5));
	METALLIC = metal;
	SPECULAR = 0.5 + 0.2 * wet;
	EMISSION = flash_color * flash + vec3(0.18, 0.2, 0.32) * rim * 0.35 + col * vec3(0.45, 0.5, 0.75) * fill + tex * emission_tint;
}

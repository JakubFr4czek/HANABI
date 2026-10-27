shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Rain-soaked surface for props (lacquered wood, stone, wood). Rain soaks the
// whole surface (porous material darkens and its roughness drops a little), but
// a smooth water film only forms where water can stand or run: patches on
// up-facing surfaces and slow rain streaks down the walls. Everything else stays
// matte, so light diffuses over the form instead of sheening off it like
// plastic. Darker band at the water line, optional fine wood grain.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec3 base_color : source_color = vec3(0.3, 0.05, 0.05);
uniform float roughness_dry : hint_range(0.0, 1.0) = 0.8;
// Roughness under a water film (puddles on tops, rain streaks).
uniform float roughness_wet : hint_range(0.0, 1.0) = 0.3;
uniform float wetness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float streak_scale = 9.0;
uniform float waterline_y = 0.35;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.0;
uniform float grain_scale = 30.0;
// Cheap stand-in for a soft sky fill (moonlit fog bounce), so backlit
// gameplay-critical props stay readable without an extra light pass. It is
// diffuse only and brighter on up-facing surfaces, so it keeps the shape.
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
uniform float procedural_ao : hint_range(0.0, 1.0) = 0.0;
uniform float fog_rim : hint_range(0.0, 2.5) = 0.0;

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

	// World-space normal (before the normal map): tops hold water, walls drain.
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = smoothstep(0.55, 0.95, wn.y);

	// Vertical rain streaks: thin columns, stretched along Y, crawling down.
	float column = noise2(vec2((wp.x + wp.z) * streak_scale, 0.5));
	float run = noise2(vec2((wp.x + wp.z) * streak_scale * 0.5, wp.y * 1.6 + TIME * 0.08));
	float streak = smoothstep(0.55, 0.9, column) * smoothstep(0.35, 0.7, run) * (1.0 - up);
	float pooled = smoothstep(0.45, 0.75, noise2(wp.xz * 1.7 + wp.y * 0.6)) * up;
	// Soaked (darker, slightly smoother) vs. covered by a water film (glossy).
	float soak = wetness * (0.75 + 0.25 * noise2(wp.xy * 2.0 + wp.zy));
	float film = clamp(wetness * (pooled + streak * 0.9), 0.0, 1.0);

	// Wood grain along the local up axis.
	float grain = noise2(vec2(v_local_pos.x * grain_scale + v_local_pos.z * grain_scale * 0.6, v_local_pos.y * 2.0));
	col *= mix(1.0, 0.65 + 0.5 * grain, grain_amount);

	// Grime and soaked band just above the water line.
	float waterline = 1.0 - smoothstep(waterline_y - 0.1, waterline_y + 0.45, wp.y);
	col *= mix(1.0, 0.45, waterline);

	col *= mix(1.0, 0.7, soak) * mix(1.0, 0.85, film);
	if (procedural_ao > 0.0) {
		float cavity = 0.58 + 0.42 * clamp(wn.y * 0.5 + 0.5, 0.0, 1.0);
		cavity -= noise2(wp.xz * 2.8) * 0.1 * procedural_ao;
		col *= mix(1.0, cavity, procedural_ao);
	}
	float rough_soaked = rough_dry * mix(1.0, 0.82, soak);

	ALBEDO = col;
	ROUGHNESS = mix(rough_soaked, min(roughness_wet, rough_soaked), film);
	METALLIC = metal;
	SPECULAR = 0.5;
	float sky_fill = fill * (0.35 + 0.65 * clamp(wn.y * 0.5 + 0.5, 0.0, 1.0));
	vec3 emission = flash_color * flash + col * vec3(0.45, 0.5, 0.75) * sky_fill + tex * emission_tint;
	if (fog_rim > 0.0) {
		vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
		float rim = pow(clamp(1.0 - abs(dot(normalize(wn), view_dir)), 0.0, 1.0), 2.4);
		emission += col * fog_rim * rim * 0.85;
	}
	EMISSION = emission;
}

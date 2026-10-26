shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Rain-soaked dark stone disc of the Dojo of the Storm (GDD §9). Carved
// concentric rings and radial slab joints hold water; shallow puddles are
// near-mirrors (they pick up the sky radiance and the moon's specular) with
// raindrop rings. The soaked stone between them stays matte (rough, with AO and
// the scanned relief) so moonlight diffuses over it instead of sheening off it.
// No emission: the stone is lit only by the moon and the flash.

#include "res://src/shaders/rain_ripples.gdshaderinc"

uniform vec3 stone_light : source_color = vec3(0.24, 0.24, 0.26);
uniform vec3 stone_dark : source_color = vec3(0.09, 0.09, 0.105);
// Scanned stone (Poly Haven japanese_stone_wall, ARM = AO/rough/metal), tiled
// in world XZ under the procedural wear so slabs read as real cut stone.
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float stone_tile = 2.2;
uniform float stone_texture_mix : hint_range(0.0, 1.0) = 0.85;
uniform float stone_normal_strength = 0.75;

varying vec3 v_world_pos;
varying vec3 v_local_normal;

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
	v_local_normal = NORMAL;
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float r = length(xz);
	float angle = atan(xz.y, xz.x);

	// Rotated octaves so the value-noise lattice never lines up into blocks.
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 warp = vec2(noise2(xz * 0.35), noise2(xz * 0.35 + 5.2)) * 1.6;
	float n_coarse = noise2(rot * (xz * 0.55 + warp)) * 0.7 + noise2(rot * rot * xz * 1.3) * 0.3;
	float n_mid = noise2(rot * xz * 3.1 + 7.0);
	float n_fine = noise2(rot * rot * xz * 9.0 + 3.0);
	float grain = n_coarse * 0.5 + n_mid * 0.3 + n_fine * 0.2;

	// Carved rings and slab joints (grooves full of water).
	float ring1 = 1.0 - smoothstep(0.01, 0.03, abs(r - 1.72));
	float ring2 = 1.0 - smoothstep(0.012, 0.035, abs(r - 3.65));
	float ring3 = 1.0 - smoothstep(0.015, 0.04, abs(r - 4.95));
	float spoke = (1.0 - smoothstep(0.01, 0.025, abs(sin(angle * 8.0)) * r)) * step(1.72, r) * step(r, 4.95);
	float groove = clamp(ring1 + ring2 + ring3 + spoke * 0.8, 0.0, 1.0);

	float top = smoothstep(0.5, 0.9, v_local_normal.y);
	// Shallow puddles in the low spots, plus water standing in every groove.
	float low = n_coarse * 0.85 + n_mid * 0.15;
	float puddle = clamp(smoothstep(0.56, 0.64, low) + groove, 0.0, 1.0) * top;
	// A thin water film around each puddle: smoother, but not yet a mirror.
	float film = smoothstep(0.48, 0.58, low) * top * (1.0 - puddle);

	vec2 suv = rot * xz / stone_tile + warp * 0.04;
	vec3 stone = texture(stone_albedo, suv).rgb;
	vec3 sarm = texture(stone_arm, suv).rgb;
	vec2 sn = texture(stone_normal, suv).rg * 2.0 - 1.0;
	// Undo the UV rotation so the normal map's tangent frame lines up with world XZ.
	sn = transpose(rot) * sn;

	vec3 col = mix(stone_dark, stone_light, grain);
	col *= mix(vec3(1.0), stone * 2.4 * sarm.r, stone_texture_mix);
	col *= mix(1.0, 0.45, groove);
	// Soaked stone is darker; standing water darker still.
	col *= mix(0.72, 0.3, puddle) * mix(1.0, 0.85, film);

	vec3 rr = rain_ripples(xz, TIME * 1.4) * puddle;
	vec2 slope = rr.xy * 0.35 + ((vec2(n_mid, noise2(rot * xz * 2.7 + 1.3)) - 0.5) * 0.06 - sn * stone_normal_strength * stone_texture_mix) * (1.0 - puddle);
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	if (top > 0.01) {
		NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(n_world, 0.0)).xyz, top));
	}

	ALBEDO = col;
	float rough_stone = mix(0.72, 0.86, n_mid) * mix(1.0, clamp(sarm.g * 1.05, 0.55, 1.0), stone_texture_mix);
	ROUGHNESS = mix(mix(rough_stone, 0.32, film), 0.04, puddle);
	// Water's F0 is ~2 % (SPECULAR 0.25), stone ~4 % (0.5).
	SPECULAR = mix(0.5, 0.3, puddle);
	METALLIC = 0.0;
	AO = mix(1.0, sarm.r, stone_texture_mix * (1.0 - puddle));
	AO_LIGHT_AFFECT = 0.35;
}

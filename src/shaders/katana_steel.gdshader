shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Katana (Grab3D model, one PBR surface): polished steel that mirrors the dark
// storm sky (sky radiance = baked cubemap) with rain beads on the blade, a
// black silk handle wrap, and a brief flare along the steel on lightning.
// Blade = mesh-local X > 0.035; wrap = bluish texels on the handle.

global uniform float storm_flash;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap; // G = roughness, B = metallic
uniform vec3 wrap_color : source_color = vec3(0.03, 0.028, 0.034);
uniform vec3 steel_tint : source_color = vec3(0.78, 0.8, 0.84);
uniform vec3 lightning_tint : source_color = vec3(0.55, 0.72, 1.0);
uniform float droplets : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_local;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb;
	vec3 orm = texture(orm_texture, UV).rgb;
	float rough = orm.g;
	float metal = orm.b;
	NORMAL_MAP = texture(normal_texture, UV).rgb;

	float x = v_local.x;
	float blade = smoothstep(0.03, 0.045, x);
	// The wrap texture is blue/white silk, the fittings are brass: split by hue.
	float wrap = step(-0.26, x) * step(x, 0.0) * smoothstep(-0.01, 0.06, albedo.b - albedo.r);

	// Black silk wrap: keep the diamond pattern as a faint sheen only.
	float lum = dot(albedo, vec3(0.3, 0.59, 0.11));
	albedo = mix(albedo, wrap_color * (0.6 + 0.8 * lum), wrap);
	rough = mix(rough, 0.55, wrap);
	metal = mix(metal, 0.0, wrap);
	// Fittings: darker antique brass.
	albedo = mix(albedo, albedo * vec3(0.55, 0.5, 0.45), (1.0 - wrap) * (1.0 - blade));

	// Polished steel; keep the texture's hamon/polish variation.
	albedo = mix(albedo, steel_tint * (0.75 + 0.45 * lum), blade);
	rough = mix(rough, 0.1 + 0.14 * (1.0 - lum), blade);
	metal = mix(metal, 1.0, blade);

	// Rain beads on the flat of the blade (mesh XZ plane), a few slowly sliding.
	if (blade > 0.0 && droplets > 0.0) {
		vec2 q = vec2(x * 90.0, v_local.z * 90.0);
		vec2 cell = floor(q);
		float h = hash21(cell);
		float slide = step(0.85, h) * fract(TIME * 0.05 + h) * 3.0;
		vec2 c = cell + vec2(0.5 + 0.3 * (hash21(cell + 3.1) - 0.5) - slide, 0.5);
		vec2 d = q - c;
		float rad = 0.12 + 0.18 * hash21(cell + 7.7);
		float bead = step(0.45, h) * (1.0 - smoothstep(rad * 0.75, rad, length(d))) * droplets * blade;
		rough = mix(rough, 0.02, bead);
		albedo *= mix(1.0, 0.7, bead);
		NORMAL_MAP = mix(NORMAL_MAP, normalize(vec3(d / max(rad, 0.01) * 0.6, 1.0)) * 0.5 + 0.5, bead);
	}

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = lightning_tint * storm_flash * blade * (0.15 + 1.2 * fres);
}

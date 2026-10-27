shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Katana (Poly Haven antique_katana_01, one PBR surface, ARM texture):
// polished steel that mirrors the dark storm sky (sky radiance = baked
// cubemap) with rain beads on the blade, rain-darkened handle and fittings,
// and a brief flare along the steel on lightning.
// Blade = mesh-local Y > 0.014 (tsuba ends at 0.012); flat of the blade = XY.

global uniform float storm_flash;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform sampler2D arm_texture : hint_default_white, filter_linear_mipmap; // R = AO, G = roughness, B = metallic
uniform vec3 steel_tint : source_color = vec3(0.86, 0.87, 0.9);
uniform vec3 lightning_tint : source_color = vec3(0.55, 0.72, 1.0);
uniform float blade_polish : hint_range(0.0, 1.0) = 0.55;
uniform float fittings_wet : hint_range(0.0, 1.0) = 0.35;
uniform float droplets : hint_range(0.0, 1.0) = 1.0;
// Soft spirit light while the blade is offered in the intro (0 = off).
uniform float spirit_glow : hint_range(0.0, 2.0) = 0.0;
uniform vec3 spirit_color : source_color = vec3(0.7, 0.82, 1.0);

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
	vec3 arm = texture(arm_texture, UV).rgb;
	float rough = arm.g;
	float metal = arm.b;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	AO = arm.r;

	float blade = smoothstep(0.012, 0.02, v_local.y);

	// Handle and fittings: darker and a little glossier from the rain.
	albedo *= mix(1.0, 0.8, fittings_wet * (1.0 - blade));
	rough = mix(rough, rough * 0.7, fittings_wet * (1.0 - blade));

	// Steel: keep the texture's hamon and polish marks, push towards a mirror.
	albedo = mix(albedo, albedo * steel_tint, blade);
	rough = mix(rough, rough * (1.0 - blade_polish), blade);
	metal = mix(metal, max(metal, 0.9), blade);

	// Rain beads on the flat of the blade, a few slowly sliding towards the guard.
	if (blade > 0.0 && droplets > 0.0) {
		vec2 q = vec2(v_local.y * 90.0, v_local.x * 90.0);
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
	EMISSION = lightning_tint * storm_flash * blade * (0.15 + 1.2 * fres)
		+ spirit_color * spirit_glow * (0.25 + 0.75 * blade) * (0.3 + 0.9 * fres);
}

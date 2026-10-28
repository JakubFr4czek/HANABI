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
// Elemental blade imbue (E3). element_glow = 0 is plain steel. The glow is an
// edge light on the cutting edge (ha) plus a faint rim, never a flat colour
// wash, so the steel texture stays readable. Kinds: 1 sakura (rose, slow
// breathing), 2 storm (cyan, short crackling arcs), 3 ink (wet black coat with
// an indigo hairline), 4 shadow (violet breath and rising wisps).
uniform float element_glow : hint_range(0.0, 3.0) = 0.0;
uniform vec3 element_color : source_color = vec3(1.0, 0.32, 0.74);
uniform int element_kind : hint_range(0, 4) = 0;
// 0..1.25: the imbue running from the guard to the tip (>= 1.2 = settled).
uniform float element_sweep = 2.0;
// 1 -> 0 after an imbue or refresh: a brief bright front.
uniform float element_flash : hint_range(0.0, 1.0) = 0.0;
// 1 during the last seconds: the glow pulses at 3 Hz from element_left.
uniform float element_warn : hint_range(0.0, 1.0) = 0.0;
uniform float element_left = 0.0;

// Intro spirit gate: steel still on the far side of the gate plane is not
// drawn, and a thin glowing seam marks where the blade crosses it.
uniform float portal_active = 0.0;
uniform vec3 portal_point = vec3(0.0);
uniform vec3 portal_normal = vec3(0.0, 0.0, 1.0);
uniform vec3 portal_color : source_color = vec3(0.8, 0.65, 1.0);

varying vec3 v_local;
varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float gate_side = dot(v_world - portal_point, portal_normal);
	if (portal_active > 0.5 && gate_side < 0.0) {
		discard;
	}
	float gate_seam = portal_active * (1.0 - smoothstep(0.0, 0.03, gate_side));
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

	// --- Elemental imbue ---------------------------------------------------
	vec3 imbue = vec3(0.0);
	if (element_glow > 0.001 && element_kind > 0) {
		float bt = clamp((v_local.y - 0.02) / 0.67, 0.0, 1.0); // habaki -> tip
		// The blade curves toward its spine (+x); the cutting edge is the -x side.
		float centre = 0.115 * pow(max(v_local.y - 0.22, 0.0), 2.0);
		float side = (v_local.x - centre) / 0.0155;
		float edge_m = (1.0 - smoothstep(-0.95, -0.15, side)) * blade;
		float reach = 1.0 - smoothstep(element_sweep - 0.14, element_sweep, bt);
		float front = exp(-pow((bt - element_sweep + 0.05) / 0.07, 2.0)) * step(bt, element_sweep + 0.05);
		float pulse = mix(1.0, 0.30 + 0.70 * (0.5 + 0.5 * sin(18.8496 * element_left)), element_warn);
		float live = element_glow * pulse * reach;
		float level = element_glow * reach;
		vec3 ec = element_color;
		vec3 glow = vec3(0.0);
		float dark = 0.0;
		if (element_kind == 1) {
			float breathe = 0.86 + 0.14 * sin(TIME * 1.7 + bt * 5.0);
			vec3 hot = mix(ec, vec3(1.0, 0.86, 0.92), 0.5);
			glow = (ec * (0.30 + 0.6 * fres) + hot * 1.8 * edge_m) * breathe;
			dark = 0.22;
		} else if (element_kind == 2) {
			float tick = floor(TIME * 22.0);
			float spark = step(0.93, hash21(vec2(floor(v_local.y * 140.0), tick)));
			float spark2 = step(0.965, hash21(vec2(floor(v_local.y * 61.0) + 11.0, tick + 3.0)));
			vec3 hot = mix(ec, vec3(0.9, 0.97, 1.0), 0.55);
			glow = ec * (0.55 + 0.7 * fres) + hot * 1.8 * edge_m * (0.75 + 1.9 * spark + 0.8 * spark2);
			dark = 0.25;
		} else if (element_kind == 3) {
			float flow = 0.5 + 0.5 * sin(bt * 9.0 - TIME * 1.4);
			glow = ec * (0.06 + 0.45 * fres) + ec * 1.1 * edge_m * (0.55 + 0.45 * flow);
			dark = 0.8;
		} else {
			float breath = 0.65 + 0.35 * sin(TIME * 1.3);
			float wisp = 0.5 + 0.5 * sin(bt * 14.0 - TIME * 2.2 + sin(bt * 5.0 + TIME * 0.7) * 2.0);
			glow = ec * (0.16 + 0.6 * fres * breath) + ec * 1.3 * edge_m * breath
				+ ec * 0.5 * wisp * wisp * breath * (0.3 + 0.7 * bt) * blade;
			dark = 0.45;
		}
		// A darker steel body lets the light on the edge stand out in the pale fog.
		albedo *= 1.0 - dark * level * blade;
		if (element_kind == 3) {
			rough = mix(rough, 0.06, level * blade);
			metal = mix(metal, 0.2, level * blade);
		}
		imbue = (glow * mix(0.55, 1.0, bt) * live + ec * front * element_flash * 2.2) * blade;
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = lightning_tint * storm_flash * blade * (0.15 + 1.2 * fres)
		+ spirit_color * spirit_glow * (0.25 + 0.75 * blade) * (0.3 + 0.9 * fres)
		+ imbue
		+ portal_color * gate_seam * 3.0;
}

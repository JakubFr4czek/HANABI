shader_type spatial;
// Ethereal focal sakura tree in the dark misty forest (GDD §9).
// Aesthetic: Sparse neon on a dark base, not kitsch.
// Deep plum/wine velvet interior shadows, authentic blush cherry blossom petals,
// crisp neon-pink Fresnel rim glow against the milk fog, and rare radiant blossom accents.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

global uniform vec4 storm_fog_color;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;

// Bark palette - deep, aged, dark wet Japanese cherry wood
uniform vec3 bark_tint : source_color = vec3(0.12, 0.09, 0.08);
uniform float normal_depth = 0.65;

// Sakura canopy palette - layered depth:
// 1. Deep interior: dark plum / midnight wine shadow
uniform vec3 deep_plum_color : source_color = vec3(0.11, 0.02, 0.07);
// 2. Mid blossoms: soft authentic Japanese sakura rose
uniform vec3 mid_petal_color : source_color = vec3(0.76, 0.28, 0.48);
// 3. Sparse neon accent: vibrant neon pink on outermost tips
uniform vec3 neon_pink_accent : source_color = vec3(1.0, 0.30, 0.68);
// 4. Ethereal rim & iridescence: grazing angle glass glow
uniform vec3 rim_glow_color : source_color = vec3(0.96, 0.65, 0.98);
// 5. Stamen spark: rare tiny golden-pink flower cores
uniform vec3 stamen_color : source_color = vec3(1.0, 0.88, 0.95);

uniform float emission_strength : hint_range(0.5, 3.0) = 1.35;
uniform float neon_sparsity : hint_range(0.0, 1.0) = 0.70;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Gentle organic canopy sway in the forest breeze for blossom foliage clumps (UV.y > 1.5)
	if (UV.y > 1.5) {
		float phase = dot(v_world_pos.xz, vec2(0.15, 0.12)) + TIME * 1.25;
		float sway = sin(phase + VERTEX.y * 0.8) * 0.035;
		VERTEX.x += sway;
		VERTEX.z += cos(phase * 0.8 + VERTEX.x * 0.8) * (sway * 0.75);
		VERTEX.y += sin(phase * 1.4) * (sway * 0.35);
	}
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float open_sky = clamp(wn.y * 0.45 + 0.5, 0.0, 1.0);

	// 1. Root flare (UV.x > 1.5)
	float root = step(1.5, UV.x);
	float along = clamp(UV.x - 2.0, 0.0, 1.0);
	vec3 soil = vec3(0.14, 0.16, 0.12);
	vec3 alb_root = mix(bark_tint, soil, smoothstep(0.08, 0.85, along));
	float grain = fract(sin(dot(UV, vec2(12.9898, 78.233))) * 43758.5453);
	alb_root *= mix(0.88, 1.08, grain);

	// 2. Bark and boughs (UV.y <= 1.5 && UV.x <= 1.5)
	vec3 tex = texture(albedo_texture, UV).rgb;
	float cover = max(tex.r, max(tex.g, tex.b));
	vec3 alb_bark = tex * bark_tint * 1.15;

	// 3. Blossom canopy clumps (UV.y > 1.5)
	float leaf = step(1.5, UV.y);

	// Multi-frequency 3D coordinates for seamless organic petal clusters
	vec3 p = v_world_pos * 3.8;
	float c1 = sin(p.x * 2.2 + sin(p.y * 2.7)) * cos(p.z * 2.2 + sin(p.x * 2.5));
	float c2 = cos(p.y * 4.3 + cos(p.z * 3.1)) * sin(p.x * 4.3 + cos(p.y * 2.0));
	float petal_pattern = c1 * 0.58 + c2 * 0.42;

	// Deep shadow vs outer blossom sprigs
	float cluster_edge = smoothstep(-0.25, 0.55, petal_pattern);
	float petal_tip = smoothstep(0.35, 0.85, petal_pattern);
	float exposure = clamp(dot(wn, vec3(0.25, 0.85, 0.35)) * 0.5 + 0.5, 0.0, 1.0);

	// Base blossom albedo: dark velvety plum in crevices, rich sakura blush on petals
	vec3 alb_blossom = mix(deep_plum_color, mid_petal_color, smoothstep(0.15, 0.85, open_sky * 0.65 + cluster_edge * 0.35));
	alb_blossom = mix(alb_blossom, neon_pink_accent * 0.85, petal_tip * 0.45 * exposure);

	// Fresnel grazing rim glow (ethereal outline against the dark milk fog)
	float ndotv = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - clamp(ndotv, 0.0, 1.0), 2.8);

	// Sparse neon accents: only outermost prominent flower tips flare
	float accent_mask = smoothstep(neon_sparsity, 0.96, petal_pattern * 0.65 + exposure * 0.35);

	// Rare delicate stamen pin-prick center sparks
	float stamen_noise = pow(max(0.0, sin(p.x * 8.0) * cos(p.y * 8.0) * sin(p.z * 8.0)), 7.0);
	float stamen = stamen_noise * step(0.35, exposure);

	// Emission composition (restrained, high contrast, non-kitschy)
	vec3 emit_rim = mix(neon_pink_accent, rim_glow_color, fresnel * 0.45) * (fresnel * 1.2);
	vec3 emit_accent = neon_pink_accent * (accent_mask * 1.4);
	vec3 emit_stamen = stamen_color * (stamen * 1.7);
	vec3 emit_body = mid_petal_color * (0.20 * open_sky * cluster_edge);
	vec3 emit_blossom = (emit_body + emit_rim + emit_accent + emit_stamen) * emission_strength;

	// Combine components
	vec3 final_albedo = mix(alb_bark, alb_blossom, leaf);
	final_albedo = mix(final_albedo, alb_root, root);

	vec3 bark_emission = storm_fog_color.rgb * 0.04 * (0.65 + 0.35 * open_sky);
	vec3 final_emission = mix(bark_emission, emit_blossom, leaf);

	ALBEDO = final_albedo;
	ROUGHNESS = mix(0.84, mix(0.72, 0.32, fresnel), leaf);
	METALLIC = 0.0;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - root) * (1.0 - leaf);
	ALPHA = mix(cover, 1.0, max(root, leaf));
	ALPHA_SCISSOR_THRESHOLD = 0.05;
	EMISSION = final_emission;
}

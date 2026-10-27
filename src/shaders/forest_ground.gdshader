shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

global uniform vec4 storm_fog_color;

uniform vec3 base_color : source_color = vec3(0.06, 0.07, 0.10);
uniform float fog_fade_start = 9.5;
uniform float fog_fade_end = 12.5;
uniform vec3 moss_color : source_color = vec3(0.08, 0.11, 0.09);
uniform float roughness_dry : hint_range(0.0, 1.0) = 0.88;
uniform float roughness_wet : hint_range(0.0, 1.0) = 0.42;
uniform float wetness : hint_range(0.0, 1.0) = 0.72;
uniform float fill = 1.35;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float up = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
	float patch = hash21(floor(v_world_pos.xz * 2.4));
	vec3 albedo = mix(base_color, moss_color, up * 0.55 + patch * 0.12);
	float wet = wetness * (0.35 + up * 0.65);
	float rough = mix(roughness_dry, roughness_wet, wet);
	vec3 lit = albedo * (0.22 + up * fill * 0.14);
	float radial = length(v_world_pos.xz);
	float fog_mix = smoothstep(fog_fade_start, fog_fade_end, radial);
	vec3 fog_col = storm_fog_color.rgb * 0.58;
	ALBEDO = mix(lit, fog_col, fog_mix);
	if (fog_mix > 0.985) {
		discard;
	}
	ROUGHNESS = rough;
	METALLIC = 0.0;
}

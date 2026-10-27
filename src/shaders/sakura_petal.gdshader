shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 petal_color : source_color = vec3(1.0, 0.22, 0.62);
uniform vec3 rim_color : source_color = vec3(1.15, 0.52, 0.92);
uniform float phantom = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float tapered = 1.0 - smoothstep(0.12, 0.96, abs(p.y));
	float body = 1.0 - smoothstep(tapered * 0.50, tapered * 0.58 + 0.01, abs(p.x));
	float notch = smoothstep(0.02, 0.14, length(p - vec2(0.0, -0.90)));
	float shape = body * notch;
	if (shape < 0.02) {
		discard;
	}
	float edge = clamp((1.0 - abs(NORMAL.z)) * 0.65 + (1.0 - shape) * 0.75, 0.0, 1.0);
	float vein = (1.0 - smoothstep(0.012, 0.035, abs(p.x))) * smoothstep(0.92, 0.2, abs(p.y));
	vec3 glass = mix(petal_color * 0.72, rim_color, edge * 0.78) + rim_color * vein * 0.14;
	glass = mix(glass, vec3(0.34, 0.055, 0.54), phantom * (0.30 + 0.10 * sin(TIME * 5.0 + p.y * 8.0)));
	ALBEDO = glass;
	EMISSION = glass * (0.20 + edge * 0.34);
	ALPHA = shape * mix(0.62, 0.46, phantom);
}

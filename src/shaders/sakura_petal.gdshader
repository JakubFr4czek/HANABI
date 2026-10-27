shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 petal_color : source_color = vec3(1.0, 0.22, 0.62);
uniform vec3 rim_color : source_color = vec3(1.15, 0.52, 0.92);
uniform vec3 glass_highlight : source_color = vec3(1.0, 0.92, 1.0);

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
	// Liquid glass: a bright reflection band drifts across the petal, strongest
	// mid-face, breaking at the rim like light on a glass shard.
	float sweep = fract(p.x * 0.35 + p.y * 0.45 + TIME * 0.35);
	float streak = pow(max(0.0, 1.0 - abs(sweep * 2.0 - 1.0) * 2.4), 3.0);
	vec3 glass = mix(petal_color * 0.72, rim_color, edge * 0.78) + rim_color * vein * 0.14;
	glass += glass_highlight * streak * 0.55 * (1.0 - edge * 0.45) * shape;
	// Instance colour (MultiMesh petals): rgb tints, alpha fades the petal out.
	glass *= COLOR.rgb;
	ALBEDO = glass;
	EMISSION = glass * (0.20 + edge * 0.34) + glass_highlight * streak * 0.30 * shape * COLOR.a;
	ALPHA = shape * 0.62 * COLOR.a;
}

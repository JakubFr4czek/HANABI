shader_type spatial;
// D18 distant matsuri fireworks: a soft, muffled bloom seen through the mist.
// Additive and unshaded, never lit, never a hard edge. fog_disabled so the glow
// survives the milk fog that swallows everything past 11 m; depth test stays on,
// so trees and hills in the loaded ring still cover it.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

uniform vec4 tint : source_color = vec4(0.95, 0.62, 0.38, 1.0);
uniform float intensity = 0.0;
// 0 = plain halo, 1 = halo with a faint expanding ring (the bloom edge).
uniform float ring = 0.5;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float halo = smoothstep(1.0, 0.0, r);
	halo = halo * halo * halo;
	float edge = exp(-pow((r - 0.55) / 0.2, 2.0));
	float a = clamp(halo + edge * ring * 0.35, 0.0, 1.0) * intensity;
	ALBEDO = tint.rgb;
	ALPHA = a;
}

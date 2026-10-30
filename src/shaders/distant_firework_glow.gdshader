shader_type spatial;
// D18 distant matsuri fireworks: a dim, muffled bloom seen through the mist.
// Additive and unshaded. fog_disabled so the glow survives the milk fog that
// swallows everything past 11 m; depth test stays on, so trees and hills in the
// loaded ring still cover it. Every term fades to zero before the quad edge, so
// there is never a hard rim.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

uniform vec4 tint : source_color = vec4(0.95, 0.62, 0.38, 1.0);
uniform float intensity = 0.0;
// Where the expanding shell sits, 0 = core, 1 = the edge of the quad.
uniform float shell_radius = 0.0;
// How strong the shell is right now (it fades as it expands).
uniform float shell_gain = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = 1.0 - smoothstep(0.55, 1.0, r);
	float core = exp(-r * r * 6.0) * 0.8;
	float haze = exp(-r * r * 1.5) * 0.45;
	float shell = exp(-pow((r - shell_radius) / 0.1, 2.0)) * shell_gain * 0.5;
	float a = clamp((core + haze + shell) * edge, 0.0, 1.0) * intensity;
	ALBEDO = tint.rgb;
	ALPHA = a;
}

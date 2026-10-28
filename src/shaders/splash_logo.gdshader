shader_type spatial;
// Boot splash, NANJO studio logo (D7). Unshaded white logo on alpha; the
// thread drops from the top, so the logo unveils downward through a soft edge.
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D logo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha : hint_range(0.0, 1.0) = 0.0;
uniform float reveal : hint_range(0.0, 1.2) = 0.0;
uniform float edge_softness = 0.06;

void fragment() {
	vec4 logo = texture(logo_tex, UV);
	// 1 above the reveal line, 0 below it; UV.y = 0 is the top of the quad.
	float unveiled = 1.0 - smoothstep(reveal - edge_softness, reveal, UV.y);
	ALBEDO = logo.rgb;
	ALPHA = logo.a * alpha * unveiled;
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// Soft volumetric lantern halo piercing milk fog at distance (Quest-compliant:
// 0 dynamic lights, 1 draw call, additive blending).
uniform vec4 glow_color : source_color = vec4(1.0, 0.32, 0.74, 1.0);
uniform float core_intensity : hint_range(0.0, 5.0) = 2.2;
uniform float falloff_exponent : hint_range(0.5, 5.0) = 2.4;

void vertex() {
	// Camera-facing billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	if (d > 1.0) {
		discard;
	}
	float soft = clamp(1.0 - d, 0.0, 1.0);
	float alpha = pow(soft, falloff_exponent);
	// Hot core
	float core = pow(clamp(1.0 - d * 2.0, 0.0, 1.0), 3.0) * 1.5;
	ALBEDO = glow_color.rgb * (alpha + core) * core_intensity;
}

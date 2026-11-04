shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// N16: the Oni boss's katana blade (dummy_sword BoxMesh, 0.014 × 0.034 × 0.84 m).
// The night forest has no specular moon (light_specular 0) and no reflections, so
// plain metal reads black. A faint cool sheen plus a moonlit line along both long
// edges of the blade keeps it readable at 4–5 m. Only this material glows: scene
// light, fog, sky and the body rim stay as they are.

uniform vec3 steel_color : source_color = vec3(0.66, 0.68, 0.72);
uniform float steel_metallic : hint_range(0.0, 1.0) = 0.75;
uniform float steel_roughness : hint_range(0.0, 1.0) = 0.24;
uniform vec3 sheen_color : source_color = vec3(0.62, 0.70, 0.86);
// Flat sheen over the whole blade (emission energy).
uniform float sheen : hint_range(0.0, 2.0) = 0.2;
// Extra light on the long edges (ha and mune) and at grazing angles.
uniform float edge_glow : hint_range(0.0, 4.0) = 0.9;
uniform float rim_glow : hint_range(0.0, 4.0) = 0.6;
uniform float half_height = 0.017; // BoxMesh size.y / 2

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	ALBEDO = steel_color;
	METALLIC = steel_metallic;
	ROUGHNESS = steel_roughness;
	float edge = smoothstep(0.55, 1.0, abs(local_pos.y) / half_height);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	EMISSION = sheen_color * (sheen + edge_glow * edge + rim_glow * rim);
}

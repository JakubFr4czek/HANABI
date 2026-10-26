shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Liquid-glass neon sakura petal shader (GDD §9):
// "Falling petals read as slightly transparent liquid glass: a bright fresnel rim
// and a subtle iridescent sheen, faked in the shader (fresnel, alpha, emission).
// No real refraction and no screen-space effects."

uniform vec3 core_color : source_color = vec3(0.48, 0.07, 0.28);
uniform vec3 rim_color : source_color = vec3(1.0, 0.34, 0.70);
uniform vec3 highlight_color : source_color = vec3(1.0, 0.76, 0.94);
uniform vec3 iridescence_color : source_color = vec3(0.42, 0.66, 1.0);

varying float v_seed;

void vertex() {
	v_seed = float(INSTANCE_ID) * 1.37 + INSTANCE_CUSTOM.x * 6.283;
	float t = TIME * 1.85 + v_seed;

	// Wind-driven swaying + 3D tumbling spin per falling petal.
	float spin_a = t * 1.35;
	float tilt_b = sin(t * 0.9 + v_seed) * 0.85;
	float ca = cos(spin_a), sa = sin(spin_a);
	float cb = cos(tilt_b), sb = sin(tilt_b);

	// Cup/curl the petal slightly like real cherry blossom glass.
	vec3 local_v = VERTEX;
	local_v.z += ( pow((UV.x - 0.5) * 2.0, 2.0) * 0.22 + sin(UV.y * 3.14159 + t) * 0.08 ) * 0.04;

	vec3 r1 = vec3(local_v.x * ca - local_v.z * sa, local_v.y, local_v.x * sa + local_v.z * ca);
	vec3 r2 = vec3(r1.x, r1.y * cb - r1.z * sb, r1.y * sb + r1.z * cb);
	VERTEX = r2;

	// Lateral wind oscillation along the trajectory.
	VERTEX.x += sin(t * 1.15 + v_seed * 2.1) * 0.14;
	VERTEX.z += cos(t * 0.92 + v_seed * 1.7) * 0.11;

	vec3 n1 = vec3(NORMAL.x * ca - NORMAL.z * sa, NORMAL.y, NORMAL.x * sa + NORMAL.z * ca);
	NORMAL = normalize(vec3(n1.x, n1.y * cb - n1.z * sb, n1.y * sb + n1.z * cb));
}

void fragment() {
	// Notched heart-like single sakura petal silhouette.
	vec2 p = (UV - vec2(0.5, 0.52)) * vec2(2.25, 1.95);
	p.x *= 1.0 - 0.30 * p.y;
	float notch = max(0.0, p.y - 0.32) * exp(-abs(p.x) * 6.5) * 0.58;
	float dist = length(vec2(p.x, p.y + notch));
	if (dist > 0.90) {
		discard;
	}

	// Fake liquid-glass normal curvature across the petal surface.
	vec3 glass_normal = normalize(NORMAL + vec3(p.x * 0.55, p.y * 0.45, 0.0));
	float ndotv = abs(dot(glass_normal, VIEW));
	float fresnel = pow(1.0 - clamp(ndotv, 0.0, 1.0), 2.2);
	float edge = smoothstep(0.48, 0.88, dist);
	float rim = clamp(edge * 0.72 + fresnel * 0.85, 0.0, 1.0);

	// Fake internal refraction / caustic glint Band + subtle blue-violet iridescence.
	float glint = pow(clamp(sin((p.x * 2.8 - p.y * 2.1) + v_seed + ndotv * 4.5) * 0.5 + 0.5, 0.0, 1.0), 5.0);
	vec3 glass_body = mix(core_color, iridescence_color, fresnel * 0.42);
	vec3 col = mix(glass_body * 0.85, rim_color * 1.35, pow(rim, 1.35));
	col += highlight_color * (glint * 0.55 + pow(rim, 3.2) * 0.65);

	// Semi-transparent center (liquid glass), sharper luminous rim.
	float alpha_mask = 1.0 - smoothstep(0.82, 0.90, dist);
	ALPHA = alpha_mask * mix(0.24, 0.86, pow(rim, 1.25));
	ALBEDO = col;
}

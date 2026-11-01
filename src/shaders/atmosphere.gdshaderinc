// Forest atmosphere (N4), shared by the crowns and the floor. Compatibility renderer: no volumetric
// fog and no height fog in the Environment, so the layers are computed per fragment here.
//   depth:  1 - exp(), so 8 m is clear, 20 m is about half milk, 40 m is nearly full (layers of the concept);
//   low:    mist lying between the trunks near the ground, thinning with height, from ~4 m out.
// All numbers come from WorldGenProfile (uniforms set by ForestWorld), nothing is hardcoded here.

float mist_amount(float dist, float height, float haze_start, float haze_end, float haze_max,
		float low_amount, float low_height) {
	float depth = (1.0 - exp(-max(dist - haze_start, 0.0) * 2.2 / max(haze_end - haze_start, 0.5))) * haze_max;
	float low = exp(-max(height, 0.0) / max(low_height, 0.1)) * low_amount * smoothstep(4.0, 14.0, dist);
	return clamp(max(depth, low), 0.0, 1.0);
}

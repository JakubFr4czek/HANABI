extends Node
## P1c: the torii lantern halo reads as a light at 28-35 m and is not a solid disc at 3 m.
## Headless there are no pixels, so this runs a CPU mirror of torii_lantern_halo.gdshader
## (keep the two in sync) with the real material parameters of a gate, and measures the
## peak colour contrast against the pale milk fog and the angular radius of the visible glow.
##   godot --headless --path . --fixed-fps 90 res://tests/torii_halo_test.tscn -- --desktop

const GATE_SCENE := preload("res://scenes/world/torii_gate.tscn")

## Pale milk fog the halo is mixed over (see torii_visuals_screenshot.gd).
const FOG := Color(0.69, 0.71, 0.72)
## Shader fragment space: the quad's half extents in metres, before distance scaling.
const HALF_SIZE := Vector2(1.2, 2.6)
const SHAFT_WIDTH := 0.17
## Readability thresholds (colour distance from fog, 0..~0.6 for these colours).
const FAR_MIN_PEAK := 0.25
const FAR_MIN_RADIUS_DEG := 2.0
const NEAR_MAX_PEAK := 0.12
## The glow edge is where the contrast drops to this level.
const VISIBLE_CONTRAST := 0.05

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var gate: ToriiGate = GATE_SCENE.instantiate()
	gate.element = Elements.SAKURA
	add_child(gate)
	await _frames(3)

	var mat: ShaderMaterial = gate._halo_mat
	var glow: Color = ToriiGate.HALO_COLORS[Elements.SAKURA]
	var core: Color = ToriiGate.HALO_CORES[Elements.SAKURA]

	var peak_28 := _peak_contrast(28.0, mat, glow, core)
	var peak_35 := _peak_contrast(35.0, mat, glow, core)
	var radius_28 := _visible_radius_deg(28.0, mat, glow, core)
	var radius_35 := _visible_radius_deg(35.0, mat, glow, core)
	var peak_3 := _peak_contrast(3.0, mat, glow, core)

	_check("a far gate is a light at 28 m (peak contrast %.2f, glow radius %.2f deg)" % [peak_28, radius_28],
		peak_28 >= FAR_MIN_PEAK and radius_28 >= FAR_MIN_RADIUS_DEG)
	_check("a far gate is a light at 35 m (peak contrast %.2f, glow radius %.2f deg)" % [peak_35, radius_35],
		peak_35 >= FAR_MIN_PEAK and radius_35 >= FAR_MIN_RADIUS_DEG)
	_check("a gate at 3 m is not a solid disc (peak contrast %.2f)" % peak_3, peak_3 <= NEAR_MAX_PEAK)
	_check("the halo peak grows with distance, so the far gate is not dimmer than the near one",
		peak_28 > peak_3 and peak_35 >= peak_28 - 0.001)

	gate.queue_free()


## Peak colour contrast against the fog at the centre of the halo (the brightest point).
func _peak_contrast(dist: float, mat: ShaderMaterial, glow: Color, core: Color) -> float:
	return _contrast_at(dist, Vector2.ZERO, mat, glow, core)


## Angular radius (degrees) of the glow along the horizontal axis, where the contrast
## is still at least VISIBLE_CONTRAST. The shader scales the quad by dist / 12 (capped),
## so the world offset of a shader-space point is p * scale.
func _visible_radius_deg(dist: float, mat: ShaderMaterial, glow: Color, core: Color) -> float:
	var scale := clampf(dist / 12.0, 1.0, float(mat.get_shader_parameter("max_scale")))
	var reach := 0.0
	for i in range(1, 1201):
		var x := float(i) / 1000.0
		if x > HALF_SIZE.x:
			break
		if _contrast_at(dist, Vector2(x, 0.0), mat, glow, core) >= VISIBLE_CONTRAST:
			reach = x
	return rad_to_deg(atan(reach * scale / dist))


## Mirror of the fragment shader at breathe = 1 (the brightest phase), intensity = 1 (awake).
func _contrast_at(dist: float, p: Vector2, mat: ShaderMaterial, glow: Color, core_c: Color) -> float:
	var near_cap: float = mat.get_shader_parameter("near_alpha_cap")
	var far_cap: float = mat.get_shader_parameter("far_alpha_cap")
	var d := p.length()
	var halo := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
	var core_k := pow(clampf(1.0 - d * 2.4, 0.0, 1.0), 2.0)
	var shaft := exp(-pow(p.x / SHAFT_WIDTH, 2.0)) * pow(clampf(1.0 - absf(p.y) / HALF_SIZE.y, 0.0, 1.0), 1.5)
	var far_k := smoothstep(3.0, 13.0, dist)
	var a := halo * lerpf(0.5, 1.0, far_k) + shaft * 0.6 * far_k + core_k * 0.4
	var far_thin := lerpf(1.0, 0.72, smoothstep(18.0, 36.0, dist))
	var alpha := clampf(a * far_thin, 0.0, lerpf(near_cap, far_cap, far_k))
	var albedo := glow.lerp(core_c, clampf(core_k, 0.0, 1.0) * 0.8)
	return alpha * _colour_distance(albedo, FOG)


func _colour_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

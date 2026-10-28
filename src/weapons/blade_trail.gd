class_name BladeTrail
extends MeshInstance3D
## Ribbon trail behind a [BladeBody]: a strip of quads between the blade
## positions of the last [member lifetime] seconds, fading with age. Drawn only
## while the blade moves fast. Built on the CPU with an ImmediateMesh, so it
## works on every renderer (Quest uses Compatibility). Color = weapon element.

## Seconds of history kept (simulation time, so trails linger in slow motion).
@export var lifetime := 0.1
## Tip speed (m/s) where the trail starts to appear, and where it is fully opaque.
@export var min_speed := 3.5
@export var full_speed := 9.0
## Where along the blade (0 hilt .. 1 tip) the streak starts and where it
## reaches its tip-edge brightness: a slim streak behind the outer blade,
## not a milky sheet over the whole swing.
@export var streak_start := 0.45
@export var streak_edge := 0.88
## Opacity of the newest, fastest part of the trail at the tip edge.
@export var max_alpha := 0.5
## Plain steel (no element): a cool moonlit glint instead of near-white.
const STEEL_TINT := Color(0.42, 0.52, 0.72)

var _blade: BladeBody
var _samples: Array = []  # [base: Vector3, tip: Vector3, age: float, intensity: float]
var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_blade = get_parent() as BladeBody
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = false
	refresh_material()
	process_physics_priority = 110  # after the weapon moved


func refresh_material() -> void:
	if _blade == null:
		return
	_material.albedo_color = STEEL_TINT if _blade.element == Elements.NONE else Elements.color(_blade.element)
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if Elements.is_additive(_blade.element) else BaseMaterial3D.BLEND_MODE_MIX


## Current visible strength 0..1 (tests / debug).
func intensity() -> float:
	return _samples[-1][3] if not _samples.is_empty() else 0.0


func clear() -> void:
	_samples.clear()
	_mesh.clear_surfaces()


func _physics_process(delta: float) -> void:
	if _blade == null or delta <= 0.0:
		return
	var base := _blade.get_blade_start_global()
	var tip := _blade.get_tip_global()
	var strength := 0.0
	if not _samples.is_empty():
		var tip_speed: float = tip.distance_to(_samples[-1][1]) / delta
		tip_speed = TimeController.to_real_speed(tip_speed) if _blade is HeldWeapon else tip_speed
		strength = smoothstep(min_speed, full_speed, tip_speed)
	for s in _samples:
		s[2] += delta
	while not _samples.is_empty() and _samples[0][2] > lifetime:
		_samples.pop_front()
	_samples.append([base, tip, 0.0, strength])
	if _blade and _blade.element != Elements.NONE and _blade.is_fade_warning:
		# Same 3 Hz beat as the blade, driven by the imbue clock (so it also holds in a pause).
		var pulse := 0.6 + 0.4 * sin(_blade.element_time_remaining * TAU * 3.0)
		_material.albedo_color = Elements.color(_blade.element) * pulse
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var any := false
	for s in _samples:
		if s[3] > 0.01:
			any = true
			break
	if not any or _samples.size() < 2:
		return
	# The surface opens with the first visible segment: ending one with no
	# vertices is an engine error (it happened when every segment had faded).
	var open := false
	for i in _samples.size() - 1:
		var a: Array = _samples[i]
		var b: Array = _samples[i + 1]
		# Ease out with age so the streak thins away instead of blinking off.
		var ka: float = 1.0 - a[2] / lifetime
		var kb: float = 1.0 - b[2] / lifetime
		var fa: float = ka * ka * a[3] * max_alpha
		var fb: float = kb * kb * b[3] * max_alpha
		if fa <= 0.0 and fb <= 0.0:
			continue
		if not open:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
			open = true
		_quad(a[0], a[1], b[0], b[1], fa, fb)
	if open:
		_mesh.surface_end()


func _quad(base_a: Vector3, tip_a: Vector3, base_b: Vector3, tip_b: Vector3, fa: float, fb: float) -> void:
	# Two bands: a soft fade-in over the mid blade, then a brighter edge band
	# out to the tip.
	var sa := base_a.lerp(tip_a, streak_start)
	var sb := base_b.lerp(tip_b, streak_start)
	var ea := base_a.lerp(tip_a, streak_edge)
	var eb := base_b.lerp(tip_b, streak_edge)
	_band(sa, ea, sb, eb, 0.0, fa * 0.45, 0.0, fb * 0.45)
	_band(ea, tip_a, eb, tip_b, fa * 0.45, fa, fb * 0.45, fb)


func _band(in_a: Vector3, out_a: Vector3, in_b: Vector3, out_b: Vector3, ai: float, ao: float, bi: float, bo: float) -> void:
	var c_ai := Color(1, 1, 1, ai)
	var c_ao := Color(1, 1, 1, ao)
	var c_bi := Color(1, 1, 1, bi)
	var c_bo := Color(1, 1, 1, bo)
	_vertex(in_a, c_ai); _vertex(out_a, c_ao); _vertex(out_b, c_bo)
	_vertex(in_a, c_ai); _vertex(out_b, c_bo); _vertex(in_b, c_bi)


func _vertex(p: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(p)

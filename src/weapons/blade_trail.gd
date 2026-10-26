class_name BladeTrail
extends MeshInstance3D
## Ribbon trail behind a [BladeBody]: a strip of quads between the blade
## positions of the last [member lifetime] seconds, fading with age. Drawn only
## while the blade moves fast. Built on the CPU with an ImmediateMesh, so it
## works on every renderer (Quest uses Compatibility). Color = weapon element.

## Seconds of history kept (simulation time, so trails linger in slow motion).
@export var lifetime := 0.12
## Tip speed (m/s) where the trail starts to appear, and where it is fully opaque.
@export var min_speed := 3.5
@export var full_speed := 9.0
## Opacity of the inner (hilt-side) edge relative to the tip edge.
@export var inner_alpha := 0.15
## Opacity of the newest, fastest part of the trail.
@export var max_alpha := 0.7

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
	_material.albedo_color = Elements.color(_blade.element)
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
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for i in _samples.size() - 1:
		var a: Array = _samples[i]
		var b: Array = _samples[i + 1]
		var fa: float = (1.0 - a[2] / lifetime) * a[3] * max_alpha
		var fb: float = (1.0 - b[2] / lifetime) * b[3] * max_alpha
		if fa <= 0.0 and fb <= 0.0:
			continue
		_quad(a[0], a[1], b[0], b[1], fa, fb)
	_mesh.surface_end()


func _quad(base_a: Vector3, tip_a: Vector3, base_b: Vector3, tip_b: Vector3, fa: float, fb: float) -> void:
	var ca_in := Color(1, 1, 1, fa * inner_alpha)
	var ca_out := Color(1, 1, 1, fa)
	var cb_in := Color(1, 1, 1, fb * inner_alpha)
	var cb_out := Color(1, 1, 1, fb)
	_vertex(base_a, ca_in); _vertex(tip_a, ca_out); _vertex(tip_b, cb_out)
	_vertex(base_a, ca_in); _vertex(tip_b, cb_out); _vertex(base_b, cb_in)


func _vertex(p: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(p)

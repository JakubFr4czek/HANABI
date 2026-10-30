class_name BladeBody
extends RigidBody3D
## A physical weapon with a blade: a RigidBody3D whose origin is the grip point,
## with the blade running along local -Z from [member blade_start] to [member blade_tip].
##
## It records its velocity before each physics step, so contact handlers can ask
## how fast a point on the weapon was moving *before* the impact
## (after the step the solver has already slowed it down).

## Where the cutting edge starts, in local space (usually just past the guard).
@export var blade_start := Vector3(0, 0, -0.12)
## Blade tip, in local space.
@export var blade_tip := Vector3(0, 0, -0.95)
## Name shown in debug output and logs.
@export var weapon_name := "weapon"
## Active element: colors the trail now, drives on-hit effects later (GDD section 5).
@export var element := Elements.NONE

var current_element: String:
	get:
		return element
	set(val):
		set_element(val)

var element_time_remaining: float = 0.0
var is_fade_warning: bool = false
var _blade_mat: ShaderMaterial = null
## Second pass (blade_rim.gdshader): light on the edge when the blade is seen
## from behind or edge-on. Attached to the steel material only while imbued
## (one extra draw call, none on plain steel).
const RIM_SHADER := preload("res://src/shaders/blade_rim.gdshader")
## Rim strength and colour per school. Storm is a saturated electric blue
## here (the UI accent cyan reads pastel on a blade).
const RIM := {
	Elements.SAKURA: {"strength": 1.0, "color": Color(1.0, 0.30, 0.68)},
	Elements.STORM: {"strength": 1.5, "color": Color(0.16, 0.48, 1.0)},
	Elements.INK: {"strength": 0.85, "color": Color(0.05, 0.06, 0.20)},   # a dark coat: the rim is mixed, so dark reads against fog
	Elements.SHADOW: {"strength": 1.0, "color": Color(0.56, 0.18, 0.95)},
}
var _rim_mat: ShaderMaterial = null

## Blade imbue animation (real time, driven by [method _update_blade_material]):
## the school runs guard-to-tip, flashes once, and fades out when it lapses.
const SWEEP_SECONDS := 0.38
const FLASH_SECONDS := 0.55
const FADE_SECONDS := 0.6
const KIND := {Elements.SAKURA: 1, Elements.STORM: 2, Elements.INK: 3, Elements.SHADOW: 4}
var _sweep_msec := -100000
var _flash_msec := -100000
var _fade_element := Elements.NONE
var _fade_msec := -100000
var _shader_cache := {}
## Draw a ribbon trail behind the blade when it moves fast.
@export var show_trail := true

## True while the wielder is performing an attack with this weapon (an enemy
## strike). Clashing with an attacking blade can be a parry.
var attacking := false
## Who holds this weapon (enemy or player holder), or null.
var wielder: Node = null
var trail: BladeTrail

# Velocity snapshot taken at the end of our _physics_process, i.e. what the
# body carried into the next physics step.
var _snap_linear := Vector3.ZERO
var _snap_angular := Vector3.ZERO
var _snap_com := Vector3.ZERO


func _ready() -> void:
	add_to_group("weapons")
	# Run after hit detectors so they still see the previous step's snapshot.
	process_physics_priority = 100
	continuous_cd = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	if show_trail:
		trail = BladeTrail.new()
		trail.name = "Trail"
		add_child(trail)


## World-space center of mass.
func get_com_global() -> Vector3:
	return global_transform * center_of_mass


## Unit vector along the blade (grip toward tip), world space.
func get_blade_axis() -> Vector3:
	return (global_transform.basis * (blade_tip - blade_start)).normalized()


func get_tip_global() -> Vector3:
	return global_transform * blade_tip


func get_blade_start_global() -> Vector3:
	return global_transform * blade_start


func set_element(new_element: String) -> void:
	if new_element != element:
		if element != Elements.NONE and new_element == Elements.NONE:
			_fade_element = element
			_fade_msec = Time.get_ticks_msec()
		elif new_element != Elements.NONE:
			_sweep_msec = Time.get_ticks_msec()
			_flash_msec = _sweep_msec
	element = new_element
	# Single source of truth: set_element sets visual state without starting a timer.
	# The imbue countdown (ElementBalance.IMBUE_SECONDS) is managed exclusively by ElementSystem via imbue_element.
	element_time_remaining = 0.0
	is_fade_warning = false
	if trail:
		trail.refresh_material()
	_update_blade_material()


func imbue_element(new_element: String, duration: float = ElementBalance.IMBUE_SECONDS) -> void:
	var now := Time.get_ticks_msec()
	if new_element == element and element != Elements.NONE:
		element_time_remaining = duration
		_flash_msec = now  # a gate topping the same school up: a flash, no new sweep
	else:
		if new_element != Elements.NONE:
			_sweep_msec = now
			_flash_msec = now
		elif element != Elements.NONE:
			_fade_element = element
			_fade_msec = now
		element = new_element
		element_time_remaining = duration if new_element != Elements.NONE else 0.0
		is_fade_warning = false
		if trail:
			trail.refresh_material()
	_update_blade_material()


func _get_blade_material() -> ShaderMaterial:
	if _blade_mat == null:
		var model := get_node_or_null("Model")
		if model:
			for child in model.get_children():
				if child is MeshInstance3D:
					_blade_mat = child.get_surface_override_material(0) as ShaderMaterial
					if _blade_mat == null and child.mesh and child.mesh.get_surface_count() > 0:
						_blade_mat = child.get_active_material(0) as ShaderMaterial
					break
	return _blade_mat


func _update_blade_material() -> void:
	var mat := _get_blade_material()
	if mat == null:
		return
	var now := Time.get_ticks_msec()
	var shown := element
	var level := 1.0
	var sweep := 2.0
	var flash := 0.0
	var warn := 0.0
	if element == Elements.NONE:
		# Lapsed: the school drains out of the steel instead of snapping off.
		var k := float(now - _fade_msec) / (FADE_SECONDS * 1000.0)
		if k < 1.0 and _fade_element != Elements.NONE:
			shown = _fade_element
			level = (1.0 - k) * (1.0 - k)
		else:
			shown = Elements.NONE
	else:
		sweep = minf(float(now - _sweep_msec) / (SWEEP_SECONDS * 1000.0), 1.0) * 1.25
		flash = clampf(1.0 - float(now - _flash_msec) / (FLASH_SECONDS * 1000.0), 0.0, 1.0)
		warn = 1.0 if is_fade_warning else 0.0
	if shown == Elements.NONE:
		_set_shader(mat, "element_glow", 0.0)
		_update_rim(mat, shown, 0.0, sweep, warn)
		return
	var c := glow_color(shown)
	_set_shader(mat, "element_color", Vector3(c.r, c.g, c.b))
	_set_shader(mat, "element_kind", int(KIND.get(shown, 1)))
	_set_shader(mat, "element_sweep", sweep)
	_set_shader(mat, "element_flash", flash)
	_set_shader(mat, "element_warn", warn)
	_set_shader(mat, "element_left", element_time_remaining)
	_set_shader(mat, "element_glow", level)
	_update_rim(mat, shown, level, sweep, warn)


## Light colour of [param school] on the blade: the UI accent, except Storm, which
## is a saturated electric blue (the accent cyan reads pastel on steel in fog).
static func glow_color(school: String) -> Color:
	return RIM[school].color if school == Elements.STORM else Elements.accent_color(school)


## Keeps the rim pass in step with the steel pass (same sweep, drain and warning).
func _update_rim(mat: ShaderMaterial, shown: String, level: float, sweep: float, warn: float) -> void:
	if shown == Elements.NONE or level <= 0.001 or not RIM.has(shown):
		if mat.next_pass == _rim_mat and _rim_mat != null:
			mat.next_pass = null
		return
	if _rim_mat == null:
		_rim_mat = ShaderMaterial.new()
		_rim_mat.shader = RIM_SHADER
	if mat.next_pass != _rim_mat:
		mat.next_pass = _rim_mat
	var spec: Dictionary = RIM[shown]
	_rim_mat.set_shader_parameter("rim_color", Vector3(spec.color.r, spec.color.g, spec.color.b))
	_rim_mat.set_shader_parameter("rim_strength", float(spec.strength) * level)
	_rim_mat.set_shader_parameter("rim_sweep", sweep)
	_rim_mat.set_shader_parameter("rim_warn", warn)
	_rim_mat.set_shader_parameter("rim_left", element_time_remaining)


## D13: a landed cut leaves a mark on the edge for [constant TRACE_SECONDS]: a trace in
## the school's colour (ink blue when the blade is plain steel), easing out.
const TRACE_SECONDS := 3.0
var trace_left := 0.0


func mark_trace() -> void:
	trace_left = TRACE_SECONDS
	_update_trace()


func _process(delta: float) -> void:
	if trace_left <= 0.0:
		return
	trace_left = maxf(trace_left - delta, 0.0)
	_update_trace()


func _update_trace() -> void:
	var mat := _get_blade_material()
	if mat == null:
		return
	var level := smoothstep(0.0, 1.0, trace_left / TRACE_SECONDS)
	var c := glow_color(element) if element != Elements.NONE else Elements.accent_color(Elements.INK)
	_set_shader(mat, "trace_color", Vector3(c.r, c.g, c.b))
	_set_shader(mat, "trace_level", level)


## Only touches the material when a value actually changed.
func _set_shader(mat: ShaderMaterial, key: String, value: Variant) -> void:
	if _shader_cache.get(key) == value:
		return
	_shader_cache[key] = value
	mat.set_shader_parameter(key, value)


## Velocity a world point on this weapon had going into the last physics step.
func get_pre_step_point_velocity(world_point: Vector3) -> Vector3:
	return _snap_linear + _snap_angular.cross(world_point - _snap_com)


## Current velocity of a world point on this weapon.
func get_point_velocity(world_point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(world_point - get_com_global())


## Call at the very end of _physics_process, after velocities were set.
func _snapshot_velocity() -> void:
	_snap_linear = linear_velocity
	_snap_angular = angular_velocity
	_snap_com = get_com_global()


func _physics_process(_delta: float) -> void:
	_snapshot_velocity()

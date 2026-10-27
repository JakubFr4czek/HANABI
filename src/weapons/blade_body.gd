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
const ELEMENT_DURATION: float = 20.0
const FADE_WARNING_TIME: float = 3.0

var current_element: String:
	get:
		return element
	set(val):
		set_element(val)

var element_time_remaining: float = 0.0
var is_fade_warning: bool = false
var _blade_mat: ShaderMaterial = null
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
	element = new_element
	# Single source of truth: set_element sets visual state without starting a timer.
	# The 20s countdown is managed exclusively by ElementSystem via imbue_element.
	element_time_remaining = 0.0
	is_fade_warning = false
	if trail:
		trail.refresh_material()
	_update_blade_material()


func imbue_element(new_element: String, duration: float = ELEMENT_DURATION) -> void:
	if new_element == element and element != Elements.NONE:
		element_time_remaining = duration
	else:
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
	if element == Elements.NONE:
		mat.set_shader_parameter("element_glow", 0.0)
	else:
		var glow := 1.0
		if is_fade_warning:
			glow = 0.6 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * 3.0)
		var c := Elements.accent_color(element)
		mat.set_shader_parameter("element_glow", glow)
		mat.set_shader_parameter("element_color", Vector3(c.r, c.g, c.b))


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

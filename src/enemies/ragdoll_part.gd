class_name RagdollPart
extends RigidBody3D
## One rigid body of an [ActiveRagdoll]. Remembers its velocity going into the
## last physics step so weapons can compute impact speed before the solver
## changed it (same idea as [BladeBody]).

var _snap_linear := Vector3.ZERO
var _snap_angular := Vector3.ZERO
var _snap_com := Vector3.ZERO


func _ready() -> void:
	# Run after weapons have read last step's snapshot.
	process_physics_priority = 100


func get_pre_step_point_velocity(world_point: Vector3) -> Vector3:
	return _snap_linear + _snap_angular.cross(world_point - _snap_com)


func _physics_process(_delta: float) -> void:
	_snap_linear = linear_velocity
	_snap_angular = angular_velocity
	_snap_com = global_transform * center_of_mass

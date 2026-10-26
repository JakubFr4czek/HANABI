class_name ActiveRagdoll
extends Node3D
## A humanoid made of [RagdollPart] rigid bodies joined by Generic6DOF joints,
## kept standing by "muscles" instead of animation playback.
##
## Muscles: each joint drives its child toward a target pose with a
## velocity-level PD drive. The correction is applied as a rigid rotation of
## the joint's whole subtree (shoulder -> upper arm, forearm, sword) about the
## joint, with the opposite momentum on the parent. Because every body in the
## subtree gets a consistent push, the joints barely have to fight and the
## solver stays stable even with stiff muscles.
##
## Balance: "puppet strings" on the whole body keep the pelvis and chest
## upright and facing the target, the pelvis at standing height and near its
## anchor. Hits lower [member muscle] and [member balance]: a little gives a
## stagger, a lot drops the body to the floor, after which it gets up again.
##
## The node origin is the point between the feet; the body faces local +Z.
## Subclasses describe the body in [method _define_parts] and [method _define_poses].

signal state_changed(new_state: State)

enum State { STANDING, KNOCKED_DOWN, GETTING_UP }

## Collision layers: 4 = enemy_body. Collides with world, props, player weapon.
const BODY_LAYER := 8
const BODY_MASK := 1 | 2 | 4

## How fast joints chase their target pose (1/s). Higher = stiffer.
@export var joint_stiffness := 12.0
## Fraction of the joint velocity error corrected per tick (0..1).
@export var joint_gain := 0.5
## How much of each muscle's push is applied back onto the parent (0..1).
## 0 = muscles act like animation driving the limbs (stable); 1 = fully
## momentum-conserving (more realistic, but light parents get flung around).
@export var muscle_reaction := 0.0
## Upright/facing drive for pelvis and chest.
@export var upright_stiffness := 8.0
@export var upright_gain := 0.4
## Pelvis height spring (1/s), correction per tick, and gravity compensation
## (fraction of total weight, applied to every body).
@export var height_stiffness := 5.0
@export var height_gain := 0.25
@export var gravity_compensation := 0.6
## How strongly the body is pulled back to its anchor point.
@export var anchor_stiffness := 2.5
@export var anchor_gain := 0.05
## Max turning speed toward the facing target (deg/s).
@export var turn_speed_deg := 90.0

var parts := {}  # name -> RagdollPart
var state := State.STANDING
## 0..1 strength of all joint muscles.
var muscle := 1.0
## 0..1 strength of the balance help.
var balance := 1.0
var current_pose := "guard"
## World point the balance help keeps the pelvis above. Starts at this node's
## origin; after a knockdown it moves to where the body got up (it is not
## dragged back with its feet scraping the floor). [method reset_body] restores it.
var anchor_position := Vector3.ZERO

var _defs := {}  # name -> part definition Dictionary
var _poses := {}  # pose name -> {part name -> Quaternion}
var _rest := {}  # name -> Transform3D relative to this node
var _order: Array[String] = []  # parents before children
var _children := {}  # part name -> Array of child part names
var _attachments := {}  # part name -> Array of bodies fixed to it (e.g. a held sword)
var _subtree := {}  # part name -> Array[RigidBody3D]: the part, its descendants and attachments
var _all_bodies: Array[RigidBody3D] = []
var _facing_yaw := 0.0
var _target_yaw := 0.0
var _state_time := 0.0
var _stuck_time := 0.0
var _pelvis_rest_height := 0.0
var _total_mass := 0.0


func _ready() -> void:
	_facing_yaw = global_rotation.y
	_target_yaw = _facing_yaw
	anchor_position = global_position
	_build()


# --- Body description (override) -----------------------------------------

## Return {part_name: def}. A def has: shape ("box"/"capsule"/"sphere"),
## size (Vector3, box), radius/height (capsule/sphere), pos (Vector3, center in
## rest pose), mass, zone, and for non-root parts: parent, joint (Vector3,
## joint point), limits ({x/y/z: Vector2(min_deg, max_deg)}, child relative to
## parent, same convention as poses). Optional: extra_shapes
## ([{shape, size, offset}]), max_torque (N·m).
## The first part without a parent is the root (pelvis).
func _define_parts() -> Dictionary:
	return {}


## Return {pose_name: {part_name: Vector3 euler_deg relative to the parent}}.
func _define_poses() -> Dictionary:
	return {}


## Called for each part after it is created, to add meshes etc.
func _decorate_part(_part_name: String, _part: RagdollPart, _def: Dictionary) -> void:
	pass


# --- Building ---------------------------------------------------------------

func _build() -> void:
	_defs = _define_parts()
	var pose_defs := _define_poses()
	for pose_name in pose_defs:
		var src: Dictionary = pose_defs[pose_name]
		var q := {}
		for part_name in src:
			var e: Vector3 = src[part_name]
			q[part_name] = Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z))).get_rotation_quaternion()
		_poses[pose_name] = q

	# Parents first.
	var remaining: Array = _defs.keys()
	while not remaining.is_empty():
		for part_name in remaining.duplicate():
			var parent: String = _defs[part_name].get("parent", "")
			if parent == "" or _order.has(parent):
				_order.append(part_name)
				remaining.erase(part_name)

	for part_name in _order:
		_children[part_name] = []
		_attachments[part_name] = []
		_create_part(part_name, _defs[part_name])
	for part_name in _order:
		var parent: String = _defs[part_name].get("parent", "")
		if parent != "":
			_children[parent].append(part_name)
			_create_joint(part_name, _defs[part_name])
	_pelvis_rest_height = _defs[_order[0]].pos.y
	_rebuild_subtrees()


func _rebuild_subtrees() -> void:
	_all_bodies.clear()
	_total_mass = 0.0
	for i in range(_order.size() - 1, -1, -1):  # children first
		var part_name := _order[i]
		var bodies: Array[RigidBody3D] = [parts[part_name]]
		for body in _attachments[part_name]:
			bodies.append(body)
		for child in _children[part_name]:
			bodies.append_array(_subtree[child])
		_subtree[part_name] = bodies
	_all_bodies.assign(_subtree[_order[0]])
	for body in _all_bodies:
		_total_mass += body.mass


func _create_part(part_name: String, def: Dictionary) -> void:
	var body := RagdollPart.new()
	body.name = part_name
	body.mass = def.mass
	body.collision_layer = BODY_LAYER
	body.collision_mask = BODY_MASK
	body.angular_damp = 0.5
	body.linear_damp = 0.05
	body.set_meta("hit_receiver", self)
	body.set_meta("body_part", part_name)
	body.set_meta("zone", def.get("zone", "torso"))
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	body.physics_material_override = mat

	body.add_child(_make_shape(def))
	for extra in def.get("extra_shapes", []):
		var cs := _make_shape(extra)
		cs.position = extra.offset
		body.add_child(cs)

	var rest := Transform3D(Basis.IDENTITY, def.pos)
	_rest[part_name] = rest
	body.transform = rest
	add_child(body)
	parts[part_name] = body
	_decorate_part(part_name, body, def)


func _make_shape(def: Dictionary) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	match def.shape:
		"box":
			var s := BoxShape3D.new()
			s.size = def.size
			cs.shape = s
		"capsule":
			var s := CapsuleShape3D.new()
			s.radius = def.radius
			s.height = def.height
			cs.shape = s
		"sphere":
			var s := SphereShape3D.new()
			s.radius = def.radius
			cs.shape = s
	return cs


func _create_joint(part_name: String, def: Dictionary) -> void:
	var joint := Generic6DOFJoint3D.new()
	joint.name = "Joint_" + part_name
	joint.position = def.joint
	add_child(joint)
	joint.node_a = joint.get_path_to(parts[def.parent])
	joint.node_b = joint.get_path_to(parts[part_name])
	var limits: Dictionary = def.get("limits", {})
	_set_axis_limit(joint, "x", limits.get("x", Vector2.ZERO))
	_set_axis_limit(joint, "y", limits.get("y", Vector2.ZERO))
	_set_axis_limit(joint, "z", limits.get("z", Vector2.ZERO))


## [param range_deg] is the allowed rotation of the child relative to the parent
## (same convention as the poses). The joint measures the angle the other way
## round (verified with tests/diag/diag_joint.tscn under Jolt), so the range is negated.
func _set_axis_limit(joint: Generic6DOFJoint3D, axis: String, range_deg: Vector2) -> void:
	var lower := deg_to_rad(-range_deg.y)
	var upper := deg_to_rad(-range_deg.x)
	match axis:
		"x":
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper)
		"y":
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper)
		"z":
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lower)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, upper)


## Rigidly attach [param body] (already in the tree) to a part with a fixed joint.
## The body then counts as part of that limb for the muscles.
func attach_to_part(part_name: String, body: RigidBody3D, at: Vector3) -> Generic6DOFJoint3D:
	var joint := Generic6DOFJoint3D.new()
	joint.name = "Attach_" + body.name
	add_child(joint)
	joint.global_position = at
	joint.node_a = joint.get_path_to(parts[part_name])
	joint.node_b = joint.get_path_to(body)
	for axis in ["x", "y", "z"]:
		_set_axis_limit(joint, axis, Vector2.ZERO)
	_attachments[part_name].append(body)
	_rebuild_subtrees()
	return joint


# --- Runtime ----------------------------------------------------------------

func root_part() -> RagdollPart:
	return parts[_order[0]]


## Turn toward a world position (yaw only).
func face_toward(world_pos: Vector3) -> void:
	var d := world_pos - root_part().global_position
	d.y = 0.0
	if d.length_squared() > 0.01:
		_target_yaw = atan2(d.x, d.z)


func set_pose(pose_name: String) -> void:
	if _poses.has(pose_name):
		current_pose = pose_name


## Reduce muscle/balance, e.g. from a hit. Values are 0..1 amounts.
func weaken(muscle_loss: float, balance_loss: float) -> void:
	muscle = clampf(muscle - muscle_loss, 0.0, 1.0)
	balance = clampf(balance - balance_loss, 0.0, 1.0)
	if balance <= 0.0 and state == State.STANDING:
		_set_state(State.KNOCKED_DOWN)


## Teleport back to the rest pose at the anchor, at full strength.
func reset_body() -> void:
	_facing_yaw = global_rotation.y
	_target_yaw = _facing_yaw
	var root_xf := Transform3D(Basis(Vector3.UP, _facing_yaw), global_position)
	for part_name in _order:
		var p: RagdollPart = parts[part_name]
		p.global_transform = root_xf * _rest[part_name]
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
	muscle = 1.0
	balance = 1.0
	anchor_position = global_position
	_set_state(State.STANDING)


func _set_state(new_state: State) -> void:
	if new_state == State.GETTING_UP:
		var p := root_part().global_position
		anchor_position = Vector3(p.x, global_position.y, p.z)
	state = new_state
	_state_time = 0.0
	_stuck_time = 0.0
	state_changed.emit(new_state)


func _physics_process(delta: float) -> void:
	_update_state(delta)
	_turn_facing(delta)
	_drive_joints(delta)
	_drive_balance(delta)


func _update_state(delta: float) -> void:
	_state_time += delta
	match state:
		State.STANDING:
			balance = minf(balance + _balance_regen() * delta, 1.0)
			muscle = minf(muscle + _muscle_regen() * delta, 1.0)
			# Failsafe: if we ended up tangled (too low or leaning a lot) for a
			# while, go through the get-up again instead of staying stuck.
			if pelvis_height() < _pelvis_rest_height * 0.85 or lean_degrees() > 35.0:
				_stuck_time += delta
				if _stuck_time > 2.0:
					_set_state(State.GETTING_UP)
			else:
				_stuck_time = 0.0
		State.KNOCKED_DOWN:
			balance = 0.0
			muscle = 0.15
			if _state_time >= _knockdown_time():
				_set_state(State.GETTING_UP)
		State.GETTING_UP:
			var t := clampf(_state_time / _getup_time(), 0.0, 1.0)
			balance = smoothstep(0.0, 1.0, t)
			muscle = lerpf(0.3, 1.0, t)
			if t >= 1.0:
				_set_state(State.STANDING)


# Overridable recovery parameters (TrainingDummy reads them from its profile).
func _balance_regen() -> float: return 0.7
func _muscle_regen() -> float: return 0.9
func _knockdown_time() -> float: return 1.6
func _getup_time() -> float: return 1.8


func _turn_facing(delta: float) -> void:
	var step := deg_to_rad(turn_speed_deg) * delta
	_facing_yaw = rotate_toward(_facing_yaw, _target_yaw, step)


func _drive_joints(delta: float) -> void:
	if muscle <= 0.0:
		return
	var pose: Dictionary = _poses.get(current_pose, {})
	for part_name in _order:
		var def: Dictionary = _defs[part_name]
		if def.get("parent", "") == "":
			continue
		var child: RagdollPart = parts[part_name]
		var parent: RagdollPart = parts[def.parent]
		var q_rel: Quaternion = pose.get(part_name, Quaternion.IDENTITY)
		var q_target := parent.global_basis.get_rotation_quaternion() * q_rel
		var omega_des := _rotation_error(q_target, child.global_basis.get_rotation_quaternion()) * joint_stiffness
		var omega_rel := child.angular_velocity - parent.angular_velocity
		var dw := (omega_des - omega_rel) * (joint_gain * muscle)
		var pivot := _joint_world(part_name)
		var max_l: float = def.get("max_torque", 300.0) * delta
		var reaction := _rotate_subtree(_subtree[part_name], pivot, dw, max_l)
		# Equal and opposite on the parent: momentum at the joint, angular momentum about it.
		if muscle_reaction > 0.0:
			parent.apply_impulse(-reaction[0] * muscle_reaction, pivot - parent.global_position)
			parent.apply_torque_impulse(-reaction[1] * muscle_reaction)


## World position of the joint above [param part_name] (moves with the parent).
func _joint_world(part_name: String) -> Vector3:
	var def: Dictionary = _defs[part_name]
	var parent: RagdollPart = parts[def.parent]
	return parent.global_transform * (_rest[def.parent].affine_inverse() * def.joint)


## Give [param bodies] the velocity change of a rigid rotation [param dw] about
## [param pivot]. Scales dw down so the angular impulse about the pivot stays
## under [param max_l]. Returns [linear impulse, angular impulse about pivot].
func _rotate_subtree(bodies: Array, pivot: Vector3, dw: Vector3, max_l: float) -> Array:
	if dw.length_squared() < 1e-10:
		return [Vector3.ZERO, Vector3.ZERO]
	var lin := []
	var ang := []
	var total_p := Vector3.ZERO
	var total_l := Vector3.ZERO
	for body: RigidBody3D in bodies:
		var st := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var r := body.global_position + st.center_of_mass - pivot
		var p := body.mass * dw.cross(r)
		var l_own: Vector3 = st.inverse_inertia_tensor.inverse() * dw
		lin.append(p)
		ang.append(l_own)
		total_p += p
		total_l += l_own + r.cross(p)
	var scale := 1.0
	if total_l.length() > max_l:
		scale = max_l / total_l.length()
	for i in bodies.size():
		var body: RigidBody3D = bodies[i]
		body.apply_central_impulse(lin[i] * scale)
		body.apply_torque_impulse(ang[i] * scale)
	return [total_p * scale, total_l * scale]


func _drive_balance(delta: float) -> void:
	if balance <= 0.0:
		return
	var pelvis := root_part()
	var q_facing := Quaternion(Vector3.UP, _facing_yaw)

	# Upright + facing: rotate the whole body about the pelvis, then the upper
	# body about the waist. External help (no reaction): the "puppet strings".
	var dw := (_rotation_error(q_facing, pelvis.global_basis.get_rotation_quaternion()) * upright_stiffness - pelvis.angular_velocity) * (upright_gain * balance)
	_rotate_subtree(_all_bodies, pelvis.global_position, dw, 2000.0 * delta)
	var upper := _upright_part()
	if upper != "":
		var pose: Dictionary = _poses.get(current_pose, {})
		var chest: RagdollPart = parts[upper]
		var q_upper: Quaternion = q_facing * pose.get(upper, Quaternion.IDENTITY)
		var dw_upper := (_rotation_error(q_upper, chest.global_basis.get_rotation_quaternion()) * upright_stiffness - chest.angular_velocity) * (upright_gain * balance)
		_rotate_subtree(_subtree[upper], _joint_world(upper), dw_upper, 800.0 * delta)

	# Height: velocity-level spring on the pelvis plus partial gravity
	# compensation; applied to every body so the whole body is lifted evenly.
	var target_h := global_position.y + _pelvis_rest_height
	var max_rise := 1.2 if state == State.GETTING_UP else 3.0
	var vy_des := clampf((target_h - pelvis.global_position.y) * height_stiffness, -3.0, max_rise)
	var dvy := (vy_des - pelvis.linear_velocity.y) * height_gain
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var lift := maxf(dvy + g * delta * gravity_compensation, 0.0) * balance

	# Anchor: gently pull back toward the spot we stand on.
	var offset := anchor_position - pelvis.global_position
	offset.y = 0.0
	var v_des := (offset * anchor_stiffness).limit_length(2.0)
	var v_xz := Vector3(pelvis.linear_velocity.x, 0, pelvis.linear_velocity.z)
	var push := (v_des - v_xz) * (anchor_gain * balance)

	for body in _all_bodies:
		body.apply_central_impulse(body.mass * Vector3(push.x, lift, push.z))


## Name of the upper-body part kept upright besides the pelvis ("" = none).
func _upright_part() -> String:
	return "chest" if parts.has("chest") else ""


## Axis * angle (radians) rotating [param from] to [param to], shortest way.
static func _rotation_error(to: Quaternion, from: Quaternion) -> Vector3:
	var q := to * from.inverse()
	if q.w < 0.0:
		q = -q
	var angle := q.get_angle()
	if angle < 0.0001:
		return Vector3.ZERO
	return q.get_axis().normalized() * angle


## Height of the pelvis above this node's origin (debug / tests).
func pelvis_height() -> float:
	return root_part().global_position.y - global_position.y


## How far the pelvis leans from vertical, in degrees (debug / tests).
func lean_degrees() -> float:
	var up := root_part().global_basis.y
	return rad_to_deg(up.angle_to(Vector3.UP))

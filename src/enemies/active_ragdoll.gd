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
## Anchor gain multiplier during a burst (a strike's step in, an evade): the
## body really goes where the feet push it instead of drifting after them.
@export var burst_gain_multiplier := 4.0
## Max turning speed toward the facing target (deg/s), how fast the turn
## speed itself may change (deg/s²), and how quickly it closes the gap (1/s).
@export var turn_speed_deg := 90.0
@export var turn_accel_deg := 360.0
@export var turn_response := 5.0
## Seconds joint targets take to blend into a pose without its own "_blend",
## and into or out of a leg overlay (walking steps).
@export var default_pose_blend := 0.3
@export var overlay_blend := 0.28
## Each time a pose starts, its joint targets get a random offset of up to this
## many degrees, so a repeated move never looks exactly the same.
@export var pose_variation_deg := 0.0
## Slow, breathing-like drift of the joint targets (deg) in the poses listed in
## [member sway_poses]: a living guard instead of a frozen one.
@export var idle_sway_deg := 0.0
@export var sway_poses: PackedStringArray = ["guard", "idle"]
## Directional hit reaction (see [method apply_hit_reaction]): peak torso tilt
## (radians) per N·s of blow impulse, up to the clamp. Fully proportional, so a
## wrist flick barely moves the body while a committed swing visibly throws it.
@export var react_angle_per_impulse := 0.022
@export var react_angle_max := 0.55
## Seconds to fade procedural (IK) joint targets in or out.
@export var ik_fade_time := 0.22

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
## Optional (x, z) -> ground y. Without it the body stands at this node's
## height (flat dojo); in the run forest it follows the hills.
var ground_probe: Callable
## > 0: the anchor may lead the pelvis by at most this far (swarm walkers).
## 0 keeps the dojo dummy's spring back to the spot it was knocked from.
var max_anchor_lead := 0.0
## Walking: the anchor glides at this world velocity (XZ) while standing, and
## the balance help carries the body along with it.
var move_velocity := Vector3.ZERO
## True while the body bursts (see [member burst_gain_multiplier]).
var burst := false
## Optional pose whose parts override [member current_pose] (e.g. legs taking
## a step while the arms hold a guard or a wind-up). "" = none.
var overlay_pose := ""

var _defs := {}  # name -> part definition Dictionary
var _poses := {}  # pose name -> {part name -> Quaternion}
var _pose_stiffness := {}  # pose name -> muscle stiffness multiplier ("_stiffness" key in the pose)
var _pose_max_speed := {}  # pose name -> max joint speed in rad/s ("_max_speed" key)
var _pose_blend := {}  # pose name -> Vector2(blend seconds, index in _EASES)
var _joint_blends := {}  # part name -> JointBlend toward its current target
var _stiffness_now := 1.0  # pose stiffness, blended like the joint targets
var _yaw_rate := 0.0
## Directional hit reaction state (see apply_hit_reaction): world tilt axis and
## peak angle the torso leans with the blow, which part was hit (flung extra),
## and the remaining / total decay time.
var _react_axis := Vector3.RIGHT
var _react_angle := 0.0
var _react_part := ""
var _react_strength := 0.0
var _react_time := 0.0
var _react_dur := 0.3
var _variation := {}  # part name -> Quaternion offset for the current pose entry
var _sway_time := 0.0
var _sway_weight := 0.0  # 0..1, eases in and out with the sway poses
var _sway_phase := {}  # part name -> Vector3 random phases
var _pose_rng := RandomNumberGenerator.new()
## Procedural joint targets (part -> Quaternion relative to the parent, e.g.
## from [SwordArmIK]) that override the pose by [member ik_weight].
var ik_targets := {}
var ik_weight := 0.0
var _ik_weight_target := 0.0
var _final := {}  # part -> final local target this tick (pose, sway, IK)
var _final_prev := {}

const _EASES := ["inout", "in", "out"]


## One joint's target moving from where it was to the new pose's angle.
class JointBlend:
	var from := Quaternion.IDENTITY
	var to := Quaternion.IDENTITY
	var now := Quaternion.IDENTITY
	var prev := Quaternion.IDENTITY
	var t := 1.0
	var duration := 0.0
	var ease := 0
	var by_overlay := false

	func advance(delta: float) -> void:
		prev = now
		t = 1.0 if duration <= 0.0 else minf(t + delta / duration, 1.0)
		now = from.slerp(to, ActiveRagdoll.ease_curve(t, ease))
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
	_pose_rng.randomize()
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
## ([{shape, size, offset}]), max_torque (N·m), friction (default 0.9).
## The first part without a parent is the root (pelvis).
func _define_parts() -> Dictionary:
	return {}


## Return {pose_name: {part_name: Vector3 euler_deg relative to the parent}}.
## Optional "_stiffness": float key makes muscles faster/stronger in that pose
## (e.g. a strike); "_max_speed": float caps how fast joints move (rad/s);
## "_blend": seconds the joint targets take to move into the pose and "_ease":
## the curve they follow ("inout", "in" = accelerate into it, "out" = settle).
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
		_pose_stiffness[pose_name] = float(src.get("_stiffness", 1.0))
		_pose_max_speed[pose_name] = float(src.get("_max_speed", INF))
		_pose_blend[pose_name] = Vector2(float(src.get("_blend", default_pose_blend)), _EASES.find(String(src.get("_ease", "inout"))))
		for part_name in src:
			if part_name.begins_with("_"):
				continue
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
	# Limbs can be flung fast (hits, knockdowns); without CCD a shin can tunnel
	# into the floor and get stuck there.
	body.continuous_cd = true
	body.set_meta("hit_receiver", self)
	body.set_meta("body_part", part_name)
	body.set_meta("zone", def.get("zone", "torso"))
	var mat := PhysicsMaterial.new()
	mat.friction = def.get("friction", 0.9)
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
	if not _poses.has(pose_name) or pose_name == current_pose:
		return
	current_pose = pose_name
	_seed_pose_variation(pose_name)


## Apply a pose immediately (spawn / pool reuse) so limbs are not stuck in rest T-pose.
func snap_pose(pose_name: String) -> void:
	if not _poses.has(pose_name):
		return
	current_pose = pose_name
	_seed_pose_variation(pose_name)
	var pose: Dictionary = _poses[pose_name]
	for part_name in _order:
		if _defs[part_name].get("parent", "") == "":
			continue
		var to: Quaternion = pose.get(part_name, Quaternion.IDENTITY)
		if _variation.has(part_name):
			to = to * (_variation[part_name] as Quaternion)
		var b: JointBlend = _joint_blends.get(part_name)
		if b == null:
			b = JointBlend.new()
			_joint_blends[part_name] = b
		b.from = to
		b.to = to
		b.now = to
		b.t = 1.0
		b.duration = 0.001
	_update_final_targets()


func _seed_pose_variation(pose_name: String) -> void:
	_variation.clear()
	if pose_variation_deg <= 0.0:
		return
	for part_name in _poses[pose_name]:
		# Mostly in the swing plane (x), less twist (y) and side tilt (z).
		var e := Vector3(_pose_rng.randf_range(-1.0, 1.0), _pose_rng.randf_range(-0.5, 0.5), _pose_rng.randf_range(-0.5, 0.5)) * deg_to_rad(pose_variation_deg)
		_variation[part_name] = Basis.from_euler(e).get_rotation_quaternion()


## Drive [param targets] (part -> local Quaternion) instead of the pose for
## those parts, fading to [param weight] over [member ik_fade_time].
func set_ik(targets: Dictionary, weight: float) -> void:
	ik_targets = targets
	_ik_weight_target = clampf(weight, 0.0, 1.0)


## Seed the random pose variation and sway (tests, replays).
func set_motion_seed(value: int) -> void:
	_pose_rng.seed = value
	_sway_phase.clear()


## Reduce muscle/balance, e.g. from a hit. Values are 0..1 amounts.
func weaken(muscle_loss: float, balance_loss: float) -> void:
	muscle = clampf(muscle - muscle_loss, 0.0, 1.0)
	balance = clampf(balance - balance_loss, 0.0, 1.0)
	if balance <= 0.0 and state == State.STANDING:
		_set_state(State.KNOCKED_DOWN)


## Directional hit reaction: the blow's momentum spreads through the body and
## the torso (plus the hit limb extra) leans WITH the cut while it decays, so
## the body visibly folds toward where the blade travelled: a hit in the left
## arm throws that arm and the torso to the blade's side, an overhead cut folds
## the torso forward, a rising cut arches it back.
## [param part] is the hit body, [param point] the world contact point,
## [param direction] the world direction the blade travelled in, [param impulse]
## the blow's impulse in N·s (see [method HeldWeapon.strike_momentum]).
func apply_hit_reaction(part: RagdollPart, point: Vector3, direction: Vector3, impulse: float) -> void:
	if part == null or impulse <= 0.0 or direction.length_squared() < 1e-6:
		return
	var dir := direction.normalized()
	# Most of the blow lands where the blade met the body, with a spin about
	# the contact (a cut to the arm rotates that arm); the rest pushes the
	# whole body along, weighted by mass, so the torso drifts with the cut.
	var direct := dir * impulse * 0.6
	part.apply_impulse(direct.limit_length(30.0), point - part.global_position)
	part.apply_torque_impulse((point - part.global_position).cross(direct) * 0.35)
	if _total_mass > 0.0:
		var spread := dir * (impulse * 0.4 / _total_mass)
		for body in _all_bodies:
			if body != part:
				body.apply_central_impulse(spread * body.mass)
	# Pose-level flinch with the blow, decaying over a fraction of a second.
	_react_dur = clampf(0.22 + impulse * 0.008, 0.22, 0.45)
	_react_time = _react_dur
	_react_strength = clampf(impulse / 16.0, 0.0, 1.0)
	var peak := clampf(impulse * react_angle_per_impulse, 0.0, react_angle_max)
	var flat := dir - Vector3.UP * dir.dot(Vector3.UP)
	if flat.length() < 0.25:
		# Near-vertical blow: fold about the facing-right axis. A downward cut
		# bows the torso forward, a rising cut arches it back.
		var up_sign := -signf(dir.dot(Vector3.UP))
		if up_sign == 0.0:
			up_sign = 1.0
		_react_axis = (Basis(Vector3.UP, _facing_yaw) * Vector3.RIGHT).normalized()
		_react_angle = peak * up_sign
	else:
		# Horizontal component: tilt about (up x blow) moves the head toward
		# the blade's travel by construction (d/dθ R(θ)·up = blow at θ = 0).
		_react_axis = Vector3.UP.cross(flat.normalized()).normalized()
		_react_angle = peak
	_react_part = part.name


## Teleport back to the rest pose at the anchor, at full strength.
func reset_body() -> void:
	_facing_yaw = global_rotation.y
	_target_yaw = _facing_yaw
	_yaw_rate = 0.0
	_joint_blends.clear()
	_final.clear()
	_final_prev.clear()
	ik_weight = 0.0
	var root_xf := Transform3D(Basis(Vector3.UP, _facing_yaw), global_position)
	for part_name in _order:
		var p: RagdollPart = parts[part_name]
		p.global_transform = root_xf * _rest[part_name]
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
	muscle = 1.0
	balance = 1.0
	anchor_position = global_position
	move_velocity = Vector3.ZERO
	overlay_pose = ""
	_react_time = 0.0
	_react_strength = 0.0
	_react_part = ""
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
	_react_time = maxf(_react_time - delta, 0.0)
	if state == State.STANDING:
		anchor_position += Vector3(move_velocity.x, 0.0, move_velocity.z) * delta
		if max_anchor_lead > 0.0:
			_leash_anchor()
	_update_state(delta)
	_turn_facing(delta)
	_drive_joints(delta)
	_drive_balance(delta)


## Keeps the walking anchor within [member max_anchor_lead] of the pelvis.
## The anchor integrates the commanded velocity on its own, so whenever the
## body lags (first steps, a slope, a shove) it runs ahead and the body then
## chases it at several m/s, overshoots and circles back.
func _leash_anchor() -> void:
	var p := root_part().global_position
	var lead := Vector3(anchor_position.x - p.x, 0.0, anchor_position.z - p.z)
	if lead.length() > max_anchor_lead:
		lead = lead.normalized() * max_anchor_lead
		anchor_position = Vector3(p.x + lead.x, anchor_position.y, p.z + lead.z)


func _update_state(delta: float) -> void:
	_state_time += delta
	match state:
		State.STANDING:
			balance = minf(balance + _balance_regen() * delta, 1.0)
			muscle = minf(muscle + _muscle_regen() * delta, 1.0)
			# Failsafe: if we ended up tangled (too low or leaning a lot) for a
			# while, go through the get-up again instead of staying stuck.
			# Height is above the ground under the pelvis, not above this node:
			# a swarm yōkai walks away from the node it spawned on, and a hill
			# under that node made every walker look like it had fallen.
			var pelvis_pos := root_part().global_position
			var ground_y := global_position.y
			if ground_probe.is_valid():
				ground_y = float(ground_probe.call(pelvis_pos.x, pelvis_pos.z))
			if pelvis_pos.y - ground_y < _pelvis_rest_height * 0.85 or lean_degrees() > 35.0:
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
	var max_rate := deg_to_rad(turn_speed_deg)
	var wanted := clampf(wrapf(_target_yaw - _facing_yaw, -PI, PI) * turn_response, -max_rate, max_rate)
	_yaw_rate = move_toward(_yaw_rate, wanted, deg_to_rad(turn_accel_deg) * delta)
	_facing_yaw = wrapf(_facing_yaw + _yaw_rate * delta, -PI, PI)


func _drive_joints(delta: float) -> void:
	if muscle <= 0.0:
		return
	_update_joint_blends(delta)
	_stiffness_now = lerpf(_stiffness_now, _pose_stiffness.get(current_pose, 1.0), 1.0 - exp(-8.0 * delta))
	var k := _stiffness_now
	var max_speed: float = _pose_max_speed.get(current_pose, INF)
	_sway_time += delta
	var sway_on := idle_sway_deg > 0.0 and state == State.STANDING and sway_poses.has(current_pose)
	_sway_weight = move_toward(_sway_weight, 1.0 if sway_on else 0.0, delta * 1.5)
	var ik_on := _ik_weight_target if state == State.STANDING else 0.0
	ik_weight = move_toward(ik_weight, ik_on, delta / maxf(ik_fade_time, 0.01))
	_update_final_targets()
	for part_name in _order:
		var def: Dictionary = _defs[part_name]
		if def.get("parent", "") == "":
			continue
		var child: RagdollPart = parts[part_name]
		var parent: RagdollPart = parts[def.parent]
		var blend: JointBlend = _joint_blends[part_name]
		var q_parent := parent.global_basis.get_rotation_quaternion()
		var q_local: Quaternion = _final[part_name]
		var q_target := q_parent * q_local
		# Feed-forward: follow the moving target instead of only chasing its error.
		var omega_ff := q_parent * (_rotation_error(q_local, _final_prev.get(part_name, q_local)) / delta)
		var omega_des := (omega_ff + _rotation_error(q_target, child.global_basis.get_rotation_quaternion()) * (joint_stiffness * k)).limit_length(max_speed)
		var omega_rel := child.angular_velocity - parent.angular_velocity
		var dw := (omega_des - omega_rel) * (joint_gain * muscle)
		var pivot := _joint_world(part_name)
		var max_l: float = def.get("max_torque", 300.0) * k * delta
		var reaction := _rotate_subtree(_subtree[part_name], pivot, dw, max_l)
		# Equal and opposite on the parent: momentum at the joint, angular momentum about it.
		if muscle_reaction > 0.0:
			parent.apply_impulse(-reaction[0] * muscle_reaction, pivot - parent.global_position)
			parent.apply_torque_impulse(-reaction[1] * muscle_reaction)


## Final local target of every joint this tick: the blended pose (with its
## random variation), the guard's sway, then the procedural targets on top.
func _update_final_targets() -> void:
	_final_prev = _final.duplicate()
	for part_name in _order:
		var blend: JointBlend = _joint_blends.get(part_name)
		if blend == null:
			continue
		var q: Quaternion = blend.now
		if _sway_weight > 0.0:
			q = q * _sway(part_name)
		if ik_weight > 0.0 and ik_targets.has(part_name):
			q = q.slerp(ik_targets[part_name], ik_weight)
		_final[part_name] = q
	_apply_hit_reaction_pose()
	if _final_prev.is_empty():
		_final_prev = _final.duplicate()


## Lean the torso (and fling the hit limb extra) with the blow while the hit
## reaction decays. The tilt is premultiplied in the facing frame, where the
## parents' world orientation roughly is, so the body folds toward the blade's
## travel in world space whatever pose or overlay is playing underneath.
func _apply_hit_reaction_pose() -> void:
	if _react_time <= 0.0 or _react_strength <= 0.0:
		return
	var w := clampf(_react_time / maxf(_react_dur, 0.01), 0.0, 1.0)
	var e := w * w * _react_strength
	if e < 0.002:
		return
	var axis_l: Vector3 = Basis(Vector3.UP, _facing_yaw).inverse() * _react_axis
	if axis_l.length_squared() < 1e-6:
		return
	axis_l = axis_l.normalized()
	var torso := Quaternion(axis_l, _react_angle * e)
	if _final.has("chest"):
		_final["chest"] = torso * (_final["chest"] as Quaternion)
	if _final.has("head"):
		_final["head"] = Quaternion(axis_l, _react_angle * 0.7 * e) * (_final["head"] as Quaternion)
	if _react_part != "" and _react_part != "chest" and _final.has(_react_part):
		_final[_react_part] = Quaternion(axis_l, _react_angle * 1.7 * e) * (_final[_react_part] as Quaternion)


## Smooth drift of one joint for the living guard: two slow sines per axis
## (breathing ~0.25 Hz plus a slower weight shift), different phase per joint.
## Legs stay put so the feet do not shuffle; the chest is held by the
## balance drive (it would only fight it).
func _sway(part_name: String) -> Quaternion:
	if part_name.contains("leg") or part_name == _upright_part():
		return Quaternion.IDENTITY
	if not _sway_phase.has(part_name):
		_sway_phase[part_name] = Vector3(_pose_rng.randf() * TAU, _pose_rng.randf() * TAU, _pose_rng.randf() * TAU)
	var ph: Vector3 = _sway_phase[part_name]
	var t := _sway_time
	var amp := deg_to_rad(idle_sway_deg) * _sway_weight
	var e := Vector3(
		sin(t * 1.6 + ph.x) * 0.7 + sin(t * 0.55 + ph.y) * 0.3,
		sin(t * 0.7 + ph.y) * 0.5,
		sin(t * 0.9 + ph.z) * 0.4) * amp
	return Basis.from_euler(e).get_rotation_quaternion()


## Retarget each joint whose pose (or leg overlay) angle changed: it blends
## from where its target is now, over the pose's "_blend" time and "_ease" curve.
func _update_joint_blends(delta: float) -> void:
	var pose: Dictionary = _poses.get(current_pose, {})
	var overlay: Dictionary = _poses.get(overlay_pose, {}) if overlay_pose != "" else {}
	var timing: Vector2 = _pose_blend.get(current_pose, Vector2(default_pose_blend, 0))
	for part_name in _order:
		if _defs[part_name].get("parent", "") == "":
			continue
		var in_overlay := overlay.has(part_name)
		var to: Quaternion = overlay.get(part_name, pose.get(part_name, Quaternion.IDENTITY))
		if not in_overlay and _variation.has(part_name):
			to = to * (_variation[part_name] as Quaternion)
		var b: JointBlend = _joint_blends.get(part_name)
		if b == null:
			b = JointBlend.new()
			b.from = to
			b.to = to
			b.now = to
			_joint_blends[part_name] = b
		elif not b.to.is_equal_approx(to):
			var overlay_change := in_overlay or b.by_overlay
			b.from = b.now
			b.to = to
			b.t = 0.0
			b.duration = overlay_blend if overlay_change else timing.x
			b.ease = 0 if overlay_change else int(timing.y)
		b.by_overlay = in_overlay
		b.advance(delta)


## Easing curves for pose blends (see _EASES): smootherstep, cubic in, cubic out.
static func ease_curve(t: float, kind: int) -> float:
	match kind:
		1: return t * t * t
		2: return 1.0 - pow(1.0 - t, 3.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


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
		var chest: RagdollPart = parts[upper]
		var q_upper: Quaternion = q_facing * (_final.get(upper, Quaternion.IDENTITY) as Quaternion)
		var dw_upper := (_rotation_error(q_upper, chest.global_basis.get_rotation_quaternion()) * upright_stiffness - chest.angular_velocity) * (upright_gain * balance)
		_rotate_subtree(_subtree[upper], _joint_world(upper), dw_upper, 800.0 * delta)

	# Height: velocity-level spring on the pelvis plus partial gravity
	# compensation; applied to every body so the whole body is lifted evenly.
	var ground_y := global_position.y
	if ground_probe.is_valid():
		ground_y = float(ground_probe.call(pelvis.global_position.x, pelvis.global_position.z))
	var target_h := ground_y + _pelvis_rest_height
	var max_rise := 1.2 if state == State.GETTING_UP else 3.0
	var vy_des := clampf((target_h - pelvis.global_position.y) * height_stiffness, -3.0, max_rise)
	var dvy := (vy_des - pelvis.linear_velocity.y) * height_gain
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var lift := maxf(dvy + g * delta * gravity_compensation, 0.0) * balance

	# Anchor: gently pull back toward the spot we stand on.
	var offset := anchor_position - pelvis.global_position
	offset.y = 0.0
	var v_des := (offset * anchor_stiffness + move_velocity).limit_length(2.5)
	var v_xz := Vector3(pelvis.linear_velocity.x, 0, pelvis.linear_velocity.z)
	var push := (v_des - v_xz) * (anchor_gain * (burst_gain_multiplier if burst else 1.0) * balance)

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


## Degrees between each joint's current and target rotation (debug / tests).
func pose_errors() -> Dictionary:
	var out := {}
	var pose: Dictionary = _poses.get(current_pose, {})
	for part_name in _order:
		var def: Dictionary = _defs[part_name]
		if def.get("parent", "") == "":
			continue
		var parent: RagdollPart = parts[def.parent]
		var rel := parent.global_basis.get_rotation_quaternion().inverse() * (parts[part_name] as RagdollPart).global_basis.get_rotation_quaternion()
		out[part_name] = snappedf(rad_to_deg(rel.angle_to(pose.get(part_name, Quaternion.IDENTITY))), 1.0)
	return out


## Height of the pelvis above this node's origin (debug / tests).
func pelvis_height() -> float:
	return root_part().global_position.y - global_position.y


## How far the pelvis leans from vertical, in degrees (debug / tests).
func lean_degrees() -> float:
	var up := root_part().global_basis.y
	return rad_to_deg(up.angle_to(Vector3.UP))

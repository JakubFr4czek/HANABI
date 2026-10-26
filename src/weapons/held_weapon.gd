class_name HeldWeapon
extends BladeBody
## A weapon the player can hold, driven toward the hand by a PD controller
## (force on the center of mass + torque), never parented to the hand.
##
## - Weight: the controller's limits are the player's arm strength
##   ([member max_force], [member max_torque]), the same for every weapon, so a
##   heavier weapon (more mass / inertia) accelerates less and lags behind the hand.
## - No clipping: the blade is a dynamic body with CCD; walls and bodies stop it
##   while the hand keeps moving.
## - No bulldozing: when the blade is held back by something (grip far from the
##   hand) the arm "gives": force and torque drop to [member blocked_strength].
## - Stable PD (Tan et al.): position error is predicted one step ahead and the
##   damping term is implicit, so the discrete controller stays critically damped
##   (no tick-to-tick ringing) at any tick rate from 72 to 120 Hz.
## - Never flies away: speed and spin are capped relative to the hand, the
##   velocity kick of a new impact against a moving body is limited, and if the
##   grip gets farther than [member break_distance] from the hand the weapon is
##   put back in the hand (unless something solid is in the way).
## - Slow motion: in a compensated slow-mo (parry) gains are scaled by
##   [method TimeController.compensation] so the blade keeps real-time speed.
## - Free & two-handed grip: each hand grabs at a local grip transform clamped to
##   the handle (tsuka), guard (tsuba), or blunt spine of the blade (mune, never
##   the cutting edge ha). A second hand can grab the weapon simultaneously,
##   steering the blade axis between the two hands and adding second-arm strength.

const ZONE_HANDLE := "handle"
const ZONE_TSUBA := "tsuba"
const ZONE_MUNE := "mune"
## Physics layer of the player's own bodies (layer 20, "player_body").
const PLAYER_BODY_LAYER := 1 << 19

## Spring frequency (Hz) and damping ratio of the linear / angular controller.
@export var follow_frequency := 9.0
@export var follow_damping := 1.0
@export var angular_frequency := 9.0
@export var angular_damping := 1.0
## Player arm strength: max force on the weapon's center of mass (N) and max torque (N·m).
@export var max_force := 260.0
@export var max_torque := 40.0
## Strength multiplier while the blade is held back by an obstacle.
@export var blocked_strength := 0.3
## Grip-to-hand distance (m) above which the blade counts as held back.
@export var blocked_distance := 0.1
## Max speed (real m/s) of the center of mass above the hand's own speed, and
## max spin (real rad/s) above the hand's own spin.
@export var max_extra_speed := 4.0
@export var max_extra_spin := 18.0
## Max velocity change (real m/s, rad/s) a new impact with a moving body may
## give the weapon in one tick, on top of what the arm itself does.
@export var max_impact_speed_change := 2.0
@export var max_impact_spin_change := 12.0
## Grip-to-hand distance (m) above which a weapon that is still moving away from
## the hand faster than [member break_flee_speed] (real m/s) is put back in the
## hand. A blade merely lagging behind a fast hand is moving toward it, so it is left alone.
@export var break_distance := 0.4
@export var break_flee_speed := 0.5

@export_group("Grip")
## Pommel end of the handle (tsuka) along local +Z (m).
@export var handle_back_z := 0.21
## Local Z of the guard (tsuba), its half-length along Z, and its outer radius (m).
@export var guard_z := -0.085
@export var guard_half_length := 0.02
@export var guard_radius := 0.04
## Distance from [member blade_tip] (m) where the blunt spine stops being grabbable.
@export var blade_grip_margin := 0.06
## Local direction from the blade centerline toward the blunt spine (mune).
## On the katana mesh, -Y is the sharp cutting edge (ha) and +Y is the blunt spine (mune).
@export var spine_direction := Vector3(0, 1, 0)
## Offset from the blade centerline onto the blunt spine surface (m).
@export var spine_offset := 0.018
## Arm strength multipliers when held with two hands.
@export var two_hand_force_multiplier := 1.6
@export var two_hand_torque_multiplier := 1.8
## How much the second hand contributes to blade twist/roll (0 = primary only, 0.5 = equal).
@export var two_hand_twist_blend := 0.4
## Longitudinal position blend between primary (0.0) and secondary (1.0) hand.
@export var two_hand_position_blend := 0.0

@export_group("Damage")
## Hits slower than this (relative m/s at the contact point) do nothing.
@export var min_hit_speed := 1.5
## Damage per m/s above [member min_hit_speed], before zone/resistance multipliers.
@export var damage_per_speed := 9.0
## Cap on base damage of a single hit.
@export var max_damage := 120.0
## Extra knock-back impulse per m/s of hit speed, on top of the physical contact.
@export var knockback_per_speed := 0.6
## Hits doing at least this much damage trigger hit-stop.
@export var hit_stop_damage := 40.0

@export_group("Parry")
## A clash with an attacking enemy blade is a parry above this relative speed (m/s)...
@export var parry_min_speed := 1.5
## ...and with the blades crossing at least this angle (degrees, 0 = parallel).
@export var parry_min_angle := 25.0
## Slow motion after a parry: time scale and real-time duration (s).
@export var parry_slowmo_scale := 0.3
@export var parry_slowmo_time := 0.6

@export_group("Misc")
## If the weapon ends up farther than this from the hand (stuck behind a wall
## after walking away), it is teleported back after [member stuck_time] s.
@export var stuck_distance := 1.2
@export var stuck_time := 0.5
## Tip speed (real m/s) that triggers a swing "whoosh".
@export var swing_sound_speed := 7.0

## Primary WeaponHolder currently holding us, or null.
var holder: Node3D = null
## All active WeaponHolders (1 = one-handed, 2 = two-handed).
var holders: Array[Node3D] = []
## How fast the tip actually moved during the last physics step (real m/s).
## Unlike the body velocity, this stays honest when the blade is blocked.
var measured_tip_speed := 0.0
## Current strength factor (1 = free, [member blocked_strength] = held back).
var strength := 1.0
## Distance between where the grip is and where the hand wants it (m).
var grip_error := 0.0

var _local_grips := {}  # holder -> Transform3D in weapon local space
var _grip_zones := {}   # holder -> String (ZONE_HANDLE / ZONE_TSUBA / ZONE_MUNE)
var _prev_contacts := {}  # collider instance id -> true, contacts in previous tick
var _receiver_cooldown := {}  # receiver instance id -> time left
var _stuck_timer := 0.0
var _swing_cooldown := 0.0
var _last_tip := Vector3.ZERO
var _prev_target := Transform3D()
var _has_prev_target := false
var _blocked_buzz := 0.0
var _impact_this_tick := false
# Velocity change the arm and gravity were expected to cause in the last step.
var _expected_dv := Vector3.ZERO
var _expected_dw := Vector3.ZERO


func _ready() -> void:
	super._ready()
	# We detect hits ourselves and snapshot at the end of our own tick.
	process_physics_priority = 0
	add_to_group("player_weapons")
	collision_mask &= ~PLAYER_BODY_LAYER
	contact_monitor = true
	max_contacts_reported = 16
	_last_tip = get_tip_global()


func is_held() -> bool:
	return not holders.is_empty()


func is_two_handed() -> bool:
	return holders.size() >= 2


func is_held_by(by: Node3D) -> bool:
	return holders.has(by)


func get_local_grip(by: Node3D = null) -> Transform3D:
	var key: Node3D = by if by != null else holder
	return _local_grips.get(key, Transform3D.IDENTITY)


func get_grip_zone(by: Node3D = null) -> String:
	var key: Node3D = by if by != null else holder
	return _grip_zones.get(key, ZONE_HANDLE)


func get_grip_point_global(by: Node3D = null) -> Vector3:
	return global_transform * get_local_grip(by).origin


## Classify which grabbable region a local-space point falls into.
func classify_grip_zone(local_point: Vector3) -> String:
	if local_point.z > guard_z + guard_half_length:
		return ZONE_HANDLE
	if local_point.z >= guard_z - guard_half_length:
		return ZONE_TSUBA
	return ZONE_MUNE


## Clamp an arbitrary local-space point onto the nearest valid grip surface:
## the handle (tsuka), the guard (tsuba), or the blunt spine of the blade (mune).
## Points along the blade are always placed on the blunt spine, never on the cutting edge.
func clamp_grip_point(local_point: Vector3) -> Vector3:
	var min_z := minf(blade_start.z, blade_tip.z) + blade_grip_margin
	var z := clampf(local_point.z, min_z, handle_back_z)
	var zone := classify_grip_zone(Vector3(local_point.x, local_point.y, z))
	match zone:
		ZONE_HANDLE:
			return Vector3(0.0, 0.0, clampf(z, guard_z + guard_half_length, handle_back_z))
		ZONE_TSUBA:
			var xy := Vector2(local_point.x, local_point.y)
			if xy.length() > guard_radius:
				xy = xy.normalized() * guard_radius
			return Vector3(xy.x, xy.y, clampf(z, guard_z - guard_half_length, guard_z + guard_half_length))
		_:
			var z_mune := clampf(z, min_z, guard_z - guard_half_length)
			var center := _blade_centerline_at_z(z_mune)
			return center + spine_direction.normalized() * spine_offset


func _blade_centerline_at_z(z: float) -> Vector3:
	var span := blade_tip.z - blade_start.z
	var t := clampf((z - blade_start.z) / span, 0.0, 1.0) if absf(span) > 1e-5 else 0.0
	return blade_start.lerp(blade_tip, t)


## True when [param local_point] along the blade is on the blunt spine (mune) side
## of the blade centerline rather than the sharp cutting edge (ha).
func is_on_blunt_side(local_point: Vector3) -> bool:
	var center := _blade_centerline_at_z(local_point.z)
	return (local_point - center).dot(spine_direction.normalized()) >= -0.002


## World-space distance from [param world_point] to the nearest grabbable point on this weapon.
func distance_to_grip(world_point: Vector3) -> float:
	var local_pt := global_transform.affine_inverse() * world_point
	var clamped := clamp_grip_point(local_pt)
	return world_point.distance_to(global_transform * clamped)


## Compute the local grip Transform3D for a hand grabbing at [param hand_global].
func compute_local_grip(hand_global: Transform3D) -> Transform3D:
	var raw_local := global_transform.affine_inverse() * hand_global
	if raw_local.origin.length() < 0.005 and raw_local.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) < 0.01:
		return Transform3D.IDENTITY
	var origin := clamp_grip_point(raw_local.origin)
	return Transform3D(raw_local.basis.orthonormalized(), origin)


func on_grabbed(by: Node3D, local_grip: Transform3D = Transform3D.IDENTITY) -> void:
	if by == null:
		return
	if not holders.has(by):
		if holders.size() >= 2:
			var prev_secondary: Node3D = holders[-1]
			prev_secondary.call("release")
		holders.append(by)
	var clamped_grip := Transform3D(local_grip.basis.orthonormalized(), clamp_grip_point(local_grip.origin))
	if local_grip.is_equal_approx(Transform3D.IDENTITY):
		clamped_grip = Transform3D.IDENTITY
	_local_grips[by] = clamped_grip
	_grip_zones[by] = classify_grip_zone(clamped_grip.origin)
	holder = holders[0]
	wielder = holder
	gravity_scale = 1.0
	_stuck_timer = 0.0
	_has_prev_target = false
	GameEvents.log_event("weapon_grabbed", {
		"weapon": weapon_name,
		"hand": str(by.get("side")),
		"zone": _grip_zones[by],
		"two_handed": holders.size() >= 2,
	})


func on_released(by: Node3D = null) -> void:
	if by == null:
		holders.clear()
		_local_grips.clear()
		_grip_zones.clear()
		holder = null
		wielder = null
		_has_prev_target = false
		GameEvents.log_event("weapon_released", {"weapon": weapon_name, "remaining_hands": 0})
		return
	if not holders.has(by):
		return
	holders.erase(by)
	_local_grips.erase(by)
	_grip_zones.erase(by)
	holder = holders[0] if not holders.is_empty() else null
	wielder = holder
	_has_prev_target = false
	GameEvents.log_event("weapon_released", {
		"weapon": weapon_name,
		"hand": str(by.get("side")),
		"remaining_hands": holders.size(),
	})


func release_all() -> void:
	for h in holders.duplicate():
		if h and h.has_method("release"):
			h.release()


## Never collide with the player's own rig (body, hands), whatever its layers are.
func register_player_collision_exceptions(player: Node) -> void:
	for body in player.find_children("*", "PhysicsBody3D", true, false):
		add_collision_exception_with(body)


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_impact_this_tick = false
	_process_contacts()
	if holder and delta > 0.0:
		if _impact_this_tick and _has_prev_target:
			_limit_impact_kick(delta)
		_drive_to(_compute_target_transform(), delta)
	_update_swing_audio(delta)
	_snapshot_velocity()


## Desired weapon-root transform in world space from the active holder(s).
func _compute_target_transform() -> Transform3D:
	var h0: Node3D = holders[0]
	var g0: Transform3D = _local_grips.get(h0, Transform3D.IDENTITY)
	var H0: Transform3D = h0.call("get_grip_transform")
	var T0: Transform3D = H0 * g0.affine_inverse()
	if holders.size() == 1:
		return T0

	var h1: Node3D = holders[1]
	var g1: Transform3D = _local_grips.get(h1, Transform3D.IDENTITY)
	var H1: Transform3D = h1.call("get_grip_transform")
	var T1: Transform3D = H1 * g1.affine_inverse()

	var q0 := T0.basis.get_rotation_quaternion()
	var q1 := T1.basis.get_rotation_quaternion()
	var q_base := q0.slerp(q1, two_hand_twist_blend).normalized()
	var v_local := g1.origin - g0.origin
	var v_world := H1.origin - H0.origin
	var basis: Basis
	if v_local.length() > 0.025 and v_world.length() > 0.025:
		var dir_base := (Basis(q_base) * v_local).normalized()
		var dir_world := v_world.normalized()
		var swing := _shortest_arc(dir_base, dir_world)
		basis = Basis((swing * q_base).normalized()).orthonormalized()
	else:
		basis = Basis(q_base).orthonormalized()
	var origin_0 := H0.origin - basis * g0.origin
	var origin_1 := H1.origin - basis * g1.origin
	return Transform3D(basis, origin_0.lerp(origin_1, two_hand_position_blend))


static func _shortest_arc(from_dir: Vector3, to_dir: Vector3) -> Quaternion:
	var d := from_dir.dot(to_dir)
	if d >= 0.99999:
		return Quaternion.IDENTITY
	if d <= -0.99999:
		var ortho := from_dir.cross(Vector3.UP)
		if ortho.length_squared() < 1e-4:
			ortho = from_dir.cross(Vector3.RIGHT)
		return Quaternion(ortho.normalized(), PI)
	return Quaternion(from_dir, to_dir)


func _primary_grip_error(target: Transform3D) -> float:
	var g0: Transform3D = _local_grips.get(holder, Transform3D.IDENTITY)
	return (global_transform * g0.origin).distance_to(target * g0.origin)


func _compute_grip_error(target: Transform3D) -> float:
	if holders.size() <= 1:
		return _primary_grip_error(target)
	var err := 0.0
	for h in holders:
		var g: Transform3D = _local_grips.get(h, Transform3D.IDENTITY)
		err = maxf(err, (global_transform * g.origin).distance_to(target * g.origin))
	return err


# --- PD controller -------------------------------------------------------------

func _drive_to(target: Transform3D, delta: float) -> void:
	grip_error = _compute_grip_error(target)
	var c := TimeController.compensation_for(delta)
	# Knocked out of the hand: put it back rather than letting it (and the hand
	# model pinned to it) fly off. Not when the hand is behind a wall or a body.
	if _is_flying_off(target, c) and _fits_at(target):
		_teleport_to(target)
		return
	if grip_error > stuck_distance:
		_stuck_timer += TimeController.real_tick()
		if _stuck_timer > stuck_time:
			_teleport_to(target)
			return
	else:
		_stuck_timer = 0.0

	# Hand velocity in simulation units, measured over real time: in a hit-stop
	# the hand keeps moving in real time but the blade must freeze with the world.
	var target_vel := Vector3.ZERO
	var target_omega := Vector3.ZERO
	if _has_prev_target:
		var to_sim := c / TimeController.real_tick()
		target_vel = (target * center_of_mass - _prev_target * center_of_mass) * to_sim
		target_omega = ActiveRagdoll._rotation_error(target.basis.get_rotation_quaternion(), _prev_target.basis.get_rotation_quaternion()) * to_sim
	_prev_target = target
	_has_prev_target = true

	# Never faster or spinning harder than the hand by more than a margin.
	linear_velocity = linear_velocity.limit_length(target_vel.length() + max_extra_speed * c)
	angular_velocity = angular_velocity.limit_length(target_omega.length() + max_extra_spin * c)

	# Held back by an obstacle -> the arm gives way (no infinite pushing).
	var want_strength := blocked_strength if grip_error > blocked_distance else 1.0
	strength = move_toward(strength, want_strength, delta * (6.0 if want_strength < strength else 3.0))
	_buzz_when_blocked(delta)

	var limit_scale := minf(c * c, 16.0) * strength
	var force_mult := two_hand_force_multiplier if holders.size() >= 2 else 1.0
	var torque_mult := two_hand_torque_multiplier if holders.size() >= 2 else 1.0

	# Linear: stable PD on the center of mass, plus holding the weapon's weight.
	# Dividing by (1 + kd·dt) makes the damping implicit, which keeps the
	# discrete loop from overshooting every tick at low tick rates.
	var w := TAU * follow_frequency * c
	var kd := 2.0 * follow_damping * w
	var com := get_com_global()
	var com_target := target * center_of_mass
	var accel := ((com_target - (com + linear_velocity * delta)) * (w * w) + (target_vel - linear_velocity) * kd) / (1.0 + kd * delta)
	var force := (mass * accel - mass * get_gravity()).limit_length(max_force * force_mult * limit_scale)
	apply_central_force(force)
	_expected_dv = (force / mass + get_gravity() * gravity_scale) * delta

	# Angular: stable PD on orientation (error to the orientation one step ahead).
	var wa := TAU * angular_frequency * c
	var kda := 2.0 * angular_damping * wa
	var q := global_basis.get_rotation_quaternion()
	var spin := angular_velocity * delta
	var q_pred := q
	if spin.length_squared() > 1e-12:
		q_pred = Quaternion(spin.normalized(), spin.length()) * q
	var err := ActiveRagdoll._rotation_error(target.basis.get_rotation_quaternion(), q_pred)
	var alpha := (err * (wa * wa) + (target_omega - angular_velocity) * kda) / (1.0 + kda * delta)
	var st := PhysicsServer3D.body_get_direct_state(get_rid())
	var torque: Vector3 = (st.inverse_inertia_tensor.inverse() * alpha).limit_length(max_torque * torque_mult * limit_scale)
	apply_torque(torque)
	_expected_dw = st.inverse_inertia_tensor * torque * delta


## A new impact with a moving body may only change our velocity by so much on
## top of what the arm did; the rest of the blow goes into the other body.
func _limit_impact_kick(delta: float) -> void:
	var c := TimeController.compensation_for(delta)
	var dv := linear_velocity - _snap_linear - _expected_dv
	var cap := max_impact_speed_change * c
	if dv.length() > cap:
		linear_velocity = _snap_linear + _expected_dv + dv.limit_length(cap)
	var dw := angular_velocity - _snap_angular - _expected_dw
	var spin_cap := max_impact_spin_change * c
	if dw.length() > spin_cap:
		angular_velocity = _snap_angular + _expected_dw + dw.limit_length(spin_cap)


func _is_flying_off(target: Transform3D, c: float) -> bool:
	var g0: Transform3D = _local_grips.get(holder, Transform3D.IDENTITY)
	var grip_point := global_transform * g0.origin
	var away := grip_point - target * g0.origin
	if away.length() <= break_distance:
		return false
	return get_point_velocity(grip_point).dot(away.normalized()) > break_flee_speed * c


## True when the weapon at [param pose] would not overlap anything it collides with.
func _fits_at(pose: Transform3D) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	for owner_id in get_shape_owners():
		var owner_xform := shape_owner_get_transform(owner_id)
		for i in shape_owner_get_shape_count(owner_id):
			query.shape = shape_owner_get_shape(owner_id, i)
			query.transform = pose * owner_xform
			if not space.intersect_shape(query, 1).is_empty():
				return false
	return true


## Put the weapon exactly in the hand (e.g. after the player teleported).
func snap_to_hand() -> void:
	if holder:
		_teleport_to(_compute_target_transform())


func _teleport_to(target: Transform3D) -> void:
	global_transform = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_stuck_timer = 0.0
	_has_prev_target = false
	if trail:
		trail.clear()


func _buzz_when_blocked(delta: float) -> void:
	_blocked_buzz -= delta
	if grip_error > blocked_distance * 1.5 and _blocked_buzz <= 0.0:
		_blocked_buzz = 0.08
		_pulse(clampf(grip_error * 0.6, 0.05, 0.25), 0.03)


# --- Contacts: hits, clashes, parries --------------------------------------------

func _tick_cooldowns(delta: float) -> void:
	for id in _receiver_cooldown.keys():
		_receiver_cooldown[id] -= delta
		if _receiver_cooldown[id] <= 0.0:
			_receiver_cooldown.erase(id)


## Read contacts from the last physics step and turn new ones into hits/clashes.
func _process_contacts() -> void:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	if state == null:
		return
	var now_contacts := {}
	# Best (fastest) new contact per receiver this tick.
	var best := {}
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i)
		if collider == null:
			continue
		var cid := collider.get_instance_id()
		now_contacts[cid] = true
		if _prev_contacts.has(cid):
			continue  # still touching from before, not a new impact
		if collider is RigidBody3D:
			_impact_this_tick = true
		var point := state.get_contact_local_position(i)
		var my_vel := get_pre_step_point_velocity(point)
		var other_vel := _pre_step_velocity_of(collider, point)
		var rel := my_vel - other_vel
		# Report real-world speeds even while the player is compensated in slow-mo.
		var speed := TimeController.to_real_speed(rel.length())
		var receiver_key: Object = collider
		if collider.has_meta("hit_receiver"):
			receiver_key = collider.get_meta("hit_receiver")
		var rid := receiver_key.get_instance_id()
		if _receiver_cooldown.has(rid):
			continue
		if not best.has(rid) or speed > best[rid].speed:
			best[rid] = {
				"collider": collider, "point": point, "speed": speed,
				"direction": rel.normalized() if rel.length() > 0.001 else Vector3.ZERO,
				"normal": state.get_contact_local_normal(i),
			}
	_prev_contacts = now_contacts

	for rid in best:
		var c: Dictionary = best[rid]
		if c.collider is BladeBody:
			_handle_clash(c)
		elif c.collider.has_meta("hit_receiver"):
			_handle_hit(c)
		else:
			continue
		_receiver_cooldown[rid] = 0.2


func _pre_step_velocity_of(body: Object, point: Vector3) -> Vector3:
	if body.has_method("get_pre_step_point_velocity"):
		return body.get_pre_step_point_velocity(point)
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		return rb.linear_velocity + rb.angular_velocity.cross(point - rb.global_transform * rb.center_of_mass)
	return Vector3.ZERO


func _handle_hit(c: Dictionary) -> void:
	if c.speed < min_hit_speed:
		return
	var part: Node = c.collider
	var receiver: Node = part.get_meta("hit_receiver")
	var base_damage := clampf((c.speed - min_hit_speed) * damage_per_speed, 0.0, max_damage)
	var hit := {
		"attacker": weapon_name,
		"element": element,
		"part": String(part.get_meta("body_part", part.name)),
		"zone": String(part.get_meta("zone", "body")),
		"speed": snappedf(c.speed, 0.01),
		"base_damage": base_damage,
		"point": c.point,
		"direction": c.direction,
		"knockback": c.direction * c.speed * knockback_per_speed,
	}
	if receiver.has_method("receive_hit"):
		hit = receiver.receive_hit(part, hit)
	var dmg: float = hit.get("damage", base_damage)
	_pulse(clampf(0.25 + dmg / 80.0, 0.25, 1.0), 0.04 + clampf(dmg / 1000.0, 0.0, 0.08))
	Sfx.play_at("impact_heavy" if dmg >= 30.0 else "impact_light", c.point, linear_to_db(clampf(0.4 + c.speed / 12.0, 0.4, 1.2)))
	if dmg >= hit_stop_damage:
		# 50 ms for a solid hit, up to 80 ms for the heaviest ones.
		TimeController.hit_stop(lerpf(0.05, 0.08, clampf((dmg - hit_stop_damage) / 60.0, 0.0, 1.0)))


func _handle_clash(c: Dictionary) -> void:
	var other: BladeBody = c.collider
	var cos_a := absf(get_blade_axis().dot(other.get_blade_axis()))
	var angle := rad_to_deg(acos(clampf(cos_a, 0.0, 1.0)))
	var clash := {
		"attacker": weapon_name,
		"defender": other.weapon_name,
		"speed": snappedf(c.speed, 0.01),
		"angle_deg": snappedf(angle, 0.1),
		"point": c.point,
		"direction": c.direction,
		"enemy_attacking": other.attacking,
	}
	var is_parry: bool = other.attacking and c.speed >= parry_min_speed and angle >= parry_min_angle
	clash["parry"] = is_parry
	GameEvents.report_clash(clash)
	SparkBurst.spawn(get_tree().current_scene, c.point, c.normal, Color(2.0, 1.4, 0.6), 40 if is_parry else 16, 4.0 if is_parry else 2.5)
	if is_parry:
		_parry(other, clash)
	else:
		_pulse(clampf(0.4 + c.speed / 10.0, 0.4, 1.0), 0.06)
		Sfx.play_at("clash", c.point, linear_to_db(clampf(0.3 + c.speed / 8.0, 0.3, 1.2)))


func _parry(other: BladeBody, clash: Dictionary) -> void:
	other.attacking = false
	if other.wielder and other.wielder.has_method("on_parried"):
		other.wielder.on_parried(clash)
	GameEvents.report_parry(clash)
	TimeController.slow_motion(parry_slowmo_scale, parry_slowmo_time, true)
	_pulse(1.0, 0.15)
	Sfx.play_at("clash", clash.point, linear_to_db(1.4))


func _pulse(amplitude: float, duration: float) -> void:
	for h in holders:
		if h and h.has_method("pulse"):
			h.pulse(amplitude, duration)


func _update_swing_audio(delta: float) -> void:
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)
	var tip := get_tip_global()
	if delta > 0.0:
		measured_tip_speed = TimeController.to_real_speed(tip.distance_to(_last_tip) / delta)
	_last_tip = tip
	if not holder:
		return
	if measured_tip_speed > swing_sound_speed and _swing_cooldown <= 0.0:
		_swing_cooldown = 0.35
		Sfx.play_at("swing", tip, linear_to_db(clampf(measured_tip_speed / 14.0, 0.3, 1.0)))

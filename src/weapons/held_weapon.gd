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
## - Free & two-handed grip: each hand grabs at a local grip transform clamped
##   to the handle (tsuka) only — never the guard or the blade. A second hand
##   can grab the other end of the handle simultaneously, steering the blade
##   axis between the two hands and adding second-arm strength.

const ZONE_HANDLE := "handle"
const ZONE_TSUBA := "tsuba"
const ZONE_MUNE := "mune"
## Physics layer of the player's own bodies (layer 20, "player_body").
const PLAYER_BODY_LAYER: int = XRPlayer.COLLISION_LAYER_BODY

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
@export var blocked_distance := 0.045
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

@export_group("Hand priority")
## The grip may trail the hand by at most this much (m) and the weapon may twist
## out of the hand's orientation by at most this much (degrees). Beyond that the
## weapon is put back within the limit, unless static geometry (walls, floor,
## props) is in the way: then the hand model stays on the hilt instead (ghost hand).
@export var max_grip_offset := 0.035
@export var max_grip_angle := 30.0
## Against an enemy body the blade collides normally and may rest on it this far
## (m) / this much (degrees) behind the hand (the arm gives way, no shoving). If
## the hand goes deeper, the blade follows the hand into that body part instead of
## wedging or being torn out of the hand, and ignores it until it is out again
## (at least [member wedge_release_min_time] s).
@export var max_contact_offset := 0.1
## Fastest hand movement (m/s) handed on to a weapon pulled back into the hand.
@export var hand_speed_limit := 8.0
@export var max_contact_angle := 50.0
@export var wedge_release_min_time := 0.1

@export_group("Grip")
## Pommel end of the handle (tsuka) along local +Z (m).
@export var handle_back_z := 0.21
## Local Z of the guard (tsuba), its half-length along Z, and its outer radius (m).
@export var guard_z := -0.085
@export var guard_half_length := 0.02
@export var guard_radius := 0.04
## Half the width of a fist along the handle (m). The grip point is the
## middle of the fist, so it stays this far inside both ends of the handle:
## a grip right at the guard put half the hand over the tsuba and blade.
@export var hand_half_width := 0.05
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
## Run upgrade multiplier applied to base damage.
@export var damage_multiplier := 1.0
## Hits doing at least this much damage trigger hit-stop.
@export var hit_stop_damage := 40.0
## Hits from this much damage up to [member hit_stop_damage] get a micro-stop.
@export var micro_stop_damage := 15.0
## Steel blades ring on clashes and cuts; wooden ones do not.
@export var metal_ring := true
## Bladed weapons deal full damage only with the cutting edge (ha) or a thrust
## with the point; clubs (false) hit the same from every side.
@export var has_edge := true
## Damage multipliers by what met the target: the cutting edge or the point,
## the flat of the blade, the blunt spine (mune), and the hilt.
@export var edge_multiplier := 1.0
@export var flat_multiplier := 0.3
@export var spine_multiplier := 0.2
@export var hilt_multiplier := 0.3
## A contact this close to the tip (m) while moving along the blade is a thrust.
@export var point_length := 0.14

@export_group("Swing power")
## A hit's weight comes from momentum: the weapon's own effective mass at the
## contact point plus the arm behind it, but the arm only counts when the swing
## is carried by the whole arm. Power (0..1) = how far the hand travelled in the
## last [member power_window] s (a committed swing) times how much of the contact
## speed comes from the hand moving rather than the wrist turning. A pure wrist
## flick can whip the tip fast, but has power ~0.
## Mass of the arm (kg) behind a fully committed one-handed swing.
@export var arm_mass := 2.5
## Extra arm mass from the second hand in a two-handed swing (fraction).
@export var second_arm_mass_factor := 0.6
## Seconds of hand motion that count toward a swing's commitment.
@export var power_window := 0.3
## Hand travel (m, relative to the head) within the window for full commitment.
@export var full_power_travel := 0.45
## Share of the damage a powerless flick keeps.
@export var flick_damage := 0.25
## Share of the momentum handed to the target (a cut passes through, a club stops).
@export var impulse_transfer := 0.4
## Cap on the impulse (N·s) of a single hit.
@export var max_hit_impulse := 30.0

@export_group("Cut resistance")
## Share of the blow's impulse that pushes back on the blade: flesh resists the
## cut, so the blade loses speed along it. A sharp cut passes through (small
## bite), a flat/spine/hilt slap or a club stops harder. The loss is Δv = J/m,
## so a heavier weapon plows through while a light one is checked — and the
## arm has to re-accelerate the blade, which is where its weight is felt.
@export var edge_bite := 0.30
@export var blunt_bite := 0.55
@export var slap_bite := 0.6
## Caps on what one hit may take from the blade (m/s of travel, rad/s of spin).
@export var max_bite_speed := 3.5
@export var max_bite_spin := 6.0

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
## While set, no hand can take this weapon (grip or recall), e.g. while the
## intro is still drawing it out of the spirit gate.
var grab_locked := false
## Real m/s at which the blade striking a trunk, gate or stone is felt and heard.
var env_strike_speed := 1.6
var _grip_zones := {}   # holder -> String (ZONE_HANDLE / ZONE_TSUBA / ZONE_MUNE)
var _prev_contacts := {}  # collider instance id -> true, contacts in previous tick
## True while the blade physically rests against an enemy body this tick.
var _touching_enemy := false
var _receiver_cooldown := {}  # receiver instance id -> time left
var _wedged := {}  # body instance id -> {"body": PhysicsBody3D, "time": float}
var _stuck_timer := 0.0
var _swing_cooldown := 0.0
var _last_tip := Vector3.ZERO
var _prev_target := Transform3D()
var _has_prev_target := false
var _blocked_buzz := 0.0
var _impact_this_tick := false
## Hand speed (real m/s, relative to the head) and hand travel (m) within the
## power window, updated every physics tick while held.
var hand_speed := 0.0
var hand_travel := 0.0
## Physics frame of the last teleport into the hand (not a swing: observers
## should not read that jump as blade speed).
var teleported_frame := -100
var _hand_hist: Array = []  # [segment length, real dt] per tick, newest last
var _prev_hand := Vector3.INF
# Velocity change the arm and gravity were expected to cause in the last step.
var _expected_dv := Vector3.ZERO
var _expected_dw := Vector3.ZERO


func _ready() -> void:
	add_to_group("player_weapons")
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


## The only grabbable region is the handle (tsuka). Kept as a classifier so
## callers can log/verify the grip zone without knowing the clamp rule.
func classify_grip_zone(_local_point: Vector3) -> String:
	return ZONE_HANDLE


## Clamp an arbitrary local-space point onto the handle: between the guard
## and the pommel end, a fist's half-width inside each end, on the
## centerline. A hand that closes on the guard or the blade itself slides
## to the nearest end of the handle instead of gripping steel.
func clamp_grip_point(local_point: Vector3) -> Vector3:
	return Vector3(0.0, 0.0, clampf(local_point.z, grip_min_z(), grip_max_z()))


## Nearest-to-the-guard and nearest-to-the-pommel grip points (fist middles).
func grip_min_z() -> float:
	return guard_z + guard_half_length + hand_half_width


func grip_max_z() -> float:
	return maxf(handle_back_z - hand_half_width * 0.6, grip_min_z())


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


## The reversed (blade-down) grip: 180° about the local Y axis — the spine
## (mune) axis. That turns the blade end-for-end (-Z to +Z) while the cutting
## edge keeps the same side it has in the normal grip, so a backhand strike
## still meets the enemy edge-first. Rotating about X instead would also
## flip the edge to the spine side, presenting the blunt back to the target.
func _reversed_grip_basis() -> Basis:
	return Basis(Vector3.UP, PI)


## Snap a hand orientation to the nearest canonical grip on the handle:
## normal, or reversed when the fist came in blade-down.
func _snap_grip_basis(raw_basis: Basis, _zone: String) -> Basis:
	var q := raw_basis.get_rotation_quaternion()
	var flip := _reversed_grip_basis().get_rotation_quaternion()
	if q.angle_to(flip) < q.angle_to(Quaternion.IDENTITY):
		return _reversed_grip_basis()
	return Basis.IDENTITY


## Compute the local grip Transform3D for a hand grabbing at [param hand_global].
## The grip snaps to normal or reversed (blade-down), whichever the fist is
## closer to.
func compute_local_grip(hand_global: Transform3D) -> Transform3D:
	var raw_local := global_transform.affine_inverse() * hand_global
	if raw_local.origin.length() < 0.005 and raw_local.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY) < 0.01:
		return Transform3D.IDENTITY
	var origin := clamp_grip_point(raw_local.origin)
	return Transform3D(_snap_grip_basis(raw_local.basis, classify_grip_zone(origin)), origin)


func on_grabbed(by: Node3D, local_grip: Transform3D = Transform3D.IDENTITY) -> void:
	if by == null:
		return
	if not holders.has(by):
		if holders.size() >= 2:
			var prev_secondary: Node3D = holders[-1]
			prev_secondary.call("release")
		holders.append(by)
	var clamped_grip := Transform3D(local_grip.basis.orthonormalized(), clamp_grip_point(local_grip.origin))
	clamped_grip.basis = _snap_grip_basis(clamped_grip.basis, classify_grip_zone(clamped_grip.origin))
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
	_tick_element(delta)
	_tick_cooldowns(delta)
	_update_wedges(delta)
	_impact_this_tick = false
	_process_contacts()
	_track_hand()
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
	var last_target := _prev_target if _has_prev_target else target
	_prev_target = target
	_has_prev_target = true
	var held_back := _keep_in_hand(target, target_vel, last_target)

	# Never faster or spinning harder than the hand by more than a margin.
	linear_velocity = linear_velocity.limit_length(target_vel.length() + max_extra_speed * c)
	angular_velocity = angular_velocity.limit_length(target_omega.length() + max_extra_spin * c)

	# Held back by an obstacle -> the arm gives way (no infinite pushing).
	var want_strength := blocked_strength if held_back else 1.0
	strength = move_toward(strength, want_strength, delta * (6.0 if want_strength < strength else 3.0))
	if held_back:
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


## Hand priority: put the weapon back within [member max_grip_offset] /
## [member max_grip_angle] of the hand and drop the velocity that carries it
## farther out, also during a hit-stop (the world freezes, the hand doesn't). Not
## when static geometry holds the blade back (ghost hand on the hilt), and an
## enemy body may hold it back up to [member max_contact_offset]; past that the
## blade follows the hand into that body part instead of wedging in it.
## Returns true while something (a wall or an enemy body) holds the blade back.
func _keep_in_hand(target: Transform3D, target_vel: Vector3, last_target: Transform3D) -> bool:
	var g0: Transform3D = _local_grips.get(holder, Transform3D.IDENTITY)
	var q := global_basis.get_rotation_quaternion()
	var q_target := target.basis.get_rotation_quaternion()
	var angle := rad_to_deg(q.angle_to(q_target))
	var offset := global_transform * g0.origin - target * g0.origin
	var max_angle := max_grip_angle
	if holders.size() >= 2:
		# Two hands hold the weapon at both grips: the second grip may not stray
		# much more than the first, so the twist allowed shrinks with the hands' spread.
		var g1: Transform3D = _local_grips.get(holders[1], Transform3D.IDENTITY)
		var spread := g0.origin.distance_to(g1.origin)
		if spread > 0.05:
			max_angle = minf(max_angle, rad_to_deg(atan(max_grip_offset * 2.0 / spread)))
	if offset.length() <= max_grip_offset and angle <= max_angle:
		# The grip can sit perfectly in the hand while the blade's far end
		# rests against a body and the hand keeps shoving: the PD holds the
		# grip, so the offset check above never trips. A slow push against
		# flesh still makes the arm give way (fast swings cut instead).
		return _touching_enemy and target_vel.length() < 1.0
	var pose := _pose_within(target, g0, offset, q, q_target, angle, max_grip_offset, max_angle)
	var hits := _overlaps_at(pose)
	if hits.blocked_by_static:
		return true
	var give_way := false
	if not hits.enemy_bodies.is_empty():
		if offset.length() <= max_contact_offset and angle <= max_contact_angle:
			return true  # resting on the enemy: plain physics, the arm gives way
		if target_vel.length() < 1.0:
			# A slow shove, not a swing: the arm gives way instead of the
			# blade sawing through the body (cut-through is for real cuts).
			give_way = true
		else:
			pose = _pose_within(target, g0, offset, q, q_target, angle, max_contact_offset, max_contact_angle)
			for body in _overlaps_at(pose).enemy_bodies:
				_cut_through(body, pose, target, last_target)
				_release_wedge(body)
	global_transform = pose
	# Carried by the hand from here: no velocity away from it, at most a real
	# hand's speed toward it (a tracking jump must not fling the weapon past the
	# hand). Spin is only stopped, not given: the arm's limited torque still has
	# to turn the weapon, which is where a heavy weapon's weight shows.
	var hand_vel := target_vel.limit_length(hand_speed_limit * TimeController.compensation())
	var out_dir := offset.normalized()
	var out := (linear_velocity - hand_vel).dot(out_dir)
	if out > 0.0:
		linear_velocity -= out_dir * out
	if angle > 0.01:
		var back := ActiveRagdoll._rotation_error(q_target, q).normalized()
		var spin_out := angular_velocity.dot(-back)
		if spin_out > 0.0:
			angular_velocity += back * spin_out
	return give_way


## The current pose pulled toward [param target] so the grip is at most
## [param max_offset] from the hand and the weapon at most [param max_angle] twisted.
func _pose_within(target: Transform3D, g0: Transform3D, offset: Vector3, q: Quaternion, q_target: Quaternion,
		angle: float, max_offset: float, max_angle: float) -> Transform3D:
	var basis := Basis(q)
	if angle > max_angle:
		basis = Basis(q_target.slerp(q, max_angle / angle).normalized())
	var grip := target * g0.origin + offset.limit_length(max_offset)
	return Transform3D(basis, grip - basis * g0.origin)


## What the weapon would overlap at [param pose]: static geometry (walls, floor,
## props) and enemy bodies (anything with a hit receiver). Loose dynamic bodies
## and bodies we already slide through don't count.
func _overlaps_at(pose: Transform3D) -> Dictionary:
	var result := {"blocked_by_static": false, "enemy_bodies": []}
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	for owner_id in get_shape_owners():
		var owner_xform := shape_owner_get_transform(owner_id)
		for i in shape_owner_get_shape_count(owner_id):
			query.shape = shape_owner_get_shape(owner_id, i)
			query.transform = pose * owner_xform
			for r in space.intersect_shape(query, 16):
				var other: Object = r.collider
				if other == null or _wedged.has(other.get_instance_id()):
					continue
				if other.has_meta("hit_receiver"):
					if not result.enemy_bodies.has(other):
						result.enemy_bodies.append(other)
				elif not (other is RigidBody3D or other is CharacterBody3D or other is PhysicalBone3D):
					result.blocked_by_static = true
	return result


# --- Wedge release ---------------------------------------------------------------

## The hand carries the blade through [param body] faster than the physics
## could report the contact: count it as a hit at the hand's speed there.
func _cut_through(body: PhysicsBody3D, pose: Transform3D, target: Transform3D, last_target: Transform3D) -> void:
	if not body.has_meta("hit_receiver"):
		return
	var rid: int = (body.get_meta("hit_receiver") as Object).get_instance_id()
	if _receiver_cooldown.has(rid) or _wedged.has(body.get_instance_id()):
		return
	var point := Geometry3D.get_closest_point_to_segment(body.global_position, pose * blade_start, pose * blade_tip)
	var local_point := pose.affine_inverse() * point
	var hand_motion := (target * local_point - last_target * local_point) / TimeController.real_tick()
	var other_vel := _pre_step_velocity_of(body, point)
	var rel := hand_motion - TimeController.compensation() * other_vel
	_handle_hit({"collider": body, "point": point, "speed": rel.length(),
		"direction": rel.normalized() if rel.length() > 0.001 else Vector3.ZERO, "normal": -rel.normalized()})
	_receiver_cooldown[rid] = 0.2


## Stop colliding with [param body] until the blade is out of it again.
func _release_wedge(body: PhysicsBody3D) -> void:
	var id := body.get_instance_id()
	if not _wedged.has(id):
		add_collision_exception_with(body)
		GameEvents.log_event("blade_wedge_release", {"weapon": weapon_name, "part": String(body.get_meta("body_part", body.name))})
	_wedged[id] = {"body": body, "time": 0.0}


func is_sliding_through(body: Object) -> bool:
	return body != null and _wedged.has(body.get_instance_id())


func _update_wedges(delta: float) -> void:
	for id in _wedged.keys():
		var entry: Dictionary = _wedged[id]
		entry.time += delta
		# Untyped first: assigning a freed body to a typed variable is a
		# script error before is_instance_valid can catch it (a wedged limb
		# freed with its yōkai on restart or pool overflow).
		var maybe: Variant = entry.body
		if not is_instance_valid(maybe):
			_wedged.erase(id)
			continue
		var body := maybe as PhysicsBody3D
		if entry.time < wedge_release_min_time or _overlaps_body(body):
			continue
		remove_collision_exception_with(body)
		_wedged.erase(id)


func _overlaps_body(body: PhysicsBody3D) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.01
	for owner_id in get_shape_owners():
		var owner_xform := shape_owner_get_transform(owner_id)
		for i in shape_owner_get_shape_count(owner_id):
			query.shape = shape_owner_get_shape(owner_id, i)
			query.transform = global_transform * owner_xform
			for r in space.intersect_shape(query, 16):
				if r.collider == body:
					return true
	return false


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
	teleported_frame = Engine.get_physics_frames()
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

func _tick_element(_delta: float) -> void:
	# Single source of truth: ElementSystem manages element duration and expiry.
	# HeldWeapon purely displays the blade visual state (glow, pulse, trail).
	_update_blade_material()


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
	_touching_enemy = false
	# Best (fastest) new contact per receiver this tick.
	var best := {}
	for i in state.get_contact_count():
		var collider := state.get_contact_collider_object(i)
		if collider == null:
			continue
		var cid := collider.get_instance_id()
		now_contacts[cid] = true
		if collider.has_meta("hit_receiver") and not _wedged.has(cid):
			_touching_enemy = true
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
		elif c.collider.has_meta("env_surface"):
			_handle_env_strike(c)
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


# --- Swing power -----------------------------------------------------------------

## Follow the hand(s) relative to the player's head: walking and turning the
## head do not count as swinging, a teleport resets the history.
func _track_hand() -> void:
	if holders.is_empty():
		_hand_hist.clear()
		_prev_hand = Vector3.INF
		hand_speed = 0.0
		hand_travel = 0.0
		return
	var p := Vector3.ZERO
	for h in holders:
		p += (h.call("get_grip_transform") as Transform3D).origin
	p /= holders.size()
	var head := get_tree().get_first_node_in_group("player_head") as Node3D
	if head:
		p -= head.global_position
	var dt := maxf(TimeController.real_tick(), 1e-4)
	if _prev_hand == Vector3.INF or p.distance_to(_prev_hand) > 0.5:
		_hand_hist.clear()
	else:
		_hand_hist.append([p.distance_to(_prev_hand), dt])
	_prev_hand = p
	var time := 0.0
	var travel := 0.0
	var keep := 0
	for i in range(_hand_hist.size() - 1, -1, -1):
		if time >= power_window:
			break
		travel += float(_hand_hist[i][0])
		time += float(_hand_hist[i][1])
		keep += 1
	if keep < _hand_hist.size():
		_hand_hist = _hand_hist.slice(_hand_hist.size() - keep)
	hand_travel = travel
	hand_speed = float(_hand_hist[-1][0]) / float(_hand_hist[-1][1]) if not _hand_hist.is_empty() else 0.0


## 0..1: how much of the arm is behind a contact at [param contact_speed] (real m/s).
func swing_power(contact_speed: float) -> float:
	var commit := smoothstep(0.05, full_power_travel, hand_travel)
	var drive := smoothstep(0.08, 0.35, hand_speed / maxf(contact_speed, 0.1))
	return commit * drive


## Effective mass (kg) of the weapon alone for a push at [param point] along [param dir].
func effective_mass_at(point: Vector3, dir: Vector3) -> float:
	var st := PhysicsServer3D.body_get_direct_state(get_rid())
	if st == null or dir.length_squared() < 1e-8:
		return mass
	var n := dir.normalized()
	var rn := (point - (global_position + st.center_of_mass)).cross(n)
	return 1.0 / (st.inverse_mass + rn.dot(st.inverse_inertia_tensor * rn))


## Momentum behind a contact: power, effective mass (weapon + arm) and the
## impulse (N·s) handed to the target.
func strike_momentum(point: Vector3, direction: Vector3, contact_speed: float) -> Dictionary:
	var power := swing_power(contact_speed)
	var arms := arm_mass * (1.0 + (second_arm_mass_factor if holders.size() > 1 else 0.0))
	var m_eff := effective_mass_at(point, direction) + arms * power
	return {"power": power, "mass": m_eff, "impulse": clampf(m_eff * contact_speed * impulse_transfer, 0.0, max_hit_impulse)}


func _handle_hit(c: Dictionary) -> void:
	if c.speed < min_hit_speed:
		return
	var part: Node = c.collider
	var receiver: Node = part.get_meta("hit_receiver")
	var strike := classify_strike(c.point, c.direction)
	var mom := strike_momentum(c.point, c.direction, c.speed)
	var base_damage := clampf((c.speed - min_hit_speed) * damage_per_speed, 0.0, max_damage) \
		* lerpf(flick_damage, 1.0, mom.power) * float(strike.multiplier) * damage_multiplier
	var hit := {
		"attacker": weapon_name,
		"element": element,
		"part": String(part.get_meta("body_part", part.name)),
		"zone": String(part.get_meta("zone", "body")),
		"speed": snappedf(c.speed, 0.01),
		"strike": strike.kind,
		"edge_alignment": snappedf(strike.alignment, 0.01),
		"base_damage": base_damage,
		"point": c.point,
		"direction": c.direction,
		"power": snappedf(mom.power, 0.01),
		"impulse": snappedf(mom.impulse, 0.01),
		"knockback": c.direction * float(mom.impulse),
	}
	if receiver.has_method("receive_hit"):
		hit = receiver.receive_hit(part, hit)
	var dmg: float = hit.get("damage", base_damage)
	# A limb taken off offers almost nothing: the blade follows through
	# clean instead of biting in.
	_apply_cut_resistance(c, mom, strike.kind, 0.25 if hit.has("severed") else 1.0)
	var loud := linear_to_db(clampf(0.4 + c.speed / 12.0, 0.4, 1.2))
	match strike.kind:
		"edge", "thrust":
			# Clean cut: crisp slice, bright thin sparks along the cut, a sharp bite in the palm.
			var amp := clampf(0.3 + dmg / 70.0, 0.3, 1.0)
			var steps := [[amp, 0.025], [amp * 0.35, 0.02 + clampf(dmg / 1000.0, 0.0, 0.08)]]
			if dmg >= hit_stop_damage:
				# A heavy cut lands: a beat of silence, then the weight thuds
				# through the hilt, harder for a committed swing.
				steps.append([0.0, 0.035])
				steps.append([clampf(0.6 + float(mom.power) * 0.4, 0.0, 1.0), 0.09])
			_pulse_pattern(steps)
			Sfx.play_at("cut", c.point, loud)
			if dmg >= 30.0:
				Sfx.play_at("impact_heavy", c.point, loud - 6.0)
			SparkBurst.spawn(get_tree().current_scene, c.point, c.direction, Color(2.0, 1.15, 0.45), 14, 3.2)
			if metal_ring and dmg >= micro_stop_damage:
				Sfx.play_at("blade_ring", c.point, linear_to_db(clampf(dmg / 120.0, 0.12, 0.45)))
		"blunt":
			var amp := clampf(0.25 + dmg / 80.0, 0.25, 1.0)
			var steps := [[amp, 0.03], [amp * 0.45, 0.02 + clampf(dmg / 1000.0, 0.0, 0.08)]]
			if dmg >= hit_stop_damage:
				steps.append([0.0, 0.035])
				steps.append([clampf(0.6 + float(mom.power) * 0.4, 0.0, 1.0), 0.1])
			_pulse_pattern(steps)
			Sfx.play_at("impact_heavy" if dmg >= 30.0 else "impact_light", c.point, loud)
		_:
			# Flat, spine or hilt: a dull slap with no bite and a few dim, slow sparks.
			_pulse_pattern([[0.3, 0.05], [0.12, 0.06]])
			Sfx.play_at("slap", c.point, loud)
			SparkBurst.spawn(get_tree().current_scene, c.point, -c.direction, Color(0.9, 0.5, 0.25), 5, 1.2)
	if dmg >= hit_stop_damage:
		# 50 ms for a solid hit, up to 80 ms for the heaviest ones; a flick
		# stops slightly shorter than a committed swing at the same damage.
		var stop := lerpf(0.05, 0.08, clampf((dmg - hit_stop_damage) / 60.0, 0.0, 1.0)) \
			* lerpf(0.85, 1.0, clampf(float(mom.power), 0.0, 1.0))
		TimeController.hit_stop(clampf(stop, 0.05, 0.08))
	elif dmg >= micro_stop_damage:
		TimeController.micro_stop(lerpf(0.025, 0.035, (dmg - micro_stop_damage) / (hit_stop_damage - micro_stop_damage)))


## The blade meets the world (a trunk, a gate, stone): a thud in the hand and
## a knock to hear, sparks off stone. No damage, it just stops.
func _handle_env_strike(c: Dictionary) -> void:
	if c.speed < env_strike_speed:
		return
	var surface := String(c.collider.get_meta("env_surface", "wood"))
	var amp := clampf(0.25 + c.speed / 10.0, 0.25, 0.9)
	_pulse_pattern([[amp, 0.03], [amp * 0.4, 0.05]])
	var loud := linear_to_db(clampf(0.3 + c.speed / 12.0, 0.3, 1.0))
	if surface == "stone":
		Sfx.play_at("clash", c.point, loud - 4.0)
		SparkBurst.spawn(get_tree().current_scene, c.point, c.normal, Color(2.0, 1.15, 0.45), 8, 2.0)
	else:
		Sfx.play_at("impact_light", c.point, loud)


## The target's flesh pushes back: part of the blow's momentum stays in the
## target, so the blade loses speed along the cut (and some spin about the
## contact). Applied as a direct velocity change, so the impact-kick limiter
## (which only caps what the solver adds on top of the arm) leaves it alone;
## the PD arm then has to re-accelerate the blade, which reads as weight.
func _apply_cut_resistance(c: Dictionary, mom: Dictionary, kind: String, scale: float = 1.0) -> void:
	var bite := slap_bite
	match kind:
		"edge", "thrust":
			bite = edge_bite
		"blunt":
			bite = blunt_bite
	var j := float(mom.impulse) * bite * scale
	if j <= 0.0:
		return
	var dv: Vector3 = -c.direction * minf(j / maxf(mass, 0.2), max_bite_speed)
	linear_velocity += dv
	var st := PhysicsServer3D.body_get_direct_state(get_rid())
	if st != null:
		var r: Vector3 = c.point - (global_position + st.center_of_mass)
		var dw: Vector3 = st.inverse_inertia_tensor * r.cross(-c.direction * j)
		angular_velocity += dw.limit_length(max_bite_spin)


## What part of the weapon met a target at world [param point] while moving in
## world [param direction] (relative to the target), and the damage multiplier:
## kind is "edge", "thrust", "flat", "spine", "hilt" or "blunt" (no edge). The
## alignment is the cosine between the cutting edge's outward normal and the
## motion across the blade (1 = edge first, -1 = spine first, 0 = flat).
func classify_strike(point: Vector3, direction: Vector3) -> Dictionary:
	if not has_edge:
		return {"kind": "blunt", "multiplier": 1.0, "alignment": 0.0}
	var local_point := global_transform.affine_inverse() * point
	if local_point.z > guard_z - guard_half_length:
		return {"kind": "hilt", "multiplier": hilt_multiplier, "alignment": 0.0}
	var axis := get_blade_axis()
	var dir := direction.normalized()
	var along := dir.dot(axis)
	if along > 0.75 and local_point.distance_to(blade_tip) < point_length + 0.03:
		return {"kind": "thrust", "multiplier": edge_multiplier, "alignment": 1.0}
	var across := dir - axis * along
	if across.length() < 0.25:
		return {"kind": "flat", "multiplier": flat_multiplier, "alignment": 0.0}
	var edge_normal := (global_basis * -spine_direction).normalized()
	var alignment := across.normalized().dot(edge_normal)
	if alignment >= 0.5:
		return {"kind": "edge", "multiplier": edge_multiplier, "alignment": alignment}
	if alignment <= -0.5:
		return {"kind": "spine", "multiplier": spine_multiplier, "alignment": alignment}
	return {"kind": "flat", "multiplier": flat_multiplier, "alignment": alignment}


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
	var mom := strike_momentum(c.point, c.direction, c.speed)
	clash["power"] = snappedf(mom.power, 0.01)
	clash["impulse"] = snappedf(mom.impulse, 0.01)
	# The blade's own mass already met the other blade in the physics step; the
	# arm behind a committed swing pushes on through and can beat a guard aside.
	if not (other is HeldWeapon and (other as HeldWeapon).is_held()):
		var arm_push: float = (float(mom.mass) - effective_mass_at(c.point, c.direction)) * c.speed * impulse_transfer
		if arm_push > 0.05:
			other.apply_impulse(c.direction * minf(arm_push, max_hit_impulse), c.point - other.global_position)
	var is_parry: bool = other.attacking and c.speed >= parry_min_speed and angle >= parry_min_angle
	clash["parry"] = is_parry
	GameEvents.report_clash(clash)
	SparkBurst.spawn(get_tree().current_scene, c.point, c.normal, Color(2.0, 1.4, 0.6), 40 if is_parry else 16, 4.0 if is_parry else 2.5)
	if is_parry:
		_parry(other, clash)
	else:
		var amp := clampf(0.4 + c.speed / 10.0, 0.4, 1.0)
		_pulse_pattern([[amp, 0.025], [amp * 0.3, 0.07]])
		Sfx.play_at("clash", c.point, linear_to_db(clampf(0.3 + c.speed / 8.0, 0.3, 1.2)))
		if metal_ring and other is HeldWeapon and (other as HeldWeapon).metal_ring:
			Sfx.play_at("blade_ring", c.point, linear_to_db(clampf(0.2 + c.speed / 10.0, 0.2, 0.8)))
		if c.speed >= 2.0:
			TimeController.micro_stop(0.025)
		if other.wielder and other.wielder.has_method("on_blade_contact"):
			clash["weapon"] = self  # not logged: lets the wielder answer this blade
			other.wielder.on_blade_contact(clash)


func _parry(other: BladeBody, clash: Dictionary) -> void:
	other.attacking = false
	if other.wielder and other.wielder.has_method("on_parried"):
		other.wielder.on_parried(clash)
	GameEvents.report_parry(clash)
	TimeController.slow_motion(parry_slowmo_scale, parry_slowmo_time, true)
	# Hard clang, a beat of silence, then the blade's ring in the palm.
	_pulse_pattern([[1.0, 0.05], [0.0, 0.03], [0.6, 0.14]])
	Sfx.play_at("clash", clash.point, linear_to_db(1.4))
	if metal_ring:
		Sfx.play_at("blade_ring", clash.point, linear_to_db(0.9))


## The enemy parried this blade: a hard knock in the palm and a ring. Feedback
## only; the clash itself already pushed the blade physically.
func feel_deflected(point: Vector3) -> void:
	_pulse_pattern([[1.0, 0.04], [0.0, 0.02], [0.7, 0.1]])
	Sfx.play_at("clash", point, linear_to_db(1.2))
	if metal_ring:
		Sfx.play_at("blade_ring", point, linear_to_db(0.6))


func _pulse(amplitude: float, duration: float) -> void:
	for h in holders:
		if h and h.has_method("pulse"):
			h.pulse(amplitude, duration)


func _pulse_pattern(steps: Array) -> void:
	for h in holders:
		if h and h.has_method("pulse_pattern"):
			h.pulse_pattern(steps)


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
		var spd := clampf(measured_tip_speed / 14.0, 0.3, 1.0)
		Sfx.play_at("swing", tip, linear_to_db(spd), 4.0, clampf(0.82 + spd * 0.38, 0.85, 1.35))

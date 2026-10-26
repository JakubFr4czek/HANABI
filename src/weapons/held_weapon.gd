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
## - Stable PD (Tan et al.): position error is predicted one step ahead, which
##   keeps high gains stable at 72–120 Hz.
## - Slow motion: in a compensated slow-mo (parry) gains are scaled by
##   [method TimeController.compensation] so the blade keeps real-time speed.

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

## The WeaponHolder currently holding us, or null.
var holder: Node3D = null
## How fast the tip actually moved during the last physics step (real m/s).
## Unlike the body velocity, this stays honest when the blade is blocked.
var measured_tip_speed := 0.0
## Current strength factor (1 = free, [member blocked_strength] = held back).
var strength := 1.0
## Distance between where the grip is and where the hand wants it (m).
var grip_error := 0.0

var _prev_contacts := {}  # collider instance id -> true, contacts in previous tick
var _receiver_cooldown := {}  # receiver instance id -> time left
var _stuck_timer := 0.0
var _swing_cooldown := 0.0
var _last_tip := Vector3.ZERO
var _prev_target := Transform3D()
var _has_prev_target := false
var _blocked_buzz := 0.0


func _ready() -> void:
	super._ready()
	# We detect hits ourselves and snapshot at the end of our own tick.
	process_physics_priority = 0
	add_to_group("player_weapons")
	contact_monitor = true
	max_contacts_reported = 16
	_last_tip = get_tip_global()


func is_held() -> bool:
	return holder != null


func on_grabbed(by: Node3D) -> void:
	holder = by
	wielder = by
	gravity_scale = 1.0
	_stuck_timer = 0.0
	_has_prev_target = false
	GameEvents.log_event("weapon_grabbed", {"weapon": weapon_name, "hand": str(by.get("side"))})


func on_released() -> void:
	GameEvents.log_event("weapon_released", {"weapon": weapon_name})
	holder = null
	wielder = null


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_process_contacts()
	if holder and delta > 0.0:
		_drive_to(holder.call("get_grip_transform"), delta)
	_update_swing_audio(delta)
	_snapshot_velocity()


# --- PD controller -------------------------------------------------------------

func _drive_to(target: Transform3D, delta: float) -> void:
	grip_error = global_position.distance_to(target.origin)
	if grip_error > stuck_distance:
		_stuck_timer += TimeController.real_tick()
		if _stuck_timer > stuck_time:
			_teleport_to(target)
			return
	else:
		_stuck_timer = 0.0

	# Target velocity of the hand, from how the target moved since last tick.
	var target_vel := Vector3.ZERO
	var target_omega := Vector3.ZERO
	if _has_prev_target:
		target_vel = (target * center_of_mass - _prev_target * center_of_mass) / delta
		target_omega = ActiveRagdoll._rotation_error(target.basis.get_rotation_quaternion(), _prev_target.basis.get_rotation_quaternion()) / delta
	_prev_target = target
	_has_prev_target = true

	# Held back by an obstacle -> the arm gives way (no infinite pushing).
	var want_strength := blocked_strength if grip_error > blocked_distance else 1.0
	strength = move_toward(strength, want_strength, delta * (6.0 if want_strength < strength else 3.0))
	_buzz_when_blocked(delta)

	var c := TimeController.compensation_for(delta)
	var limit_scale := minf(c * c, 16.0) * strength

	# Linear: stable PD on the center of mass, plus holding the weapon's weight.
	var w := TAU * follow_frequency * c
	var com := get_com_global()
	var com_target := target * center_of_mass
	var accel := (com_target - (com + linear_velocity * delta)) * (w * w) + (target_vel - linear_velocity) * (2.0 * follow_damping * w)
	var force := mass * accel - mass * get_gravity()
	apply_central_force(force.limit_length(max_force * limit_scale))

	# Angular: stable PD on orientation (error to the orientation one step ahead).
	var wa := TAU * angular_frequency * c
	var q := global_basis.get_rotation_quaternion()
	var spin := angular_velocity * delta
	var q_pred := q
	if spin.length_squared() > 1e-12:
		q_pred = Quaternion(spin.normalized(), spin.length()) * q
	var err := ActiveRagdoll._rotation_error(target.basis.get_rotation_quaternion(), q_pred)
	var alpha := err * (wa * wa) + (target_omega - angular_velocity) * (2.0 * angular_damping * wa)
	var st := PhysicsServer3D.body_get_direct_state(get_rid())
	var torque: Vector3 = st.inverse_inertia_tensor.inverse() * alpha
	apply_torque(torque.limit_length(max_torque * limit_scale))


## Put the weapon exactly in the hand (e.g. after the player teleported).
func snap_to_hand() -> void:
	if holder:
		_teleport_to(holder.call("get_grip_transform"))


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
	if holder and holder.has_method("pulse"):
		holder.pulse(amplitude, duration)


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

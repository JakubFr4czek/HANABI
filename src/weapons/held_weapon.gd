class_name HeldWeapon
extends BladeBody
## A weapon the player can hold. While held it follows the hand by setting its
## velocity every physics tick (a simple "velocity follow"), so it still
## collides with walls and bodies instead of clipping through them.
##
## TEMPORARY: the next task replaces the follow with a PD controller (force +
## torque, mass-dependent lag). Hit/clash detection below stays as is.

## Hits slower than this (relative m/s at the contact point) do nothing.
@export var min_hit_speed := 1.5
## Damage per m/s above [member min_hit_speed], before zone/resistance multipliers.
@export var damage_per_speed := 9.0
## Cap on base damage of a single hit.
@export var max_damage := 120.0
## Extra knock-back impulse per m/s of hit speed, on top of the physical contact.
@export var knockback_per_speed := 0.6
## Follow limits while held.
@export var max_follow_speed := 25.0
@export var max_follow_angular_speed := 30.0
## If the weapon ends up farther than this from the hand (stuck behind a wall
## after walking away), it is teleported back after [member stuck_time] s.
@export var stuck_distance := 1.2
@export var stuck_time := 0.5
## Tip speed that triggers a swing "whoosh".
@export var swing_sound_speed := 7.0

## The WeaponHolder currently holding us, or null.
var holder: Node3D = null

var _prev_contacts := {}  # collider instance id -> true, contacts in previous tick
var _receiver_cooldown := {}  # receiver instance id -> time left
var _stuck_timer := 0.0
var _swing_cooldown := 0.0
var _last_tip := Vector3.ZERO
## How fast the tip actually moved during the last physics step (m/s). Unlike
## the body velocity, this stays honest when the blade is blocked.
var measured_tip_speed := 0.0


func _ready() -> void:
	super._ready()
	# We detect hits ourselves and snapshot at the end of our own tick.
	process_physics_priority = 0
	add_to_group("player_weapons")
	contact_monitor = true
	max_contacts_reported = 16


func is_held() -> bool:
	return holder != null


func on_grabbed(by: Node3D) -> void:
	holder = by
	gravity_scale = 0.0
	_stuck_timer = 0.0
	GameEvents.log_event("weapon_grabbed", {"weapon": weapon_name, "hand": str(by.get("side"))})


func on_released() -> void:
	GameEvents.log_event("weapon_released", {"weapon": weapon_name})
	holder = null
	gravity_scale = 1.0


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_process_contacts()
	if holder:
		_follow(holder.call("get_grip_transform"), delta)
	_update_swing_audio(delta)
	_snapshot_velocity()


## Drive the body so that next step it lands on [param target] (grip pose).
func _follow(target: Transform3D, delta: float) -> void:
	var current := global_transform
	var dist := current.origin.distance_to(target.origin)
	if dist > stuck_distance:
		_stuck_timer += delta
		if _stuck_timer > stuck_time:
			global_transform = target
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_stuck_timer = 0.0
			return
	else:
		_stuck_timer = 0.0

	# Angular: rotate from current to target orientation within one step.
	var q_err := target.basis.get_rotation_quaternion() * current.basis.get_rotation_quaternion().inverse()
	if q_err.w < 0.0:
		q_err = -q_err
	var angle := q_err.get_angle()
	var omega := Vector3.ZERO
	if angle > 0.0001:
		omega = q_err.get_axis().normalized() * (angle / delta)
	omega = omega.limit_length(max_follow_angular_speed)

	# Linear: Godot's linear_velocity is the center-of-mass velocity, but we
	# want the grip (body origin) to reach the target, so add the rotational part.
	var grip_vel := (target.origin - current.origin) / delta
	var com_offset := get_com_global() - current.origin
	var com_vel := grip_vel + omega.cross(com_offset)
	linear_velocity = com_vel.limit_length(max_follow_speed)
	angular_velocity = omega


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
		var speed := rel.length()
		var receiver_key: Object = collider
		if collider.has_meta("hit_receiver"):
			receiver_key = collider.get_meta("hit_receiver")
		var rid := receiver_key.get_instance_id()
		if _receiver_cooldown.has(rid):
			continue
		if not best.has(rid) or speed > best[rid].speed:
			best[rid] = {
				"collider": collider, "point": point, "speed": speed,
				"direction": rel.normalized() if speed > 0.001 else Vector3.ZERO,
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


func _handle_clash(c: Dictionary) -> void:
	var other: BladeBody = c.collider
	var cos_a := absf(get_blade_axis().dot(other.get_blade_axis()))
	var clash := {
		"attacker": weapon_name,
		"defender": other.weapon_name,
		"speed": snappedf(c.speed, 0.01),
		"angle_deg": snappedf(rad_to_deg(acos(clampf(cos_a, 0.0, 1.0))), 0.1),
		"point": c.point,
		"direction": c.direction,
	}
	GameEvents.report_clash(clash)
	_pulse(clampf(0.4 + c.speed / 10.0, 0.4, 1.0), 0.06)
	Sfx.play_at("clash", c.point, linear_to_db(clampf(0.3 + c.speed / 8.0, 0.3, 1.2)))


func _pulse(amplitude: float, duration: float) -> void:
	if holder and holder.has_method("pulse"):
		holder.pulse(amplitude, duration)


func _update_swing_audio(delta: float) -> void:
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)
	var tip := get_tip_global()
	measured_tip_speed = tip.distance_to(_last_tip) / delta
	_last_tip = tip
	if not holder:
		return
	if measured_tip_speed > swing_sound_speed and _swing_cooldown <= 0.0:
		_swing_cooldown = 0.35
		Sfx.play_at("swing", tip, linear_to_db(clampf(measured_tip_speed / 14.0, 0.3, 1.0)))

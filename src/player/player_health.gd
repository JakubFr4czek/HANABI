class_name PlayerHealth
extends Node
## The player's hit points and hurtbox (group "player_health"). Enemies test
## their blades against [method hurt_capsule] and call [method take_hit].
##
## Timers run in real time (hit-stop and slow-mo do not stretch them). In the
## training arena a defeat is not the end: after [member revive_time] the
## player is back at full health. In a run ([member auto_revive] = false),
## death ends the run.

signal damaged(amount: float, hp_left: float, source: Vector3)
signal healed(amount: float, hp_left: float)
signal died
signal revived

@export var max_hp := 100.0
## Seconds of invulnerability after a hit, so one cut cannot hit twice.
@export var invulnerable_time := 0.6
@export var revive_time := 3.0
## True in the training arena; false in a survival run where death ends the run.
@export var auto_revive := true
## Passive HP regenerated per real second.
@export var regen_per_sec := 0.0
## Hurtbox: a capsule from just above the eyes down this far, this thick.
@export var torso_length := 0.75
@export var radius := 0.2

var hp := 100.0
## Eyes of the player (camera). Set by the rig.
var head: Node3D

var _invulnerable := 0.0
var _down_time := 0.0


func _ready() -> void:
	add_to_group("player_health")
	hp = max_hp


func is_alive() -> bool:
	return hp > 0.0


## [top, bottom, radius] of the body capsule in world space.
func hurt_capsule() -> Array:
	var h := head.global_position if head else Vector3.ZERO
	return [h + Vector3(0.0, 0.08, 0.0), h - Vector3(0.0, torso_length, 0.0), radius]


## Apply a hit. Returns false when it was ignored (down, or just hit).
func take_hit(amount: float, source: Vector3, info: Dictionary = {}) -> bool:
	if not is_alive() or _invulnerable > 0.0 or amount <= 0.0:
		return false
	var final_amount := amount
	var es := get_tree().get_first_node_in_group("element_system") if get_tree() else null
	# Abyssal Sea (Ink Node 5): standing in your own ink wards the hit off.
	if es and es.has_method("is_player_warded") and es.is_player_warded():
		return false
	if es and es.has_method("get_incoming_damage_multiplier"):
		final_amount *= es.get_incoming_damage_multiplier()
	hp = maxf(hp - final_amount, 0.0)
	_invulnerable = invulnerable_time
	var event := info.duplicate()
	event["damage"] = snappedf(final_amount, 0.1)
	event["hp_left"] = snappedf(hp, 0.1)
	GameEvents.log_event("player_hit", event)
	damaged.emit(final_amount, hp, source)
	if hp <= 0.0:
		_down_time = revive_time
		GameEvents.log_event("player_defeated", {"attacker": info.get("attacker", "")})
		died.emit()
	return true


func heal(amount: float) -> float:
	if not is_alive() or amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(hp + amount, max_hp)
	var gained := hp - before
	if gained > 0.0:
		healed.emit(gained, hp)
	return gained


func add_max_hp(bonus: float, also_heal: bool = true) -> void:
	if bonus <= 0.0:
		return
	max_hp += bonus
	if also_heal and is_alive():
		hp = minf(hp + bonus, max_hp)
		healed.emit(bonus, hp)


func heal_full() -> void:
	hp = max_hp
	_down_time = 0.0
	_invulnerable = 0.0
	healed.emit(max_hp, hp)


func _physics_process(_delta: float) -> void:
	var dt := TimeController.real_tick()
	_invulnerable = maxf(_invulnerable - dt, 0.0)
	if is_alive():
		if regen_per_sec > 0.0 and hp < max_hp:
			hp = minf(hp + regen_per_sec * dt, max_hp)
	elif auto_revive:
		_down_time -= dt
		if _down_time <= 0.0:
			heal_full()
			GameEvents.log_event("player_revived", {})
			revived.emit()

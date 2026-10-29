class_name OniBossBrain
extends DuelistBrain
## Combat brain for the Oni Boss (docs/GDD.md §7, §8, Zadanie D15).
##
## Features:
## - Active pursuit of the player without dojo-leash restriction.
## - 3 battle phases based on HP (Stalker -> Aggressor -> Enraged).
## - Integration with [OniAiClient] for async Meta AI tactics and speech taunts.
## - 100% resilient local fallback when offline, erroring, or lacking API key.
## - 3 distinct telegraphed attacks: Overhead Kanabo Slam, Cleave Sweep, Demon Lunge.

signal speech_requested(text: String)
signal phase_changed(new_phase: int)

const AI_POLL_INTERVAL := 3.5

var ai_client: OniAiClient
var phase := 1

var _ai_timer := 0.5  # First decision shortly after spawn
var _last_ai_decision := {}
var _recent_player_actions: Array[String] = []


func setup(p_body: Node3D, p_profile: EnemyProfile) -> void:
	super.setup(p_body, p_profile)
	attacks_enabled = true
	attack_table["vertical"].range = 2.85
	attack_table["vertical"].damage = 25.0
	attack_table["horizontal"].range = 2.80
	attack_table["horizontal"].damage = 20.0
	attack_table["thrust"].range = 3.10
	attack_table["thrust"].damage = 30.0
	_apply_phase_parameters()
	if ai_client == null:
		ai_client = OniAiClient.new()
		ai_client.name = "OniAiClient"
		add_child(ai_client)


func think(delta: float, ctx: Dictionary) -> Dictionary:
	_update_phase(ctx)
	_poll_ai(delta, ctx)

	var intent := super.think(delta, ctx)

	# Active pursuit when outside normal engage distance
	var has_player := ctx.has("player_position") and ctx.has("self_position")
	if has_player and state == State.STALK and attacks_enabled:
		var to_player: Vector3 = ctx.player_position - ctx.self_position
		to_player.y = 0.0
		var dist := to_player.length()
		var engage_d := float(_last_ai_decision.get("target_distance", 2.2))
		if dist > engage_d + 0.15:
			var fwd := to_player.normalized()
			var chase_mult := 1.7 if phase >= 3 else (1.45 if phase == 2 else 1.25)
			intent.move = fwd * (difficulty.move_speed * chase_mult)
			intent.plant = false

	return intent


func _update_phase(_ctx: Dictionary = {}) -> void:
	var boss := body as TrainingDummy
	if boss == null or boss.profile == null or boss.profile.max_hp <= 0.0:
		return

	var ratio := boss.hp / boss.profile.max_hp
	var target_phase := 1
	if ratio < 0.30:
		target_phase = 3
	elif ratio < 0.60:
		target_phase = 2

	if target_phase != phase:
		phase = target_phase
		_apply_phase_parameters()
		phase_changed.emit(phase)
		GameEvents.log_event("oni_phase_shift", {"phase": phase, "hp_ratio": ratio})


func refresh_phase_parameters() -> void:
	_apply_phase_parameters()


func _apply_phase_parameters() -> void:
	match phase:
		1:
			difficulty.move_speed = 1.85
			difficulty.aggression = 0.4
			difficulty.combo_chance = 0.25
			difficulty.windup_scale = 1.15
			difficulty.damage_scale = 1.3
		2:
			difficulty.move_speed = 2.25
			difficulty.aggression = 0.65
			difficulty.combo_chance = 0.55
			difficulty.windup_scale = 0.95
			difficulty.damage_scale = 1.5
		3:
			difficulty.move_speed = 2.65
			difficulty.aggression = 0.90
			difficulty.combo_chance = 0.75
			difficulty.windup_scale = 0.70
			difficulty.damage_scale = 1.75


func _poll_ai(delta: float, ctx: Dictionary) -> void:
	_ai_timer -= delta
	if _ai_timer > 0.0 or ai_client == null:
		return
	_ai_timer = AI_POLL_INTERVAL

	var state_data := _gather_combat_state(ctx)
	ai_client.request_decision(state_data, _on_ai_decision)


func _gather_combat_state(ctx: Dictionary) -> Dictionary:
	var boss := body as TrainingDummy
	var boss_hp := boss.hp if boss else 100.0
	var boss_max := boss.profile.max_hp if boss and boss.profile else 100.0

	var p_health := get_tree().get_first_node_in_group("player_health") as PlayerHealth
	var p_hp := p_health.hp if p_health else 100.0

	var dist := 4.0
	if ctx.has("player_position") and ctx.has("self_position"):
		var p_pos: Vector3 = ctx.player_position
		var s_pos: Vector3 = ctx.self_position
		dist = Vector3(p_pos.x - s_pos.x, 0.0, p_pos.z - s_pos.z).length()

	return {
		"boss_hp": snappedf(boss_hp, 0.1),
		"boss_max_hp": snappedf(boss_max, 0.1),
		"boss_hp_percent": int(clampf(boss_hp / maxf(boss_max, 1.0) * 100.0, 0.0, 100.0)),
		"player_hp": snappedf(p_hp, 0.1),
		"distance": snappedf(dist, 0.1),
		"phase": phase,
		"player_recent_actions": _recent_player_actions.duplicate(),
	}


func _on_ai_decision(decision: Dictionary) -> void:
	_last_ai_decision = decision
	var speech: String = decision.get("speech", "")
	if speech != "":
		speech_requested.emit(speech)

	var tactic: String = decision.get("tactic", "advance")
	match tactic:
		"circle_left":
			_circle_dir = 1.0
		"circle_right":
			_circle_dir = -1.0
		"retreat":
			_retreat_time = 0.6
		"attack":
			var preferred_attack: String = decision.get("attack", "slam")
			var attack_name := "vertical"
			match preferred_attack:
				"slam": attack_name = "vertical"
				"sweep": attack_name = "horizontal"
				"thrust": attack_name = "thrust"
				"combo": attack_name = "vertical"
			if state == State.STALK and _cooldown <= 0.2:
				force_attack(attack_name)

	GameEvents.log_event("oni_ai_decision_applied", {
		"tactic": tactic,
		"attack": decision.get("attack", ""),
		"source": decision.get("source", "fallback")
	})


func on_parried(info: Dictionary) -> void:
	super.on_parried(info)
	_record_player_action("parry")
	# Taunt or grunt on parry
	var speech := "Dobra obrona!" if phase < 3 else "Daremnie!"
	speech_requested.emit(speech)


func on_hit(hit: Dictionary) -> void:
	super.on_hit(hit)
	_record_player_action("cut")


func _record_player_action(action: String) -> void:
	_recent_player_actions.append(action)
	while _recent_player_actions.size() > 4:
		_recent_player_actions.pop_front()


## Overrides leash radius check to prevent the boss from getting tethered to a 3m circle.
func _keep_in_leash(move: Vector3, _ctx: Dictionary, _t: Dictionary) -> Vector3:
	# Boss roams freely in the arena
	return move

var current_phase: int:
	get:
		return phase


func apply_ai_decision(decision: Dictionary) -> void:
	_on_ai_decision(decision)


func update_combat_phase() -> void:
	_update_phase({})

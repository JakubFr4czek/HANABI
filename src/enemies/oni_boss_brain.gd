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
## N8: what the boss decided and who decided it ("ai" | "fallback" | "mock") – the demo
## overlay under the speech bubble shows it.
signal thought_changed(tactic: String, attack: String, source: String)

const AI_POLL_INTERVAL := 3.5

var ai_client: OniAiClient
var phase := 1

var _ai_timer := 0.5  # First decision shortly after spawn
var _last_ai_decision := {}
var _recent_player_actions: Array[String] = []
## F5: true when this brain drives the masked katana swordsman (the test-room duelist
## as the run boss). The AI picks a tactic from OniAiClient.DUELIST_TACTICS every
## 2-5 s; "duel" = no override, the duelist's own logic (offline fallback).
var katana_mode := false
## The swordsman tactic being executed now (F5).
var current_tactic := "duel"
## Seconds the current tactic still holds before it lapses back to "duel".
var tactic_time_left := 0.0
## N13 entrance: seconds the swordsman stands planted in guard, faces the player and
## speaks before the duel starts. Any cut on him, or the first AI decision, ends it at once.
var intro_hold := 0.0
## N15: seconds left of the retreat's opening back-hop (hiki-ashi: planted, bursting slide
## back, so the body really leaves the player's reach instead of trailing its walk anchor).
var _retreat_hop := 0.0
## N15: the retreat gives at least this much ground (3.2 m, or ~1 m past where it began).
var _retreat_until := -1.0
const RETREAT_HOP_TIME := 0.45
const RETREAT_HOP_SPEED := 1.7
## Back-off directions tried when straight back is walled (a trunk, a rock): degrees off -fwd.
const RETREAT_DODGE_ANGLES := [0.0, 35.0, -35.0, 70.0, -70.0]


## Starts the entrance: hold for [param seconds]; the first AI decision waits for its end.
func start_intro(seconds: float) -> void:
	intro_hold = seconds
	_ai_timer = maxf(_ai_timer, seconds)


func setup(p_body: Node3D, p_profile: EnemyProfile) -> void:
	super.setup(p_body, p_profile)
	attacks_enabled = true
	katana_mode = bool(p_body.get("katana_duelist")) if p_body != null else false
	if katana_mode:
		# The test-room duelist's own katana reach and damage stay as they are.
		_apply_phase_parameters()
		if ai_client == null:
			ai_client = OniAiClient.new()
			ai_client.name = "OniAiClient"
			ai_client.katana_mode = true
			add_child(ai_client)
		return
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
	if katana_mode and intro_hold > 0.0:
		intro_hold = maxf(intro_hold - delta, 0.0)
		_poll_ai(delta, ctx)
		var hold := {"pose": "guard", "attacking": false, "move": Vector3.ZERO, "tell": 0.0,
			"arm_speed": difficulty.arm_speed, "plant": true}
		if ctx.has("player_position"):
			hold["face_position"] = ctx.player_position
		return hold
	_poll_ai(delta, ctx)

	var intent := super.think(delta, ctx)
	if katana_mode:
		return _katana_tactic_intent(delta, ctx, intent)

	# Active pursuit when outside normal engage distance
	var has_player := ctx.has("player_position") and ctx.has("self_position")
	if has_player and state == State.STALK and attacks_enabled:
		var to_player: Vector3 = ctx.player_position - ctx.self_position
		to_player.y = 0.0
		var dist := to_player.length()
		var engage_d := float(_last_ai_decision.get("target_distance", 1.8))
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
	if katana_mode:
		_apply_katana_parameters()
		return
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
	_ai_timer = _rng.randf_range(2.0, 5.0) if katana_mode else AI_POLL_INTERVAL

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
		"player_style": _player_style(),
	}


## N8: 2–3 facts about the player's style from the event log (own hits only).
func _player_style() -> Dictionary:
	var right := Vector3.RIGHT
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		right = cam.global_basis.x
		right.y = 0.0
		right = right.normalized() if right.length_squared() > 1e-4 else Vector3.RIGHT
	var boss_name := ""
	var boss := body as TrainingDummy
	if boss != null and boss.profile != null:
		boss_name = boss.profile.display_name
	var hits: Array = []
	for h in GameEvents.recent(40, "hit"):
		# Hits the boss itself dealt are not the player's style.
		if boss_name == "" or String(h.get("attacker", "")) != boss_name:
			hits.append(h)
	return OniAiClient.player_style_facts(hits, right)


func _on_ai_decision(decision: Dictionary) -> void:
	intro_hold = 0.0
	_last_ai_decision = decision
	var speech: String = decision.get("speech", "")
	if speech != "":
		speech_requested.emit(speech)
	if katana_mode:
		_apply_katana_tactic(String(decision.get("tactic", "duel")), String(decision.get("attack", "")))
		thought_changed.emit(current_tactic, String(decision.get("attack", "")), String(decision.get("source", "fallback")))
		var pos := body.global_position if body != null and body.is_inside_tree() else Vector3.ZERO
		GameEvents.log_event("oni_ai_decision_applied", {
			"tactic": current_tactic,
			"attack": decision.get("attack", ""),
			"source": decision.get("source", "fallback"),
			"reason": decision.get("fallback_reason", ""),
			"x": snappedf(pos.x, 0.01), "z": snappedf(pos.z, 0.01),
		})
		return
	thought_changed.emit(String(decision.get("tactic", "advance")), String(decision.get("attack", "")),
		String(decision.get("source", "fallback")))

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
	intro_hold = 0.0
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



# --- F5: the masked katana swordsman ------------------------------------------------

## Phase parameters for the human-sized swordsman: the "hard" duelist, a touch quicker
## each phase. The tactic of the moment is laid on top (see _apply_katana_tactic).
func _apply_katana_parameters() -> void:
	var base := EnemyCatalog.oni_difficulty()
	difficulty.move_speed = [1.15, 1.35, 1.6][clampi(phase - 1, 0, 2)]
	difficulty.aggression = [0.5, 0.65, 0.8][clampi(phase - 1, 0, 2)]
	difficulty.combo_chance = base.combo_chance + 0.12 * (phase - 1)
	difficulty.windup_scale = base.windup_scale * [1.0, 0.92, 0.82][clampi(phase - 1, 0, 2)]
	difficulty.damage_scale = base.damage_scale
	difficulty.block_chance = base.block_chance
	difficulty.feint_chance = base.feint_chance
	difficulty.riposte_chance = base.riposte_chance
	match current_tactic:
		"aggressive":
			difficulty.aggression = 1.0
			difficulty.combo_chance = minf(difficulty.combo_chance + 0.3, 0.9)
			difficulty.move_speed *= 1.2
		"defensive":
			difficulty.aggression = 0.15
			difficulty.block_chance = 0.85
			difficulty.riposte_chance = minf(base.riposte_chance + 0.3, 0.9)
		"feint":
			difficulty.feint_chance = 1.0


## Executes a tactic the AI (or the test mock) picked; unknown names fall back to "duel".
func _apply_katana_tactic(tactic: String, attack: String) -> void:
	if not OniAiClient.DUELIST_TACTICS.has(tactic):
		tactic = "duel"
	current_tactic = tactic
	tactic_time_left = 4.5
	_apply_katana_parameters()
	match tactic:
		"aggressive":
			if state == State.STALK:
				force_attack(_katana_attack(attack))
		"feint":
			# A feinted cut: the wind-up switches line half-way (DuelistBrain feint).
			if state == State.STALK:
				force_attack(_katana_attack(attack))
		"flank_left":
			_circle_dir = 1.0
		"flank_right":
			_circle_dir = -1.0
		"retreat":
			# Breaks off a wind-up and gives ground before the next exchange.
			if state == State.ATTACK:
				_enter_recover(0.3)
			_retreat_time = 1.2
			_retreat_hop = RETREAT_HOP_TIME
			_retreat_until = -1.0
			_cooldown = maxf(_cooldown, 1.6)


func _katana_attack(attack: String) -> String:
	match attack:
		"sweep": return "horizontal"
		"thrust": return "thrust"
	return "vertical"


## Footwork of the tactic on top of the duelist's own intent.
func _katana_tactic_intent(delta: float, ctx: Dictionary, intent: Dictionary) -> Dictionary:
	if tactic_time_left > 0.0:
		tactic_time_left -= delta
		if tactic_time_left <= 0.0:
			current_tactic = "duel"
			_apply_katana_parameters()
	if not (ctx.has("player_position") and ctx.has("self_position")):
		return intent
	if state != State.STALK and not (current_tactic == "retreat" and state == State.RECOVER):
		return intent
	var to_player: Vector3 = ctx.player_position - ctx.self_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist < 0.01:
		return intent
	var fwd := to_player / dist
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var speed := difficulty.move_speed
	match current_tactic:
		"flank_left", "flank_right":
			var s := 1.0 if current_tactic == "flank_left" else -1.0
			intent.move = side * s * speed * 0.8 + fwd * clampf(dist - 2.0, -0.5, 0.5) * speed
			intent.plant = false
		"retreat":
			if _retreat_until < 0.0:
				_retreat_until = maxf(3.2, dist + 1.0)
			if dist < _retreat_until:
				var back := _retreat_direction(-fwd)
				if _retreat_hop > 0.0:
					# Opening hop: planted burst (TrainingDummy.burst), the feet slide back.
					_retreat_hop -= delta
					intent.move = back * speed * RETREAT_HOP_SPEED
					intent.plant = true
				else:
					intent.move = back * speed
					intent.plant = false
		"defensive":
			pass
		_:
			# Pursuit: the boss does not wait at the edge of the forest for the player.
			if dist > 3.0:
				intent.move = fwd * speed * 1.3
				intent.plant = false
	return intent


## N15: straight back, or the first clear diagonal if a trunk/rock stands behind the boss
## (TrainingDummy._blocked_toward zeroes the walk into a wall, so he would just stand there).
func _retreat_direction(back: Vector3) -> Vector3:
	if body == null or not body.has_method("_blocked_toward"):
		return back
	var sgn := 1.0 if _circle_dir >= 0.0 else -1.0
	for deg: float in RETREAT_DODGE_ANGLES:
		var dir := back.rotated(Vector3.UP, deg_to_rad(deg * sgn))
		if not bool(body.call("_blocked_toward", dir)):
			return dir
	return back

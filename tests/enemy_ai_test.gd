extends Node
## Headless checks for the duelist enemy AI (training dummy) and player health:
## attack geometry and damage, telegraph/fairness rules, parry -> stagger,
## interrupts, combos, feints, blocks, movement, difficulty, hurt feedback. Run:
##   godot --headless --path . --fixed-fps 90 res://tests/enemy_ai_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")
const FIGHT_SPOT := Vector3(0.0, 0.0, 1.45)

var room: Node3D
var dummy: TrainingDummy
var brain: DuelistBrain
var player: DesktopPlayer
var health: PlayerHealth
var failures := 0
var events: Array[Dictionary] = []


func _ready() -> void:
	room = ROOM.instantiate()
	add_child(room)
	dummy = room.dummy
	brain = dummy.brain as DuelistBrain
	player = room.player
	health = player.health
	GameEvents.event_logged.connect(func(e): events.append(e))
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	await _wait(0.5)
	await _test_attacks()
	await _test_parry_staggers()
	await _test_fairness()
	await _test_interrupt()
	await _test_combo_and_feint()
	await _test_block()
	await _test_movement()
	await _test_difficulty()
	await _test_player_down()


# --- Attacks: telegraphed, distinct, and they hurt an unguarded player -------

func _test_attacks() -> void:
	for attack in ["vertical", "horizontal", "thrust"]:
		await _start_fight(_calm(), FIGHT_SPOT, false)
		brain.force_attack(attack)
		var max_tell := 0.0
		var stayed_up := true
		var tip_start := Vector3.INF
		var tip_end := Vector3.ZERO
		var hits := []
		for i in 4 * 90:
			await get_tree().physics_frame
			stayed_up = stayed_up and dummy.state == ActiveRagdoll.State.STANDING
			if brain.attack_phase == DuelistBrain.AttackPhase.WINDUP:
				max_tell = maxf(max_tell, dummy._eyes.emission_energy_multiplier)
			if brain.attack_phase == DuelistBrain.AttackPhase.STRIKE:
				var tip := _local(dummy.sword.get_tip_global())
				if tip_start == Vector3.INF:
					tip_start = tip
				tip_end = tip
			if brain.state == DuelistBrain.State.RECOVER:
				break
		hits = events.filter(func(e): return e.type == "player_hit" and e.get("attack", "") == attack)
		var d := tip_end - tip_start
		print("    %s: wind-up %.2f s (seen %.2f s), tip moved %s in the dummy's frame (x left, y up, z toward the player), %d hit(s), hp %.0f" % [
			attack, brain.last_windup_time, brain.last_visible_tell, d.snapped(Vector3.ONE * 0.01), hits.size(), health.hp])
		_check("%s: wind-up shown at least %.1f s, in view, with the eye tell lit" % [attack, DuelistBrain.MIN_TELL],
			brain.last_windup_time >= DuelistBrain.MIN_TELL and brain.last_visible_tell >= DuelistBrain.MIN_TELL and max_tell > 1.0)
		var shape_ok := false
		match attack:
			"vertical": shape_ok = d.y < -0.35 and absf(d.y) > absf(d.x)
			"horizontal": shape_ok = absf(d.x) > 0.45 and absf(d.x) > absf(d.y)
			"thrust": shape_ok = d.z > 0.25 and d.z > absf(d.x)
		_check("%s: the blade moves along its own line (%s)" % [attack, d.snapped(Vector3.ONE * 0.01)], shape_ok)
		_check("%s: an unguarded player gets hurt once (%d hit, hp %.0f)" % [attack, hits.size(), health.hp],
			hits.size() == 1 and health.hp < health.max_hp)
		_check("%s: the dummy keeps its feet" % attack, stayed_up)
	dummy.set_attacks_enabled(false)


# --- Parry interrupts the attack and staggers the dummy -----------------------

func _test_parry_staggers() -> void:
	await _start_fight(_calm(), Vector3(0.0, 0.0, 1.3), true)
	player.force_block = true
	await _wait(1.0)
	events.clear()
	brain.force_attack("vertical")
	var parried := false
	for i in 4 * 90:
		await get_tree().physics_frame
		if events.any(func(e): return e.type == "parry"):
			parried = true
			break
	await get_tree().physics_frame
	_check("high block parries the vertical cut", parried)
	_check("parry interrupts the attack: dummy STAGGER, blade no longer attacking, counter window open",
		brain.state == DuelistBrain.State.STAGGER and not dummy.sword.attacking and dummy.counter_time_left() > 0.5)
	await _wait(0.5)
	_check("a parried strike does not hurt the player (hp %.0f)" % health.hp,
		not events.any(func(e): return e.type == "player_hit") and health.hp == health.max_hp)
	player.force_block = false
	var back := false
	for i in int((brain.difficulty.stagger_time + 2.5) * 90):
		await get_tree().physics_frame
		if brain.state == DuelistBrain.State.STALK:
			back = true
			break
	_check("after the stagger the dummy recovers and resumes stalking", back)
	dummy.set_attacks_enabled(false)


# --- Fairness: no attacks the player cannot see --------------------------------

func _test_fairness() -> void:
	# Player turned away: the dummy may move, but never starts a wind-up out of view.
	await _start_fight(_calm(), FIGHT_SPOT, false, PI)
	brain.force_attack("vertical")
	var unseen_windup := false
	for i in 3 * 90:
		await get_tree().physics_frame
		if brain.attack_phase != DuelistBrain.AttackPhase.NONE and not brain._in_view(dummy._perceive(1.0 / 90.0)):
			unseen_windup = unseen_windup or brain._timer < 0.05
	var hurt := events.filter(func(e): return e.type == "player_hit")
	_check("player looking away: no wind-up starts out of view, no damage (%d hits)" % hurt.size(), not unseen_windup and hurt.is_empty())

	# Wind-up started in view, then the player turns away: the attack is dropped.
	await _start_fight(_calm(), FIGHT_SPOT, false)
	brain.force_attack("thrust")
	for i in 90:
		await get_tree().physics_frame
		if brain.attack_phase == DuelistBrain.AttackPhase.WINDUP:
			break
	player.teleport(FIGHT_SPOT, PI)
	var struck := false
	for i in int((DuelistBrain.LOOK_AWAY_ABORT + 0.5) * 90):
		await get_tree().physics_frame
		struck = struck or brain.attack_phase == DuelistBrain.AttackPhase.STRIKE
	_check("turning away during a wind-up cancels it (aborted, no strike)",
		not struck and events.any(func(e): return e.type == "enemy_attack_aborted"))
	dummy.set_attacks_enabled(false)


# --- A hard hit during the wind-up staggers the dummy -------------------------

func _test_interrupt() -> void:
	await _start_fight(_calm(), FIGHT_SPOT, false)
	brain.force_attack("vertical")
	for i in 90:
		await get_tree().physics_frame
		if brain.attack_phase == DuelistBrain.AttackPhase.WINDUP and brain._timer > 0.15:
			break
	var chest: RagdollPart = dummy.parts["chest"]
	dummy.receive_hit(chest, {"part": "chest", "attacker": "test", "element": "physical", "zone": "torso", "base_damage": 40.0,
		"point": chest.global_position, "direction": Vector3.FORWARD, "speed": 6.0})
	await get_tree().physics_frame
	_check("a heavy hit during the wind-up interrupts it into STAGGER",
		brain.state == DuelistBrain.State.STAGGER and events.any(func(e): return e.type == "enemy_interrupted"))
	dummy.set_attacks_enabled(false)


# --- Combos and feints still respect the minimum tell --------------------------

func _test_combo_and_feint() -> void:
	var combo := _calm()
	combo.combo_chance = 1.0
	combo.max_combo = 2
	await _start_fight(combo, FIGHT_SPOT, false)
	brain.force_attack("vertical")
	var strikes := 0
	var tells := []
	var was_striking := false
	for i in 5 * 90:
		await get_tree().physics_frame
		var striking := brain.attack_phase == DuelistBrain.AttackPhase.STRIKE
		if striking and not was_striking:
			strikes += 1
			tells.append(snappedf(brain.last_windup_time, 0.01))
		was_striking = striking
		if brain.state == DuelistBrain.State.RECOVER:
			break
	_check("combo: two strikes chained before recovering, each with its own tell %s" % str(tells),
		strikes == 2 and tells.all(func(t): return t >= DuelistBrain.MIN_TELL))

	var feint := _calm()
	feint.feint_chance = 1.0
	await _start_fight(feint, FIGHT_SPOT, false)
	brain.force_attack("vertical")
	var struck_with := ""
	for i in 4 * 90:
		await get_tree().physics_frame
		if brain.attack_phase == DuelistBrain.AttackPhase.STRIKE:
			struck_with = brain.current_attack
			break
	var feints := events.filter(func(e): return e.type == "enemy_feint")
	_check("feint: the vertical wind-up switches into another attack, which still gets a full tell (%s, %.2f s)" % [struck_with, brain.last_windup_time],
		feints.size() == 1 and struck_with != "" and struck_with != "vertical" and brain.last_windup_time >= DuelistBrain.MIN_TELL)
	dummy.set_attacks_enabled(false)


# --- Blocking the player's swings (chance-based) ----------------------------------

func _test_block() -> void:
	for chance in [1.0, 0.0]:
		var d := _calm()
		d.block_chance = chance
		d.reaction_time = 0.05
		d.attack_cooldown = Vector2(60.0, 60.0)
		await _start_fight(d, Vector3(0.0, 0.0, 1.3), true)
		await _wait(0.6)
		events.clear()
		player.swing_duration = 0.3
		player.swing(DesktopPlayer.SLASH_HORIZONTAL)
		var blocked := false
		for i in 90:
			await get_tree().physics_frame
			blocked = blocked or brain.state == DuelistBrain.State.BLOCK
		var block_events := events.filter(func(e): return e.type == "enemy_block")
		print("    block chance %.0f%%: %s" % [chance * 100.0, ", ".join(block_events.map(func(e): return "%s landed=%s" % [e.pose, e.landed]))])
		if chance > 0.5:
			_check("block chance 100%: the dummy raises a block against the swing", blocked and not block_events.is_empty())
		else:
			_check("block chance 0%: the dummy does not block", not blocked and block_events.is_empty())
		await _wait(0.6)
	dummy.set_attacks_enabled(false)


# --- Movement: close in, back off, circle within the player's view ---------------

func _test_movement() -> void:
	var d := _calm()
	d.attack_cooldown = Vector2(60.0, 60.0)
	await _start_fight(d, Vector3(0.0, 0.0, 3.2), false)
	var start := _distance()
	await _wait(3.0)
	_check("too far: the dummy closes in (%.2f m -> %.2f m)" % [start, _distance()], _distance() < start - 0.8 and dummy.state == ActiveRagdoll.State.STANDING)

	await _start_fight(d, Vector3(0.0, 0.0, 0.75), false)
	start = _distance()
	await _wait(2.0)
	_check("too close: the dummy backs off (%.2f m -> %.2f m)" % [start, _distance()], _distance() > start + 0.2)

	await _start_fight(d, Vector3(0.0, 0.0, 1.55), false)
	var bearing0 := _bearing()
	var max_view := 0.0
	for i in 4 * 90:
		await get_tree().physics_frame
		max_view = maxf(max_view, absf(brain._view_angle(dummy._perceive(1.0 / 90.0))))
	var turned := absf(wrapf(_bearing() - bearing0, -180.0, 180.0))
	_check("at engage distance the dummy circles (%.0f° around the player) and stays in view (max %.0f° off-center)" % [turned, max_view],
		turned > 10.0 and max_view <= DuelistBrain.VIEW_HALF_ANGLE and dummy.state == ActiveRagdoll.State.STANDING)
	dummy.set_attacks_enabled(false)


# --- Difficulty is data: easy reads slower and hits softer, hard never cheats ---

func _test_difficulty() -> void:
	var easy := DuelistDifficulty.preset("easy")
	var hard := DuelistDifficulty.preset("hard")
	await _start_fight(hard, FIGHT_SPOT, false)
	brain.set_seed(3)
	brain.force_attack("vertical")
	for i in 3 * 90:
		await get_tree().physics_frame
		if brain.attack_phase == DuelistBrain.AttackPhase.STRIKE:
			break
	var hard_tell := brain.last_windup_time
	var hard_hit := 0.0
	for i in 90:
		await get_tree().physics_frame
	for e in events:
		if e.type == "player_hit":
			hard_hit = e.damage
	await _start_fight(easy, FIGHT_SPOT, false)
	brain.force_attack("vertical")
	for i in 3 * 90:
		await get_tree().physics_frame
		if brain.attack_phase == DuelistBrain.AttackPhase.STRIKE:
			break
	var easy_tell := brain.last_windup_time
	var easy_hit := 0.0
	for i in 90:
		await get_tree().physics_frame
	for e in events:
		if e.type == "player_hit":
			easy_hit = e.damage
	_check("difficulty: easy wind-up %.2f s > hard %.2f s >= %.1f s minimum; easy hits softer (%.1f vs %.1f)" % [easy_tell, hard_tell, DuelistBrain.MIN_TELL, easy_hit, hard_hit],
		easy_tell > hard_tell and hard_tell >= DuelistBrain.MIN_TELL and easy_hit > 0.0 and easy_hit < hard_hit)
	dummy.set_attacks_enabled(false)


# --- Player health: feedback, defeat, revive ------------------------------------

func _test_player_down() -> void:
	await _start_fight(_calm(), FIGHT_SPOT, false)
	health.hp = 5.0
	brain.force_attack("vertical")
	var vignette := 0.0
	for i in 3 * 90:
		await get_tree().physics_frame
		vignette = maxf(vignette, player.hurt_feedback.intensity)
		if not health.is_alive():
			break
	_check("a hit shows the red vignette (%.2f) and the hurt sound is loaded" % vignette,
		vignette > 0.4 and player.hurt_feedback.vignette.visible and Sfx._streams.has("player_hurt") and Sfx._streams.has("enemy_tell"))
	_check("at 0 HP the player is defeated", not health.is_alive() and events.any(func(e): return e.type == "player_defeated"))
	await _wait(0.3)
	_check("the dummy stops fighting a downed player (state %s)" % brain.state_name(), brain.state == DuelistBrain.State.IDLE)
	await _wait(health.revive_time)
	_check("the player is back at full health after %.0f s (hp %.0f)" % [health.revive_time, health.hp], health.is_alive() and health.hp == health.max_hp)
	dummy.set_attacks_enabled(false)


# --- Helpers -------------------------------------------------------------------------

## Normal difficulty without randomness in the way of a single scripted attack.
func _calm() -> DuelistDifficulty:
	var d := DuelistDifficulty.preset("normal")
	d.feint_chance = 0.0
	d.combo_chance = 0.0
	d.block_chance = 0.0
	d.riposte_chance = 0.0
	return d


## Reset the room, place the player (armed or not) and start sparring.
func _start_fight(difficulty: DuelistDifficulty, at: Vector3, armed: bool, yaw: float = 0.0) -> void:
	dummy.set_attacks_enabled(false)
	player.force_block = false
	room.reset_room()
	health.heal_full()
	if armed:
		player.take_weapon(room.katana)
	else:
		player.left_holder.release()
		player.holder.release()
		room.katana.global_position = Vector3(-3.5, 0.3, 3.5)
	room.kanabo.global_position = Vector3(3.5, 0.3, -3.5)
	player.teleport(at, yaw)
	dummy.set_difficulty(difficulty)
	brain.set_seed(7)
	await _wait(0.8)
	events.clear()
	dummy.set_attacks_enabled(true)


## World point in the dummy's frame: x = its left, y = up, z = toward its front.
func _local(p: Vector3) -> Vector3:
	var pelvis := dummy.root_part().global_position
	return Basis(Vector3.UP, dummy._facing_yaw).inverse() * (p - pelvis)


func _distance() -> float:
	var d := player.camera.global_position - dummy.root_part().global_position
	d.y = 0.0
	return d.length()


## Where the dummy stands around the player (degrees).
func _bearing() -> float:
	var d := dummy.root_part().global_position - player.camera.global_position
	return rad_to_deg(atan2(d.x, d.z))


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame

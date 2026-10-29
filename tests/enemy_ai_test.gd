extends Node
## Headless checks for the duelist enemy AI (training dummy) and player health:
## attack geometry and damage, telegraph/fairness rules, parry -> stagger,
## interrupts, combos, feints, blocks, movement, difficulty, hurt feedback. Run:
##   godot --headless --path . --fixed-fps 90 res://tests/enemy_ai_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")
const FIGHT_SPOT := Vector3(0.0, 0.0, 1.45)
## The dummy's ma-ai (profile engage_distance), measured to the player's head.
const MA_AI := 1.9
## Close enough that the player's cuts really reach the dummy's body.
const CLOSE := 1.25
## A light overhead cut: the hand barely travels (little arm behind it).
const LIGHT_OVERHEAD := [Vector3(0.03, 0.05, 0), Vector3(0.0, -0.05, 0)]

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
	_base_brain_holds_guard()
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
	await _test_block_lands()
	await _test_evade()
	await _test_movement()
	await _test_footwork()
	await _test_guard_tracks_blade()
	await _test_openings()
	await _test_riposte()
	await _test_defence_rate()
	await _test_strike_step()
	await _test_tempo_varies()
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
		await _start_fight(d, Vector3(0.0, 0.0, MA_AI), true)
		await _wait(0.6)
		events.clear()
		_step_in_and_swing(DesktopPlayer.SLASH_HORIZONTAL, 0.3)
		var blocked := false
		for i in 90:
			await get_tree().physics_frame
			blocked = blocked or brain.state == DuelistBrain.State.BLOCK
		# Raised blocks (a passive guard may still catch the blade).
		var block_events := events.filter(func(e): return e.type == "enemy_block" and not e.landed)
		print("    block chance %.0f%%: %s" % [chance * 100.0, ", ".join(block_events.map(func(e): return "%s landed=%s" % [e.pose, e.landed]))])
		if chance > 0.5:
			_check("block chance 100%: the dummy raises a block against the swing", blocked and not block_events.is_empty())
		else:
			_check("block chance 0%: the dummy does not block", not blocked and block_events.is_empty())
		await _wait(0.6)
	dummy.set_attacks_enabled(false)


# --- The block meets the blade: light cuts are parried, full swings break it ---

func _test_block_lands() -> void:
	var results := {}
	for kind in ["light", "full"]:
		var d := _calm()
		d.block_chance = 1.0
		d.anticipation = 1.0
		d.riposte_chance = 0.0
		d.attack_cooldown = Vector2(60.0, 60.0)
		await _start_fight(d, Vector3(0.0, 0.0, MA_AI), true)
		await _wait(0.6)
		events.clear()
		_step_in_and_swing(DesktopPlayer.SLASH_HORIZONTAL if kind == "full" else LIGHT_OVERHEAD, 0.3 if kind == "full" else 0.22)
		await _wait(1.0)
		var landed := events.filter(func(e): return e.type == "enemy_block" and e.landed)
		results[kind] = landed[0] if not landed.is_empty() else {}
		print("      events: %s" % ", ".join(events.filter(func(e): return e.type in ["enemy_block", "enemy_state", "enemy_evade", "clash", "hit", "enemy_opening", "enemy_phase"]).map(func(e): return "%s %s%s" % [e.type, e.get("state", e.get("result", e.get("part", e.get("opening", "")))), " cd %.2f pat %.2f" % [e.cooldown, e.patience] if e.has("cooldown") else ""])))
		print("    %s cut vs. guard: %s" % [kind, "no contact" if landed.is_empty() else "%s, arm %.0f%%" % [landed[0].result, float(landed[0].power) * 100.0]])
	_check("a light cut into the guard is parried (%s)" % results.light.get("result", "no contact"),
		results.light.get("result", "") == "parry")
	_check("a full-arm cut beats the guard aside and staggers the dummy (%s)" % results.full.get("result", "no contact"),
		results.full.get("result", "") == "broken")
	dummy.set_attacks_enabled(false)


# --- Evading: a step back out of reach instead of a block ----------------------

func _test_evade() -> void:
	var d := _calm()
	d.evade_chance = 1.0
	d.reaction_time = 0.05
	d.attack_cooldown = Vector2(60.0, 60.0)
	await _start_fight(d, Vector3(0.0, 0.0, MA_AI), true)
	await _wait(0.6)
	events.clear()
	_step_in_and_swing(DesktopPlayer.SLASH_HORIZONTAL, 0.3)
	var start := _distance()
	var far := start
	for i in 70:
		await get_tree().physics_frame
		far = maxf(far, _distance())
	_check("evade: the dummy steps back out of reach of the swing (%.2f m -> %.2f m)" % [start, far],
		events.any(func(e): return e.type == "enemy_evade") and far > start + 0.2 and brain.state != DuelistBrain.State.BLOCK)
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

	await _start_fight(d, Vector3(0.0, 0.0, MA_AI), false)
	var bearing0 := _bearing()
	var max_view := 0.0
	for i in 4 * 90:
		await get_tree().physics_frame
		max_view = maxf(max_view, absf(brain._view_angle(dummy._perceive(1.0 / 90.0))))
	var turned := absf(wrapf(_bearing() - bearing0, -180.0, 180.0))
	_check("at engage distance the dummy circles (%.0f° around the player) and stays in view (max %.0f° off-center)" % [turned, max_view],
		turned > 10.0 and max_view <= DuelistBrain.VIEW_HALF_ANGLE and dummy.state == ActiveRagdoll.State.STANDING)
	dummy.set_attacks_enabled(false)


# --- Footwork: calm when nothing happens, answers the player's steps ---------

func _test_footwork() -> void:
	var d := DuelistDifficulty.preset("normal")
	d.attack_cooldown = Vector2(60.0, 60.0)
	d.block_chance = 0.0
	d.evade_chance = 0.0
	await _start_fight(d, Vector3(0.0, 0.0, MA_AI), false)
	brain._patience = 60.0
	# Player stands still: no fidgeting, no pressing in.
	var reversals := 0
	var prev_v := Vector3.ZERO
	var fast := 0
	var too_close := 0
	var ticks := 6 * 90
	for i in ticks:
		await get_tree().physics_frame
		var v := dummy.move_velocity
		if v.length() > 0.1 and prev_v.length() > 0.1 and v.dot(prev_v) < 0.0:
			reversals += 1
		if v.length() > 0.1:
			prev_v = v
		if v.length() > 0.45:
			fast += 1
		if _distance() < 1.35:
			too_close += 1
	print("    player still: %d direction reversals in 6 s, fast %.0f%% of the time, inside 1.35 m %.0f%%" % [reversals, 100.0 * fast / ticks, 100.0 * too_close / ticks])
	_check("calm guard while the player waits (%d reversals, fast %.0f%%, never pressing in)" % [reversals, 100.0 * fast / ticks],
		reversals <= 2 and fast < ticks * 0.1 and too_close == 0)
	# Player backs off 0.8 m: it follows to ma-ai.
	var at := player.global_position
	player.teleport(at + (at - dummy.root_part().global_position * Vector3(1, 0, 1)).normalized() * 0.8)
	await _wait(2.5)
	_check("follows a player who backs off back to ma-ai (%.2f m)" % _distance(), absf(_distance() - MA_AI) < 0.35)
	dummy.set_attacks_enabled(false)


# --- The guard follows the player's blade -------------------------------------------

func _test_guard_tracks_blade() -> void:
	var d := _calm()
	d.attack_cooldown = Vector2(60.0, 60.0)
	await _start_fight(d, Vector3(0.0, 0.0, MA_AI), true)
	brain._patience = 60.0
	var tips := {}
	var aims := []
	for side in [-0.2, 0.2]:
		player.hand_offset = Vector3(side, 0.0, 0.0)
		await _wait(1.2)
		tips[side] = _local(dummy.sword.get_tip_global()).x
		var throat := player.camera.global_position + Vector3.DOWN * 0.25
		var fist := dummy.sword.global_position
		aims.append(snappedf(rad_to_deg(dummy.sword.get_blade_axis().angle_to((throat - fist).normalized())), 1.0))
	player.hand_offset = Vector3.ZERO
	print("    guard tip x (dummy's left +): player blade to its right %.2f m, to its left %.2f m; blade off the line to the throat %s°" % [tips[-0.2], tips[0.2], aims])
	# The player's hand to their right (+) is the dummy's left (+x).
	_check("the guard leans toward the player's blade (%.2f m -> %.2f m)" % [tips[-0.2], tips[0.2]], tips[0.2] - tips[-0.2] > 0.05)
	_check("the point stays on the player (%s° off the line to the throat)" % [aims], aims.all(func(a): return a < 35.0))
	dummy.set_attacks_enabled(false)


# --- Openings: it punishes a missed swing and a raised blade -------------------------

func _test_openings() -> void:
	# A full swing that falls short: the dummy answers while the player recovers.
	var d := _calm()
	d.block_chance = 0.0
	d.attack_cooldown = Vector2(0.0, 0.0)
	await _start_fight(d, Vector3(0.0, 0.0, 2.15), true)
	brain._cooldown = 0.0
	brain._patience = 60.0
	events.clear()
	player.swing_duration = 0.25
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	var opening := ""
	var waited := 0.0
	for i in int(1.6 * 90):
		await get_tree().physics_frame
		waited += 1.0 / 90.0
		if brain.state == DuelistBrain.State.ATTACK:
			opening = brain.last_opening
			break
	# Whether it reads the miss itself or the blade swinging wide, it attacks
	# while the player is still busy with the swing.
	_check("a swing that falls short is punished at once (attack after %.2f s on opening '%s')" % [waited, opening],
		opening in ["whiff", "wide", "raised"] and waited < 1.0)

	# The player lifts the blade high and holds it: the body is open for a thrust.
	await _start_fight(d, Vector3(0.0, 0.0, 2.0), true)
	brain._cooldown = 0.0
	brain._patience = 60.0
	# Lift it slowly: no swing, just an open guard.
	var lift := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	lift.tween_property(player, "hand_offset", Vector3(0.0, 0.5, 0.0), 0.8)
	var attack := ""
	opening = ""
	for i in int(1.5 * 90):
		await get_tree().physics_frame
		if brain.state == DuelistBrain.State.ATTACK:
			opening = brain.last_opening
			attack = brain.current_attack
			break
	print("    raised: swing end %.2f s ago, peak %.1f, opening events %s" % [brain._clock - brain._swing_end, brain._swing_peak, events.filter(func(e): return e.type == "enemy_opening").map(func(e): return e.opening)])
	player.hand_offset = Vector3.ZERO
	_check("a raised blade opens the body: it attacks the opening (%s with a %s)" % [opening, attack], opening == "raised")
	dummy.set_attacks_enabled(false)


# --- Riposte: a parried light cut is answered at once --------------------------------

func _test_riposte() -> void:
	var d := _calm()
	d.block_chance = 1.0
	d.riposte_chance = 1.0
	d.attack_cooldown = Vector2(60.0, 60.0)
	await _start_fight(d, Vector3(0.0, 0.0, MA_AI), true)
	await _wait(0.6)
	events.clear()
	_step_in_and_swing(LIGHT_OVERHEAD, 0.22)
	var opening := ""
	for i in int(1.2 * 90):
		await get_tree().physics_frame
		if brain.state == DuelistBrain.State.ATTACK:
			opening = brain.last_opening
			break
	print("    riposte events: %s" % ", ".join(events.filter(func(e): return e.type in ["enemy_block", "enemy_state", "enemy_parry", "clash", "enemy_opening"]).map(func(e): return "%s %s %s" % [e.type, e.get("state", e.get("result", "")), e.get("riposte", "")])))
	_check("after parrying a light cut it ripostes at once (%s)" % (opening if opening != "" else "no attack"), opening == "riposte")
	dummy.set_attacks_enabled(false)


# --- Defence rate: with a sure read it stops most cuts that would land ---------------

func _test_defence_rate() -> void:
	var d := _calm()
	d.block_chance = 1.0
	d.anticipation = 1.0
	d.attack_cooldown = Vector2(60.0, 60.0)
	var swings := [DesktopPlayer.SLASH_HORIZONTAL, LIGHT_OVERHEAD, DesktopPlayer.SLASH_OVERHEAD, DesktopPlayer.SLASH_HORIZONTAL, LIGHT_OVERHEAD, DesktopPlayer.SLASH_OVERHEAD]
	var met := 0
	var hits := 0
	var reached := 0
	for k in swings.size():
		await _start_fight(d, Vector3(0.0, 0.0, MA_AI), true)
		brain.set_seed(40 + k)
		await _wait(0.5)
		events.clear()
		_step_in_and_swing(swings[k], 0.3)
		await _wait(0.9)
		var was_met := events.any(func(e): return e.type == "enemy_block" and e.landed)
		var was_hit := events.any(func(e): return e.type == "hit")
		if was_met:
			met += 1
		if was_met or was_hit:
			reached += 1
		hits += events.filter(func(e): return e.type == "hit").size()
		print("      cut %d: %s" % [k, ", ".join(events.filter(func(e): return e.type in ["enemy_block", "hit", "enemy_evade", "enemy_opening"]).map(func(e): return "%s %s" % [e.type, e.get("result", e.get("part", e.get("pose", e.get("opening", ""))))]))])
	print("    defence: %d of %d cuts reached the dummy, the guard met %d of them; %d hit(s) (full-arm cuts may break through)" % [reached, swings.size(), met, hits])
	_check("with a sure read the guard meets the cuts that reach it (%d of %d)" % [met, reached], reached >= 3 and met >= reached - 1)
	dummy.set_attacks_enabled(false)


# --- The attack: wind-up on planted feet, then one decisive step in -------------

func _test_strike_step() -> void:
	await _start_fight(_calm(), Vector3(0.0, 0.0, 2.15), false)
	brain.force_attack("vertical")
	var windup_anchor := Vector3.INF
	var windup_drift := 0.0
	var stepping := false
	var strike_start := 0.0
	var strike_end := 0.0
	var recover_far := 0.0
	for i in 5 * 90:
		await get_tree().physics_frame
		if brain.state == DuelistBrain.State.ATTACK and brain.attack_phase == DuelistBrain.AttackPhase.WINDUP:
			if windup_anchor == Vector3.INF:
				windup_anchor = dummy.anchor_position
			windup_drift = maxf(windup_drift, dummy.anchor_position.distance_to(windup_anchor))
			stepping = stepping or dummy.overlay_pose != ""
		elif brain.state == DuelistBrain.State.ATTACK:
			if strike_start == 0.0:
				strike_start = _distance()
			strike_end = _distance()
			stepping = stepping or dummy.overlay_pose != ""
		elif brain.state == DuelistBrain.State.RECOVER:
			recover_far = maxf(recover_far, _distance())
		elif brain.state == DuelistBrain.State.STALK and recover_far > 0.0:
			# The step back may finish while settling into the guard.
			for j in 90:
				await get_tree().physics_frame
				recover_far = maxf(recover_far, _distance())
			break
	var hits := events.filter(func(e): return e.type == "player_hit")
	print("    strike step: wind-up drift %.3f m, %.2f m -> %.2f m during the strike, back to %.2f m after it, %d hit(s)" % [windup_drift, strike_start, strike_end, recover_far, hits.size()])
	_check("the wind-up stands on planted feet (drift %.3f m, no walking steps)" % windup_drift, windup_drift < 0.06 and not stepping)
	_check("the strike closes the gap in one step (%.2f m -> %.2f m) and lands (%d hit)" % [strike_start, strike_end, hits.size()],
		strike_start - strike_end > 0.25 and hits.size() == 1)
	_check("after the cut it steps back out toward ma-ai (zanshin, %.2f m)" % recover_far, recover_far > strike_end + 0.25)
	dummy.set_attacks_enabled(false)


# --- Tempo: wind-ups differ from attack to attack, never below the tell -------

func _test_tempo_varies() -> void:
	var times: Array[float] = []
	for k in 6:
		var d := _calm()
		d.hesitate_chance = 0.3
		await _start_fight(d, FIGHT_SPOT, false)
		brain.set_seed(100 + k)
		brain.force_attack("vertical")
		for i in 3 * 90:
			await get_tree().physics_frame
			if brain.attack_phase == DuelistBrain.AttackPhase.STRIKE:
				break
		times.append(snappedf(brain.last_windup_time, 0.01))
	_check("wind-up tempo varies %s (spread %.2f s >= 0.12) and never drops below %.1f s" % [times, times.max() - times.min(), DuelistBrain.MIN_TELL],
		times.max() - times.min() >= 0.12 and times.min() >= DuelistBrain.MIN_TELL)
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
	d.evade_chance = 0.0
	d.riposte_chance = 0.0
	d.hesitate_chance = 0.0
	return d


## Reset the room, place the player (armed or not) and start sparring.
func _start_fight(difficulty: DuelistDifficulty, at: Vector3, armed: bool, yaw: float = 0.0) -> void:
	dummy.set_attacks_enabled(false)
	player.force_block = false
	player._kill_swing()
	player.hand_offset = Vector3.ZERO
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
	dummy.set_motion_seed(7)
	await _wait(0.8)
	events.clear()
	dummy.set_attacks_enabled(true)


## Step in from ma-ai to cutting distance and cut at once (as a player does).
func _step_in_and_swing(points: Array, duration: float) -> void:
	var toward := dummy.root_part().global_position - player.global_position
	toward.y = 0.0
	player.teleport(dummy.root_part().global_position * Vector3(1, 0, 1) - toward.normalized() * CLOSE, player.rotation.y)
	player.swing_duration = duration
	player.swing(points)


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


## The base brain is the do-nothing default: it holds guard and takes hits in silence.
func _base_brain_holds_guard() -> void:
	var base := EnemyBrain.new()
	_check("the base brain holds guard", base.think(0.016, {})["pose"] == "guard")
	base.on_hit({})
	base.on_parried({})
	_check("the base brain takes hits and parries without changing its intent", base.think(0.016, {}) == {"pose": "guard"})
	base.free()


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame

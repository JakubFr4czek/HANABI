extends Node
## Diagnostic: 40 s of sparring at a difficulty (default "normal"; pass
## `-- hard` / `-- easy`). The desktop player keeps ma-ai, now and then steps
## in with a random cut (light or full) and steps back; prints how the dummy
## spent its time and what happened: attacks and their openings, blocks,
## parries, guard breaks, evades, hits both ways.
const ROOM := preload("res://scenes/test_room.tscn")
var counts := {}
var openings := {}
var player_hits := 0
var dummy_hits := 0


func _on_event(e: Dictionary) -> void:
	match e.type:
		"enemy_opening":
			openings[e.opening] = int(openings.get(e.opening, 0)) + 1
		"hit":
			player_hits += 1
		"player_hit":
			dummy_hits += 1
		"enemy_block":
			var k := "block_raised" if not e.landed else "guard_" + String(e.get("result", "?"))
			counts[k] = int(counts.get(k, 0)) + 1
		"enemy_evade", "enemy_feint", "enemy_guard_broken", "enemy_parry", "enemy_attack_aborted":
			counts[e.type] = int(counts.get(e.type, 0)) + 1
const CUTS := {
	"horizontal": [Vector3(0.6, -0.22, 0), Vector3(-0.6, -0.3, 0)],
	"overhead": [Vector3(0.05, 0.5, 0), Vector3(0.0, -0.5, 0)],
	"light": [Vector3(0.03, 0.05, 0), Vector3(0.0, -0.05, 0)],
	"thrust": [Vector3(0, -0.2, -0.05), Vector3(0, -0.15, 0.42)],
}


func _ready() -> void:
	var room = ROOM.instantiate()
	add_child(room)
	var dummy: TrainingDummy = room.dummy
	var brain := dummy.brain as DuelistBrain
	var player: DesktopPlayer = room.player
	var level := "normal"
	for a in OS.get_cmdline_user_args():
		if a in ["easy", "normal", "hard"]:
			level = a
	GameEvents.event_logged.connect(_on_event)
	await _wait(0.5)
	player.take_weapon(room.katana)
	player.teleport(Vector3(0, 0, 1.9))
	dummy.set_difficulty(DuelistDifficulty.preset(level))
	dummy.set_attacks_enabled(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var state_time := {}
	var next_cut := 1.5
	var t := 0.0
	var max_jerk := 0.0
	var w_hist := [Vector3.ZERO, Vector3.ZERO]
	var jerk_sum := 0.0
	var n := 0
	while t < 40.0:
		await get_tree().physics_frame
		t += 1.0 / 90.0
		state_time[brain.state_name()] = float(state_time.get(brain.state_name(), 0.0)) + 1.0 / 90.0
		var w := (dummy.parts["lower_arm_r"] as RagdollPart).angular_velocity
		var j := (w - 2.0 * (w_hist[0] as Vector3) + (w_hist[1] as Vector3)).length() * 8100.0
		if brain.state in [DuelistBrain.State.STALK, DuelistBrain.State.BLOCK]:
			jerk_sum += j
			n += 1
		w_hist = [w, w_hist[0]]
		if not player.health.is_alive():
			player.health.heal_full()
		next_cut -= 1.0 / 90.0
		if next_cut <= 0.0:
			next_cut = rng.randf_range(1.5, 3.0)
			# Step in to cutting distance, cut, step back to ma-ai.
			var to_d := dummy.root_part().global_position - player.global_position
			to_d.y = 0.0
			if to_d.length() > 0.5:
				player.teleport(dummy.root_part().global_position * Vector3(1, 0, 1) - to_d.normalized() * 1.25, atan2(-to_d.x, -to_d.z))
			var kind: String = CUTS.keys()[rng.randi() % CUTS.size()]
			player.swing_duration = rng.randf_range(0.18, 0.32)
			player.swing(CUTS[kind])
			get_tree().create_timer(0.9).timeout.connect(func():
				var d2 := dummy.root_part().global_position - player.global_position
				d2.y = 0.0
				player.teleport(dummy.root_part().global_position * Vector3(1, 0, 1) - d2.normalized() * 1.9, atan2(-d2.x, -d2.z)))
	var shares := {}
	for k in state_time:
		shares[k] = "%.0f%%" % (100.0 * state_time[k] / t)
	print("SPAR %s 40 s: time %s" % [level, shares])
	print("SPAR attacks by opening %s" % [openings])
	print("SPAR defence %s" % [counts])
	print("SPAR hits: player landed %d, dummy landed %d; sword-arm jerk in guard/block mean %.0f rad/s³" % [player_hits, dummy_hits, jerk_sum / maxf(n, 1)])
	get_tree().quit()


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame

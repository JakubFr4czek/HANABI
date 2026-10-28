extends Node
## Headless verification for E2c Ofuda currency (docs/ELEMENTS_PLAN.md (d)):
## - Drop table (ElementBalance.OFUDA_*): swarm yōkai 25% ×1, elites always 1–2
## - A kill scatters physical Ofuda pickups; the soul magnet draws them in
##   and the wallet (RunGame.ofuda_count) grows
## - RunGame.unlock_skill spends the wallet (the E2d menu's only path)
## - Death / new run resets bank, unlocks and loose pickups (per-run)
##   godot --headless --path . --fixed-fps 90 res://tests/ofuda_drop_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_ofuda_drop_high_score.cfg"

var failures := 0
var run: RunGame
var player: DesktopPlayer


func _ready() -> void:
	await _run_all()
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = TEST_SAVE_PATH
	add_child(run)
	await _frames(12)
	player = run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)

	await _test_drop_table()
	await _test_kill_scatters_pickups()
	await _test_magnet_collects()
	await _test_wallet_spending()
	await _test_per_run_reset()

	run.queue_free()


func _test_drop_table() -> void:
	# Swarm rate: 200 seeded rolls must land within 4σ of the table's chance.
	var swarm := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -3.0), player.global_position)
	await _frames(3)
	_check("Swarm yōkai is not elite", not swarm.is_elite())
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	var total := 0
	for i in 200:
		total += run.ofuda_drop_count_for(swarm, rng)
	var p := ElementBalance.OFUDA_SWARM_CHANCE
	_check("Swarm Ofuda drops average ~%d%% (got %d/200)" % [int(p * 100.0), total],
		absf(float(total) - 200.0 * p) <= 4.0 * sqrt(200.0 * p * (1.0 - p)))

	var elite := run.wave_director.spawn_elite_at(Vector3(2.0, 0.0, -3.0), player.global_position, Elements.STORM)
	await _frames(3)
	_check("Elite yōkai is elite", elite.is_elite())
	var elite_ok := true
	for i in 24:
		var n := run.ofuda_drop_count_for(elite, rng)
		if n < ElementBalance.OFUDA_ELITE_MIN or n > ElementBalance.OFUDA_ELITE_MAX:
			elite_ok = false
	_check("Elite Ofuda drops are always %d–%d" % [ElementBalance.OFUDA_ELITE_MIN, ElementBalance.OFUDA_ELITE_MAX], elite_ok)
	run.wave_director.clear_enemies()
	await _frames(3)


func _test_kill_scatters_pickups() -> void:
	_check("No loose Ofuda before the kill", _pickup_count() == 0)
	# An elite guarantees its drops: kill it where it stands.
	var elite := run.wave_director.spawn_elite_at(
		player.global_position + Vector3(0.0, 0.0, -2.5), player.global_position, Elements.SAKURA)
	await _frames(4)
	elite.die({"element": Elements.SAKURA})
	await _frames(3)
	_check("Elite death scatters %d–%d physical Ofuda pickups (got %d)" % [ElementBalance.OFUDA_ELITE_MIN, ElementBalance.OFUDA_ELITE_MAX, _pickup_count()],
		_pickup_count() >= ElementBalance.OFUDA_ELITE_MIN and _pickup_count() <= ElementBalance.OFUDA_ELITE_MAX)


func _test_magnet_collects() -> void:
	# The pickups lie ~2.5 m away, inside the 3.8 m soul-magnet radius:
	# stepping physics must pull every one into the wallet.
	var before := run.ofuda_count
	var deadline := 0
	while _pickup_count() > 0 and deadline < 600:
		await _frames(6)
		deadline += 6
	_check("Soul magnet collects every scattered Ofuda", _pickup_count() == 0)
	_check("Wallet grew by the collected pickups (%d -> %d)" % [before, run.ofuda_count],
		run.ofuda_count >= before + ElementBalance.OFUDA_ELITE_MIN and run.ofuda_count <= before + ElementBalance.OFUDA_ELITE_MAX)

	# A lone pickup placed beside the player is collected the same way.
	var drops := OfudaPickup.spawn_drops(run.get_node("OfudaPickups"),
		player.global_position + Vector3(0.9, 0.9, 0.0), 1, RandomNumberGenerator.new())
	for d in drops:
		d.collected.connect(run._on_ofuda_pickup_collected)
	var single_before := run.ofuda_count
	deadline = 0
	while _pickup_count() > 0 and deadline < 600:
		await _frames(6)
		deadline += 6
	_check("Single nearby Ofuda is magnet-collected (+1)", run.ofuda_count == single_before + 1)


func _test_wallet_spending() -> void:
	run.start_run()
	run.wave_director.stop_director()
	await _frames(3)
	var poor: Dictionary = run.unlock_skill("petal_sense")
	_check("Unlock with empty wallet fails (insufficient Ofuda)",
		not poor.get("ok", true) and poor.get("reason") == SkillTreeData.REASON_OFUDA
		and run.ofuda_count == 0)
	var c1 := int(SkillTreeData.node_by_id("petal_sense").cost)
	var c2 := int(SkillTreeData.node_by_id("razor_petals").cost)
	run.add_ofuda(c1 + 2)
	var bought: Dictionary = run.unlock_skill("petal_sense")
	_check("Unlock spends the wallet (%d - %d = 2)" % [c1 + 2, c1],
		bought.get("ok", false) and run.ofuda_count == 2 and int(bought.get("balance", -1)) == 2)
	var locked: Dictionary = run.unlock_skill("life_bloom")
	_check("Node 4 without Node 2/3 fails and keeps the wallet",
		not locked.get("ok", true) and locked.get("reason") == SkillTreeData.REASON_PREREQUISITE
		and run.ofuda_count == 2)
	run.add_ofuda(c2 - 2 + 2)
	var chain: Dictionary = run.unlock_skill("razor_petals")
	_check("Node 2 spends %d more (2 left after top-up)" % c2,
		chain.get("ok", false) and run.ofuda_count == 2)
	_check("Wrist HUD shows the Ofuda tally", run.diegetic_hud.wrist_label.text.contains("札×2"))


func _test_per_run_reset() -> void:
	# Unlocks and bank from _test_wallet_spending are live; scatter a pickup,
	# then start a new run: everything per-run must reset.
	OfudaPickup.spawn_drops(run.get_node("OfudaPickups"),
		player.global_position + Vector3(0.0, 0.9, -2.0), 2, RandomNumberGenerator.new())
	await _frames(2)
	_check("Setup: node unlocked", run.skill_tree.is_unlocked("petal_sense"))
	_check("Setup: wallet funded (ofuda=%d)" % run.ofuda_count, run.ofuda_count == 2)
	_check("Setup: pickups loose (count=%d)" % _pickup_count(), _pickup_count() == 2)
	run.start_run()
	await _frames(3)
	_check("New run resets Ofuda bank, tree unlocks and loose pickups",
		run.ofuda_count == 0 and run.skill_tree.unlocked_count() == 0 and _pickup_count() == 0)


func _pickup_count() -> int:
	return run.get_node("OfudaPickups").get_child_count()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

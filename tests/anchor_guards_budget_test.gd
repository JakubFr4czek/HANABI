extends Node
## Live yōkai and draw calls over a 600 s walk, long enough for the planner cap to climb
## from 2 to its hard maximum of 8 (it rises one a 45 s). Guard groups stand at the gates
## and shrines within 40 m, as in the run. Maxima are kept per cap level, so the budget is
## read where it is tightest (cap 8 with a full guard group).
## godot --headless --path . --fixed-fps 90 res://tests/anchor_guards_budget_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
const TEST_SAVE_PATH := "user://test_anchor_guards_budget_high_score.cfg"
const WALK_SECONDS := 600
const STEP_METRES := 3.0
## Draw calls walk the whole scene tree, so they are read every few frames, not every one.
const DRAW_EVERY := 15

var failures := 0
var run: RunGame


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
	await _frames(30)

	var wd := run.wave_director
	var player := run.player as DesktopPlayer
	var health := run._player_health()
	# Per cap level: maxima of live yōkai, guards, draw calls and physics bodies.
	var by_cap := {}
	var not_playing := 0
	var over_cap := 0
	var frames := 0
	for s in WALK_SECONDS:
		var x := STEP_METRES * float(s + 1)
		player.teleport(Vector3(x, run.forest_world.height_at(x, 0.0), 0.0), 0.0)
		# The walk is for the budget, not for the player's survival: keep them alive.
		health.hp = health.max_hp
		for f in 90:
			await get_tree().physics_frame
			frames += 1
			if run.state != RunGame.RunState.PLAYING:
				not_playing += 1
			var total := wd.alive_enemies().size()
			var guards := _guard_count()
			var cap := wd.concurrent_cap()
			if not by_cap.has(cap):
				by_cap[cap] = {"frames": 0, "total": 0, "wave": 0, "guards": 0, "draws": 0, "yokai_draws": 0, "bodies": 0}
			var m: Dictionary = by_cap[cap]
			m.frames += 1
			m.total = maxi(m.total, total)
			m.wave = maxi(m.wave, total - guards)
			m.guards = maxi(m.guards, guards)
			if total > cap:
				over_cap += 1
			if frames % DRAW_EVERY == 0:
				m.draws = maxi(m.draws, RunPerfProbe.estimate_scene_cost(run).draw_calls)
				m.yokai_draws = maxi(m.yokai_draws, RunPerfProbe.estimate_scene_cost(wd).draw_calls)
				m.bodies = maxi(m.bodies, RunPerfProbe.count_yokai_physics_bodies(run))

	print("BUDGET 600 s walk: %d frames, %d not playing" % [frames, not_playing])
	for cap in by_cap.keys():
		var m: Dictionary = by_cap[cap]
		print("BUDGET cap=%d frames=%d max_live=%d max_wave=%d max_guards=%d max_draws=%d max_yokai_draws=%d max_bodies=%d"
			% [cap, m.frames, m.total, m.wave, m.guards, m.draws, m.yokai_draws, m.bodies])
	_check("Live yokai, guards included, never exceed the planner cap (%d frames over)" % over_cap, over_cap == 0)
	var hard := wd.get_profile().cap_hard
	var top: Dictionary = by_cap.get(hard, {})
	_check("The walk reaches the hard cap of %d (%d frames there)" % [hard, top.get("frames", 0)], not top.is_empty())
	if top.is_empty():
		return
	print("BUDGET headroom at the hard cap: %d draw calls (menu test asks for 30)" % (RunPerfBudget.MAX_DRAW_CALLS - top.draws))
	_check("At the hard cap of %d, draw calls stay under the Quest budget (%d <= %d)" % [hard, top.draws, RunPerfBudget.MAX_DRAW_CALLS],
		top.draws <= RunPerfBudget.MAX_DRAW_CALLS)
	_check("At the hard cap of %d, physics bodies stay under the Quest budget (%d <= %d)" % [hard, top.bodies, RunPerfBudget.MAX_YOKAI_PHYSICS_BODIES],
		top.bodies <= RunPerfBudget.MAX_YOKAI_PHYSICS_BODIES)


func _guard_count() -> int:
	var n := 0
	for e in run.wave_director.alive_enemies():
		if e.guard_post != 0:
			n += 1
	return n


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

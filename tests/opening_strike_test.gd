extends Node
## D11 (opening strike): the cinematic on the real run scene. The stage is its own
## world with the run's WorldGen profile and six yōkai. Each cut is a real Kirisute split
## through Yokai.receive_hit, and the game's own classify_strike reads it as a clean edge
## cut at 8 m/s or more, with the contact in frame. The finisher's flash builds into white
## and the cinematic hands over to the intro, freeing its stage. A skip ends it within its
## fade. The rig never moves, the clock never touches Engine.time_scale, and the stage
## stays under the Quest draw budget. Stepping is frame-driven, nothing waits in real time.
## Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/opening_strike_test.tscn -- --desktop
## Exit code 0 when everything passed.

const RUN_SCENE := preload("res://scenes/run.tscn")
const FRAME := 1.0 / 90.0

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	var cin := run.run_cinematic
	var player := run.player as DesktopPlayer
	var cam := player.camera
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	# The run's forest streams in for a while and the player settles onto it: the rig
	# is measured once that is over, so only the cinematic can move it below.
	await _frames(150)

	_check("the run scene carries the opening strike, idle until the splash hands over", cin != null and not cin.is_active())
	cin.prepare()
	var stage := cin.stage_root()
	_check("the stage is a world of its own, apart from the run's physics and draw calls",
		stage != null and stage.get_world_3d() != run.get_world_3d())
	_check("the stage forest uses the run's WorldGen profile (seed %d)" % WorldGenProfile.load_active().world_seed,
		cin.forest() != null and cin.forest().profile.world_seed == WorldGenProfile.load_active().world_seed)
	_check("six yōkai stand in the glade (%d)" % cin.stage_yokai().size(), cin.stage_yokai().size() == 6)

	var finished := [0]
	var white_at_finish := [0.0]
	cin.finished.connect(func() -> void:
		finished[0] += 1
		white_at_finish[0] = cin.white_level())
	cin.start()
	_check("start() shows the board: active, and the main camera sees only the board layer",
		cin.is_active() and cin.visible and cam.cull_mask == RunSplash.SPLASH_LAYER)
	var rig_before := player.global_transform

	var cuts := cin.CUTS
	var cut_done := []
	for i in cuts.size():
		cut_done.append(false)
	var prev_clock := 0.0
	var clock_samples := []
	var frames := 0
	var worst_speed := INF
	var worst_align := 1.0
	var contact_ok := true
	var worst_draws := 0
	var white_held := 0.0
	var finisher_burst := 0
	var worst_lights := 0
	var min_glow := INF
	var max_pieces := 0
	var time_scale_ok := true
	var rig_moved := 0.0
	var split_ok := true
	var last_split := 0
	while cin.is_active() and frames < 900:
		await get_tree().physics_frame
		# The stage is freed the frame the cinematic ends: stop reading it there.
		if not cin.is_active():
			break
		frames += 1
		rig_moved = maxf(rig_moved, player.global_position.distance_to(rig_before.origin))
		time_scale_ok = time_scale_ok and is_equal_approx(Engine.time_scale, 1.0)
		var t := cin.elapsed()
		clock_samples.append(t - prev_clock)
		prev_clock = t
		max_pieces = maxi(max_pieces, _piece_count(stage))
		for i in cuts.size():
			var at: float = cuts[i].at
			if cut_done[i] or t < at:
				continue
			cut_done[i] = true
			var f := cin.cut_frame(i)
			var katana := run.katana
			# The blade at the contact, and the game's own read of that contact.
			katana.global_transform = cin.katana_at(at)
			var strike := katana.classify_strike(f.point, f.motion)
			worst_align = minf(worst_align, float(strike.alignment))
			contact_ok = contact_ok and strike.kind == "edge"
			var speed := (cin.katana_at(at + 0.005).origin - cin.katana_at(at - 0.005).origin).length() / 0.01
			worst_speed = minf(worst_speed, speed)
			# The contact point (the yōkai's chest) is read from the frame: the body is freed by its split.
			var chest: Vector3 = f.point
			var tip: Vector3 = katana.global_transform * (katana.blade_tip)
			var stage_cam := cin.stage_camera()
			contact_ok = contact_ok and stage_cam.is_position_in_frustum(chest) and stage_cam.is_position_in_frustum(tip)
			contact_ok = contact_ok and stage_cam.to_local(chest).z < -1.0
			# Let the split happen (the cut is in the next frames), then count its pieces.
			await _frames(2)
			var pieces := _piece_count(stage)
			split_ok = split_ok and pieces >= mini(last_split + 2, ElementBalance.KIRISUTE_MAX_PIECES)
			last_split = pieces
			worst_draws = maxi(worst_draws, RunPerfProbe.estimate_scene_cost(stage)["draw_calls"])
			worst_lights = maxi(worst_lights, RunPerfProbe.count_dynamic_lights(stage))
			for c in stage.get_children():
				if c is KirisuteChunk:
					min_glow = minf(min_glow, (c as KirisuteChunk).hot_energy)
			if i == cuts.size() - 1:
				finisher_burst = stage.get_child_count() - _piece_count(stage)
		if t >= 3.22 and t < cin.FINISH_AT:
			white_held = maxf(white_held, cin.white_level())

	_check("every cut is a clean edge cut by the game's own classify_strike (worst alignment %.2f)" % worst_align,
		contact_ok and worst_align >= ElementBalance.KIRISUTE_MIN_ALIGNMENT)
	_check("each cut's blade moves at Kirisute speed (worst %.1f m/s, need ≥ %.1f)" % [worst_speed, ElementBalance.KIRISUTE_MIN_SPEED],
		worst_speed >= ElementBalance.KIRISUTE_MIN_SPEED)
	_check("each cut splits its yōkai: pieces grow by two at every contact", split_ok)
	_check("six cuts, six splits (%d)" % cin.split_count(), cin.split_count() == 6)
	_check("the pieces stay under the Kirisute cap (peak %d of %d)" % [max_pieces, ElementBalance.KIRISUTE_MAX_PIECES],
		max_pieces <= ElementBalance.KIRISUTE_MAX_PIECES and max_pieces > 0)
	_check("the stage stays under the Quest draw budget at the cuts (%d of %d)" % [worst_draws, RunPerfBudget.MAX_DRAW_CALLS],
		worst_draws <= RunPerfBudget.MAX_DRAW_CALLS and worst_draws > 0)
	_check("the finisher bursts at its contact in its school's colour (%d new effect nodes)" % finisher_burst,
		finisher_burst > 0)
	# The dimmest school (Ink, 0.8) boosted: the pieces start hotter than a run's cut of that school.
	var dimmest := KirisuteCut.hot_energy(Elements.INK) * cin.CUT_GLOW_BOOST
	_check("the cut pieces start %.0f%% hotter than a run's cut (dimmest %.2f, need ≥ %.2f)" % [
		(cin.CUT_GLOW_BOOST - 1.0) * 100.0, min_glow, dimmest - 0.01],
		min_glow >= dimmest - 0.01)
	_check("the stage stays under the dynamic light budget (%d of %d)" % [worst_lights, RunPerfBudget.MAX_DYNAMIC_LIGHTS],
		worst_lights <= RunPerfBudget.MAX_DYNAMIC_LIGHTS)
	_check("the white is full before the cinematic ends (%.2f)" % white_held, white_held >= 0.99)
	_check("the cinematic runs about three seconds (%d frames, %.2f s on its clock)" % [frames, prev_clock],
		frames <= 360 and prev_clock >= 3.2 and prev_clock <= 3.4)
	var slow := 0.0
	for k in range(1, clock_samples.size()):
		if clock_samples[k - 1] > 0.0 and clock_samples[k - 1] < FRAME * 0.5:
			slow += 1.0
	_check("local hit-stops slow the clock for a few frames after each cut (%d slow frames)" % slow, slow >= 6)
	_check("Engine.time_scale stays 1.0 through the cinematic", time_scale_ok and is_equal_approx(Engine.time_scale, 1.0))
	# The intro lifts the rig onto its hover after the white, so only the cinematic's frames count.
	_check("the rig does not move while the cinematic plays (%.4f m)" % rig_moved, rig_moved < 0.001
		and player.global_transform.basis.is_equal_approx(rig_before.basis))
	_check("the cinematic hands over once, on white (finished %d, white %.2f)" % [finished[0], white_at_finish[0]],
		finished[0] == 1 and white_at_finish[0] >= 0.99)
	_check("the intro starts after the white", run.run_intro.is_active() and not cin.is_active())
	_check("the stage is freed and the main camera gets its world back", cin.stage_root() == null
		and cam.cull_mask != RunSplash.SPLASH_LAYER)

	# Skip: a press mid-way fades to white within its fade, keeps the cuts already made, and ends once.
	finished[0] = 0
	run.run_intro.skip()
	await _frames(20)
	cin.start()
	await _frames(int(1.0 / FRAME) + 1)
	var before_skip := cin.split_count()
	cin.skip()
	cin.skip()
	var skip_frames := 0
	while cin.is_active() and skip_frames < 200:
		await get_tree().physics_frame
		skip_frames += 1
	_check("a skip ends the cinematic within its fade (%d frames)" % skip_frames,
		skip_frames <= int(cin.SKIP_FADE * 90.0) + 3 and finished[0] == 1)
	_check("a skip keeps the cuts already made (%d of %d) and goes white (%.2f)" % [cin.split_count(), before_skip, white_at_finish[0]],
		cin.split_count() == before_skip and white_at_finish[0] >= 0.99 and before_skip == 2)
	_check("the intro takes over from a skipped cinematic too", run.run_intro.is_active())

	# The splash's hand-over: a skipped splash skips the whole opening (D11), an unskipped one plays it.
	run.run_intro.skip()
	await _frames(20)
	run.run_splash.was_skipped = false
	run._on_boot_splash_finished()
	_check("an unskipped splash hands over to the opening strike", cin.is_active() and not run.run_intro.is_active())
	cin.skip()
	await _frames(50)
	run.run_splash.was_skipped = true
	run._on_boot_splash_finished()
	_check("a skipped splash skips the opening strike, straight to the intro", run.run_intro.is_active() and not cin.is_active())
	run.queue_free()


func _piece_count(root: Node) -> int:
	var n := 0
	if not is_instance_valid(root):
		return n
	for c in root.get_children():
		if c is KirisuteChunk:
			n += 1
	return n


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

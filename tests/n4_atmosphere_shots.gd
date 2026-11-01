extends Node
## N4 atmosphere shots and measurements from the real run scene (windowed, not headless):
##   godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --resolution 960x540 res://tests/n4_atmosphere_shots.tscn -- --desktop --shots=docs/n4 --prefix=before
## Four frames, the same camera for PRE and POST: the spawn glade, a torii 30 m down
## the trail, a PEAK wave, and the ground beside the trail from close. Each prints a
## MEASURE line (frame contrast, ground luminance, trunk-vs-fog at 15 m, torii hue,
## moonbeam column). Numbers come from AtmosphereMetrics, the same code the suite uses.

const RUN_SCENE := preload("res://scenes/run.tscn")
const GROUND_DISTANCES := [4.0, 6.0, 8.0, 10.0, 12.0]
const GROUND_OFFSETS := [-3.2, -2.4, 2.4, 3.2]

var shots_dir := ""
var prefix := "shot"
var run: RunGame = null
var player: DesktopPlayer = null
var forest: ForestWorld = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
		elif a.begins_with("--prefix="):
			prefix = a.trim_prefix("--prefix=")
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	for _k in 30:
		await get_tree().process_frame
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	# Frozen weather, as in the suite: no lightning flash may light a frame.
	var lightning := run.get_node_or_null("Arena/StormLightning")
	if lightning:
		lightning.process_mode = Node.PROCESS_MODE_DISABLED
		lightning.set("_strike_age", -1.0)
		lightning.call("_set_flash", 0.0)
	player = run.player as DesktopPlayer
	forest = run.forest_world

	var spawn := run.find_child("PlayerSpawn", true, false) as Node3D
	var at := Vector2(spawn.global_position.x, spawn.global_position.z)
	var along: Vector2 = AtmosphereMetrics.trail_direction(forest, at)
	var yaw := atan2(-along.x, -along.y)
	var glade := await _look(Vector3(at.x, forest.height_at(at.x, at.y), at.y), yaw, -8.0, "glade")
	_report("glade", glade)

	var far: Vector2 = AtmosphereMetrics.trail_point(forest, at, along, 30.0)
	if far != Vector2.INF:
		# A gate beside the trail, 30 m ahead, seen from the spawn.
		var side: Vector2 = Vector2(-along.y, along.x)
		var gate_xz: Vector2 = far + side * 3.0
		forest.torii_manager.clear_gates()
		var gate: Node3D = forest.torii_manager.spawn_gate_at(gate_xz.x, gate_xz.y, Elements.STORM)
		await _frames(30)
		var gp: Vector3 = gate.global_position
		var to: Vector3 = gp - Vector3(at.x, 0.0, at.y)
		var torii := await _look(Vector3(at.x, forest.height_at(at.x, at.y), at.y), atan2(-to.x, -to.z), -2.0, "torii30")
		_report("torii30", torii, gp)
		print("MEASURE torii30_cyan_share=%.3f" % AtmosphereMetrics.cyan_share(torii, player.camera, gp))
		gate.queue_free()
		await _frames(10)

	var back: Vector2 = AtmosphereMetrics.trail_point(forest, at, along, 20.0)
	if back != Vector2.INF:
		var d: Vector2 = AtmosphereMetrics.trail_direction(forest, back)
		var side: Vector2 = Vector2(-d.y, d.x)
		var ground := await _look(Vector3(back.x, forest.height_at(back.x, back.y), back.y), atan2(-side.x, -side.y), -30.0, "ground")
		_report("ground", ground)

	await _peak_wave()
	get_tree().quit(0)


## Peak wave: the director runs in 0.1 s steps until a PEAK wave is open with the field
## full, then the player turns to the nearest yōkai.
func _peak_wave() -> void:
	var director := run.wave_director
	var center := run._player_center()
	var forward := -player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	director.start_director()
	var guard := 0
	while guard < 6000:
		director.step_director(0.1, center, forward)
		guard += 1
		if director._planner.wave_open and director._planner.state == WavePlanner.State.PEAK \
				and director.alive_count() >= 4:
			break
	await _frames(40)
	var alive := director.alive_enemies()
	if not alive.is_empty():
		var target := (alive[0] as Node3D).global_position
		for y in alive:
			var p := (y as Node3D).global_position
			if p.distance_squared_to(player.global_position) < target.distance_squared_to(player.global_position):
				target = p
		var dir := target - player.global_position
		player.teleport(player.global_position, atan2(dir.x, dir.z) + PI)
	await _frames(40)
	var img := await _capture("peak")
	_report("peak", img)


## Teleports the player to a ground point, aims the camera and returns the rendered frame.
func _look(ground: Vector3, yaw: float, pitch_deg: float, name: String) -> Image:
	player.teleport(ground + Vector3.UP * 0.2, yaw)
	player.camera.rotation.x = deg_to_rad(pitch_deg)
	await _frames(60)
	return await _capture(name)


func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.is_compressed():
		img.decompress()
	if name != "" and shots_dir != "":
		img.save_png(shots_dir.path_join("%s_%s.png" % [prefix, name]))
	return img


func _report(label: String, img: Image, gate_pos: Vector3 = Vector3.INF) -> void:
	var cam: Camera3D = player.camera
	var ground := 0.0
	var ground_n := 0
	var fwd: Vector3 = -cam.global_transform.basis.z
	var base: Vector3 = cam.global_position
	for d in GROUND_DISTANCES:
		var c: Vector3 = base + Vector3(fwd.x, 0.0, fwd.z).normalized() * d
		for o in GROUND_OFFSETS:
			var side: Vector3 = cam.global_transform.basis.x * o
			var p := Vector3(c.x + side.x, forest.height_at(c.x + side.x, c.z + side.z) + 0.05, c.z + side.z)
			var l: float = AtmosphereMetrics.patch_lum(img, cam, p)
			if l >= 0.0:
				ground += l
				ground_n += 1
	var trunk_txt := "trunk15=n/a"
	var best := INF
	var best_base := Vector3.INF
	for b in AtmosphereMetrics.trunk_bases(forest):
		var dist := cam.global_position.distance_to(b)
		if absf(dist - 15.0) < best and not cam.is_position_behind(b + Vector3.UP * 1.5):
			best = absf(dist - 15.0)
			best_base = b
	if best_base != Vector3.INF and best < 3.0:
		var tp := best_base + Vector3.UP * 1.5
		var trunk := AtmosphereMetrics.patch_lum(img, cam, tp, 2)
		var side := cam.global_transform.basis.x * 1.2
		var fog := AtmosphereMetrics.patch_lum(img, cam, tp + side, 2)
		if trunk >= 0.0 and fog >= 0.0:
			trunk_txt = "trunk15=%.3f fog_beside=%.3f diff=%+.3f" % [trunk, fog, fog - trunk]
	var torii_txt := ""
	if gate_pos != Vector3.INF:
		var g := AtmosphereMetrics.patch_color(img, cam, gate_pos + Vector3.UP * 3.0, 3)
		var f := AtmosphereMetrics.patch_color(img, cam, gate_pos + Vector3.UP * 3.0 + cam.global_transform.basis.x * 3.0, 3)
		if g.r >= 0.0 and f.r >= 0.0:
			torii_txt = " torii_hue=%.0f fog_hue=%.0f gap=%.0f torii_sat=%.2f" % [
				AtmosphereMetrics.hue_deg(g), AtmosphereMetrics.hue_deg(f),
				AtmosphereMetrics.hue_gap(g, f), g.s]
	var sh := AtmosphereMetrics.shaft(img)
	print("MEASURE %s rms=%.3f ground=%.3f (%d patches) %s%s shaft_excess=%.3f shaft_width=%.3f mean=%.3f" % [
		label, AtmosphereMetrics.rms_contrast(img), ground / maxf(1.0, ground_n), ground_n, trunk_txt, torii_txt,
		sh.excess, sh.width, AtmosphereMetrics.mean_lum(img)])


func _frames(count: int) -> void:
	for _k in count:
		await get_tree().process_frame

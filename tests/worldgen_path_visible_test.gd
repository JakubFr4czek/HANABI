extends Node
## The footpath is visible in the rendered game frame (docs/WORLDGEN_TOOL.md).
## Windowed, not headless: it reads the pixels the run scene draws, with the fog
## and the night palette of the active profile. Two frames: from the spawn looking
## down the trail, and 20 m further along it. In each, the trail's luminance is
## compared with the ground on both sides of it, at several distances.
##   godot --path . --fixed-fps 90 res://tests/worldgen_path_visible_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
const PATCH := 3  # half-size of the sampled square, in pixels
## Distances along the trail, and lateral offsets (metres) across it: the trail is
## 2 m wide, so its samples sit inside ±0.6 m, the ground beside it at ±2.4 to ±3.2 m.
const DISTANCES := [2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 9.0, 10.0, 11.0, 12.0]
const TRAIL_OFFSETS := [-0.6, -0.3, 0.0, 0.3, 0.6]
const GROUND_OFFSETS := [-3.2, -2.8, -2.4, 2.4, 2.8, 3.2]
const MIN_CONTRAST := 0.25
const DEBUG_DIR := "/tmp/hanabi_path_visible"

## N4 atmosphere thresholds (measured PRE/POST, docs/n4/README.md). Frames are the
## spawn glade (pitch -8), a torii 30 m away and the ground beside the trail from close.
const RMS_MIN := 1.2  # frame contrast; PRE 1.15, now ~1.47
const TRUNK_DIFF_MIN := 0.03  # trunk 8-20 m vs the mist (informational until the sampling is fixed)
const GROUND_GLADE_MIN := 0.08  # ground beside the trail, not black (PRE 0.065)
const GROUND_GLADE_MAX := 0.25  # ... and not washed out
const GROUND_NEAR_MIN := 0.012  # close ground stays readable (PRE 0.001-0.007)
const TORII_CYAN_MIN := 0.015  # share of cyan pixels around a STORM gate (now ~0.026)
const TORII_HUE_GAP_MIN := 8.0  # gate glow hue vs the mist, degrees (now ~12)
const SHAFT_WIDTH_MAX := 0.10  # widest bright moonbeam column, share of the frame width
const SHAFT_PEAK_MAX := 0.30  # moonbeam brightness above the sky median (display luminance)

var failures := 0


func _ready() -> void:
	# Project rule: no window in the suite. Reading the framebuffer headless never
	# returns a frame, so this check is reported as SKIP instead of hanging the run.
	if DisplayServer.get_name() == "headless":
		print("SKIP  worldgen path visibility needs a window (run windowed by hand, see docs/WORLDGEN_TOOL.md)")
		get_tree().quit(0)
		return
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	for _k in 30:
		await get_tree().process_frame
	var forest := run.forest_world
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	DirAccess.make_dir_recursive_absolute(DEBUG_DIR)

	var spawn := run.find_child("PlayerSpawn", true, false) as Node3D
	var at := Vector2(spawn.global_position.x, spawn.global_position.z)
	var along := _trail_direction(forest, at)
	_check("A trail leads away from the spawn", along != Vector2.ZERO)
	if along != Vector2.ZERO:
		var from_spawn := await _frame_contrast(run, at, along, "spawn")
		var far := _trail_point(forest, at, along, 20.0)
		_check("The trail runs on for 20 m from the spawn", far != Vector2.INF)
		if far != Vector2.INF:
			var far_dir := _trail_direction(forest, far)
			var from_far := await _frame_contrast(run, far, far_dir, "20m")
			print("RESULT spawn=%+.0f%%  20m=%+.0f%%" % [from_spawn * 100.0, from_far * 100.0])
	await _atmosphere_checks(run, forest, at, along)
	run.queue_free()
	await get_tree().process_frame


## Looks down the trail from [param at] and checks the rendered trail against the
## ground beside it. Returns the mean contrast over the samples on screen.
func _frame_contrast(run: RunGame, at: Vector2, along: Vector2, label: String) -> float:
	var player := run.player as DesktopPlayer
	var forest := run.forest_world
	var height := forest.height_at(at.x, at.y) + 0.2
	player.teleport(Vector3(at.x, height, at.y), atan2(-along.x, -along.y))
	player.camera.rotation.x = deg_to_rad(-8.0)
	for _k in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.is_compressed():
		img.decompress()
	var debug := img.duplicate() as Image
	var cam := player.camera
	var perp := Vector2(-along.y, along.x)
	var trail_sum := 0.0
	var trail_n := 0
	var ground_sum := 0.0
	var ground_n := 0
	for d in DISTANCES:
		var centre := _trail_point(forest, at, along, d)
		if centre == Vector2.INF:
			continue
		for o in TRAIL_OFFSETS:
			var p: Vector2 = centre + perp * o
			_mark(debug, cam, forest, p, Color.RED)
			var l := _patch_luminance(img, cam, forest, p)
			if l >= 0.0:
				trail_sum += l
				trail_n += 1
		for o in GROUND_OFFSETS:
			var p: Vector2 = centre + perp * o
			_mark(debug, cam, forest, p, Color.BLUE)
			var l := _patch_luminance(img, cam, forest, p)
			if l >= 0.0:
				ground_sum += l
				ground_n += 1
	debug.save_png(DEBUG_DIR.path_join("frame_%s.png" % label))
	if trail_n < 10 or ground_n < 10:
		_check("%s: the trail is on screen (%d trail, %d ground samples)" % [label, trail_n, ground_n], false)
		return -1.0
	var trail_l := trail_sum / trail_n
	var ground_l := ground_sum / ground_n
	var mean := trail_l / ground_l - 1.0
	print("MEASURE %s trail=%.4f ground=%.4f (%d/%d samples on screen)  contrast=%+.0f%%" % [label, trail_l, ground_l, trail_n, ground_n, mean * 100.0])
	_check("%s: the trail reads against the ground (%+.0f%%, need %+.0f%%)" % [label, mean * 100.0, MIN_CONTRAST * 100.0],
		mean >= MIN_CONTRAST)
	return mean


## Mean relative luminance (linear light) of a PATCH square around a ground point,
## or -1 when the point is behind the camera or off screen.
func _patch_luminance(img: Image, cam: Camera3D, forest: ForestWorld, xz: Vector2) -> float:
	var world := Vector3(xz.x, forest.height_at(xz.x, xz.y) + 0.05, xz.y)
	if cam.is_position_behind(world):
		return -1.0
	var screen := cam.unproject_position(world)
	var cx := int(round(screen.x))
	var cy := int(round(screen.y))
	if cx < PATCH or cy < PATCH or cx >= img.get_width() - PATCH or cy >= img.get_height() - PATCH:
		return -1.0
	var sum := 0.0
	var n := 0
	for y in range(cy - PATCH, cy + PATCH + 1):
		for x in range(cx - PATCH, cx + PATCH + 1):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * _s2l(c.r) + 0.7152 * _s2l(c.g) + 0.0722 * _s2l(c.b)
			n += 1
	return sum / n


## Draws a cross on the debug frame at a ground point (for reading the probe by eye).
func _mark(img: Image, cam: Camera3D, forest: ForestWorld, xz: Vector2, col: Color) -> void:
	var world := Vector3(xz.x, forest.height_at(xz.x, xz.y) + 0.05, xz.y)
	if cam.is_position_behind(world):
		return
	var sp := cam.unproject_position(world)
	for k in range(-6, 7):
		for j in [-1, 0, 1]:
			_dot(img, int(sp.x) + k, int(sp.y) + j, col)
			_dot(img, int(sp.x) + j, int(sp.y) + k, col)


func _dot(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


static func _s2l(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


## Unit direction of the trail nearest to [param p] (xz), or zero.
func _trail_direction(forest: ForestWorld, p: Vector2) -> Vector2:
	var found := forest.paths.samples_in_rect(Rect2(p - Vector2(30.0, 30.0), Vector2(60.0, 60.0)), 1.0)
	var best := Vector2.ZERO
	var best_d := INF
	for s in found:
		var d := Vector2(s.x, s.y).distance_to(p)
		if d < best_d and d > 0.0:
			best_d = d
			best = Vector2(s.z, s.w)
	return best


## The trail point about [param metres] ahead of [param from], along [param dir],
## or Vector2.INF when the trail does not go that way.
func _trail_point(forest: ForestWorld, from: Vector2, dir: Vector2, metres: float) -> Vector2:
	var found := forest.paths.samples_in_rect(Rect2(from - Vector2(30.0, 30.0), Vector2(60.0, 60.0)), 0.5)
	var best := Vector2.INF
	var best_err := INF
	for s in found:
		var p := Vector2(s.x, s.y)
		var rel := p - from
		if rel.dot(dir) <= 0.0:
			continue
		var err := absf(rel.length() - metres)
		if err < best_err:
			best_err = err
			best = p
	return best


## N4: the rendered atmosphere. Glade frame (contrast, trunk against the mist, ground, moonbeam),
## the ground from close, and a STORM gate 30 m down the trail (cyan share and hue).
func _atmosphere_checks(run: RunGame, forest: ForestWorld, at: Vector2, along: Vector2) -> void:
	var player := run.player as DesktopPlayer
	var cam: Camera3D = player.camera
	var yaw: float = atan2(-along.x, -along.y)
	var glade_ground: Vector3 = Vector3(at.x, forest.height_at(at.x, at.y), at.y)
	# Frozen weather: no lightning strike may light the frame (its timer runs on real time).
	var lightning := run.get_node_or_null("Arena/StormLightning")
	if lightning:
		lightning.process_mode = Node.PROCESS_MODE_DISABLED
		lightning.set("_strike_age", -1.0)
		lightning.call("_set_flash", 0.0)
	var glade: Image = await _grab(player, glade_ground, yaw, -8.0)
	_save(glade, "n4_glade")

	var rms: float = AtmosphereMetrics.rms_contrast(glade)
	_check("N4 glade frame has contrast: RMS %.2f, need >= %.2f" % [rms, RMS_MIN], rms >= RMS_MIN)
	var ground: float = AtmosphereMetrics.ground_mean(glade, cam, forest, [4.0, 6.0, 8.0, 10.0, 12.0], [-3.2, -2.4, 2.4, 3.2])
	print("MEASURE glade ground=%.3f" % ground)
	_check("N4 ground beside the trail is neither black nor washed out (%.3f, need %.2f..%.2f)" % [ground, GROUND_GLADE_MIN, GROUND_GLADE_MAX],
		ground >= GROUND_GLADE_MIN and ground <= GROUND_GLADE_MAX)
	# Trunks against the mist: the frame 20 m down the trail, looking along it (the trees stand beside the path).
	var walk_xz: Vector2 = _trail_point(forest, at, along, 20.0)
	if walk_xz != Vector2.INF:
		var walk_dir: Vector2 = _trail_direction(forest, walk_xz)
		var walk: Image = await _grab(player, Vector3(walk_xz.x, forest.height_at(walk_xz.x, walk_xz.y), walk_xz.y), atan2(-walk_dir.x, -walk_dir.y), -8.0)
		_save(walk, "n4_walk20")
		var trunk: float = AtmosphereMetrics.trunk_contrast(walk, player.camera, forest)
		# Informational only (not a pass/fail check yet): the sampled "mist" points often land on the
		# dark ground behind the trunk, so this number does not yet measure trunk-against-mist (docs/n4/README.md).
		print("MEASURE trunk 8-20m diff=%.3f (informational, threshold %.3f not enforced)" % [trunk, TRUNK_DIFF_MIN])
	# Layers (N4 fix1): the floor at 8, 20 and 40 m from the glade camera gets lighter with distance
	# (mist between the trunks), not one flat wall. Measured here, asserted once the numbers are known.
	var lay := [-6.0, -3.2, 3.2, 6.0]
	var l8: float = AtmosphereMetrics.ground_mean(glade, cam, forest, [8.0], lay)
	var l20: float = AtmosphereMetrics.ground_mean(glade, cam, forest, [20.0], lay)
	var l40: float = AtmosphereMetrics.ground_mean(glade, cam, forest, [40.0], lay)
	print("MEASURE layers floor 8m=%.3f 20m=%.3f 40m=%.3f" % [l8, l20, l40])
	_check("N4 layers: the floor lightens from 8 m to 20 m (%.3f < %.3f)" % [l8, l20],
		l8 >= 0.0 and l20 >= 0.0 and l8 < l20)
	# 40 m is informational: the hills (4.6 m amplitude) often hide that patch behind a dark slope.
	print("MEASURE layers 40m=%.3f (informational, not asserted: terrain occlusion)" % l40)
	var sh: Dictionary = AtmosphereMetrics.shaft(glade)
	print("MEASURE glade shaft excess=%.3f width=%.3f" % [sh.excess, sh.width])
	_check("N4 no moonbeam column across the sky (width %.3f, need <= %.2f)" % [sh.width, SHAFT_WIDTH_MAX],
		float(sh.width) <= SHAFT_WIDTH_MAX)
	_check("N4 moonbeam peak stays soft (excess %.3f, need <= %.2f)" % [sh.excess, SHAFT_PEAK_MAX],
		float(sh.excess) <= SHAFT_PEAK_MAX)

	var far_xz: Vector2 = _trail_point(forest, at, along, 20.0)
	if far_xz != Vector2.INF:
		var far_dir: Vector2 = _trail_direction(forest, far_xz)
		var near_yaw: float = atan2(-far_dir.y, -far_dir.x)
		var near: Image = await _grab(player, Vector3(far_xz.x, forest.height_at(far_xz.x, far_xz.y), far_xz.y), near_yaw, -30.0)
		var near_ground: float = AtmosphereMetrics.ground_mean(near, player.camera, forest, [3.0, 4.0, 5.0, 6.0], [-2.4, 2.4])
		print("MEASURE near ground=%.3f" % near_ground)
		_check("N4 ground from close is readable (%.3f, need >= %.3f)" % [near_ground, GROUND_NEAR_MIN], near_ground >= GROUND_NEAR_MIN)

	# A STORM (cyan) gate 30 m down the trail; no other gate in the frame.
	var far30: Vector2 = _trail_point(forest, at, along, 30.0)
	if far30 == Vector2.INF:
		_check("N4 trail runs 30 m from the spawn for the torii shot", false)
		return
	forest.torii_manager.clear_gates()
	var side: Vector2 = Vector2(-along.y, along.x)
	var gate_xz: Vector2 = far30 + side * 3.0
	var gate: Node3D = forest.torii_manager.spawn_gate_at(gate_xz.x, gate_xz.y, Elements.STORM)
	await get_tree().process_frame
	var gate_pos: Vector3 = gate.global_position
	var to_gate: Vector3 = gate_pos - Vector3(at.x, 0.0, at.y)
	var torii: Image = await _grab(player, glade_ground, atan2(-to_gate.x, -to_gate.z), -2.0)
	_save(torii, "n4_torii30")
	var cyan: float = AtmosphereMetrics.cyan_share(torii, player.camera, gate_pos)
	_check("N4 the torii glows cyan (share %.3f, need >= %.3f)" % [cyan, TORII_CYAN_MIN], cyan >= TORII_CYAN_MIN)
	var g: Color = AtmosphereMetrics.patch_color(torii, player.camera, gate_pos + Vector3.UP * 3.0, 3)
	var f: Color = AtmosphereMetrics.patch_color(torii, player.camera, gate_pos + Vector3.UP * 3.0 + player.camera.global_transform.basis.x * 3.0, 3)
	var gap: float = AtmosphereMetrics.hue_gap(g, f) if g.r >= 0.0 and f.r >= 0.0 else -1.0
	print("MEASURE torii hue gap=%.1f" % gap)
	_check("N4 the gate glow has its own hue against the mist (gap %.1f deg, need >= %.1f)" % [gap, TORII_HUE_GAP_MIN],
		gap >= TORII_HUE_GAP_MIN)
	forest.torii_manager.clear_gates()


## Looks from [param ground] (world, on the ground) with the given yaw and pitch and returns the frame.
func _grab(player: DesktopPlayer, ground: Vector3, yaw: float, pitch_deg: float) -> Image:
	player.teleport(ground + Vector3.UP * 0.2, yaw)
	player.camera.rotation.x = deg_to_rad(pitch_deg)
	for _k in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img.is_compressed():
		img.decompress()
	return img


## Keeps the frames the checks read, for a look after a failure (DEBUG_DIR).
func _save(img: Image, name: String) -> void:
	img.save_png(DEBUG_DIR.path_join("%s.png" % name))


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

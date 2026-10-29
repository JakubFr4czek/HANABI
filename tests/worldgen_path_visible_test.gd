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


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

extends Node
## N7 pixel checks on the real run scene (windowed; headless reports SKIP). The 3-minute demo
## profile plays on the real forest with the stand-in player (N7PacingSim); the camera is turned
## by the test at the moments that matter, and the pictures are measured pixel by pixel:
##  a) first contact: the nearest yōkai is in the picture (silhouette pixels >= MIN_SILHOUETTE_PX);
##  b) peak wave (the 9th wave, PEAK): turned to the pack, at least MIN_YOKAI_IN_PEAK silhouettes;
##  c) the same peak turned to a random direction (reported, not a threshold);
##  d) the Oni is in the picture (silhouette pixels >= MIN_ONI_PX).
## A silhouette is measured as the pixels of the yōkai's screen box that differ between the frame
## with it and the same frame with every yōkai hidden. --shots DIR saves the review set (docs/n7)
## and the enemy count chart from the simulation data.
##   godot --path . --fixed-fps 90 res://tests/n7_pacing_visual_test.tscn -- --desktop --shots /abs/dir

const RUN_SCENE := preload("res://scenes/run.tscn")
const DEMO_PROFILE := "res://data/waves/demo.tres"
const PLAY_SECONDS := 260.0
const T_START := 5.0
## The first sight is looked for every second from here to T_CONTACT_END: the first yōkai at 6–12 m
## that the camera can see (a yōkai behind a trunk is not a picture).
const T_CONTACT_START := 20.0
const T_CONTACT_END := 120.0
## The peak is looked for every 2 s from here to T_PEAK_END. The demo's PEAK waves are 3, 6, 9: the
## 6th wave (min 2–3, with the Oni) opens at 145–175 s in the stand-in runs; the exact time moves
## with the world, so the window is wide.
const T_PEAK_START := 150.0
const T_PEAK_END := 260.0
const MIN_PEAK_YOKAI_ALIVE := 4
## The Oni is placed on the first PEAK after 120 s (wave 6: ~145 s in the stand-in run, but the world
## moves the peaks); it is looked for every 2 s from T_ONI_START to T_ONI_END.
const T_ONI_START := 120.0
const T_ONI_END := 420.0
const MIN_YOKAI_IN_PEAK := 3
const MIN_SILHOUETTE_PX := 120
## First sight: the first yōkai the camera sees at 6–12 m. In the demo's dark forest it is small
## (~10 px of silhouette at 8 m); the bar is a few pixels of change, not a full figure.
const MIN_FIRST_SIGHT_PX := 8
const MIN_ONI_PX := 300
## Luminance change (0..1) that counts as a silhouette pixel.
const LUM_DIFF := 0.05
const SEED := 7

var out_dir := ""
var failures := 0
var _run: RunGame
var _sim: N7PacingSim
var _contact_done := false
var _peak_done := false
var _oni_done := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  N7 pixel checks need a window (run windowed, see docs/n7)")
		get_tree().quit(0)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
		DirAccess.make_dir_recursive_absolute(out_dir)
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	_run = RUN_SCENE.instantiate()
	_run.skip_run_intro = true
	add_child(_run)
	for i in 20:
		await get_tree().process_frame
	_run.set_physics_process(false)
	_run.wave_director.profile = load(DEMO_PROFILE) as WaveProfile
	_sim = N7PacingSim.new()
	_sim.pauses = [[T_START, Callable(self, "_shot_start")]]
	var t := T_CONTACT_START
	while t <= T_CONTACT_END:
		_sim.pauses.append([t, Callable(self, "_probe_first_contact")])
		t += 1.0
	t = T_ONI_START
	while t <= T_ONI_END:
		_sim.pauses.append([t, Callable(self, "_probe_oni")])
		t += 2.0
	t = T_PEAK_START
	while t <= T_PEAK_END:
		_sim.pauses.append([t, Callable(self, "_probe_peak")])
		t += 2.0
	# The sim pops its pauses from the front: they must be in time order (the probes overlap).
	_sim.pauses.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	await _sim.play(get_tree(), _run, _run.wave_director, PLAY_SECONDS, SEED, false)
	_check("First contact: a yōkai in the picture was found between %.0f and %.0f s" % [T_CONTACT_START, T_CONTACT_END], _contact_done)
	_check("Oni: the Oni was found in the picture between %.0f and %.0f s" % [T_ONI_START, T_ONI_END], _oni_done)
	_check("Peak: a PEAK wave with >= %d yōkai alive and >= %d silhouettes turned to the pack was found between %.0f and %.0f s" % [
		MIN_PEAK_YOKAI_ALIVE, MIN_YOKAI_IN_PEAK, T_PEAK_START, T_PEAK_END], _peak_done)
	for w in _sim.wave_opens:
		print("INFO  wave %d opens at %.1f s (%s)" % [w.wave, w.t, w.state])
	if out_dir != "":
		N7Chart.write_png([{"samples": _sim.samples}], out_dir.path_join("enemies_over_time.png"))
		print("saved enemies_over_time")


func _shot_start(_t: float) -> void:
	_aim(Vector3(0.0, 1.2, -10.0))
	var res := await _measure(0.0)
	_save(res.on, "1_start")
	_check("Start: the calm opening, no yōkai in the picture yet (%d silhouette pixels)" % res.total_px,
		res.yokai_count == 0)


func _probe_first_contact(_t: float) -> void:
	if _contact_done:
		return
	var cam := _player().camera
	var near: Array[Yokai] = []
	for y in _wave_yokai():
		var d := y.root_part().global_position.distance_to(cam.global_position)
		if d >= 6.0 and d <= 12.0:
			near.append(y)
	near.sort_custom(func(a: Yokai, b: Yokai) -> bool:
		return a.root_part().global_position.distance_squared_to(cam.global_position) < b.root_part().global_position.distance_squared_to(cam.global_position))
	for y in near:
		var pos := y.root_part().global_position
		_aim(pos + Vector3(0.0, 1.0, 0.0))
		var res := await _measure(0.0)
		print("INFO  contact probe %.0f s: yōkai %.1f m away, %d silhouette pixels" % [_t, pos.distance_to(cam.global_position), res.nearest_px])
		if res.nearest_px >= MIN_FIRST_SIGHT_PX:
			_save(res.on, "2_first_contact")
			_check("First contact at %.0f s: the yōkai %.1f m away is in the picture (%d silhouette pixels, need %d)" % [
				_t, pos.distance_to(cam.global_position), res.nearest_px, MIN_FIRST_SIGHT_PX], true)
			_contact_done = true
			return


func _probe_peak(_t: float) -> void:
	if _peak_done:
		return
	var pl := _director()._planner
	print("INFO  probe %.0f s: state=%s wave=%d alive=%d cap=%d credits=%.1f open=%s skipped=%d" % [_t,
		WavePlanner.STATE_NAMES[pl.state], pl.wave, _wave_yokai().size(), _director().concurrent_cap(),
		pl.credits, str(pl.wave_open), _director().spawn_stats.skipped])
	if pl.state != WavePlanner.State.PEAK:
		return
	var pack := _wave_yokai()
	if pack.size() < MIN_PEAK_YOKAI_ALIVE:
		return
	var centre := Vector3.ZERO
	for y in pack:
		centre += y.root_part().global_position
	centre /= float(pack.size())
	_aim(centre + Vector3(0.0, 1.0, 0.0))
	var res := await _measure(0.0)
	var dists := ""
	for y in pack:
		dists += " %.1f" % y.root_part().global_position.distance_to(_player().camera.global_position)
	print("INFO  peak probe %.0f s: %d alive (distances%s), %d silhouettes in the picture" % [_t, pack.size(), dists, res.yokai_count])
	if res.yokai_count < MIN_YOKAI_IN_PEAK:
		return
	_save(res.on, "3_peak_pack")
	_check("Peak wave %d at %.0f s turned to the pack: %d yōkai alive, %d silhouettes in the picture (need %d)" % [
		_director().wave, _t, pack.size(), res.yokai_count, MIN_YOKAI_IN_PEAK], true)
	_peak_done = true
	await _shot_peak_random(_t)


func _shot_peak_random(_t: float) -> void:
	var yaw := 1.9
	var cam := _player().camera
	cam.look_at(cam.global_position + Vector3(sin(yaw), -0.05, -cos(yaw)) * 10.0, Vector3.UP)
	var res := await _measure(0.0)
	_save(res.on, "4_peak_random")
	print("INFO  peak, random direction: %d silhouettes in the picture" % res.yokai_count)


func _probe_oni(_t: float) -> void:
	if _oni_done:
		return
	var oni := _director().get_active_oni()
	if oni == null:
		return
	_aim(oni.global_position + Vector3(0.0, 1.2, 0.0))
	var res := await _measure(2.4)
	var oni_px: int = res.px[res.targets.find(oni)]
	if oni_px < MIN_ONI_PX:
		return
	_save(res.on, "5_oni")
	_check("Oni at %.0f s is in the picture (%d silhouette pixels, need %d)" % [_t, oni_px, MIN_ONI_PX], true)
	_oni_done = true


## Grabs the picture with the yōkai shown, then with every live yōkai and the Oni hidden.
## yokai_count: yōkai whose screen box has at least MIN_SILHOUETTE_PX silhouette pixels;
## nearest_px: silhouette pixels of the body nearest the picture centre (the one aimed at);
## px / targets: silhouette pixels per body. [param oni_height] is the Oni's height (2.4 m).
func _measure(oni_height: float) -> Dictionary:
	var targets: Array = []
	for y in _director().alive_enemies():
		targets.append(y)
	var oni := _director().get_active_oni()
	if oni != null:
		targets.append(oni)
	# The world is frozen while the two frames are taken: rain, orbs and particles would otherwise
	# change between the frames and read as silhouettes. Only the visibility of the bodies differs.
	var time_scale := Engine.time_scale
	Engine.time_scale = 0.0
	await _frames(3)
	var on := await _grab()
	for t in targets:
		t.visible = false
	await _frames(3)
	var off := await _grab()
	for t in targets:
		t.visible = true
	Engine.time_scale = time_scale
	var cam := _player().camera
	var counts: Array[int] = []
	var total := 0
	var nearest_px := 0
	for t in targets:
		var height := oni_height if t == oni else 1.7
		var px := _box_diff(cam, on, off, (t as Node3D).global_position, height)
		counts.append(px)
		total += px
	var yokai_count := 0
	for i in targets.size():
		if targets[i] != oni and counts[i] >= MIN_SILHOUETTE_PX:
			yokai_count += 1
	# The aimed target is the one nearest the picture centre: its own count is what the shot shows.
	var centre := Vector2(on.get_width(), on.get_height()) * 0.5
	var best_d := INF
	for i in targets.size():
		var pos: Vector3 = (targets[i] as Node3D).global_position
		if cam.is_position_behind(pos):
			continue
		var d := cam.unproject_position(pos + Vector3(0.0, 1.0, 0.0)).distance_to(centre)
		if d < best_d:
			best_d = d
			nearest_px = counts[i]
	return {"on": on, "yokai_count": yokai_count, "nearest_px": nearest_px, "total_px": total,
		"targets": targets, "px": counts}


## Silhouette pixels of one body: the pixels of its screen box that differ between the two frames.
func _box_diff(cam: Camera3D, on: Image, off: Image, pos: Vector3, height: float) -> int:
	if cam.is_position_behind(pos):
		return 0
	var a := cam.unproject_position(pos + Vector3(0.0, 0.1, 0.0))
	var b := cam.unproject_position(pos + Vector3(0.0, height, 0.0))
	var side := cam.unproject_position(pos + Vector3(0.4, 0.9, 0.0)).x - cam.unproject_position(pos + Vector3(-0.4, 0.9, 0.0)).x
	var half := absf(side) * 0.5
	var box := Rect2(minf(a.x, b.x) - half, minf(a.y, b.y), 2.0 * half + absf(b.x - a.x), absf(b.y - a.y))
	var screen := Rect2(Vector2.ZERO, Vector2(on.get_width(), on.get_height()))
	box = box.intersection(screen)
	var px := 0
	for y in range(int(box.position.y), int(box.end.y)):
		for x in range(int(box.position.x), int(box.end.x)):
			if absf(_lum(on.get_pixel(x, y)) - _lum(off.get_pixel(x, y))) > LUM_DIFF:
				px += 1
	return px


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _aim(target: Vector3) -> void:
	var cam := _player().camera
	cam.look_at(target, Vector3.UP)


func _save(img: Image, name: String) -> void:
	if out_dir != "":
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _player() -> DesktopPlayer:
	return _run.player as DesktopPlayer


func _director() -> WaveDirector:
	return _run.wave_director


func _wave_yokai() -> Array[Yokai]:
	var out: Array[Yokai] = []
	for y in _director().alive_enemies():
		if y.guard_post == 0:
			out.append(y)
	return out


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

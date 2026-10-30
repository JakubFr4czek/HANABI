extends Node
## D18 visual check on the real run scene (run.tscn): a far burst lifts the mist and
## the sky above the trees, a near one lifts it more, and neither is sharp or dazzling.
## The numbers come from the rain-free pass; the rain-on pass is only saved for judging.
## Pixels need a window, so headless prints SKIP (run_tests.sh counts it as skipped).
##   godot --path . --fixed-fps 90 res://tests/d18_fireworks_visual_test.tscn -- --desktop --shots /tmp/hanabi_d18
## Writes 00/01/02 (rain off) and *_rain (rain on) PNGs: no burst, far burst, near burst.

const RUN_SCENE := preload("res://scenes/run.tscn")
## Largest lift of the burst over the area (0..1 luminance): a visible glow in the mist.
const MIN_LIFT := 0.03
## Peak luminance over the area: a glow, not a flash.
const MAX_PEAK := 0.92
## Share of the area above 0.8 luminance: no blown-out patch.
const MAX_BRIGHT_SHARE := 0.02
## Largest luminance step between neighbouring pixels of the lift: a soft bloom, not an edge.
const MAX_EDGE_STEP := 0.05
## Luminance change between neighbours of the unlit frame below which it counts as sky.
const SMOOTH_UNLIT := 0.02
const AREA_RADIUS := 110
const PEAK_AFTER := 0.5

var out_dir := "/tmp/hanabi_d18"
var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  pixel checks need a window (run without --headless)")
		get_tree().quit(0)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://d18_shots_save.cfg"
	add_child(run)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var fw := run.distant_fireworks
	fw.set_enabled(false)
	# The storm's own bolts would flash the whole frame and fake the lift: no strikes here.
	var storm := run.get_node_or_null("Arena/StormLightning") as StormLightning
	if storm:
		storm.set_process(false)
		storm.visible = false
		storm._set_flash(0.0)
	var player := run.player as Node3D
	var forward := -player.global_basis.z
	forward.y = 0.0
	var ahead := atan2(forward.normalized().x, -forward.normalized().z)
	var cam := get_viewport().get_camera_3d()
	await _frames(60)

	# Pass 1 (rain off, so drifting drops cannot fake the numbers): measured.
	# Pass 2 (rain on): the same moments, saved for judging the look.
	# Every particle emitter in the run is rain or petals or sparks: the measured pass
	# hides all of them but the burst's own sparks, which are controlled per frame.
	var emitters: Array[Node] = []
	for n in run.find_children("*", "GPUParticles3D", true, false):
		if not fw.is_ancestor_of(n):
			emitters.append(n)
	for rain_on in [false, true]:
		for n in emitters:
			(n as Node3D).visible = rain_on
		var tag := "_rain" if rain_on else ""
		# Left of the trunk, over the open sky above the mist (the trunk hides the right side).
		var far := fw.fire(DistantFireworks.Kind.FAR, true, ahead - 0.12)
		var far_pair := await _lit_and_unlit(fw, cam, player, far)
		await _save(far_pair.lit, "01_far_burst_in_mist" + tag)
		await _save(far_pair.unlit, "00_same_frame_no_burst" + tag)
		await _frames(int(2.6 * 90.0))
		var near := fw.fire(DistantFireworks.Kind.NEAR, true, ahead - 0.30)
		var near_pair := await _lit_and_unlit(fw, cam, player, near)
		await _save(near_pair.lit, "02_near_burst_behind_trees" + tag)
		await _frames(int(2.6 * 90.0))
		if not rain_on:
			var far_stats := _measure(far_pair.unlit, far_pair.lit, far_pair.glow_only, _screen_point(cam, player, far))
			var near_stats := _measure(near_pair.unlit, near_pair.lit, near_pair.glow_only, _screen_point(cam, player, near))
			_report("far burst lifts the mist above the trees (lift %.3f)" % far_stats.lift, far_stats.lift >= MIN_LIFT)
			_report("far burst is not dazzling (peak %.2f, bright share %.3f)" % [far_stats.peak, far_stats.bright], far_stats.peak <= MAX_PEAK and far_stats.bright <= MAX_BRIGHT_SHARE)
			_report("far burst has no hard edge (largest step %.3f)" % far_stats.edge, far_stats.edge <= MAX_EDGE_STEP)
			_report("near burst lifts more than the far one, glow alone (%.3f vs %.3f)" % [near_stats.glow_lift, far_stats.glow_lift], near_stats.glow_lift > far_stats.glow_lift)
			_report("near burst is not dazzling (peak %.2f, bright share %.3f)" % [near_stats.peak, near_stats.bright], near_stats.peak <= MAX_PEAK and near_stats.bright <= MAX_BRIGHT_SHARE)
			_report("near burst has no hard edge (largest step %.3f)" % near_stats.edge, near_stats.edge <= MAX_EDGE_STEP)
	run.queue_free()
	await _frames(2)


## Freezes the burst at its peak and grabs three frames of the same moment: the
## burst lit, the same frame with its sparks hidden (the glow alone), and the frame
## with the whole burst hidden. Same geometry in all three, so anything that moved
## in the forest cannot fake the lift. The sparks are points by design, so the
## hard-edge check uses the glow alone.
func _lit_and_unlit(fw: DistantFireworks, cam: Camera3D, player: Node3D, info: Dictionary) -> Dictionary:
	await _frames(int(PEAK_AFTER * 90.0))
	fw.process_mode = Node.PROCESS_MODE_DISABLED
	var glows: Array[Node] = fw.find_children("Glow*", "MeshInstance3D", false, false)
	var sparks: Array[Node] = fw.find_children("Sparks", "GPUParticles3D", false, false)
	var lit := await _grab()
	for n in sparks:
		(n as Node3D).visible = false
	var glow_only := await _grab()
	for n in glows:
		(n as Node3D).visible = false
	var unlit := await _grab()
	for n in glows:
		(n as Node3D).visible = true
	for n in sparks:
		(n as Node3D).visible = true
	fw.process_mode = Node.PROCESS_MODE_PAUSABLE
	return {"lit": lit, "glow_only": glow_only, "unlit": unlit}


## Screen position of a burst. Its centre sits at distance and height from the player.
func _screen_point(cam: Camera3D, player: Node3D, info: Dictionary) -> Vector2:
	var dir := Vector3(sin(float(info.azimuth)), 0.0, -cos(float(info.azimuth)))
	var at := player.global_position + dir * float(info.dist) + Vector3(0.0, float(info.height), 0.0)
	return cam.unproject_position(at)


## Largest lift, peak, bright share and largest edge step of the glow over a square
## around the burst. Edge: the step in the glow alone (sparks hidden), where the unlit
## frame is smooth, so geometry in front of the burst does not count.
func _measure(base: Image, lit: Image, glow_only: Image, centre: Vector2) -> Dictionary:
	var x0 := int(centre.x) - AREA_RADIUS
	var y0 := int(centre.y) - AREA_RADIUS
	var lift := 0.0
	var glow_lift := 0.0
	var peak := 0.0
	var bright := 0
	var edge := 0.0
	var n := 0
	var w := lit.get_width()
	var h := lit.get_height()
	for y in range(maxi(y0, 0), mini(y0 + 2 * AREA_RADIUS, h - 1)):
		for x in range(maxi(x0, 0), mini(x0 + 2 * AREA_RADIUS, w - 1)):
			var l := lit.get_pixel(x, y).get_luminance()
			var b := base.get_pixel(x, y).get_luminance()
			var d := l - b
			lift = maxf(lift, d)
			glow_lift = maxf(glow_lift, glow_only.get_pixel(x, y).get_luminance() - b)
			peak = maxf(peak, l)
			if l > 0.8:
				bright += 1
			var right_base := base.get_pixel(x + 1, y).get_luminance()
			var right_glow := glow_only.get_pixel(x + 1, y).get_luminance() - right_base
			var glow_d := glow_only.get_pixel(x, y).get_luminance() - b
			if absf(right_base - b) < SMOOTH_UNLIT:
				edge = maxf(edge, absf(glow_d - right_glow))
			n += 1
	return {"lift": lift, "glow_lift": glow_lift, "peak": peak, "bright": float(bright) / maxf(n, 1), "edge": edge}


func _report(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _grab() -> Image:
	await _frames(2)
	return get_viewport().get_texture().get_image()


func _save(img: Image, name: String) -> void:
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)


func _frames(count: int) -> void:
	for _k in count:
		await get_tree().physics_frame

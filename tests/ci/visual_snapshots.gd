extends Node
## CI: in-game screenshots from fixed camera positions of the real run scene and
## a performance sample on a fixed view, for run-to-run comparison.
## Shots (same placement as tools/worldgen/game_path_screenshots.gd, D8):
##   spawn        - from the PlayerSpawn, looking down the trail
##   path_20m     - 20 m along the trail
##   shrine       - 4 m from the nearest shrine, looking at it
##   spawn_back   - from the spawn, looking the other way
## Perf: 120 frames on the spawn view: draw calls, primitives (RenderingServer),
## process/physics ms (Performance), FPS and RunPerfProbe's scene cost estimate.
##   godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 960x540 \
##     res://tests/ci/visual_snapshots.tscn -- --desktop --out=/tmp/hanabi_shots
## Writes <out>/shots/*.png and <out>/perf.json. Exit 1 only when the scene could not be set up.

const RUN_SCENE_PATH := "res://scenes/run.tscn"
const PERF_FRAMES := 120
const PROBE_PATH := "res://src/run/run_perf_probe.gd"

var out_dir := "/tmp/hanabi_shots"
var run: Node = null
var player: Node3D = null
var forest: Node = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("shots"))
	var ok := await _run_all()
	print("\n%s" % ("ALL PASSED" if ok else "FAILURES (setup)"))
	get_tree().quit(0 if ok else 1)


func _run_all() -> bool:
	var scene: PackedScene = load(RUN_SCENE_PATH)
	run = scene.instantiate()
	if "skip_run_intro" in run:
		run.set("skip_run_intro", true)
	add_child(run)
	await _frames(30)
	var wd: Node = run.get("wave_director")
	if wd and wd.has_method("stop_director"):
		wd.stop_director()
	if wd and wd.has_method("clear_enemies"):
		wd.clear_enemies()
	player = run.get("player")
	forest = run.get("forest_world")
	if player == null or not player.has_method("teleport") or forest == null:
		print("SNAP FAIL needs the desktop player and the forest (run with -- --desktop)")
		return false
	var spawn := run.find_child("PlayerSpawn", true, false) as Node3D
	var at := spawn.global_position if spawn else player.global_position
	var along := _direction_at(Vector2(at.x, at.z))
	var yaw := atan2(-along.x, -along.y)
	await _place(at, yaw, -8.0)
	await _shot("spawn")
	var perf := await _sample_perf()
	await _place(at, yaw + PI, -8.0)
	await _shot("spawn_back")
	var far := _point_along(Vector2(at.x, at.z), 20.0)
	if far != Vector2.INF:
		var d := _direction_at(far)
		await _place(Vector3(far.x, float(forest.height_at(far.x, far.y)), far.y), atan2(-d.x, -d.y), -8.0)
		await _shot("path_20m")
	var shrine := _nearest_shrine(at)
	if shrine:
		var sp := shrine.global_position
		var from := sp + (at - sp).normalized() * 4.0
		from.y = float(forest.height_at(from.x, from.z))
		var to := sp - from
		await _place(from, atan2(-to.x, -to.z), -10.0)
		await _shot("shrine")
	else:
		print("SNAP note: no shrine spawned near the start; shrine shot skipped")
	var f := FileAccess.open(out_dir.path_join("perf.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(perf, "  "))
	print("PERF %s" % JSON.stringify(perf))
	return true


func _place(p: Vector3, yaw: float, pitch_deg: float) -> void:
	player.teleport(p + Vector3.UP * 0.2, yaw)
	var cam := player.get("camera") as Camera3D
	if cam:
		cam.rotation.x = deg_to_rad(pitch_deg)
	await _frames(60)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.is_compressed():
		img.decompress()
	img.save_png(out_dir.path_join("shots").path_join(name + ".png"))
	print("SHOT %s" % name)


func _sample_perf() -> Dictionary:
	var draws: Array[float] = []
	var prims: Array[float] = []
	var proc_ms: Array[float] = []
	var phys_ms: Array[float] = []
	var frame_ms: Array[float] = []
	var last := Time.get_ticks_usec()
	for k in PERF_FRAMES:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		draws.append(
			float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		)
		prims.append(
			float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		)
		proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var out := {
		"draw_calls": {"mean": _mean(draws), "max": draws.max()},
		"primitives": {"mean": _mean(prims), "max": prims.max()},
		"frame_ms": {"mean": _mean(frame_ms), "p95": _p95(frame_ms)},
		"process_ms": {"mean": _mean(proc_ms), "p95": _p95(proc_ms)},
		"physics_ms": {"mean": _mean(phys_ms), "p95": _p95(phys_ms)},
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
	}
	if ResourceLoader.exists(PROBE_PATH):
		var probe: Script = load(PROBE_PATH)
		if probe and probe.has_method("estimate_scene_cost"):
			out["scene_estimate"] = probe.call("estimate_scene_cost", run)
	return out


func _direction_at(p: Vector2) -> Vector2:
	var paths: Object = forest.get("paths")
	if paths == null:
		return Vector2(0.0, -1.0)
	var found: Array = paths.samples_in_rect(Rect2(p - Vector2(40.0, 40.0), Vector2(80.0, 80.0)), 1.0)
	var best := Vector2.ZERO
	var best_d := INF
	for s in found:
		var d := Vector2(s.x, s.y).distance_to(p)
		if d < best_d:
			best_d = d
			best = Vector2(s.z, s.w)
	return best if best != Vector2.ZERO else Vector2(0.0, -1.0)


func _point_along(from: Vector2, metres: float) -> Vector2:
	var paths: Object = forest.get("paths")
	if paths == null:
		return Vector2.INF
	var found: Array = paths.samples_in_rect(Rect2(from - Vector2(60.0, 60.0), Vector2(120.0, 120.0)), 1.0)
	var best := Vector2.INF
	var best_err := INF
	for s in found:
		var p := Vector2(s.x, s.y)
		var err := absf(p.distance_to(from) - metres)
		if err < best_err:
			best_err = err
			best = p
	return best


func _nearest_shrine(at: Vector3) -> Node3D:
	var hm: Node = run.get("hokora_manager")
	if hm == null or not hm.has_method("alive_shrines"):
		return null
	var best: Node3D = null
	var best_d := INF
	for s in hm.alive_shrines():
		var d := (s as Node3D).global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = s
	return best


static func _mean(a: Array[float]) -> float:
	var s := 0.0
	for v in a:
		s += v
	return snappedf(s / maxf(1.0, a.size()), 0.01)


static func _p95(a: Array[float]) -> float:
	var b := a.duplicate()
	b.sort()
	return snappedf(b[int(clampf(0.95 * (b.size() - 1), 0, b.size() - 1))], 0.01) if not b.is_empty() else 0.0


func _frames(count: int) -> void:
	for k in count:
		await get_tree().process_frame

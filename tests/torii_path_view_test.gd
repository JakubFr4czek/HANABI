extends Node
## F2 visual check (windowed; SKIP headless). The camera stands on a straight footpath, looking along
## it toward a decorative gate that stands on the path. The gate's passage centre must sit near the
## middle of the frame, and the frame is written out for a look before and after the change.
##   xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 960x540 res://tests/torii_path_view_test.tscn -- --out docs/f2/post_path_view.png
## The camera is chosen from the footpath, not from a gate, so the same camera can be reused for a
## "before" run on an older checkout (see docs/f2/README.md).

const RUN_SCENE := preload("res://scenes/run.tscn")
## Passage centre within this fraction of the frame width from the middle column.
const CENTRE_TOLERANCE := 0.12
const VIEW_DISTANCE := 14.0

var failures := 0
var out_path := "/tmp/hanabi_f2_path_view.png"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  F2 path view needs a window (run windowed, see the header)")
		get_tree().quit(0)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_path = args[i + 1]
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(20)

	var forest := run.forest_world
	var player := run.player as DesktopPlayer
	_check("The run has a DesktopPlayer and a forest with footpaths", player != null and forest != null and forest.paths != null)
	if player == null or forest == null or forest.paths == null:
		run.queue_free()
		return

	# The gate: the decorative gate nearest the origin that stands on a footpath (centre within 0.3 m
	# of the rendered line). The view starts VIEW_DISTANCE metres behind it, along the path.
	var gate := _pick_gate(forest)
	_check("A decorative gate stands on a footpath near the glade", gate != Vector3.INF)
	if gate == Vector3.INF:
		run.queue_free()
		return
	var tangent := _tangent_at(forest, Vector2(gate.x, gate.z))
	var eye_xz := Vector2(gate.x, gate.z) - tangent * VIEW_DISTANCE
	var ground := Vector3(eye_xz.x, forest.height_at(eye_xz.x, eye_xz.y), eye_xz.y)
	var yaw := atan2(-tangent.x, -tangent.y)
	player.teleport(ground + Vector3.UP * 0.2, yaw)
	player.camera.rotation.x = deg_to_rad(-4.0)
	await _frames(60)

	var cam := player.camera
	var size := get_viewport().get_visible_rect().size
	# Passage centre: the gate's middle, a little above the ground (the lintel is 3.1 m up).
	var centre := gate + Vector3.UP * 1.6
	var in_front := not cam.is_position_behind(centre)
	var px := cam.unproject_position(centre)
	var off := absf(px.x - size.x * 0.5) / size.x
	print("F2 view: gate=(%.2f, %.2f, %.2f) screen=(%.0f, %.0f) of %.0fx%.0f, offset %.3f of width" % [
		gate.x, gate.y, gate.z, px.x, px.y, size.x, size.y, off])
	_check("The gate's passage lies in front of the camera", in_front)
	_check("The gate's passage centre sits near the middle of the frame (offset %.3f of width)" % off,
		off <= CENTRE_TOLERANCE)

	var img: Image = get_viewport().get_texture().get_image()
	if img.is_compressed():
		img.decompress()
	var dir := out_path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(out_path)
	print("F2 frame written to %s" % out_path)
	run.queue_free()


## A decorative gate on the footpath (within 0.3 m of the rendered centre line), nearest the origin
## and at least VIEW_DISTANCE + 4 m from it along the path; Vector3.INF when there is none.
func _pick_gate(forest: ForestWorld) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for key in forest._chunks:
		var root: Node3D = forest._chunks[key]
		for g in root.get_meta("torii_world_positions", []):
			var gp: Vector3 = g
			var c := Vector2(gp.x, gp.z)
			var n := forest.paths.smooth_nearest(c, 0.3, ForestWorld.PATH_SIMPLIFY_TOL)
			if n == Vector4.ZERO:
				continue
			var d := c.length()
			if d < best_d and d > VIEW_DISTANCE + 4.0:
				# The gate must have a straight run behind it: the path 14 m back points the same way.
				var t := Vector2(n.z, n.w)
				var back := c - t * VIEW_DISTANCE
				var m := forest.paths.smooth_nearest(back, 0.3, ForestWorld.PATH_SIMPLIFY_TOL)
				if m == Vector4.ZERO or absf(t.dot(Vector2(m.z, m.w))) < 0.98:
					continue
				best_d = d
				best = gp
	return best


func _tangent_at(forest: ForestWorld, c: Vector2) -> Vector2:
	var n := forest.paths.smooth_nearest(c, 0.3, ForestWorld.PATH_SIMPLIFY_TOL)
	return Vector2(n.z, n.w)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

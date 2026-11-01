extends Node
## N5 pixel checks on the real run scene (windowed; headless reports SKIP):
##  a) the trail edge is a curve: the x of the gravel edge per picture row, its second difference
##     stays small (a stepped edge, like the 1 m lattice, jumps from row to row);
##  b) ferns are in the picture: green pixels by the trail edges (the cut-out cards);
##  c) the same views save as screenshots when --shots DIR is given (docs/n5/).
##   godot --path . --fixed-fps 90 res://tests/n5_forest_visual_test.tscn -- --shots /abs/dir

const RUN_SCENE := preload("res://scenes/run.tscn")
## Largest second difference of the trail-edge x between rows, pixels: a smooth edge stays well under it.
const MAX_EDGE_STEP_PX := 2.5
## Fern pixels (green cut-out cards) in the ground band of the edge view: at least this many.
const MIN_FERN_PIXELS := 150

var out_dir := ""
var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  N5 pixel checks need a window (run windowed, see docs/n5)")
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
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	var player := run.player as DesktopPlayer
	var forest := run.forest_world
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(20)
	forest.finish_pending()

	# Stand on the trail 9 m out from the glade, looking along it and down at the gravel.
	var along := _trail_point(forest, 9.0)
	var dir: Vector3 = along.dir
	var stand: Vector3 = along.pos - dir * 3.5
	_stand(player, forest, stand, dir)
	player.camera.look_at(along.pos + Vector3(0.0, -0.9, 0.0) + dir * 1.5, Vector3.UP)
	await _frames(30)
	var img := await _capture("n5_trail_edge_near")
	var edge := _edge_steps(img)
	print("MEASURE trail edge: rows %d, max second difference %.2f px, mean %.2f px" % [edge.rows, edge.max_step, edge.mean_step])
	_check("The trail edge is a curve, not steps (max second difference %.2f px, need <= %.1f)" % [edge.max_step, MAX_EDGE_STEP_PX],
		edge.rows >= 12 and edge.max_step <= MAX_EDGE_STEP_PX)
	# Ferns are in the picture when hiding their kind changes the ground band: the same frame, twice.
	var ferns_on := _fern_nodes(forest)
	for node in ferns_on:
		node.visible = false
	await _frames(3)
	var without := await _capture("n5_trail_edge_no_ferns")
	for node in ferns_on:
		node.visible = true
	await _frames(3)
	var fern_px := _changed_pixels(img, without)
	print("MEASURE fern pixels changed by showing the ferns (ground band): %d over %d fern nodes" % [fern_px, ferns_on.size()])
	_check("Ferns are in the picture beside the trail (%d pixels change when they are shown, need %d)" % [fern_px, MIN_FERN_PIXELS],
		ferns_on.size() > 0 and fern_px >= MIN_FERN_PIXELS)

	# A wider view down the trail: the same frame, for the review (no metric).
	player.camera.look_at(along.pos + Vector3(0.0, 1.2, 0.0) + dir * 12.0, Vector3.UP)
	await _frames(20)
	await _capture("n5_trail_wide")

	if out_dir != "":
		await _review_shots(run, forest, player)

	run.queue_free()
	await get_tree().process_frame


## The review set for docs/n5 (same cameras before and after): the glade in four directions, a gate
## 35 m out through the trunks, a sakura far off, and two frames across a chunk border.
func _review_shots(run: RunGame, forest: ForestWorld, player: DesktopPlayer) -> void:
	for k in 4:
		var yaw := TAU * float(k) / 4.0
		var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
		_stand(player, forest, Vector3(0.0, 0.0, 2.2), facing)
		player.camera.rotation.x = deg_to_rad(-4.0)
		await _frames(30)
		await _capture("n5_glade_dir%d" % k)
	var gate := _gate_at_distance(forest, 35.0)
	if gate != Vector3.INF:
		var gdir := Vector3(gate.x, 0.0, gate.z).normalized()
		var stand := Vector3(gate.x, 0.0, gate.z) - gdir * 35.0
		_stand(player, forest, stand, gdir)
		player.camera.look_at(gate + Vector3(0.0, 2.6, 0.0), Vector3.UP)
		await _frames(30)
		await _capture("n5_torii_35m")
	var sakura := forest.nearest_sakura_position(Vector3.ZERO)
	if sakura != Vector3.INF and Vector2(sakura.x, sakura.z).length() > 14.0:
		var sdir := Vector3(sakura.x, 0.0, sakura.z).normalized()
		_stand(player, forest, sakura - sdir * 24.0, sdir)
		player.camera.look_at(sakura + Vector3(0.0, 4.0, 0.0), Vector3.UP)
		await _frames(30)
		await _capture("n5_sakura_24m")
	var edge := forest.profile.chunk_size * 0.5
	for frame in 2:
		var x := edge - 0.8 if frame == 0 else edge + 0.6
		_stand(player, forest, Vector3(x, 0.0, 6.0), Vector3(1.0, 0.0, 0.0))
		player.camera.rotation.x = deg_to_rad(-3.0)
		await _frames(30 if frame == 0 else 2)
		await _capture("n5_border_frame_%s" % ("a" if frame == 0 else "b"))


func _gate_at_distance(forest: ForestWorld, metres: float) -> Vector3:
	for key in forest._chunks:
		for g in (forest._chunks[key] as Node3D).get_meta("torii_world_positions", []):
			var gv: Vector3 = g
			if absf(Vector2(gv.x, gv.z).length() - metres) < 2.0:
				return gv
	return Vector3.INF


## A path point about [param metres] from the spawn glade, with the trail's direction there.
func _trail_point(forest: ForestWorld, metres: float) -> Dictionary:
	var best := {"pos": Vector3.ZERO, "dir": Vector3(0.0, 0.0, -1.0)}
	var best_d := INF
	for s in forest.paths.samples_in_rect(Rect2(Vector2(-40.0, -40.0), Vector2(80.0, 80.0)), 1.0):
		var d := absf(Vector2(s.x, s.y).length() - metres)
		if d < best_d:
			best_d = d
			best.pos = Vector3(s.x, forest.height_at(s.x, s.y), s.y)
			best.dir = Vector3(s.z, 0.0, s.w).normalized()
	return best


func _stand(player: DesktopPlayer, forest: ForestWorld, at: Vector3, facing: Vector3) -> void:
	var yaw := atan2(-facing.x, -facing.z)
	player.teleport(Vector3(at.x, forest.height_at(at.x, at.z) + 0.2, at.z), yaw)


func _capture(name: String) -> Image:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if out_dir != "":
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)
	return img


## Edge of the gravel per picture row, in the ground band: the x where the luminance crosses halfway
## between the gravel (bright) and the duff (dark) of that row. Returns the second differences.
func _edge_steps(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var xs: Array[float] = []
	for y in range(int(h * 0.62), int(h * 0.92)):
		# Luminance, box-blurred 7 px across: the rain streaks (thin bright lines) would read as edges.
		var raw := PackedFloat32Array()
		raw.resize(w)
		for x in w:
			var c := img.get_pixel(x, y)
			raw[x] = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
		var lum := PackedFloat32Array()
		lum.resize(w)
		for x in w:
			var acc := 0.0
			var cnt := 0
			for k in range(maxi(0, x - 3), mini(w, x + 4)):
				acc += raw[k]
				cnt += 1
			lum[x] = acc / float(cnt)
		# Gravel and duff of this row: the brightest and darkest run of the middle third.
		var lo := 1.0
		var hi := 0.0
		for x in range(w / 3, w * 2 / 3):
			lo = minf(lo, lum[x])
			hi = maxf(hi, lum[x])
		if hi - lo < 0.04:
			continue
		var mid := (lo + hi) * 0.5
		var found := -1.0
		for x in range(1, w):
			if (lum[x - 1] - mid) * (lum[x] - mid) <= 0.0 and absf(lum[x] - lum[x - 1]) > 0.0:
				found = float(x) - (mid - lum[x - 1]) / (lum[x] - lum[x - 1])
				break
		if found >= 0.0:
			xs.append(found)
	var max_step := 0.0
	var sum := 0.0
	for k in range(1, xs.size() - 1):
		var step := absf(xs[k + 1] - 2.0 * xs[k] + xs[k - 1])
		max_step = maxf(max_step, step)
		sum += step
	var n := maxi(xs.size() - 2, 1)
	return {"rows": xs.size(), "max_step": max_step, "mean_step": sum / float(n)}


## The fern kinds' MultiMesh nodes in the ring (every chunk).
func _fern_nodes(forest: ForestWorld) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		for u in forest.profile.undergrowth.size():
			if forest.profile.undergrowth[u].cutout:
				var node := chunk.get_node_or_null("Undergrowth%d" % u) as MultiMeshInstance3D
				if node != null:
					out.append(node)
	return out


## Pixels of the ground band (lower 55 %) that differ between two frames of the same view.
func _changed_pixels(a: Image, b: Image) -> int:
	var n := 0
	for y in range(int(a.get_height() * 0.45), a.get_height()):
		for x in a.get_width():
			var d := a.get_pixel(x, y) - b.get_pixel(x, y)
			if absf(d.r) + absf(d.g) + absf(d.b) > 0.06:
				n += 1
	return n


func _frames(count: int) -> void:
	for _k in count:
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

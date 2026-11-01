extends Node
## N5 pixel checks on the real run scene (windowed; headless reports SKIP):
##  a) forest wall: from the glade, the share of picture pixels in the horizon band that are darker
##     than the sky (trunks and crowns, not the sky or the mist), mean over four directions, must be
##     clearly above the one measured before N5 (N5_PRE_FOREST_SHARE, docs/n5/before);
##  b) the trail edge is a curve, not steps (second difference of the edge x per picture row);
##  c) ferns are in the picture beside the trail (hiding their nodes changes the ground band);
##  d) --shots DIR saves the review set (docs/n5): glade views, the gate 35 m out, a sakura, two
##     frames across a chunk border, and the trail.
##   godot --path . --fixed-fps 90 res://tests/n5_forest_visual_test.tscn -- --desktop --shots /abs/dir

const RUN_SCENE := preload("res://scenes/run.tscn")
## Mean forest share of the four glade views before N5, in percent: measured on HEAD 48dfe1c with
## this test's own tree-difference method (docs/n5/before).
const N5_PRE_FOREST_SHARE := 15.5
## The wall must reach this multiple of the pre-N5 share.
const N5_MIN_FOREST_GAIN := 1.5
## Largest second difference of the trail-edge x between rows, pixels: a smooth edge stays under it.
const MAX_EDGE_STEP_PX := 2.5
## Frames measured for the trail edge (median of their maxima).
const N_EDGE_FRAMES := 5
## Changed pixels in the ground band when the ferns are shown: at least this many.
const MIN_FERN_PIXELS := 150
## Luminance change (blurred, 0..1) that counts as a tree pixel.
const N5_TREE_DIFF := 0.03

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

	# a) the forest wall, seen from the glade in four directions: the same frame with and without
	# the tree nodes; the pixels that change are the trees (fog and sky stay the same).
	var shares: Array[float] = []
	var tree_nodes := _tree_nodes(forest)
	for k in 4:
		var facing := Vector3(-sin(TAU * float(k) / 4.0), 0.0, -cos(TAU * float(k) / 4.0))
		_stand(player, forest, Vector3(0.0, 0.0, 2.2), facing)
		player.camera.rotation.x = deg_to_rad(-4.0)
		await _frames(30)
		var with_trees := await _capture("n5_glade_dir%d" % k)
		for node in tree_nodes:
			node.visible = false
		await _frames(3)
		var without_trees := await _capture("n5_glade_dir%d_no_trees" % k)
		for node in tree_nodes:
			node.visible = true
		await _frames(3)
		shares.append(_tree_share(with_trees, without_trees))
	var mean := 0.0
	for s in shares:
		mean += s
	mean /= 4.0
	print("MEASURE forest share in the horizon band: %s, mean %.1f%% (pre-N5 %.1f%%)" % [str(shares), mean, N5_PRE_FOREST_SHARE])
	_check("The glade is walled by forest: mean share %.1f%%, need >= %.1f%% (%.1fx pre-N5)" % [mean, N5_PRE_FOREST_SHARE * N5_MIN_FOREST_GAIN, N5_MIN_FOREST_GAIN],
		mean >= N5_PRE_FOREST_SHARE * N5_MIN_FOREST_GAIN)

	# b) and c): the trail edge and the ferns, from a point on the trail 9 m out.
	# View A (fixed, the same on HEAD and after N5): the trail 9 m out from the glade. The edge metric runs here.
	var along := _trail_point(forest, 9.0)
	var dir: Vector3 = along.dir
	var stand: Vector3 = along.pos - dir * 3.5
	_stand(player, forest, stand, dir)
	player.camera.look_at(along.pos + Vector3(0.0, -0.9, 0.0) + dir * 1.5, Vector3.UP)
	await _frames(30)
	# Rain falls differently in every frame: the same view is measured on N_EDGE_FRAMES frames and the
	# median of the per-frame maxima is taken, so one streak cannot make or break the verdict.
	var maxima: Array[float] = []
	var means: Array[float] = []
	var img: Image = null
	var rows := 0
	for k in N_EDGE_FRAMES:
		await _frames(1)
		var frame := await _capture("n5_trail_edge_near" if k == 0 else "")
		if k == 0:
			img = frame
		var e := _edge_steps(frame)
		rows = e.rows
		maxima.append(e.max_step)
		means.append(e.mean_step)
	maxima.sort()
	means.sort()
	var edge := {"rows": rows, "max_step": maxima[maxima.size() / 2], "mean_step": means[means.size() / 2]}
	print("MEASURE trail edge (median of %d frames): rows %d, max second difference %.2f px (frames %s), mean %.2f px" % [N_EDGE_FRAMES, edge.rows, edge.max_step, str(maxima), edge.mean_step])
	_check("The trail edge is a curve, not steps (max second difference %.2f px, need <= %.1f)" % [edge.max_step, MAX_EDGE_STEP_PX],
		edge.rows >= 12 and edge.max_step <= MAX_EDGE_STEP_PX)

	# View B: a fern 1.6–3 m off the trail, 4–10 m from the glade, framed from the trail. The ferns are
	# hidden and shown again on the same view; the pixels that change are the ferns in the picture.
	var fern_view := _fern_trail_point(forest)
	var fern_px := 0
	var fern_nodes := _fern_nodes(forest)
	if not fern_view.is_empty():
		var fdir: Vector3 = fern_view.dir
		_stand(player, forest, fern_view.pos - fdir * 2.6, fdir)
		player.camera.look_at(fern_view.pos + Vector3(0.0, -0.9, 0.0) + fdir * 1.5, Vector3.UP)
		await _frames(30)
		var with_ferns := await _capture("n5_fern_trail")
		for node in fern_nodes:
			node.visible = false
		await _frames(3)
		var without_ferns := await _capture("n5_fern_trail_no_ferns")
		for node in fern_nodes:
			node.visible = true
		await _frames(3)
		fern_px = _changed_pixels(with_ferns, without_ferns)
	print("MEASURE fern pixels changed by showing the ferns on the fern view: %d over %d fern nodes" % [fern_px, fern_nodes.size()])
	_check("Ferns are in the picture beside the trail (%d pixels change when they are shown, need %d)" % [fern_px, MIN_FERN_PIXELS],
		not fern_view.is_empty() and fern_px >= MIN_FERN_PIXELS)

	if out_dir != "":
		await _review_shots(forest, player, along)

	run.queue_free()
	await get_tree().process_frame


## The review set for docs/n5 (the same cameras before and after): a gate 35 m from the glade,
## a sakura 24 m out, two frames across a chunk border, and the trail further on.
func _review_shots(forest: ForestWorld, player: DesktopPlayer, along: Dictionary) -> void:
	var gate := _clear_gate_view(forest, 35.0)
	if gate != Vector3.INF:
		var from := Vector3(0.0, 0.0, 2.2)
		var gdir := (Vector3(gate.x, 0.0, gate.z) - from).normalized()
		_stand(player, forest, from, gdir)
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
	var dir: Vector3 = along.dir
	player.camera.look_at(along.pos + Vector3(0.0, 1.2, 0.0) + dir * 12.0, Vector3.UP)
	await _frames(20)
	await _capture("n5_trail_wide")


## Tree MultiMesh nodes of the ring and the forest (near, far, scene and back crowns).
func _tree_nodes(forest: ForestWorld) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var prefixes := ["Trees", "Focal", "FarTrees", "SceneTrees", "BackTrees"]
	for child in forest.get_children():
		for p in prefixes:
			if String(child.name).begins_with(p):
				out.append(child as Node3D)
	for key in forest._chunks:
		for child in (forest._chunks[key] as Node3D).get_children():
			for p in prefixes:
				if String(child.name).begins_with(p):
					out.append(child as Node3D)
	return out


## Share of the horizon band (28–50 % of the picture height) where the trees change the picture:
## the blurred frames differ by more than N5_TREE_DIFF (rain streaks are thin and drop out of the blur).
func _tree_share(with_img: Image, without_img: Image) -> float:
	var a := _blur(with_img)
	var b := _blur(without_img)
	var h := with_img.get_height()
	var changed := 0
	var total := 0
	for y in range(int(h * 0.28), int(h * 0.50)):
		for x in with_img.get_width():
			total += 1
			if absf(a[y * with_img.get_width() + x] - b[y * with_img.get_width() + x]) > N5_TREE_DIFF:
				changed += 1
	return float(changed) / maxf(1.0, float(total)) * 100.0


## Luminance of an image, box-blurred 5x5 (a plain float array, row-major).
func _blur(img: Image) -> PackedFloat32Array:
	var w := img.get_width()
	var h := img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	var y0 := maxi(2, int(h * 0.28) - 2)
	var y1 := mini(h - 2, int(h * 0.50) + 2)
	for y in range(y0, y1):
		for x in w:
			lum[y * w + x] = _lum(img.get_pixel(x, y))
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in range(y0 + 2, y1 - 2):
		for x in range(2, w - 2):
			var acc := 0.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					acc += lum[(y + dy) * w + x + dx]
			out[y * w + x] = acc / 25.0
	return out


static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## A path point about [param metres] from the spawn glade, with the trail's direction there.
func _trail_point(forest: ForestWorld, metres: float) -> Dictionary:
	var best_pos := Vector3.ZERO
	var best_dir := Vector3(0.0, 0.0, -1.0)
	var best_d := INF
	for s in forest.paths.samples_in_rect(Rect2(Vector2(-40.0, -40.0), Vector2(80.0, 80.0)), 1.0):
		var d := absf(Vector2(s.x, s.y).length() - metres)
		if d < best_d:
			best_d = d
			best_pos = Vector3(s.x, forest.height_at(s.x, s.y), s.y)
			best_dir = Vector3(s.z, 0.0, s.w).normalized()
	return {"pos": best_pos, "dir": best_dir}


## A gate about [param metres] from the glade whose sightline from the glade is clear of trunks
## and which no nearer gate hides (so it is framed, not a close gate in view).
func _clear_gate_view(forest: ForestWorld, metres: float) -> Vector3:
	var eye := Vector3(0.0, 1.6, 2.2)
	var gates: Array[Vector3] = []
	for key in forest._chunks:
		for g in (forest._chunks[key] as Node3D).get_meta("torii_world_positions", []):
			gates.append(g)
	var space := get_viewport().world_3d.direct_space_state
	var fallback := Vector3.INF
	for gv in gates:
		if absf(Vector2(gv.x, gv.z).length() - metres) >= 2.0:
			continue
		var target := gv + Vector3(0.0, 2.6, 0.0)
		# Another gate nearer the viewer and within 3 m of the line of sight would hide this one.
		var hidden := false
		for other in gates:
			if other != gv and other.distance_to(eye) < gv.distance_to(eye) and _seg_dist_xz(eye, target, other) < 3.0:
				hidden = true
		if hidden:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target, ForestWorld.TRUNK_LAYER)).is_empty():
			return gv
		if fallback == Vector3.INF:
			fallback = gv
	# No clear sightline at this distance: the first lonely gate, with its trunks in front of it.
	return fallback


## Distance in the ground plane from point [param p] to the segment a–b.
static func _seg_dist_xz(a: Vector3, b: Vector3, p: Vector3) -> float:
	var a2 := Vector2(a.x, a.z)
	var ab := Vector2(b.x, b.z) - a2
	var ap := Vector2(p.x, p.z) - a2
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return (a2 + ab * t).distance_to(Vector2(p.x, p.z))


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
		# Luminance, box-blurred 7 px across: rain streaks (thin bright lines) would read as edges.
		var raw := PackedFloat32Array()
		raw.resize(w)
		for x in w:
			raw[x] = _lum(img.get_pixel(x, y))
		var lum := PackedFloat32Array()
		lum.resize(w)
		for x in w:
			var acc := 0.0
			var cnt := 0
			for k in range(maxi(0, x - 3), mini(w, x + 4)):
				acc += raw[k]
				cnt += 1
			lum[x] = acc / float(cnt)
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
			if forest.profile.undergrowth[u].get("cutout") == true:
				var node := chunk.get_node_or_null("Undergrowth%d" % u) as MultiMeshInstance3D
				if node != null:
					out.append(node)
	return out


## A trail point beside a fern: the fern stands 1.6–3 m off the centre line and 6–14 m from the glade.
## Returns {pos, dir} of the trail there, or an empty dictionary when no such fern exists in the ring.
func _fern_trail_point(forest: ForestWorld) -> Dictionary:
	for key in forest._chunks:
		var root := forest._chunks[key] as Node3D
		for u in forest.profile.undergrowth.size():
			if not forest.profile.undergrowth[u].get("cutout") == true:
				continue
			for xf in root.get_meta("xfs_Undergrowth%d" % u, []):
				var t: Transform3D = xf
				var w := root.position + t.origin
				var from_glade := Vector2(w.x, w.z).length()
				if from_glade < 4.0 or from_glade > 10.0:
					continue
				var best := {}
				var best_d := INF
				for sm in forest.paths.samples_in_rect(Rect2(Vector2(w.x, w.z) - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), 0.5):
					var d := Vector2(sm.x - w.x, sm.y - w.z).length()
					if d < best_d:
						best_d = d
						best = {"pos": Vector3(sm.x, forest.height_at(sm.x, sm.y), sm.y), "dir": Vector3(sm.z, 0.0, sm.w).normalized()}
				if not best.is_empty() and best_d >= 1.6 and best_d <= 3.0:
					return best
	return {}


## The nearest fern (cut-out kind) to [param at] on the ground, or INF when none is within 8 m.
func _nearest_fern(forest: ForestWorld, at: Vector3, dir: Vector3) -> Vector3:
	var gates: Array[Vector3] = []
	var ferns: Array[Vector3] = []
	for key in forest._chunks:
		var root := forest._chunks[key] as Node3D
		for g in root.get_meta("torii_world_positions", []):
			gates.append(g)
		for u in forest.profile.undergrowth.size():
			if not forest.profile.undergrowth[u].get("cutout") == true:
				continue
			for xf in root.get_meta("xfs_Undergrowth%d" % u, []):
				var t: Transform3D = xf
				var w := root.position + t.origin
				if Vector2(w.x - at.x, w.z - at.z).length() < 8.0:
					ferns.append(w)
	# Nearest first; a fern whose sightline from the camera (2.4 m back along the trail) meets a gate is skipped.
	ferns.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return Vector2(a.x - at.x, a.z - at.z).length() < Vector2(b.x - at.x, b.z - at.z).length())
	for w in ferns:
		var cam := w - dir * 2.4
		var hidden := false
		for g in gates:
			if Vector2(g.x - cam.x, g.z - cam.z).length() < w.distance_to(cam) and _seg_dist_xz(cam, w, g) < 2.0:
				hidden = true
		if not hidden:
			return w
	return Vector3.INF


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

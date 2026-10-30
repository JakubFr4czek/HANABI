extends Node
## Surface intersections in the endless forest (VR report: "overlapping textures, z-fighting,
## everything that does not look right"). Headless, on a standalone ForestWorld with its torii gates:
##  a) torii gates: no tree trunk or boulder stands within POST_CLEAR of a gate post, or of the lintel.
##     Gates come from ToriiManager: at run start and from anchors on the footpaths.
##  b) footpaths: no tree trunk stands within PATH_CLEAR of a footpath centre line.
##  c) ground: the shrine spurs (ribbon strips laid on the trail) sit at least COPLANAR_EPS above
##     the rendered terrain at every point of their triangles: never coplanar, never buried.
## Failures print the (x, z) and kind of each offending object.
##   godot --headless --path . --fixed-fps 90 res://tests/surface_interpenetration_test.tscn

const POST_X := 1.15
const LINTEL_HALF := 1.7
const POST_CLEAR := 0.6
const PATH_CLEAR := 1.5
const COPLANAR_EPS := 0.005
const SHRINE_OFFSET := 12.0
const ANCHORS := 4
const PATH_SPACING := 6.0
const MAX_REPORT := 8
## Points of a ribbon triangle as barycentric weights: 3 corners, 3 edge midpoints, the centre.
const TRI_WEIGHTS := [
	Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0),
	Vector3(0.5, 0.5, 0.0), Vector3(0.0, 0.5, 0.5), Vector3(0.5, 0.0, 0.5),
	Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)]

var failures := 0
var _gates_checked := 0
var _closest_post := INF
var _trunks_checked := 0
var _closest_trunk := INF
var _ribbon_points := 0
var _lowest_ribbon := INF


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	await _run_all()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("TIME  surface checks %.0f ms" % ms)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var follow := Node3D.new()
	add_child(follow)
	var forest := ForestWorld.new()
	add_child(forest)
	var t_ring := Time.get_ticks_usec()
	forest.setup(follow)
	forest.finish_pending()
	print("TIME  forest ring built in %.0f ms" % ((Time.get_ticks_usec() - t_ring) / 1000.0))
	# Gate placement reads the trunk colliders through physics: let the space take them in first.
	await get_tree().physics_frame

	var tm := forest.torii_manager
	var size: float = forest._chunk_size
	var obstacles := _obstacles(forest)
	var trunk_total := 0
	var boulder_total := 0
	for key in obstacles:
		for o in obstacles[key]:
			if o.kind == "trunk":
				trunk_total += 1
			else:
				boulder_total += 1
	print("MEASURE ring chunks=%d trunks=%d boulders=%d" % [forest._chunks.size(), trunk_total, boulder_total])

	# a) the gates of the run start, then gates placed from anchors on the footpaths.
	_check_gates(tm.get_active_gates(), obstacles)
	var anchors := _anchors(forest, Rect2(0.0, 0.0, size, size))
	for a in anchors:
		tm.clear_gates()
		tm.ensure_gates_ahead(Vector3(a.x, forest.height_at(a.x, a.y), a.y), Vector3(a.z, 0.0, a.w))
		_check_gates(tm.get_active_gates(), obstacles)
	print("MEASURE gates checked=%d, closest post-to-object %.2f m" % [_gates_checked, _closest_post])
	_check("Torii posts and lintels keep >= %.1f m from every trunk and boulder (%d gates, closest %.2f m)" % [
		POST_CLEAR, _gates_checked, _closest_post], _closest_post >= POST_CLEAR)

	# b) trunks against the footpath centre lines.
	_check_paths(forest, obstacles)
	print("MEASURE trunks checked=%d, closest trunk-to-path %.2f m" % [_trunks_checked, _closest_trunk])
	_check("Tree trunks keep >= %.1f m from every footpath centre line (%d trunks, closest %.2f m)" % [
		PATH_CLEAR, _trunks_checked, _closest_trunk], _closest_trunk >= PATH_CLEAR)

	# c) shrine spurs against the rendered terrain.
	var t_spur := Time.get_ticks_usec()
	var spurs := _check_spurs(forest, anchors)
	print("TIME  shrine spurs checked in %.0f ms" % ((Time.get_ticks_usec() - t_spur) / 1000.0))
	print("MEASURE spurs=%d ribbon points=%d, lowest above ground %.1f mm" % [spurs, _ribbon_points, _lowest_ribbon * 1000.0])
	_check("Shrine spurs lie >= %.0f mm above the rendered ground (%d spurs, %d points, lowest %.1f mm)" % [
		COPLANAR_EPS * 1000.0, spurs, _ribbon_points, _lowest_ribbon * 1000.0],
		spurs > 0 and _lowest_ribbon >= COPLANAR_EPS)


## Trunks and boulders of the ring, as xz positions, grouped by chunk. Trunks: the planted spots of
## every entry (ordinary and focal); boulders: the undergrowth stones.
func _obstacles(forest: ForestWorld) -> Dictionary:
	var out := {}
	for key in forest._chunks:
		var chunk := forest._chunks[key] as Node3D
		var list: Array[Dictionary] = []
		for e in forest.profile.trees.size():
			for label in ["Trees%d" % e, "Focal%d" % e]:
				for xf in chunk.get_meta("xfs_" + label, []):
					var base := chunk.position + (xf as Transform3D).origin
					list.append({"xz": Vector2(base.x, base.z), "kind": "trunk"})
		for p in chunk.get_meta("undergrowth_world_positions", []):
			var v: Vector3 = p
			list.append({"xz": Vector2(v.x, v.z), "kind": "boulder"})
		out[key] = list
	return out


## a) Each gate's two posts and its lintel against every trunk and boulder near it.
func _check_gates(gates: Array[ToriiGate], obstacles: Dictionary) -> void:
	var clashes: Array[String] = []
	for g in gates:
		var xf := g.global_transform
		var posts: Array[Vector2] = [_xz(xf * Vector3(-POST_X, 0.0, 0.0)), _xz(xf * Vector3(POST_X, 0.0, 0.0))]
		var lintel_a := _xz(xf * Vector3(-LINTEL_HALF, 0.0, 0.0))
		var lintel_b := _xz(xf * Vector3(LINTEL_HALF, 0.0, 0.0))
		_gates_checked += 1
		for list in obstacles.values():
			for o in list:
				var p: Vector2 = o.xz
				for post in posts:
					var d := p.distance_to(post)
					_closest_post = minf(_closest_post, d)
					if d < POST_CLEAR and clashes.size() < MAX_REPORT:
						clashes.append(_clash_line(o.kind, p, "gate post at (%.2f, %.2f)" % [post.x, post.y], d))
				var dl := ForestPaths.segment_distance(p, lintel_a, lintel_b)
				_closest_post = minf(_closest_post, dl)
				if dl < POST_CLEAR and clashes.size() < MAX_REPORT:
					clashes.append(_clash_line(o.kind, p, "gate lintel", dl))
	for line in clashes:
		print(line)


## b) Trunks against the footpath centre lines. Only the segments near each chunk are read.
func _check_paths(forest: ForestWorld, obstacles: Dictionary) -> void:
	var clashes: Array[String] = []
	var size: float = forest._chunk_size
	for key in obstacles:
		var chunk := forest._chunks[key] as Node3D
		var rect := Rect2(chunk.position.x, chunk.position.z, size, size)
		var segments := forest.paths.segments_in_rect(rect.grow(PATH_CLEAR + 2.0))
		for o in obstacles[key]:
			if o.kind != "trunk":
				continue
			var p: Vector2 = o.xz
			var d := ForestPaths.distance_to_segments(segments, p)
			_trunks_checked += 1
			_closest_trunk = minf(_closest_trunk, d)
			if d < PATH_CLEAR and clashes.size() < MAX_REPORT:
				clashes.append(_clash_line(o.kind, p, "footpath centre line", d))
	for line in clashes:
		print(line)


## c) Shrine spurs routed from the footpaths. Each ribbon triangle is read at its corners, edge
## midpoints and centre, against the height the terrain mesh renders there. Returns the spur count.
func _check_spurs(forest: ForestWorld, anchors: Array[Vector4]) -> int:
	var clashes: Array[String] = []
	var spurs := 0
	for a in anchors:
		# The tangent is (a.z, a.w); the normal, which the shrine stands off by SHRINE_OFFSET, is (-a.w, a.z).
		var shrine := Node3D.new()
		shrine.position = Vector3(a.x - a.w * SHRINE_OFFSET, 0.0, a.y + a.z * SHRINE_OFFSET)
		forest.add_child(shrine)
		forest.connect_shrine(shrine)
		var spur := shrine.get_node_or_null("PathSpur") as MeshInstance3D
		if spur != null:
			spurs += 1
			var verts: PackedVector3Array = (spur.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for t in range(0, verts.size() - 2, 3):
				for w in TRI_WEIGHTS:
					var p: Vector3 = verts[t] * w.x + verts[t + 1] * w.y + verts[t + 2] * w.z
					var dy := p.y - forest._mesh_height(p.x, p.z)
					_ribbon_points += 1
					_lowest_ribbon = minf(_lowest_ribbon, dy)
					if dy < COPLANAR_EPS and clashes.size() < MAX_REPORT:
						clashes.append("  spur ribbon at (%.2f, %.2f): %.1f mm above the rendered ground, need %.0f mm (%s)" % [
							p.x, p.z, dy * 1000.0, COPLANAR_EPS * 1000.0, "buried" if dy < 0.0 else "coplanar"])
		shrine.queue_free()
	for line in clashes:
		print(line)
	return spurs


## Anchors on the footpaths inside [param rect]: Vector4(x, z, tangent.x, tangent.y), evenly spaced.
func _anchors(forest: ForestWorld, rect: Rect2) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var samples := forest.paths.samples_in_rect(rect, PATH_SPACING)
	if samples.is_empty():
		return out
	for k in ANCHORS:
		out.append(samples[(2 * k + 1) * samples.size() / (2 * ANCHORS)])
	return out


func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _clash_line(kind: String, at: Vector2, against: String, d: float) -> String:
	return "  %s at (%.2f, %.2f): %.2f m from %s" % [kind, at.x, at.y, d, against]


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

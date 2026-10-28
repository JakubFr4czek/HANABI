extends Node
## CI visual fuzz: puts the desktop player at random LEGAL spots of the real run
## scene (on the terrain at standing height, on footpaths, near shrines and torii
## gates, across several chunks), looks in a few directions and checks every
## rendered frame automatically:
##   - not nearly all black / all white, not one flat colour (camera in a mesh?)
##   - no magenta pixels (missing texture or broken shader)
##   - the camera is not inside a collider (trunk, rock, prop)
##   - no terrain hole: the ray down hits the ground near height_at(), and rays
##     below the horizon hit something (no sky under the horizon)
##   - finite camera transform, no new RuntimeGuard violation (script errors)
## Windowed (it reads pixels): run under Xvfb with the compatibility renderer:
##   godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 960x540 \
##     res://tests/ci/visual_fuzz.tscn -- --desktop --seed=7 --locations=16 --dirs=4 --out=/tmp/vfuzz
## Every failure prints seed, location index, kind, position and yaw; rerun one
## location with --only=<index> (the RNG still draws every earlier location).

const RUN_SCENE_PATH := "res://scenes/run.tscn"
const KINDS := ["terrain", "path", "shrine", "torii"]
const CHUNKS_OUT := 3  # spread over +-3 chunks around the spawn
const EYE := 1.65
const THUMB_WIDTH := 480
const DARK_FRAC_MAX := 0.985
const BRIGHT_FRAC_MAX := 0.90
const FLAT_STD_MIN := 0.004
const MAGENTA_FRAC_MAX := 0.003
const SETTLE_FIRST := 75
const SETTLE_TURN := 12

var seed_value := 0
var locations := 16
var dirs := 4
var only := -1
var out_dir := "/tmp/hanabi_visual_fuzz"
var rng := RandomNumberGenerator.new()
var run: Node = null
var player: Node3D = null
var forest: Node = null
var spawn_pos := Vector3.ZERO
var chunk := 28.0
var guard_seen := 0
var frames_checked := 0
var report: Array = []
var failures := 0
var _last_target := Vector3.INF


func _ready() -> void:
	_parse_args()
	rng.seed = seed_value
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("frames"))
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("failed"))
	print("VFUZZ seed=%d locations=%d dirs=%d out=%s" % [seed_value, locations, dirs, out_dir])
	await _run_all()
	_write_report()
	print("VFUZZ RESULT seed=%d frames=%d failures=%d" % [seed_value, frames_checked, failures])
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _parse_args() -> void:
	seed_value = int(Time.get_unix_time_from_system()) % 1000000
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--seed="):
			seed_value = int(v)
		elif a.begins_with("--locations="):
			locations = maxi(1, int(v))
		elif a.begins_with("--dirs="):
			dirs = maxi(1, int(v))
		elif a.begins_with("--only="):
			only = int(v)
		elif a.begins_with("--out="):
			out_dir = v


func _run_all() -> void:
	var scene: PackedScene = load(RUN_SCENE_PATH)
	run = scene.instantiate()
	if "skip_run_intro" in run:
		run.set("skip_run_intro", true)
	add_child(run)
	await _frames(30)
	var wd: Node = run.get("wave_director")
	if wd:
		# Enemies would walk into frames at random; this test is about the world.
		if wd.has_method("stop_director"):
			wd.stop_director()
		if wd.has_method("clear_enemies"):
			wd.clear_enemies()
	player = run.get("player")
	forest = run.get("forest_world")
	if player == null or not player.has_method("teleport") or forest == null:
		_fail_global("needs the desktop player and the forest (run with -- --desktop)")
		return
	if "_chunk_size" in forest:
		chunk = float(forest.get("_chunk_size"))
	var spawn := run.find_child("PlayerSpawn", true, false) as Node3D
	spawn_pos = spawn.global_position if spawn else player.global_position
	guard_seen = _guard_count()
	for i in locations:
		var kind: String = KINDS[i % KINDS.size()]
		_last_target = Vector3.INF
		var spot := _pick_spot(kind)
		var base_yaw := rng.randf_range(-PI, PI)
		var pitches: Array[float] = []
		for d in dirs:
			pitches.append(deg_to_rad(rng.randf_range(-15.0, 5.0)))
		if only >= 0 and i != only:
			continue
		if spot == Vector3.INF:
			print("VFUZZ note: loc %d (%s): no legal spot found, skipped" % [i, kind])
			continue
		if _last_target != Vector3.INF:
			base_yaw = _yaw_to(spot, _last_target)
		for d in dirs:
			var yaw := base_yaw + TAU * d / dirs
			await _shoot(i, kind, d, spot, yaw, pitches[d], SETTLE_FIRST if d == 0 else SETTLE_TURN)


# --- Spots ---------------------------------------------------------------------


## A legal standing spot for [param kind], or Vector3.INF.
func _pick_spot(kind: String) -> Vector3:
	for attempt in 16:
		var p := Vector3.INF
		match kind:
			"terrain":
				p = (
					spawn_pos
					+ Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * chunk * CHUNKS_OUT
				)
			"path":
				p = _path_spot()
			"shrine":
				p = _near(_shrines())
			"torii":
				p = _near(_gates())
		if p == Vector3.INF:
			# Nothing of that kind around yet: fall back to open terrain.
			p = spawn_pos + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * chunk * CHUNKS_OUT
		p.y = float(forest.height_at(p.x, p.z))
		if _legal(p):
			return p
	return Vector3.INF


func _path_spot() -> Vector3:
	var paths: Object = forest.get("paths")
	if paths == null or not paths.has_method("samples_in_rect"):
		return Vector3.INF
	var c := (
		Vector2(spawn_pos.x, spawn_pos.z)
		+ Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * chunk * CHUNKS_OUT
	)
	var found: Array = paths.samples_in_rect(Rect2(c - Vector2(40.0, 40.0), Vector2(80.0, 80.0)), 1.0)
	if found.is_empty():
		return Vector3.INF
	var s = found[rng.randi_range(0, found.size() - 1)]
	return Vector3(s.x, 0.0, s.y)


func _shrines() -> Array:
	var hm: Node = run.get("hokora_manager")
	return hm.alive_shrines() if hm and hm.has_method("alive_shrines") else []


func _gates() -> Array:
	var tm: Node = forest.get("torii_manager") if "torii_manager" in forest else null
	return tm.get_active_gates() if tm and tm.has_method("get_active_gates") else []


## A spot 2.5-5 m from a random object of the list, facing it.
func _near(objects: Array) -> Vector3:
	if objects.is_empty():
		return Vector3.INF
	var o := objects[rng.randi_range(0, objects.size() - 1)] as Node3D
	_last_target = o.global_position
	var a := rng.randf_range(-PI, PI)
	return o.global_position + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.5, 5.0)


func _legal(p: Vector3) -> bool:
	if not _finite(p):
		return false
	if (
		forest.has_method("trunk_push")
		and (forest.trunk_push(p + Vector3.UP, Vector3.FORWARD, 0.6) as Vector3).length() > 0.001
	):
		return false
	if forest.has_method("is_clear_of_props") and not forest.is_clear_of_props(p.x, p.z, 0.6):
		return false
	return true


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z) if Vector2(d.x, d.z).length() > 0.01 else 0.0


# --- One frame -----------------------------------------------------------------


func _shoot(i: int, kind: String, d: int, spot: Vector3, yaw: float, pitch: float, settle: int) -> void:
	player.teleport(spot + Vector3.UP * 0.2, yaw)
	var cam := player.get("camera") as Camera3D
	if cam:
		cam.rotation.x = pitch
	await _frames(settle)
	await RenderingServer.frame_post_draw
	var name := "loc%02d_%s_d%d" % [i, kind, d]
	var errors: Array[String] = []
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null or not _finite_xf(cam.global_transform):
		errors.append("camera transform not finite")
	var img := get_viewport().get_texture().get_image()
	if img.is_compressed():
		img.decompress()
	var stats := _frame_stats(img)
	if stats.dark > DARK_FRAC_MAX:
		errors.append("frame nearly all black (%.1f%% dark)" % (stats.dark * 100.0))
	if stats.bright > BRIGHT_FRAC_MAX:
		errors.append("frame nearly all white (%.1f%% bright)" % (stats.bright * 100.0))
	if stats.std < FLAT_STD_MIN:
		errors.append("frame is one flat colour (std %.4f): camera inside a mesh?" % stats.std)
	if stats.magenta > MAGENTA_FRAC_MAX:
		errors.append("magenta pixels %.2f%% (missing texture / shader error)" % (stats.magenta * 100.0))
	if cam and _finite_xf(cam.global_transform):
		errors.append_array(_physics_checks(cam))
	var g := _guard_count()
	if g > guard_seen:
		errors.append("RuntimeGuard: %d new violation(s)" % (g - guard_seen))
		guard_seen = g
	frames_checked += 1
	var thumb := img.duplicate() as Image
	thumb.resize(THUMB_WIDTH, int(THUMB_WIDTH * img.get_height() / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
	thumb.save_png(out_dir.path_join("frames").path_join(name + ".png"))
	var pos := cam.global_position if cam else spot
	var entry := {
		"seed": seed_value,
		"index": i,
		"kind": kind,
		"dir": d,
		"name": name,
		"position": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"yaw_deg": snappedf(rad_to_deg(yaw), 0.1),
		"pitch_deg": snappedf(rad_to_deg(pitch), 0.1),
		"stats": stats,
		"errors": errors,
	}
	report.append(entry)
	if not errors.is_empty():
		failures += 1
		img.save_png(out_dir.path_join("failed").path_join(name + ".png"))
		for e in errors:
			print(
				(
					"VFUZZ FAIL seed=%d loc=%d kind=%s dir=%d pos=%s yaw=%.1f pitch=%.1f :: %s"
					% [
						seed_value,
						i,
						kind,
						d,
						str(pos.snapped(Vector3.ONE * 0.01)),
						rad_to_deg(yaw),
						rad_to_deg(pitch),
						e
					]
				)
			)
		print("    repro: -- --desktop --seed=%d --locations=%d --dirs=%d --only=%d" % [seed_value, locations, dirs, i])


## Fractions of dark / bright / magenta pixels and the luminance spread, on a
## 160 px wide copy of the frame (fast enough under software rendering).
func _frame_stats(src: Image) -> Dictionary:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGB8)
	var w := 160
	var h := maxi(1, int(w * src.get_height() / float(src.get_width())))
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var n := 0
	var dark := 0
	var bright := 0
	var magenta := 0
	var sum := 0.0
	var sum2 := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += l
			sum2 += l * l
			n += 1
			if maxf(c.r, maxf(c.g, c.b)) < 3.0 / 255.0:
				dark += 1
			if minf(c.r, minf(c.g, c.b)) > 0.97:
				bright += 1
			if c.r > 0.85 and c.b > 0.85 and c.g < 0.2:
				magenta += 1
	var mean := sum / n
	return {
		"mean": snappedf(mean, 0.0001),
		"std": snappedf(sqrt(maxf(sum2 / n - mean * mean, 0.0)), 0.0001),
		"dark": snappedf(float(dark) / n, 0.0001),
		"bright": snappedf(float(bright) / n, 0.0001),
		"magenta": snappedf(float(magenta) / n, 0.0001),
	}


func _physics_checks(cam: Camera3D) -> Array[String]:
	var out: Array[String] = []
	var space := cam.get_world_3d().direct_space_state
	var exclude := _player_rids()
	# Inside a collider: a small sphere at the eye must touch nothing.
	var shape := SphereShape3D.new()
	shape.radius = 0.12
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, cam.global_position)
	q.exclude = exclude
	q.collide_with_areas = false
	var hits := space.intersect_shape(q, 4)
	if not hits.is_empty():
		var who := hits[0].get("collider") as Object
		out.append("camera inside a collider (%s)" % (who.get("name") if who else "?"))
	if (
		forest.has_method("trunk_push")
		and (forest.trunk_push(cam.global_position, -cam.global_basis.z, 0.25) as Vector3).length() > 0.001
	):
		out.append("camera inside a tree trunk (trunk_push)")
	# Terrain hole: straight down must hit the ground where height_at() says it is.
	var down := _ray(space, cam.global_position, cam.global_position + Vector3.DOWN * 30.0, exclude)
	var ground := float(forest.height_at(cam.global_position.x, cam.global_position.z))
	if down.is_empty():
		out.append("terrain hole: nothing under the camera (height_at %.2f)" % ground)
	elif absf((down.position as Vector3).y - ground) > 1.0:
		out.append(
			(
				"ground collision %.2f m off height_at (%.2f vs %.2f)"
				% [absf((down.position as Vector3).y - ground), (down.position as Vector3).y, ground]
			)
		)
	# Below the horizon there must be something, not sky.
	var flat := -cam.global_basis.z
	flat.y = 0.0
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	for deg in [20.0, 35.0, 60.0]:
		var dir := (flat * cos(deg_to_rad(deg)) + Vector3.DOWN * sin(deg_to_rad(deg))).normalized()
		if _ray(space, cam.global_position, cam.global_position + dir * 80.0, exclude).is_empty():
			out.append("terrain hole: a ray %d° below the horizon hits nothing" % int(deg))
			break
	return out


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)


func _player_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for n in [player] + player.find_children("*", "CollisionObject3D", true, false):
		if n is CollisionObject3D:
			rids.append((n as CollisionObject3D).get_rid())
	var katana: Node = run.get("katana")
	if katana is CollisionObject3D:
		rids.append((katana as CollisionObject3D).get_rid())
	return rids


# --- Report --------------------------------------------------------------------


func _write_report() -> void:
	var f := FileAccess.open(out_dir.path_join("visual_fuzz.json"), FileAccess.WRITE)
	if f:
		f.store_string(
			JSON.stringify({"seed": seed_value, "frames": frames_checked, "failures": failures, "shots": report}, "  ")
		)


func _fail_global(msg: String) -> void:
	failures += 1
	print("VFUZZ FAIL seed=%d :: %s" % [seed_value, msg])


func _guard_count() -> int:
	return int(get_node("/root/RuntimeGuard").violation_count()) if has_node("/root/RuntimeGuard") else 0


static func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _finite_xf(t: Transform3D) -> bool:
	return _finite(t.origin) and _finite(t.basis.x) and _finite(t.basis.y) and _finite(t.basis.z)


func _frames(count: int) -> void:
	for k in count:
		await get_tree().process_frame

extends Node
## N10 visual test on the real run scene (windowed; headless reports SKIP). The window is what
## OBS records: before = the raw head view (head rolled 12°), after = the spectator camera.
##   timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 960x540 res://tests/n10_spectator_visual_test.tscn -- --desktop --shots docs/n10
## Checks: the spectator frame has a level horizon (strongest sky/ground edge at the same row on
## the left and right of the frame) while the raw rolled view does not; in third person with a
## trunk right behind the player the camera stays in front of it (no bark pixels in frame).

const RUN_SCENE := preload("res://scenes/run.tscn")
const ROLL_DEG := 12.0
const TRUNK_COLOR := Color(0.85, 0.12, 0.75)
var out_dir := "/tmp/hanabi_n10"
var run: RunGame
var player: DesktopPlayer
var spec: SpectatorCamera
var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  n10_spectator_visual_test needs a window (pixels)")
		print("\nALL PASSED (0 failed)")
		get_tree().quit(0)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(200.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT in n10_spectator_visual_test")
		get_tree().quit(1))
	seed(1010)
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://n10_shots_save.cfg"
	add_child(run)
	player = run.player as DesktopPlayer
	spec = run.spectator
	_check("spectator exists on PC, off by default", spec != null and not spec.is_active())
	var health := get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health:
		health.max_hp = 100000.0
		health.hp = 100000.0
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(40)

	# A level look with the head rolled, as a tilted headset would be.
	player._pitch = deg_to_rad(4.0)
	player.camera.rotation = Vector3(player._pitch, 0.0, deg_to_rad(ROLL_DEG))
	await _frames(10)
	var raw := await _grab("n10_00_before_head_view.png")
	var raw_tilt := _horizon_tilt(raw)

	spec.set_mode(SpectatorCamera.Mode.FIRST_PERSON)
	await _frames(90)
	var fp := await _grab("n10_01_fp_smoothed_level.png")
	var fp_tilt := _horizon_tilt(fp)
	print("horizon rows: raw %s, spectator %s" % [raw_tilt, fp_tilt])
	_check("raw rolled head view: horizon tilted (Δ %d px)" % raw_tilt.z, raw_tilt.z >= 12)
	_check("spectator FP: horizon level (Δ %d px <= 6, raw %d)" % [fp_tilt.z, raw_tilt.z], fp_tilt.z <= 6 and fp_tilt.z < raw_tilt.z)
	_check("spectator fills the window 16:9 (%s)" % [fp.get_size()], absf(float(fp.get_width()) / fp.get_height() - 16.0 / 9.0) < 0.02)
	player.camera.rotation.z = 0.0

	# Third person with a test trunk on the boom right behind the player.
	var head := player.camera.global_position
	var back := player.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var right := player.global_basis.x
	var trunk := _make_trunk(head + back * 1.3 + right * 0.3)
	run.add_child(trunk)
	await _frames(4)
	spec.set_mode(SpectatorCamera.Mode.THIRD_PERSON)
	await _frames(90)
	var tp := await _grab("n10_02_tp_trunk_behind.png")
	var cam := spec.camera.global_position
	var q := PhysicsRayQueryParameters3D.create(head, cam, ForestWorld.TRUNK_LAYER)
	var hit := spec.camera.get_world_3d().direct_space_state.intersect_ray(q)
	var bark := _color_fraction(tp, TRUNK_COLOR)
	_check("TP: no trunk between head and camera (hit %s)" % [not hit.is_empty()], hit.is_empty())
	_check("TP: frame not covered by the trunk (%.1f%% bark pixels)" % (bark * 100.0), bark < 0.03)
	trunk.queue_free()

	# Both modes in a fight: three yōkai closing in, the katana swinging.
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pp := player.global_position
	for k in 3:
		var a := deg_to_rad(-30.0 + 30.0 * k)
		var pos := pp + fwd.rotated(Vector3.UP, a) * (3.2 + 0.6 * k)
		pos.y = run.forest_world.height_at(pos.x, pos.z)
		run.wave_director.spawn_enemy_at(pos, pp)
	spec.set_clean_frame(true)
	await _frames(70)
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	await _frames(9)
	var tp_fight := await _grab("n10_03_tp_combat.png")
	spec.set_mode(SpectatorCamera.Mode.FIRST_PERSON)
	await _frames(50)
	player.swing(DesktopPlayer.SLASH_OVERHEAD)
	await _frames(9)
	var fp_fight := await _grab("n10_04_fp_combat.png")
	_check("combat shots differ between modes (Δ %.3f)" % _mean_delta(tp_fight, fp_fight), _mean_delta(tp_fight, fp_fight) > 0.02)
	spec.set_mode(SpectatorCamera.Mode.OFF)
	await _frames(3)
	var off := await _grab("n10_05_off.png")
	_check("F7 off returns the window to the head view (Δ vs FP %.3f)" % _mean_delta(off, fp_fight), _mean_delta(off, fp_fight) > 0.01)

	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _make_trunk(pos: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "N10TestTrunk"
	body.collision_layer = ForestWorld.TRUNK_LAYER
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 6.0
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.35
	m.bottom_radius = 0.35
	m.height = 6.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = TRUNK_COLOR
	m.material = mat
	mi.mesh = m
	body.add_child(mi)
	body.position = pos + Vector3(0, 1.0, 0)
	return body


## Strongest dark/bright row edge (5-row smoothed luminance step) in a band at 15% and 85% of the
## width, upper 80% of the frame. Returns (row_left, row_right, |difference|).
func _horizon_tilt(img: Image) -> Vector3i:
	var rows := []
	for fx in [0.15, 0.85]:
		var cx := int(img.get_width() * fx)
		var lum := PackedFloat32Array()
		lum.resize(img.get_height())
		for y in img.get_height():
			var s := 0.0
			for dx in range(-6, 7, 3):
				s += img.get_pixel(cx + dx, y).get_luminance()
			lum[y] = s / 5.0
		var best := 0.0
		var best_y := 0
		for y in range(8, int(img.get_height() * 0.8)):
			var up := 0.0
			var dn := 0.0
			for k in 5:
				up += lum[y - 1 - k]
				dn += lum[mini(y + k, img.get_height() - 1)]
			var d := absf(up - dn) / 5.0
			if d > best:
				best = d
				best_y = y
		rows.append(best_y)
	return Vector3i(rows[0], rows[1], absi(rows[0] - rows[1]))


func _color_fraction(img: Image, c: Color) -> float:
	var n := 0
	var hit := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			n += 1
			var p := img.get_pixel(x, y)
			if absf(p.r - c.r) < 0.12 and absf(p.g - c.g) < 0.12 and absf(p.b - c.b) < 0.12:
				hit += 1
	return float(hit) / maxf(n, 1)


func _mean_delta(a: Image, b: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, a.get_height(), 6):
		for x in range(0, a.get_width(), 6):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	return sum / maxf(n, 1)


func _grab(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	return img


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame

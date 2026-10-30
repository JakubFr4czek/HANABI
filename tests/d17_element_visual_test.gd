extends Node
## D17 visual check on the real run scene, windowed (not headless): four schools of
## swarm yōkai 8 m ahead must read as four colours in the picture, and a counter
## blade hit must do more than a same-school one (the real katana hit path).
##   .tools/Godot.app/Contents/MacOS/Godot --path . --fixed-fps 90 res://tests/d17_element_visual_test.tscn -- --shots docs/d17
## Time is stepped by frames, not waited for. Pixel checks need a framebuffer, so the
## headless suite reports SKIP (the harness counts it as skipped, not as a pass).

const RUN_SCENE := preload("res://scenes/run.tscn")
## Patch around each yōkai's eye, sampled in the picture (pixels, half-width).
const PATCH_HALF := 2
## Two schools' eye colours must differ by at least this much (RGB distance, 0..1 scale):
## the smallest gap a player still reads as another colour across the fog.
const COLOUR_GAP := 0.12

var out_dir := "docs/d17"
var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  element colour pixel checks need a window (run windowed, see docs/d17)")
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
	var director := run.wave_director
	director.stop_director()
	director.clear_enemies()
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	await _frames(20)

	# 1. One yōkai of each school, 8 m ahead, side by side (the eye patches are measured).
	var bodies: Array[Yokai] = []
	var xs := [-2.4, -0.8, 0.8, 2.4]
	for k in 4:
		var x: float = xs[k]
		var at := Vector3(x, _ground(director, x, -5.8), -5.8)
		bodies.append(director.spawn_enemy_at(at, player.global_position, Elements.COMBAT_ELEMENTS[k]))
	await _frames(30)
	var picture := await _shot("1_four_schools_8m")
	var eyes: Array[Color] = []
	for y in bodies:
		var head := (y.parts["head"] as RagdollPart).global_position
		var at := player.camera.unproject_position(head)
		eyes.append(_patch_colour(picture, at))
		print("eye %-6s at (%d, %d) %s" % [y.body_element, at.x, at.y, _hex(eyes[-1])])
	var closest := 1.0
	for a in eyes.size():
		for b in range(a + 1, eyes.size()):
			var gap := Vector3(eyes[a].r - eyes[b].r, eyes[a].g - eyes[b].g, eyes[a].b - eyes[b].b).length()
			closest = minf(closest, gap)
	_check("four schools read as four colours at 8 m (closest pair %.2f ≥ %.2f)" % [closest, COLOUR_GAP],
		closest >= COLOUR_GAP)

	# 2. The real hit path: a counter (Ink on Storm) and the same school (Storm on Storm).
	var counter_dmg := await _hit_once(run, player, director, Elements.INK, Elements.STORM, "2_counter_ink_on_storm")
	var same_dmg := await _hit_once(run, player, director, Elements.STORM, Elements.STORM, "3_same_storm_on_storm")
	var plain_dmg := await _hit_once(run, player, director, Elements.NONE, Elements.STORM, "4_plain_on_storm")
	print("hit damage: counter %.1f, same school %.1f, plain steel %.1f" % [counter_dmg, same_dmg, plain_dmg])
	_check("a counter hit does more than plain steel, and the same school less",
		counter_dmg > plain_dmg * 1.3 and same_dmg < plain_dmg * 0.7)
	run.queue_free()


## One yōkai of [param defender] school, struck once by the blade imbued with [param attacker]
## school, at the real katana hit path. Returns the damage the body took.
func _hit_once(run: RunGame, player: DesktopPlayer, director: WaveDirector, attacker: String, defender: String, shot: String) -> float:
	director.clear_enemies()
	if attacker == Elements.NONE:
		run.element_system.reset()
	else:
		run.element_system.imbue(attacker, 20.0)
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	await _frames(4)
	var y := director.spawn_enemy_at(player.global_position + Vector3(0.0, 0.0, -1.6), player.global_position, defender)
	y.configure_kind(Yokai.Kind.SWARM, defender, 900.0)
	await _frames(30)
	var katana: HeldWeapon = run.katana
	var chest: RagdollPart = y.parts["chest"]
	var before := y.hp
	var pose := Basis(Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0))
	katana.global_transform = Transform3D(pose, chest.global_position + Vector3(0.0, 0.0, 0.5))
	var across := (katana.global_basis * -katana.spine_direction).normalized()
	katana._handle_hit({"collider": chest, "point": chest.global_position, "speed": 9.0,
		"direction": across, "normal": -across})
	await _frames(2)
	await _shot(shot)
	var dealt := before - y.hp
	director.clear_enemies()
	return dealt


func _ground(director: WaveDirector, x: float, z: float) -> float:
	return float(director.ground_height.call(x, z)) if director.ground_height.is_valid() else 0.0


## Average colour of a (2·PATCH_HALF+1)² patch around [param at] in the picture.
func _patch_colour(img: Image, at: Vector2) -> Color:
	var sum := Vector3.ZERO
	var n := 0
	for dx in range(-PATCH_HALF, PATCH_HALF + 1):
		for dy in range(-PATCH_HALF, PATCH_HALF + 1):
			var px := clampi(int(at.x) + dx, 0, img.get_width() - 1)
			var py := clampi(int(at.y) + dy, 0, img.get_height() - 1)
			var c := img.get_pixel(px, py)
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	return Color(sum.x / n, sum.y / n, sum.z / n)


func _hex(c: Color) -> String:
	return "#%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
	return img

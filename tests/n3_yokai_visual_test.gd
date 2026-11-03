extends Node
## N3 visual check on the real run scene, windowed (not headless): the yōkai's new mask and
## tapered body must read in the picture. Pixel checks:
##   1. four schools, 8 m ahead: the eye colours still differ (the D17 gap, COLOUR_GAP);
##   2. one swarm yōkai, 3 m ahead: its silhouette differs from the fog behind it by at
##      least SILHOUETTE_CONTRAST on average (body pixels against the same pixels with the
##      yōkai hidden, from the same frame).
## Shots (for docs/n3, PRE and POST from the same camera):
##   godot --path . --fixed-fps 90 res://tests/n3_yokai_visual_test.tscn -- --shots docs/n3
## Time is stepped by frames, not waited for. The headless suite reports SKIP.

const RUN_SCENE := preload("res://scenes/run.tscn")
## Patch around each yōkai's eye, sampled in the picture (pixels, half-width).
const PATCH_HALF := 2
## Two schools' eye colours must differ by at least this much (RGB distance, 0..1 scale).
const COLOUR_GAP := 0.12
## Mean luminance change of the silhouette against the fog (0..1 scale).
const SILHOUETTE_CONTRAST := 0.05
## Mean luminance change of the head (mask, horns, eyes) against the fog at 3 m: the face must
## read as a face, not a dark patch. Measured on the POST build with a margin.
const MASK_CONTRAST := 0.08
## The horns against the sky above the head (silhouette contrast of the pixels they change).
const HORN_CONTRAST := 0.05
## The mask's face against the collar under it (mean luminance difference, either direction).
const FACE_HOOD_LUMA := 0.05
## Right eye in the head frame (the mask's socket, YokaiForms.EYE_*). Kept as numbers so the
## same scene also runs on the pre-N3 tree for the PRE shots.
const EYE_LOCAL := Vector3(0.0305, -0.02, 0.13)
## N12: the body's fresnel rim must lift the yōkai's pixels at 4 m by at least this much mean
## luminance against the same frame with the rim off (it is what separates it from the fog).
const RIM_LIFT := 0.006

var out_dir := ""
var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  yōkai pixel checks need a window (run windowed, see docs/n3)")
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
	# The run-start controls hint (added after N3) floats over the yōkai's head in this view.
	run.controls_hint_shown = true
	add_child(run)
	var player := run.player as DesktopPlayer
	var director := run.wave_director
	director.stop_director()
	director.clear_enemies()
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	await _frames(20)

	# 1. Four schools at 8 m: the eyes must still tell the schools apart.
	var bodies: Array[Yokai] = []
	var xs := [-2.4, -0.8, 0.8, 2.4]
	for k in 4:
		var x: float = xs[k]
		bodies.append(director.spawn_enemy_at(Vector3(x, _ground(director, x, -5.8), -5.8), player.global_position, Elements.COMBAT_ELEMENTS[k]))
	for b in bodies:
		b.set_pose("stalk")
	await _frames(30)
	var picture := await _shot("2_four_schools_8m")
	var eyes: Array[Color] = []
	for y in bodies:
		var at := _eye_screen_point(player, y)
		eyes.append(_patch_colour(picture, at))
		print("eye %-6s at (%d, %d) %s" % [y.body_element, at.x, at.y, _hex(eyes[-1])])
	var closest := 1.0
	for a in eyes.size():
		for b in range(a + 1, eyes.size()):
			var gap := Vector3(eyes[a].r - eyes[b].r, eyes[a].g - eyes[b].g, eyes[a].b - eyes[b].b).length()
			closest = minf(closest, gap)
	_check("four schools read as four colours at 8 m (closest pair %.2f ≥ %.2f)" % [closest, COLOUR_GAP],
		closest >= COLOUR_GAP)
	director.clear_enemies()

	# 2. One swarm yōkai at 3 m: the silhouette against the fog, from the same frame.
	var near := director.spawn_enemy_at(Vector3(0.0, _ground(director, 0.0, -0.8), -0.8), player.global_position, Elements.NONE)
	near.set_pose("stalk")
	await _frames(30)
	var shown := await _shot("1_swarm_3m")
	near.visible = false
	await RenderingServer.frame_post_draw
	var fog := get_viewport().get_texture().get_image()
	if out_dir != "":
		fog.save_png(out_dir.path_join("1_swarm_3m_fog_only.png"))
	near.visible = true
	var contrast := _silhouette_contrast(shown, fog, _body_box(player, near))
	print("silhouette contrast at 3 m: %.3f (≥ %.2f)" % [contrast, SILHOUETTE_CONTRAST])
	_check("the yōkai's silhouette reads against the fog at 3 m (contrast %.3f ≥ %.2f)" % [contrast, SILHOUETTE_CONTRAST],
		contrast >= SILHOUETTE_CONTRAST)
	var mask_contrast := _silhouette_contrast(shown, fog, _head_box(player, near))
	print("mask (head) contrast at 3 m: %.3f (≥ %.2f)" % [mask_contrast, MASK_CONTRAST])
	_check("the demon mask reads against the fog at 3 m (contrast %.3f ≥ %.2f)" % [mask_contrast, MASK_CONTRAST],
		mask_contrast >= MASK_CONTRAST)
	var zones := _head_zones(player, near)
	var horn_contrast := _silhouette_contrast(shown, fog, zones.horns)
	var horn_pixels := _changed_pixels(shown, fog, zones.horns)
	print("horns against the sky at 3 m: contrast %.3f, changed pixels %d" % [horn_contrast, horn_pixels])
	_check("the horns show against the sky at 3 m (contrast %.3f ≥ %.2f, %d px)" % [horn_contrast, HORN_CONTRAST, horn_pixels],
		horn_contrast >= HORN_CONTRAST and horn_pixels >= 6)
	var face := _mean_luma(shown, zones.face)
	var hood := (_mean_luma(shown, zones.hood_l) + _mean_luma(shown, zones.hood_r)) * 0.5
	print("face %.3f against hood %.3f (|Δ| %.3f ≥ %.2f)" % [face, hood, absf(face - hood), FACE_HOOD_LUMA])
	# An absolute difference: the red face separates from the navy collar by hue and luminance together.
	_check("the mask's face differs in luminance from the collar at 3 m (|Δ| %.3f ≥ %.2f)" % [absf(face - hood), FACE_HOOD_LUMA],
		absf(face - hood) >= FACE_HOOD_LUMA)
	# A close look at the face (1.5 m): the mask, eyes and sigil, for the shot log.
	near.global_position = Vector3(0.0, _ground(director, 0.0, 0.7), 0.7)
	near.place_at(near.global_position, 0.0)
	await _frames(30)
	await _shot("1b_swarm_1m5")
	director.clear_enemies()

	# N12: one swarm yōkai at 4 m (the video distance): the rounded body with its rim reads
	# against the fog, and the rim is what lifts it (the same frame with the rim off).
	var mid := director.spawn_enemy_at(Vector3(0.0, _ground(director, 0.0, -1.8), -1.8), player.global_position, Elements.NONE)
	mid.set_pose("stalk")
	await _frames(30)
	var lit := await _shot("n12_swarm_4m")
	var box := _body_box(player, mid)
	mid.visible = false
	await RenderingServer.frame_post_draw
	var fog4 := get_viewport().get_texture().get_image()
	mid.visible = true
	mid._skin.set_shader_parameter("rim_tint", Color.BLACK)
	await RenderingServer.frame_post_draw
	var unlit := get_viewport().get_texture().get_image()
	mid._skin.set_shader_parameter("rim_tint", Yokai.SKIN_RIM)
	var c4 := _silhouette_contrast(lit, fog4, box)
	var lift := _mean_luma(lit, box) - _mean_luma(unlit, box)
	print("4 m: silhouette contrast %.3f, rim lift %.4f" % [c4, lift])
	_check("the yōkai reads against the fog at 4 m (contrast %.3f ≥ %.2f)" % [c4, SILHOUETTE_CONTRAST], c4 >= SILHOUETTE_CONTRAST)
	# The box is mostly fog, so the lift is diluted: a small mean means a clear edge.
	_check("the body's rim lifts its silhouette at 4 m (Δ luma %.4f ≥ %.3f)" % [lift, RIM_LIFT], lift >= RIM_LIFT)
	director.clear_enemies()

	# 3. Elite at 3 m, and the same body in a Kirisute cut (the pieces keep the mask on the head piece).
	var elite := director.spawn_elite_at(Vector3(0.0, 0.0, -0.8), player.global_position, Elements.INK)
	elite.set_pose("stalk")
	await _frames(30)
	await _shot("3_elite_ink_3m")
	director.clear_enemies()

	var cut := director.spawn_enemy_at(Vector3(0.0, 0.0, -2.0), player.global_position, Elements.STORM)
	cut.configure_kind(Yokai.Kind.SWARM, Elements.STORM, 900.0)
	await _frames(30)
	var chest := cut.parts["chest"] as RagdollPart
	var pieces_before := KirisuteChunk._alive.size()
	cut.receive_hit(chest, {
		"base_damage": 40.0, "zone": "torso", "element": Elements.STORM, "kirisute_offer": true,
		"point": chest.global_position, "direction": Vector3.RIGHT, "blade_axis": Vector3.UP,
		"knockback": Vector3.ZERO, "impulse": 14.0, "strike": "edge", "speed": 9.0,
	})
	await _frames(3)
	var pieces := KirisuteChunk._alive.size() - pieces_before
	_check("a Kirisute cut splits the yōkai into two pieces with skin and cap (%d new)" % pieces, pieces >= 2)
	await _shot("4_kirisute_cut")
	director.clear_enemies()

	# The Oni boss close by: the demon mask on the boss (N3, the same mask as the yōkai).
	var oni := director.spawn_oni_boss(player.global_position)
	oni.global_position = Vector3(0.0, 0.0, -0.2)
	oni.home_position = oni.global_position
	oni.rotation.y = 0.0
	oni.reset_body()
	await _frames(30)
	await _shot("5_oni_close")
	director.clear_enemies()

	run.queue_free()


func _eye_screen_point(player: DesktopPlayer, y: Yokai) -> Vector2:
	var head := y.parts["head"] as RagdollPart
	return player.camera.unproject_position(head.to_global(EYE_LOCAL))


## The screen box of one yōkai (head to feet, with a margin), from its body parts.
## The screen box of one yōkai's head (the mask and horns), about 1.3 head radii around its centre.
func _head_box(player: DesktopPlayer, y: Yokai) -> Rect2i:
	var head := y.parts["head"] as RagdollPart
	var centre := player.camera.unproject_position(head.global_position)
	var edge := player.camera.unproject_position(head.global_position + player.camera.global_basis.x * 0.09)
	var r := absf(edge.x - centre.x) * 1.3
	return Rect2i(Vector2i(centre - Vector2(r, r)), Vector2i(Vector2(2.0 * r, 2.0 * r)))


## Screen zones of one yōkai's head: the horns above it, the face (centre) and the hood at each side.
func _head_zones(player: DesktopPlayer, y: Yokai) -> Dictionary:
	var box := _head_box(player, y)
	var c := Vector2(box.position) + Vector2(box.size) * 0.5
	var r := float(box.size.x) * 0.5 / 1.3
	return {
		"horns": Rect2i(Vector2i(c + Vector2(-1.5 * r, -2.6 * r)), Vector2i(Vector2(3.0 * r, 1.2 * r))),
		"face": Rect2i(Vector2i(c + Vector2(-0.45 * r, -0.4 * r)), Vector2i(Vector2(0.9 * r, 0.9 * r))),
		# The hood (the head's dark neck and collar under the mask; the head sphere is hidden by the
		# mask, so this is the body the face sits on). The fog beside the head is not measured.
		"hood_l": Rect2i(Vector2i(c + Vector2(-0.9 * r, 1.0 * r)), Vector2i(Vector2(0.8 * r, 0.5 * r))),
		"hood_r": Rect2i(Vector2i(c + Vector2(0.1 * r, 1.0 * r)), Vector2i(Vector2(0.8 * r, 0.5 * r))),
	}


func _changed_pixels(with_body: Image, fog: Image, box: Rect2i) -> int:
	var n := 0
	for py in range(maxi(box.position.y, 0), mini(box.end.y, with_body.get_height())):
		for px in range(maxi(box.position.x, 0), mini(box.end.x, with_body.get_width())):
			var a := fog.get_pixel(px, py)
			var b := with_body.get_pixel(px, py)
			if absf(_luma(a) - _luma(b)) + absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.04:
				n += 1
	return n


func _mean_luma(img: Image, box: Rect2i) -> float:
	var total := 0.0
	var n := 0
	for py in range(maxi(box.position.y, 0), mini(box.end.y, img.get_height())):
		for px in range(maxi(box.position.x, 0), mini(box.end.x, img.get_width())):
			total += _luma(img.get_pixel(px, py))
			n += 1
	return total / float(maxi(n, 1))


func _body_box(player: DesktopPlayer, y: Yokai) -> Rect2i:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for part_name in ["head", "chest", "pelvis", "leg_l", "leg_r"]:
		var p := y.parts[part_name] as RagdollPart
		var s := player.camera.unproject_position(p.global_position)
		lo = lo.min(s)
		hi = hi.max(s)
	var margin := 14.0
	return Rect2i(Vector2i(lo - Vector2(margin, margin)), Vector2i(hi - lo + Vector2(2.0 * margin, 2.0 * margin)))


## Mean luminance change, over the pixels the yōkai changes in [param with_body] against
## [param fog] (the same frame with it hidden): how far its silhouette stands off the fog.
func _silhouette_contrast(with_body: Image, fog: Image, box: Rect2i) -> float:
	var total := 0.0
	var n := 0
	var x0 := clampi(box.position.x, 0, with_body.get_width() - 1)
	var y0 := clampi(box.position.y, 0, with_body.get_height() - 1)
	var x1 := clampi(box.end.x, 0, with_body.get_width() - 1)
	var y1 := clampi(box.end.y, 0, with_body.get_height() - 1)
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var a := fog.get_pixel(px, py)
			var b := with_body.get_pixel(px, py)
			var changed := absf(_luma(a) - _luma(b)) + absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			if changed > 0.04:
				total += absf(_luma(b) - _luma(a))
				n += 1
	return total / float(n) if n > 0 else 0.0


static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


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
	if img and out_dir != "":
		img.save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)
	return img

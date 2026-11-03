extends Node
## N9 pixel checks of the menu board on the real run scene (windowed; headless reports SKIP).
## The menu is opened next to a tree in the night forest, through PauseController, and the
## rendered frame is measured:
##  a) the frame is really there: the four rails read as lacquer (red-dominant, not fog or
##     paper) and the gilt corner fittings as gold;
##  b) the content is contrasted: title and body text against the paper >= 4.5 : 1, and the
##     paper itself is not black;
##  c) the board sits in the middle of the view and fills a good part of it;
##  d) from 30° to the side (2.2 m away) the board's thickness shows: the outer wall of the
##     near rail is several pixels wide and lacquer-coloured.
## --shots DIR saves the review set (tree, settings, controls map, 30°, credits, mid-lift);
## --before only takes the pictures (used on the commit before N9, which has no board API).
##   godot --path . --fixed-fps 90 res://tests/n9_menu_visual_test.tscn -- --desktop --shots /abs/dir [--before]

const RUN_SCENE := preload("res://scenes/run.tscn")
const MIN_CONTRAST := 4.5
const MIN_WALL_PX := 4.0

var out_dir := ""
var before := false
var failures := 0
var run: RunGame
var player: DesktopPlayer
var cam: Camera3D
var menu: SkillTreeMenu


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  N9 menu pixel checks need a window (run windowed, see docs/n9)")
		get_tree().quit(0)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
		DirAccess.make_dir_recursive_absolute(out_dir)
	before = args.has("--before")
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://n9_shots_save.cfg"
	VrComfortSettings.sandbox_enabled = false
	add_child(run)
	player = run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(40)
	# Stand 2.6 m from a trunk's bark, facing it: the board hangs clear with the tree behind it.
	var trunk := _nearest_trunk()
	var tree_pos := Vector3(trunk.x, 0.0, trunk.y)
	var dir := (Vector3.ZERO - tree_pos).normalized()
	if dir.length() < 0.1:
		dir = Vector3.BACK
	var stand := tree_pos + dir * (trunk.z + 2.6)
	stand.y = run.forest_world.height_at(stand.x, stand.z)
	player.teleport(stand, atan2(-(tree_pos.x - stand.x), -(tree_pos.z - stand.z)))
	await _frames(40)
	run.skill_points = 6
	run.unlock_skill("petal_sense")
	run.element_system.imbue(Elements.SAKURA)
	run.element_system.element_time_remaining = 14.0
	var fwd := player.get_look_direction()
	run.wave_director.spawn_enemy_at(stand + fwd * 5.0 + Vector3(1.6, 0, 0), stand)
	player.hand_offset = Vector3(0.55, -0.45, 0.0)
	await _frames(60)

	cam = Camera3D.new()
	add_child(cam)
	cam.fov = player.camera.fov
	cam.near = 0.05
	cam.global_transform = player.camera.global_transform
	cam.current = true

	run.pause_controller.open()
	menu = run.pause_controller.menu
	await _frames(40)
	cam.global_transform = player.camera.global_transform
	menu.select_node("razor_petals")
	var cp := cam.global_position
	menu.update_pointer("mouse", cp, (menu.canvas_to_world(Vector2(1260, 830)) - cp).normalized(), false, false)
	await _frames(10)
	var img := await _shot("01_tree")
	if not before:
		_check_frame(img)
		_check_content(img)
		_check_framing(img)

	menu.select_settings()
	menu.canvas.settings_page = SkillTreeCanvas.PAGE_MOVE
	await _frames(12)
	await _shot("02_settings_movement")
	menu.canvas.settings_page = SkillTreeCanvas.PAGE_CONTROLS
	await _frames(12)
	await _shot("03_controls_map")

	# 30° to the board's right, 2.2 m from its centre, a little above: the object, not the card.
	menu.select_element(Elements.SAKURA)
	await _frames(10)
	var centre := menu.global_position
	var normal := menu.global_basis.z.normalized()
	var right := menu.global_basis.x.normalized()
	cam.global_position = centre + (normal * cos(deg_to_rad(30.0)) + right * sin(deg_to_rad(30.0))) * 2.2 + Vector3.UP * 0.3
	cam.look_at(centre, Vector3.UP)
	await _frames(6)
	var angled := await _shot("04_angle30")
	if not before:
		_check_thickness(angled)
	cam.global_transform = player.camera.global_transform

	if not before:
		menu.call("select_credits")
		await _frames(12)
		await _shot("05_credits")
		menu.call("scroll_credits", 17)
		await _frames(12)
		await _shot("06_credits_scrolled")
		# Mid-lift: about 0.1 s after opening.
		run.pause_controller.close()
		await _frames(30)
		run.pause_controller.open()
		await _frames(9)
		await _shot("07_opening_lift")
	run.pause_controller.close()
	await _frames(20)
	run.queue_free()


# --- Checks -------------------------------------------------------------------------

## Board-space point -> screen pixel (through the animated board node).
func _px(local: Vector3) -> Vector2:
	var board := menu.get_node("Board") as Node3D
	return cam.unproject_position(board.global_transform * local)


func _sp(u: float, y: float, d: float) -> Vector3:
	return SkillTreeMenu.surface_point(u, y, d)


func _check_frame(img: Image) -> void:
	var half := SkillTreeMenu.PANEL_SIZE * 0.5
	var fw := SkillTreeMenu.FRAME_WIDTH
	var face := SkillTreeMenu.FRAME_FRONT
	var rails := {
		"top": _sp(0.0, half.y + fw * 0.45, face), "bottom": _sp(0.0, -(half.y + fw * 0.45), face),
		"left": _sp(-(half.x + fw * 0.45), 0.0, face), "right": _sp(half.x + fw * 0.45, 0.0, face),
	}
	var lacquer := 0
	var notes: Array[String] = []
	for k: String in rails:
		var c := _avg(img, _px(rails[k]))
		var ok := c.r > 1.5 * c.g and c.r > 1.4 * c.b and c.r > 0.03 and c.r < 0.6
		lacquer += 1 if ok else 0
		notes.append("%s %s" % [k, _rgb(c)])
	_check("N9: all four rails render as red-black lacquer (%d of 4: %s)" % [lacquer, ", ".join(notes)], lacquer == 4)
	var gold := 0
	notes.clear()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := _sp(sx * (half.x + fw - 0.04), sy * (half.y + fw * 0.5 + 0.001), face + 0.0028)
			var c := _avg(img, _px(p))
			var ok := c.r > 0.3 and c.r > c.g and c.g > c.b and c.r - c.b > 0.12
			gold += 1 if ok else 0
			notes.append(_rgb(c))
	_check("N9: the gilt corner fittings render as gold (%d of 4: %s)" % [gold, ", ".join(notes)], gold >= 3)


func _check_content(img: Image) -> void:
	var title := _contrast(img, Rect2(150, 24, 400, 44))
	_check("N9: the title is contrasted against the paper (%.1f : 1 >= %.1f)" % [title, MIN_CONTRAST], title >= MIN_CONTRAST)
	var body := _contrast(img, Rect2(1020, 410, 480, 110))
	_check("N9: the body text of the detail pane is contrasted (%.1f : 1 >= %.1f)" % [body, MIN_CONTRAST], body >= MIN_CONTRAST)
	# The paper is warm lacquer, not black: an empty patch of the tree page.
	var paper := _avg(img, _canvas_px(Vector2(880, 300)), 4)
	_check("N9: the paper is not black (%s, brightest channel >= 0.05)" % _rgb(paper), maxf(paper.r, maxf(paper.g, paper.b)) >= 0.05)


func _check_framing(img: Image) -> void:
	var size := Vector2(img.get_width(), img.get_height())
	var c := _canvas_px(SkillTreeCanvas.SIZE * 0.5)
	var l := _canvas_px(Vector2(0, 500))
	var r := _canvas_px(Vector2(1600, 500))
	_check("N9: the board's centre is in the middle of the view (%.0f, %.0f of %s)" % [c.x, c.y, size],
		absf(c.x - size.x * 0.5) < size.x * 0.2 and absf(c.y - size.y * 0.5) < size.y * 0.3)
	_check("N9: the board fills %.0f%% of the width (>= 50%%)" % ((r.x - l.x) / size.x * 100.0), (r.x - l.x) >= size.x * 0.5)


func _check_thickness(img: Image) -> void:
	var half := SkillTreeMenu.OUTER_SIZE * 0.5
	var front := _px(_sp(half.x, 0.0, SkillTreeMenu.FRAME_FRONT - 0.008))
	var back := _px(_sp(half.x, 0.0, -SkillTreeMenu.BOARD_DEPTH))
	var wall := front.distance_to(back)
	var c := _avg(img, (front + back) * 0.5, 1)
	_check("N9: at 30° the near rail's outer wall is %.1f px wide (>= %.0f): the board has thickness" % [wall, MIN_WALL_PX], wall >= MIN_WALL_PX)
	_check("N9: and that wall is lacquer, not fog (%s)" % _rgb(c), c.r > 1.3 * c.b and c.r > 1.2 * c.g)


# --- Pixels -------------------------------------------------------------------------

func _canvas_px(p: Vector2) -> Vector2:
	return cam.unproject_position(menu.canvas_to_world(p))


func _avg(img: Image, p: Vector2, r := 1) -> Color:
	var acc := Color(0, 0, 0, 0)
	var n := 0
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := clampi(roundi(p.x) + dx, 0, img.get_width() - 1)
			var y := clampi(roundi(p.y) + dy, 0, img.get_height() - 1)
			acc += img.get_pixel(x, y)
			n += 1
	return acc / float(n)


## Text against its ground in a canvas rect: (L98 + 0.05) / (L30 + 0.05), relative luminance.
func _contrast(img: Image, rect: Rect2) -> float:
	var a := _canvas_px(rect.position)
	var b := _canvas_px(rect.end)
	var lums: Array[float] = []
	for x in range(int(minf(a.x, b.x)), int(maxf(a.x, b.x)) + 1):
		for y in range(int(minf(a.y, b.y)), int(maxf(a.y, b.y)) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				lums.append(_lum(img.get_pixel(x, y)))
	if lums.size() < 20:
		return 0.0
	lums.sort()
	var lo := lums[int(lums.size() * 0.30)]
	var hi := lums[int(lums.size() * 0.98)]
	return (hi + 0.05) / (lo + 0.05)


static func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


static func _rgb(c: Color) -> String:
	return "(%.2f %.2f %.2f)" % [c.r, c.g, c.b]


func _shot(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if out_dir != "" and img and not img.is_empty():
		var tag := "before" if before else "after"
		img.save_png(out_dir.path_join("n9_%s_%s.png" % [tag, name]))
		print("saved ", name)
	return img


func _nearest_trunk() -> Vector3:
	var best := Vector3(0.0, 4.0, 0.3)
	var best_d := INF
	for cell in run.forest_world._trunk_cells:
		for e: Vector3 in run.forest_world._trunk_cells[cell]:
			var d := Vector2(e.x, e.y).length()
			if e.z >= 0.25 and d > 3.0 and d < best_d:
				best_d = d
				best = e
	return best


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame

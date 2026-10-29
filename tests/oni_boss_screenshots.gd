extends Node
## Screenshot generator for D15: the Oni boss at real scale, mid-telegraph and with its speech bubble.
##
## Windowed only (no --headless): the frame has to be rendered before it can be read back.
## Before each PNG the composition is checked, and the run stops with exit 1 (writing no PNG
## for that shot) if the boss is not standing at its height, its head, feet, kanabō or bubble
## leave the frame, or its silhouette matches the background behind it.
## Default output is /tmp/hanabi_shots; the committed references in docs/d15 are only
## refreshed with an explicit --shots docs/d15.
##   godot --path . --fixed-fps 90 res://tests/oni_boss_screenshots.tscn -- --desktop --shots docs/d15

const RUN_SCENE := preload("res://scenes/run.tscn")
const SILHOUETTE_MIN_DELTA := 0.10
const FRAME_MARGIN := 24.0
const HEAD_TOP_OFFSET := 0.17  # head sphere radius 0.115 × ONI_SCALE 1.5
const SETTLE_FRAMES := 45
const TELEGRAPH_ORBIT_DEG := 35.0

var out_dir := "/tmp/hanabi_shots"
var run: RunGame
var player: DesktopPlayer
var oni: RunOniBoss
var cam: Camera3D


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		print("\nWATCHDOG TIMEOUT in oni_boss_screenshots!")
		get_tree().quit(1)
	)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	if DisplayServer.get_name() == "headless":
		print("FAIL  screenshots need a window: run without --headless")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)

	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	player = run.player as DesktopPlayer
	cam = player.camera
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	oni = run.wave_director.spawn_oni_boss(player.global_position)
	# The player's own katana crosses the boss in the reference frames; hide it so the Oni reads.
	if run.katana:
		run.katana.visible = false
	await _frames(12)

	if not await _scale_shot():
		_finish(1)
		return
	if not await _telegraph_shot():
		_finish(1)
		return
	if not await _bubble_shot():
		_finish(1)
		return
	_finish(0)


func _finish(code: int) -> void:
	print("\n%s" % ("ALL PASSED (screenshots generated)" if code == 0 else "FAILURES (remaining shots not written)"))
	get_tree().quit(code)


## 1. Scale: the whole boss, 5 m in front of the player, guard stance.
func _scale_shot() -> bool:
	_stage_boss(Vector3(0.0, 0.0, -5.0), 0.0)
	oni.set_attacks_enabled(false)
	oni.set_pose("guard")
	_stage_player(Vector3.ZERO, Vector3(0.0, 1.35, -5.0))
	await _frames(SETTLE_FRAMES)
	if not _standing("scale"):
		return false
	var head := oni.head_part().global_position
	var pts: Array[Vector3] = [head + Vector3.UP * HEAD_TOP_OFFSET, _feet_point()]
	return await _shoot("01_boss_scale_vs_player", pts, _torso_point(), false)


## 2. Telegraph: the kanabō is raised above the head during the windup of an overhead slam.
func _telegraph_shot() -> bool:
	# Stands 2.9 m out: inside the Oni's attack gate (2.85 m + 0.55 m step), wide enough to keep the raised club in frame.
	_stage_boss(Vector3(0.0, 0.0, -2.9), 0.0)
	oni.set_attacks_enabled(true)
	var brain := oni.brain as DuelistBrain
	brain.set_seed(1)
	brain.difficulty.move_speed = 0.0
	brain.difficulty.hesitate_chance = 0.0
	brain.difficulty.feint_chance = 0.0
	_stage_player(Vector3.ZERO, Vector3(0.0, 1.45, -2.9))
	await _frames(SETTLE_FRAMES)
	if not _standing("telegraph"):
		return false
	# The boss drifts during the settle frames, and a forced attack only starts inside
	# range + MAX_STEP, so put the player 2.9 m from where the boss actually stands.
	var b := oni.root_part().global_position
	var toward := player.global_position - b
	toward.y = 0.0
	toward = toward.normalized() if toward.length_squared() > 0.01 else Vector3(0.0, 0.0, 1.0)
	# Orbit the camera off the boss's centre line so the raised club sits against the sky, not the mask.
	var stand := b + toward.rotated(Vector3.UP, deg_to_rad(TELEGRAPH_ORBIT_DEG)) * 2.9
	_stage_player(Vector3(stand.x, 0.0, stand.z), Vector3(b.x, 1.45, b.z))
	# Face the player and let the brain settle in STALK first (same sequence as the combat test).
	oni.face_toward(player.global_position)
	await _frames(6)
	brain.force_attack("vertical")
	var raised := false
	var max_top := -INF
	var max_head := 0.0
	for _k in 120:
		await _frames(1)
		var head_y := oni.head_part().global_position.y
		max_top = maxf(max_top, _kanabo_top().y)
		max_head = head_y
		if brain.attack_phase == DuelistBrain.AttackPhase.WINDUP and _kanabo_top().y > head_y + 0.15:
			raised = true
			break
	if not raised:
		var dist := Vector2(oni.root_part().global_position.x - player.global_position.x, oni.root_part().global_position.z - player.global_position.z).length()
		print("FAIL  telegraph: kanabō never rose above the head during the windup (top %.2f m, head %.2f m, state %d, phase %d, cooldown %.2f, forced '%s', attacks %s, dist %.2f)" % [max_top, max_head, brain.state, brain.attack_phase, brain._cooldown, brain._forced_attack, str(brain.attacks_enabled), dist])
		return false
	# Centre the frame between the raised club and the feet so both stay in shot.
	# A wider lens for this shot: at 2.9 m the raised club and the feet need more vertical field.
	cam.fov = 85.0
	cam.look_at((_kanabo_top() + _feet_point()) * 0.5, Vector3.UP)
	var head_c := oni.head_part().global_position
	var pts: Array[Vector3] = [_kanabo_top(), head_c + Vector3.UP * HEAD_TOP_OFFSET, _feet_point()]
	return await _shoot("02_boss_attack_windup", pts, _torso_point(), false)


## 3. Speech: the bubble shows the AI line above the head, legible against the fog.
func _bubble_shot() -> bool:
	_stage_boss(Vector3(0.0, 0.0, -4.0), 0.0)
	oni.set_attacks_enabled(false)
	oni.set_pose("guard")
	_stage_player(Vector3.ZERO, Vector3(0.0, 2.1, -4.0))
	await _frames(SETTLE_FRAMES)
	if not _standing("speech"):
		return false
	var line := "Ten las spłynie twoją krwią!"
	oni.speech_bubble.instant_show(line)
	await _frames(8)
	if not oni.speech_bubble.is_showing() or oni.speech_bubble.get_text() != line:
		print("FAIL  speech: bubble does not show the AI line (got '%s')" % oni.speech_bubble.get_text())
		return false
	var head := oni.head_part().global_position
	var pts: Array[Vector3] = [head + Vector3.UP * HEAD_TOP_OFFSET, _feet_point()]
	pts.append_array(_bubble_corners())
	return await _shoot("03_boss_speech_bubble", pts, _torso_point(), true)


## Renders the frame with and without the boss, runs every check, and saves the PNG only if all pass.
func _shoot(shot_name: String, must_show: Array[Vector3], torso: Vector3, check_bubble: bool) -> bool:
	if not _in_frame(must_show, shot_name):
		return false
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	oni.visible = false
	await RenderingServer.frame_post_draw
	var bare := get_viewport().get_texture().get_image()
	oni.visible = true
	if shot == null or shot.is_empty() or bare == null or bare.is_empty():
		print("FAIL  %s: no rendered frame (is a window open?)" % shot_name)
		return false
	var px := cam.unproject_position(torso)
	var delta := _color_delta(_sample_color(shot, px, 4), _sample_color(bare, px, 4))
	if delta < SILHOUETTE_MIN_DELTA:
		print("FAIL  %s: silhouette matches the background (delta %.3f < %.2f)" % [shot_name, delta, SILHOUETTE_MIN_DELTA])
		return false
	if check_bubble and not _bubble_legible(shot, shot_name):
		return false
	shot.save_png(out_dir.path_join(shot_name + ".png"))
	print("PASS  %s: silhouette delta %.3f, saved %s" % [shot_name, delta, out_dir.path_join(shot_name + ".png")])
	return true


func _in_frame(points: Array[Vector3], shot_name: String) -> bool:
	var rect := get_viewport().get_visible_rect().grow(-FRAME_MARGIN)
	for p in points:
		if not cam.is_position_in_frustum(p) or not rect.has_point(cam.unproject_position(p)):
			print("FAIL  %s: point %s is not fully in frame (frustum %s, screen %s, rect %s)" % [shot_name, p, cam.is_position_in_frustum(p), cam.unproject_position(p), rect])
			return false
	return true


func _bubble_legible(img: Image, shot_name: String) -> bool:
	var corners := _bubble_corners()
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for c in corners:
		var s := cam.unproject_position(c)
		min_x = minf(min_x, s.x)
		min_y = minf(min_y, s.y)
		max_x = maxf(max_x, s.x)
		max_y = maxf(max_y, s.y)
	var x0 := clampi(int(floor(min_x)), 0, img.get_width() - 1)
	var x1 := clampi(int(ceil(max_x)), 0, img.get_width() - 1)
	var y0 := clampi(int(floor(min_y)), 0, img.get_height() - 1)
	var y1 := clampi(int(ceil(max_y)), 0, img.get_height() - 1)
	var bright := 0
	var dark := 0
	var n := 0
	for x in range(x0, x1 + 1, 2):
		for y in range(y0, y1 + 1, 2):
			var lum := _luminance(img.get_pixel(x, y))
			n += 1
			if lum > 0.45:
				bright += 1
			elif lum < 0.02:
				dark += 1
	# Legible = the bubble has ink (dark plate) and bright glyphs on it.
	var legible := n > 0 and bright >= 0.02 * n and dark >= 0.5 * n
	if not legible:
		print("FAIL  %s: speech bubble is not legible (bright %d, dark %d of %d px)" % [shot_name, bright, dark, n])
	return legible


func _standing(label: String) -> bool:
	var height := oni.get_measured_height()
	var feet_y := oni.get_feet_lowest_y()
	var ground := run.forest_world.height_at(oni.root_part().global_position.x, oni.root_part().global_position.z)
	if height < 2.5 or height > 3.0 or absf(feet_y - ground) > 0.15:
		print("FAIL  %s: boss is not standing (height %.2f m, feet %.2f m above ground %.2f m)" % [label, height, feet_y, ground])
		return false
	return true


## Puts the boss on the forest floor, facing [param yaw] (0 = +Z, toward the player at -Z),
## and resets its ragdoll to the rest pose there.
func _stage_boss(pos: Vector3, yaw: float) -> void:
	pos.y = run.forest_world.height_at(pos.x, pos.z)
	oni.home_position = pos
	oni.anchor_position = pos
	oni.global_rotation = Vector3(0.0, yaw, 0.0)
	oni.reset()
	# A line from the previous shot must not drift into this frame.
	oni.speech_bubble.visible = false


## Stands the player at [param pos] looking at [param look_at_pos] (yaw from the flat direction,
## pitch from the height difference to the camera).
func _stage_player(pos: Vector3, look_at_pos: Vector3) -> void:
	var ground := run.forest_world.height_at(pos.x, pos.z)
	var to := look_at_pos - pos
	player.teleport(Vector3(pos.x, ground, pos.z), atan2(-to.x, -to.z))
	var eye := cam.global_position
	var flat := Vector2(look_at_pos.x - eye.x, look_at_pos.z - eye.z).length()
	cam.rotation.x = atan2(look_at_pos.y - eye.y, flat)


func _feet_point() -> Vector3:
	var root := oni.root_part().global_position
	return Vector3(root.x, oni.get_feet_lowest_y(), root.z)


## Centre of the visible torso shell, the point whose pixels must differ from the background.
func _torso_point() -> Vector3:
	var shell := oni.find_child("OniBodyShell", true, false) as MeshInstance3D
	if shell == null or shell.mesh == null:
		push_warning("OniBodyShell missing: silhouette check falls back to the pelvis")
		return (oni.parts["pelvis"] as RagdollPart).global_position
	return shell.global_transform * shell.mesh.get_aabb().get_center()


## Highest world point of the visible kanabō. Returns a point far below the floor when the
## club is missing, so the frame check fails loudly instead of passing on a stale value.
func _kanabo_top() -> Vector3:
	var club: MeshInstance3D = null
	var arm := oni.parts.get("lower_arm_r") as RagdollPart
	if arm:
		club = arm.find_child("OniKanaboVisual", true, false) as MeshInstance3D
	if club == null or club.mesh == null:
		push_warning("OniKanaboVisual missing on the right forearm")
		return Vector3(0.0, -999.0, 0.0)
	var aabb := club.mesh.get_aabb()
	var best := Vector3.ZERO
	var best_y := -INF
	for k in 8:
		var w := club.global_transform * aabb.get_endpoint(k)
		if w.y > best_y:
			best_y = w.y
			best = w
	return best


## The four corners of the speech bubble plate (1.30 × 0.30 m, billboarded to the camera).
func _bubble_corners() -> Array[Vector3]:
	var c := oni.speech_bubble.global_position
	var r := cam.global_basis.x * 0.65
	var u := cam.global_basis.y * 0.15
	var out: Array[Vector3] = [c - r - u, c + r - u, c + r + u, c - r + u]
	return out


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _sample_color(img: Image, pos: Vector2, radius: int = 2) -> Color:
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	var count := 0
	var cx := int(round(pos.x))
	var cy := int(round(pos.y))
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				sum += img.get_pixel(x, y)
				count += 1
	return sum / maxf(float(count), 1.0)


func _color_delta(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _luminance(c: Color) -> float:
	var lin := func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)

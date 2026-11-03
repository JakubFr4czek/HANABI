extends Node
## F3 screenshots: the opening shrine as the player sees it from 12 m, at 1.5 m (the prompt
## and the warm pulse of the altar), and after the offering. The same script runs before and
## after the change, from the same cameras (windowed, real frames from the game):
##   timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 960x540 res://tests/f3_prompt_shots.tscn -- --shots docs/f3 --tag before

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_f3"
var tag := "shot"
var run: RunGame
var player: DesktopPlayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--tag")
	if i >= 0 and i + 1 < args.size():
		tag = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://f3_shots_save.cfg"
	add_child(run)
	player = run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(40)

	var shrine := run.hokora_manager.shrine_at(Vector2i.ZERO)
	if shrine == null:
		push_error("no opening shrine")
		get_tree().quit(1)
		return
	var altar := shrine.altar_position()
	# The shrine's front (+Z): the side the altar and the sign face.
	var dir := -shrine.global_basis.z
	dir.y = 0.0
	dir = dir.normalized()

	# 1. From 12 m: the shrine in the fog, no prompt yet.
	_stand_facing(altar, altar - dir * 12.0)
	await _frames(60)
	await _shot("%s_01_far_12m" % tag)

	# 2. At 1.5 m: inside the prompt reach, looking down at the altar as a player does.
	_stand_facing(altar, altar - dir * 1.5)
	_look_down(20.0)
	await _frames(60)
	await _shot("%s_02_near_1p5m" % tag)

	# 3. The press: E is the desktop activation (a real key event, not a direct call).
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.keycode = KEY_E
	key.pressed = true
	get_viewport().push_input(key)
	await _frames(6)
	await _shot("%s_03_cards_rising" % tag)
	await _frames(90)

	# 4. The cut: the damage card. The shrine goes dark for the run.
	for c in get_tree().get_nodes_in_group("ofuda_talismans"):
		var card := c as OfudaTalisman
		if int(card.entry.get("kind", -1)) == RunBuffs.Kind.DAMAGE:
			card.slice(card.global_position, Vector3.RIGHT)
	await _frames(60)
	_stand_facing(altar, altar - dir * 1.5)
	_look_down(20.0)
	await _frames(40)
	await _shot("%s_04_after_offering" % tag)
	get_tree().quit(0)


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)


## Puts the player at [param stand] (ground height), facing [param target].
func _stand_facing(target: Vector3, stand: Vector3) -> void:
	stand.y = run.forest_world.height_at(stand.x, stand.z)
	var yaw := atan2(-(target.x - stand.x), -(target.z - stand.z))
	player.teleport(stand, yaw)
	run.forest_world.finish_pending()


func _look_down(degrees: float) -> void:
	player._pitch = deg_to_rad(-degrees)
	player.camera.rotation.x = player._pitch


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame

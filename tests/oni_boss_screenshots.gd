extends Node
## Screenshot generator for D15: Oni Boss AI, Scale, Combat, and Speech Bubble.
## Saves real in-game rendered frames to docs/d15/
## Usage:
##   godot --path . --fixed-fps 90 res://tests/oni_boss_screenshots.tscn -- --desktop --shots docs/d15

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "docs/d15"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()

	# 1. Scale & Stance Shot (~4.8 m away, full body in frame)
	var oni := run.wave_director.spawn_oni_boss(player.global_position)
	oni.anchor_position = Vector3(0.0, 0.0, -4.8)
	oni.home_position = oni.anchor_position
	if oni.parts.has("pelvis"):
		(oni.parts["pelvis"] as RagdollPart).global_position = Vector3(0.0, 1.47, -4.8)
	oni.set_attacks_enabled(false)
	oni.set_pose("guard")
	player.teleport(Vector3(0.0, 0.0, 0.0), 0.0)
	player.camera.rotation.x = deg_to_rad(2.0)
	await _frames(30)
	await _shot("01_boss_scale_vs_player")

	# 2. Attack Wind-Up Shot (~2.6 m away, Kanabō raised overhead, glowing eyes)
	player.teleport(Vector3(0.0, 0.0, -2.4), 0.0)
	player.camera.rotation.x = deg_to_rad(14.0)
	oni.set_attacks_enabled(true)
	oni.play_attack("vertical")
	await _frames(18)
	await _shot("02_boss_attack_windup")

	# 3. Speech Bubble Shot (billboard displayed over head)
	player.teleport(Vector3(0.0, 0.0, -1.8), 0.0)
	player.camera.rotation.x = deg_to_rad(18.0)
	if oni.speech_bubble:
		oni.speech_bubble.show_speech("Ten las spłynie twoją krwią!", 10.0)
	await _frames(22)
	await _shot("03_boss_speech_bubble")

	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await _frames(2)
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("SAVED SHOT: ", out_dir.path_join(name + ".png"))

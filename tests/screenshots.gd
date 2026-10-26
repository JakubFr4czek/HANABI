extends Node
## Renders the test room (desktop rig) and saves screenshots to the folder given
## after `--shots`, e.g. `godot --path . res://tests/screenshots.tscn -- --desktop --shots /tmp/x`.
const ROOM := preload("res://scenes/test_room.tscn")
var out_dir := "user://screenshots"
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var room = ROOM.instantiate()
	add_child(room)
	var player: DesktopPlayer = room.player
	player.global_position = Vector3(0.3, 0, 2.2)
	await _frames(150)
	await _shot("1_standing_guard")
	player.global_position = Vector3(0.1, 0, 1.25)
	player.swing_duration = 0.35
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	await _frames(40)
	await _shot("2_mid_slash")
	await _frames(25)
	await _shot("3_after_hit")
	player.swing_duration = 0.1
	for k in 3:
		player.swing(DesktopPlayer.SLASH_HORIZONTAL)
		await _frames(70)
	await _frames(30)
	await _shot("4_knocked_down")
	await _frames(330)
	await _shot("5_got_up")
	player.global_position = Vector3(-1.6, 0, 1.6)
	player.rotation.y = deg_to_rad(-40)
	await _frames(60)
	await _shot("6_side_view")
	get_tree().quit()
func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

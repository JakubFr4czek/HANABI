extends Node
## Renders the test room (desktop rig) and saves screenshots to the folder given
## after `--shots`, e.g. `godot --path . res://tests/screenshots.tscn -- --desktop --shots /tmp/x`.
const ROOM := preload("res://scenes/test_room.tscn")
var out_dir := "user://screenshots"
var room: Node3D
var player: DesktopPlayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	room = ROOM.instantiate()
	add_child(room)
	player = room.player
	var dummy: TrainingDummy = room.dummy

	# 1. Katana in hand, dummy on guard.
	player.teleport(Vector3(0.3, 0, 2.2))
	await _frames(150)
	await _shot("1_katana_guard")

	# 2. Sakura trail mid-slash (slow swing so the frame catches the arc).
	room.katana.set_element(Elements.SAKURA)
	player.teleport(Vector3(0.0, 0, 1.6))
	player.swing_duration = 0.3
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	await _frames(32)
	await _shot("2_sakura_trail")
	await _frames(60)

	# 3. Storm trail, overhead cut, seen from the side.
	room.katana.set_element(Elements.STORM)
	player.teleport(Vector3(-1.4, 0, 1.6), deg_to_rad(-35))
	player.swing_duration = 0.3
	player.swing(DesktopPlayer.SLASH_OVERHEAD)
	await _frames(30)
	await _shot("3_storm_overhead")
	await _frames(60)

	# 4-5. Dummy attacks: windup, then the parry against a high block.
	room.reset_room()
	room.katana.set_element(Elements.NONE)
	player.teleport(Vector3(0.0, 0, 1.3))
	player.force_block = true
	await _frames(90)
	dummy.set_attacks_enabled(true)
	var parried := [false]  # array: lambdas capture locals by value
	var got_windup := false
	GameEvents.parry.connect(func(_p): parried[0] = true)
	for k in 600:
		await get_tree().process_frame
		if not got_windup and (dummy.brain as DummyBrain).phase == DummyBrain.Phase.WINDUP:
			await _frames(25)
			await _shot("4_dummy_windup")
			got_windup = true
		if parried[0]:
			await _frames(3)
			await _shot("5_parry_slowmo")
			break
	dummy.set_attacks_enabled(false)
	player.force_block = false
	await _frames(120)

	# 6. Heavy kanabō in hand.
	player.take_weapon(room.kanabo)
	player.teleport(Vector3(1.6, 0, 1.6), deg_to_rad(35))
	await _frames(90)
	await _shot("6_kanabo")
	get_tree().quit()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

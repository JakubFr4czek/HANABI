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
	# Judge the image, not the debug UI.
	for layer in player.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for dev_ui in ["HitDebugPanel", "HelpLabel"]:
		var n := room.get_node_or_null(dev_ui) as Node3D
		if n:
			n.visible = false

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
	dummy.set_difficulty(preload("res://tests/combat_test.gd").calm_difficulty())
	dummy.set_attacks_enabled(true)
	(dummy.brain as DuelistBrain).force_attack("vertical")
	var parried := [false]  # array: lambdas capture locals by value
	var got_windup := false
	GameEvents.parry.connect(func(_p): parried[0] = true)
	for k in 600:
		await get_tree().process_frame
		if not got_windup and (dummy.brain as DuelistBrain).attack_phase == DuelistBrain.AttackPhase.WINDUP:
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

	player.take_weapon(room.katana)

	# 7. Wide Dojo of the Storm vista with silent branching lightning illuminating the fog & water.
	room.katana.set_element(Elements.STORM)
	player.teleport(Vector3(1.1, 0, 3.8), deg_to_rad(14))
	player.camera.rotation.x = deg_to_rad(-2)
	if room.lightning:
		room.lightning.trigger_strike(-0.22)
	await _frames(2)
	await _shot("7_dojo_storm_vista")

	# 8. Close-up right at the north-western edge of the stone platform looking down & out over the water:
	# clearly shows the stone rim, dark Fresnel depth drop-off at the edge, shore & pillar ripples,
	# wave-broken reflections of the giant torii, and the surface mist fading into dense fog.
	await _frames(45)
	player.teleport(Vector3(-2.6, 0, -3.6), deg_to_rad(28))
	player.camera.rotation.x = deg_to_rad(-19)
	await _frames(90)  # let the camera-following rain refill after the teleport
	await _shot("8_water_and_fog")

	# 9. Macro on the held katana: wet steel, rain beads, black silk wrap.
	room.katana.set_element(Elements.NONE)
	player.teleport(Vector3(0.0, 0, 2.0))
	player.camera.rotation.x = 0.0
	await _frames(60)
	var body := room.katana.get_node("Model/katana/katana_body") as Node3D
	var macro := Camera3D.new()
	macro.fov = 40.0
	macro.near = 0.02
	room.add_child(macro)
	var focus := body.global_transform * Vector3(0.05, 0.035, 0.0)
	var side := (body.global_basis * Vector3.UP).normalized()
	macro.look_at_from_position(focus + side * 0.55 + Vector3(0.0, 0.12, 0.0), focus)
	macro.make_current()
	await _frames(3)
	await _shot("9_katana_macro")
	macro.queue_free()

	get_tree().quit()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

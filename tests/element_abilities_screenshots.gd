extends Node
## Headless-window screenshots of all 8 E2b abilities for visual review.
## Run (needs a display, NOT --headless):
##   Godot --path . res://tests/element_abilities_screenshots.tscn -- --shots /tmp/hanabi_ability_shots

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_ability_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	run.state = RunGame.RunState.PLAYING
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-16.0)
	var dummy := run.wave_director.spawn_enemy_at(Vector3(0.0, 0.0, -1.6), player.global_position)
	await _frames(6)

	var shots: Array = [
		[Elements.SAKURA, 1, "sakura1_senbonzakura"],
		[Elements.SAKURA, 2, "sakura2_hanamai"],
		[Elements.STORM, 1, "storm1_raikiri"],
		[Elements.STORM, 2, "storm2_shiden"],
		[Elements.INK, 1, "ink1_sumi_gaeshi"],
		[Elements.INK, 2, "ink2_kage_nawa"],
		[Elements.SHADOW, 1, "shadow1_kagemusha"],
		[Elements.SHADOW, 2, "shadow2_yami_watari"],
	]
	for entry in shots:
		if dummy == null or not is_instance_valid(dummy) or dummy.is_dead:
			dummy = run.wave_director.spawn_enemy_at(player.global_position + Vector3(0.0, 0.0, -1.6), player.global_position)
		run.element_system.imbue(String(entry[0]), 20.0)
		run.element_system.ability_1_cooldown = 0.0
		run.element_system.ability_2_cooldown = 0.0
		if int(entry[1]) == 1:
			run.element_system.execute_ability_1(Vector3.BACK)
		else:
			run.element_system.execute_ability_2(Vector3.BACK)
		await _frames(2)
		# Self-centred effects (orbit barrier, decoy) sit at the player's feet:
		# step back so they enter the frame instead of hiding under the camera.
		if String(entry[2]) in ["sakura2_hanamai", "shadow1_kagemusha"]:
			player.teleport(player.global_position + Vector3(0.0, 0.0, 2.6), 0.0)
			await _frames(2)
		await _shot(String(entry[2]))
		await _frames(10)
	await _kirisute_shots(run, player)
	run.queue_free()
	get_tree().quit(0)


## D4: each school's finisher. A clean cut splits the yōkai along the blade's plane:
## one frame at the moment of the cut (the hit-stop freezes the world there), and one
## about a second later with the pieces on the ground.
func _kirisute_shots(run: RunGame, player: DesktopPlayer) -> void:
	for element in Elements.COMBAT_ELEMENTS:
		run.skill_points = 1000
		for node: Dictionary in SkillTreeData.nodes_for_element(element):
			run.unlock_skill(String(node.id))
		# One yōkai alone in the frame: the earlier shots' enemies would hide the cut.
		run.wave_director.stop_director()
		run.wave_director.clear_enemies()
		player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
		await _frames(4)
		run.element_system.imbue(element, 20.0)
		var y := run.wave_director.spawn_enemy_at(player.global_position + Vector3(0.0, 0.0, -1.6), player.global_position)
		y.configure_kind(Yokai.Kind.SWARM, Elements.NONE, 900.0)
		await _frames(30)
		var katana: HeldWeapon = run.katana
		var chest: RagdollPart = y.parts["chest"]
		# A level sweep to the right at chest height: the edge leads toward +X, the blade
		# points away from the camera, so the plane is horizontal and the pieces fly
		# sideways out of frame's centre instead of into the lens.
		var pose := Basis(Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0))
		katana.global_transform = Transform3D(pose, chest.global_position + Vector3(0.0, 0.0, 0.5))
		var across := (katana.global_basis * -katana.spine_direction).normalized()
		katana._handle_hit({"collider": chest, "point": chest.global_position, "speed": 12.0,
			"direction": across, "normal": -across})
		await _frames(2)
		await _shot("kirisute_%s_cut" % element)
		# From the side and above, the held katana out of the frame, so both halves read as
		# cut pieces on the ground.
		player.teleport(Vector3(-1.3, 0.0, 1.4), -0.9)
		player.camera.rotation.x = deg_to_rad(-30.0)
		katana.visible = false
		await _frames(90)
		await _shot("kirisute_%s_pieces" % element)
		katana.visible = true
		player.camera.rotation.x = deg_to_rad(-16.0)
		# Let the pieces dissolve before the next school, so each shot shows one cut.
		await _frames(int((ElementBalance.KIRISUTE_PIECE_SECONDS + ElementBalance.KIRISUTE_DISSOLVE_SECONDS) * 90.0) + 30)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)

extends Node
## Yokai close-up (non-headless): idle, winding up (tell), just hit.

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	run.xp_to_next = 999999
	var player := run.player as DesktopPlayer
	player.teleport(Vector3(0, 0, 0), 0.0)
	player.camera.rotation.x = deg_to_rad(-6.0)
	var at := Vector3(0.0, 0.0, -2.0)
	at.y = float(run.wave_director.ground_height.call(at.x, at.z))
	var y := run.wave_director.spawn_enemy_at(at, Vector3.ZERO)
	y.brain.set_physics_process(false)
	y.configure_kind(Yokai.Kind.SWARM, Elements.NONE, 9999.0)
	await _frames(60)
	await _shot("yokai_idle")
	y.brain.force_attack("right")
	y.brain.set_physics_process(true)
	for i in 120:
		await get_tree().physics_frame
		if y.brain.state == YokaiBrain.State.WINDUP:
			break
	await _frames(20)
	await _shot("yokai_tell")
	var chest: RagdollPart = y.parts["chest"]
	y.receive_hit(chest, {"attacker": "katana", "element": "physical", "part": "chest", "zone": "torso", "speed": 6.0,
		"strike": "edge", "edge_alignment": 0.9, "base_damage": 30.0, "point": chest.global_position, "direction": Vector3.RIGHT,
		"power": 0.5, "impulse": 6.0, "knockback": Vector3.RIGHT * 6.0})
	await _frames(3)
	await _shot("yokai_hit")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)

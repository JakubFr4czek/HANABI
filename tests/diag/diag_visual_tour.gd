extends Node
## Visual tour (non-headless): a series of gameplay shots to hunt artifacts.
##   godot --path . res://tests/diag/diag_visual_tour.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_tour"
var run: RunGame
var dp: DesktopPlayer


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(30)
	dp = run.player as DesktopPlayer
	run.xp_to_next = 999999
	# 1. Props up close: find the nearest tree, gate, lantern, rock.
	for label in ["Trees", "Torii", "Lanterns", "Rocks"]:
		var p := _nearest_prop(label)
		if p != Vector3.INF:
			var dir := (dp.global_position - p)
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
			var dist := 3.2 if label != "Torii" else 6.0
			var stand := p + dir * dist
			# Stand somewhere clear of trunks.
			for k in 12:
				var cand := p + dir.rotated(Vector3.UP, k * 0.52) * dist
				if run.forest_world.trunk_push(cand, -dir, 1.3).length() < 0.01:
					stand = cand
					dir = dir.rotated(Vector3.UP, k * 0.52)
					break
			stand.y = run.forest_world.height_at(stand.x, stand.z)
			dp.teleport(stand, atan2(dir.x, dir.z))
			dp.camera.rotation.x = deg_to_rad(-6.0 if label != "Torii" else 10.0)
			await _frames(25)
			await _shot("prop_" + label.to_lower())
	# 2. A fight: a pack around the player, swing into them.
	dp.teleport(run.spawn.global_position, 0.0)
	dp.camera.rotation.x = deg_to_rad(-8.0)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	for i in 5:
		var a := -0.9 + i * 0.45
		var at := dp.global_position + Vector3(sin(a) * 2.4, 0.0, -cos(a) * 2.4)
		at.y = run.forest_world.height_at(at.x, at.z)
		run.wave_director.spawn_enemy_at(at, dp.global_position)
	await _frames(70)
	await _shot("fight_pack")
	dp.swing_duration = 0.14
	dp.swing(DesktopPlayer.SLASH_HORIZONTAL)
	await _frames(9)
	await _shot("fight_cut")
	await _frames(40)
	await _shot("fight_after_cut")
	await _frames(60)
	await _shot("fight_petals")
	# 3. Level-up: a rank and a heal, no card choice (D1).
	run.xp_to_next = 1
	run.add_xp(5)
	await _frames(40)
	await _shot("levelup_rank")
	await _frames(20)
	# 4. Look down at the feet / ground and up into the canopy.
	dp.camera.rotation.x = deg_to_rad(-70.0)
	await _frames(10)
	await _shot("ground")
	dp.camera.rotation.x = deg_to_rad(60.0)
	await _frames(10)
	await _shot("canopy")
	# 5. Death and the end screen.
	dp.camera.rotation.x = deg_to_rad(-8.0)
	dp.health._invulnerable = 0.0
	dp.health.take_hit(10000.0, dp.global_position + Vector3.FORWARD)
	await _frames(90)
	await _shot("end_screen")
	get_tree().quit(0)


func _nearest_prop(label: String) -> Vector3:
	var best := INF
	var out := Vector3.INF
	for key in run.forest_world._chunks:
		var chunk := run.forest_world._chunks[key] as Node3D
		var mm := chunk.get_node_or_null(label) as MultiMeshInstance3D
		if mm == null or mm.multimesh == null:
			continue
		for i in mm.multimesh.instance_count:
			var p := chunk.global_transform * mm.multimesh.get_instance_transform(i).origin
			var d := p.distance_to(dp.global_position)
			if d < best and d > 3.0:
				best = d
				out = p
	return out


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	print("saved ", shot_name)

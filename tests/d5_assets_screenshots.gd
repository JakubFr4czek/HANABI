extends Node
## D5 visual review of the asset swap, in the real run scene (windowed, not headless):
## a panorama from the glade, a torii in the fog down the trail (the concept's view),
## the forest floor at a slope, and a stone lantern at two metres.
##   godot --path . --fixed-fps 90 res://tests/d5_assets_screenshots.tscn -- --desktop --shots /abs/dir

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_d5"


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
	var forest := run.forest_world
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(20)
	forest.finish_pending()

	# The glade looking out into the forest.
	_stand(player, forest, Vector3(0.0, 0.0, 2.2), Vector3(0.0, 0.0, -1.0))
	player.camera.rotation.x = deg_to_rad(-4.0)
	await _frames(30)
	await _shot("d5_glade_panorama")

	# Concept view: down the trail towards a torii in the fog, trunks in front.
	var gate := _gate_at(forest, Vector3.ZERO, 20.0, 34.0)
	if gate != Vector3.INF:
		var dir := Vector3(gate.x, 0.0, gate.z).normalized()
		var stand := _clear_spot(forest, gate - dir * 22.0, dir)
		_stand(player, forest, stand, dir)
		player.camera.look_at(gate + Vector3(0.0, 2.2, 0.0), Vector3.UP)
		await _frames(30)
		await _shot("d5_concept_torii_in_fog")

	# Forest floor: looking down at the ground beside the glade (moss on the slopes).
	_stand(player, forest, Vector3(4.0, 0.0, 6.0), Vector3(0.0, 0.0, -1.0))
	player.camera.rotation.x = deg_to_rad(-38.0)
	await _frames(30)
	await _shot("d5_ground_moss_closeup")

	# A stone lantern two metres off, if a chunk in the ring holds one.
	var lantern := _lantern_near(forest, Vector3.ZERO, 6.0, 40.0)
	if lantern != Vector3.INF:
		var dir := Vector3(lantern.x, 0.0, lantern.z).normalized()
		var stand := _clear_spot(forest, lantern - dir * 2.2, dir)
		_stand(player, forest, stand, dir)
		player.camera.look_at(lantern + Vector3(0.0, 0.9, 0.0), Vector3.UP)
		await _frames(30)
		await _shot("d5_stone_lantern_2m")

	run.queue_free()
	get_tree().quit(0)


func _gate_at(forest: ForestWorld, from: Vector3, lo: float, hi: float) -> Vector3:
	for key in forest._chunks:
		for g in (forest._chunks[key] as Node3D).get_meta("torii_world_positions", []):
			var gv: Vector3 = g
			var d := Vector2(gv.x - from.x, gv.z - from.z).length()
			if d >= lo and d <= hi:
				return gv
	return Vector3.INF


func _lantern_near(forest: ForestWorld, from: Vector3, lo: float, hi: float) -> Vector3:
	for key in forest._chunks:
		for l in (forest._chunks[key] as Node3D).get_meta("lantern_world_positions", []):
			var lv: Vector3 = l
			var d := Vector2(lv.x - from.x, lv.z - from.z).length()
			if d >= lo and d <= hi:
				return lv
	return Vector3.INF


## A spot near [param want] with no trunk or prop within 2.5 m, so the camera is not inside a tree.
func _clear_spot(forest: ForestWorld, want: Vector3, dir: Vector3) -> Vector3:
	for k in 24:
		var side := Vector3(-dir.z, 0.0, dir.x) * (0.5 * float(k % 7 - 3))
		var cand := want + side + dir * (0.4 * float(k / 7))
		if forest.is_clear_of_props(cand.x, cand.z, 2.5):
			return cand
	return want


func _stand(player: DesktopPlayer, forest: ForestWorld, at: Vector3, facing: Vector3) -> void:
	var yaw := atan2(-facing.x, -facing.z)
	player.teleport(Vector3(at.x, forest.height_at(at.x, at.z) + 0.2, at.z), yaw)


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame

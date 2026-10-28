extends Node
## Windowed screenshots from the game (run scene, not the preview): the footpath
## seen from the spawn and from 20 m further along it, with the fog and the
## night palette of the active profile (docs/WORLDGEN_TOOL.md).
##   godot --path . --fixed-fps 90 res://tools/worldgen/game_path_screenshots.tscn -- --desktop --shots /tmp/hanabi_d8_game

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_d8_game"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(30)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var player := run.player as DesktopPlayer
	var forest := run.forest_world
	var spawn := run.find_child("PlayerSpawn", true, false) as Node3D
	var at := spawn.global_position
	var along := _direction_at(forest, Vector2(at.x, at.z), 2.0)
	var yaw := atan2(-along.x, -along.y)
	# From the spawn, looking down the trail.
	player.teleport(at, yaw)
	player.camera.rotation.x = deg_to_rad(-8.0)
	await _frames(60)
	await _shot("path_from_spawn")
	# 20 m further along the trail (the first trail point about 20 m out).
	var far := _point_along(forest, Vector2(at.x, at.z), 20.0)
	if far != Vector2.INF:
		var dir := _direction_at(forest, far, 2.0)
		var y := atan2(-dir.x, -dir.y)
		player.teleport(Vector3(far.x, forest.height_at(far.x, far.y) + 0.2, far.y), y)
		player.camera.rotation.x = deg_to_rad(-8.0)
		await _frames(60)
		await _shot("path_20m_along")
	get_tree().quit(0)


## Unit direction of the trail near [param p] (xz), or zero when no trail is near.
func _direction_at(forest: ForestWorld, p: Vector2, reach: float) -> Vector2:
	var found := forest.paths.samples_in_rect(Rect2(p - Vector2(40.0, 40.0), Vector2(80.0, 80.0)), 1.0)
	var best := Vector2.ZERO
	var best_d := INF
	for s in found:
		var d := Vector2(s.x, s.y).distance_to(p)
		if d < best_d and d >= 0.0:
			best_d = d
			best = Vector2(s.z, s.w)
	return best if best != Vector2.ZERO else Vector2(0.0, -1.0)


## The trail point whose distance from [param from] is closest to [param metres].
func _point_along(forest: ForestWorld, from: Vector2, metres: float) -> Vector2:
	var found := forest.paths.samples_in_rect(Rect2(from - Vector2(60.0, 60.0), Vector2(120.0, 120.0)), 1.0)
	var best := Vector2.INF
	var best_err := INF
	for s in found:
		var p := Vector2(s.x, s.y)
		var err := absf(p.distance_to(from) - metres)
		if err < best_err:
			best_err = err
			best = p
	return best


func _frames(count: int) -> void:
	for k in count:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("SHOT %s" % out_dir.path_join(name + ".png"))

extends Node
## Windowed screenshots for the wave work (D10): the start of a run (first minute),
## a PEAK wave in the middle of the ramp, a top-down view of the spawn ring, and the
## "Fale" dock with its chart. Run in a window (not headless):
##   .tools/Godot.app/Contents/MacOS/Godot --path . res://tests/spawn_screenshots.tscn -- --shots docs/d10
## Time is stepped, not waited for: the director is driven in 0.1 s steps.

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "docs/d10"


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
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	await _frames(20)
	var director := run.wave_director
	director.stop_director()
	director.clear_enemies()
	director.start_director()
	var center := run._player_center()
	var forward := -player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	# 1. The first minute: step to 60 s and let the yōkai settle. The player's view
	# never holds a spawn point, so the shot also turns the player to the nearest one.
	for i2 in 600:
		director.step_director(0.1, center, forward)
	await _frames(30)
	await _shot("1_run_start_first_minute")
	await _face_wave(player, director)
	await _shot("1b_run_start_turned_to_wave")
	print("first minute: %d alive, run %.0f s, wave %d" % [director.alive_count(), director.run_seconds, director.wave])
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	await _frames(10)

	# 2. A PEAK wave mid-ramp: step until a PEAK wave is open with the field full.
	var guard := 0
	while guard < 6000:
		director.step_director(0.1, center, forward)
		guard += 1
		if director._planner.wave_open and director._planner.state == WavePlanner.State.PEAK \
				and director.alive_count() >= 4:
			break
	await _frames(40)
	await _shot("2_peak_wave")
	await _face_wave(player, director)
	await _shot("2b_peak_wave_turned_to_pack")
	print("peak wave: %d alive, run %.0f s, wave %d" % [director.alive_count(), director.run_seconds, director.wave])
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	await _frames(10)

	# 3. Top-down view of the ring: 40 spawn points from the spawner (red) and the player
	# (green), drawn 24 m up so they clear the cedar canopy (a plan projection, not a height).
	# Its own environment: the run's fog would hide the ring.
	var marks := Node3D.new()
	add_child(marks)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.95, 0.25, 0.22)
	red.emission_enabled = true
	red.emission = Color(0.95, 0.25, 0.22)
	for k in 40:
		var pos := director.find_spawn_point(center, forward)
		marks.add_child(_dot(pos + Vector3(0.0, 24.0, 0.0), 0.5, red))
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.3, 0.9, 0.5)
	green.emission_enabled = true
	green.emission = Color(0.3, 0.9, 0.5)
	marks.add_child(_dot(center + Vector3(0.0, 24.0, 0.0), 0.7, green))
	var top := Camera3D.new()
	top.position = center + Vector3(0.0, 60.0, 0.0)
	top.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	top.fov = 60.0
	top.environment = _clear_environment()
	add_child(top)
	top.make_current()
	await _frames(20)
	await _shot("3_spawn_ring_top_down")
	marks.queue_free()
	top.queue_free()
	player.camera.make_current()

	# 4. The "Fale" dock with its chart, drawn on the window.
	var layer := CanvasLayer.new()
	add_child(layer)
	var dock := WaveDock.new()
	dock.position = Vector2(12.0, 12.0)
	layer.add_child(dock)
	dock.load_preset("default")
	await _frames(10)
	await _shot("4_fale_dock")

	run.queue_free()
	get_tree().quit(0)


## Turns the player to the alive yōkai nearest the ring (the spot a player would turn to).
func _face_wave(player: DesktopPlayer, director: WaveDirector) -> void:
	var alive := director.alive_enemies()
	if alive.is_empty():
		return
	var target := alive[0].root_part().global_position
	for y in alive:
		var p := y.root_part().global_position
		if p.distance_squared_to(player.global_position) < target.distance_squared_to(player.global_position):
			target = p
	var dir := target - player.global_position
	player.teleport(player.global_position, atan2(dir.x, dir.z) + PI)
	await _frames(40)


func _dot(at: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	mi.position = at
	return mi


func _clear_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 1.0
	env.fog_enabled = false
	return env


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

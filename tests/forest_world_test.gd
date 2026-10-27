extends Node
## Headless coverage for docs/NIGHT_PLAN.md item 3: chunked forest hills,
## recycled props, shrine clearing, and Quest-oriented instance budgets.

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(14)
	run.wave_director.stop_director()
	var forest := run.forest_world
	var player := run.player as DesktopPlayer
	_check("RunGame spawns the endless forest around the shrine", forest != null)
	_check("Forest keeps a bounded 3×3 chunk ring", forest.chunk_count == 9)

	var before := forest.center_chunk
	player.teleport(Vector3(34.0, 0.0, 6.0), 0.0)
	await _frames(6)
	_check("Forest chunks recycle when the player crosses chunk borders",
		forest.center_chunk != before)

	var nearest := forest.nearest_prop_distance()
	_check("Shrine clearing stays free of forest props",
		nearest >= ForestWorld.PROP_CLEARING_RADIUS - 0.05 or nearest == INF)
	_check("Clearing sits flush with the stone platform (%.2f m)" % forest.height_at(2.0, 2.0),
		absf(forest.height_at(2.0, 2.0) - ForestWorld.CLEARING_HEIGHT) < 0.01)
	var relief := 0.0
	for k in 24:
		relief = maxf(relief, absf(forest.height_at(20.0 + k * 3.0, 14.0 - k * 2.0) - ForestWorld.CLEARING_HEIGHT))
	_check("Hills roll through the forest (relief %.2f m)" % relief, relief > 0.6)

	# Walk out into the forest: the terrain under the player is solid.
	player.teleport(Vector3(31.0, 3.5, 9.0), 0.0)
	await _frames(90)
	var ground := forest.height_at(player.global_position.x, player.global_position.z)
	_check("Player stands on forest terrain far from the shrine (feet %.2f, ground %.2f)" % [player.global_position.y, ground],
		player.is_on_floor() and absf(player.global_position.y - ground) < 0.35)
	var boundary := run.get_node_or_null("Room/Boundary") as StaticBody3D
	_check("Dojo ring wall no longer fences the run", boundary == null or boundary.collision_layer == 0)

	var water := run.get_node_or_null("Arena/WaterMirror") as MeshInstance3D
	_check("Run replaces the endless water mirror with forest terrain", water != null and not water.visible)

	var props := forest.total_prop_instances()
	_check("Shared MultiMesh props stay within a Quest-friendly budget", props > 24 and props < 980)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

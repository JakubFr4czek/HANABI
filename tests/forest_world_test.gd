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
		nearest >= ForestWorld.PROP_CLEARING_RADIUS - 0.25 or nearest == INF)
	_check("Rolling hills rise outside the clearing",
		forest.height_at(20.0, 6.0) > forest.height_at(2.0, 2.0) + 0.5)

	var water := run.get_node_or_null("Arena/WaterMirror") as MeshInstance3D
	_check("Run replaces the endless water mirror with forest terrain", water != null and not water.visible)

	var props := forest.total_prop_instances()
	_check("Shared MultiMesh props stay within a Quest-friendly budget", props > 24 and props < 650)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

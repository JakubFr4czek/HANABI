extends Node
## The XR rig root stays at the spawn while locomotion moves the origin/body,
## so ForestWorld must anchor chunks on the feet, not on the follow node's
## origin — otherwise the whole forest stays behind and the player walks out
## of the trees a few seconds after leaving the spawn. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/xr_forest_anchor_test.tscn -- --desktop
## Exit code 0 when everything passed.

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


## Fake XR-style follow: the origin never moves, the feet do.
class FakeXrFollow extends Node3D:
	var feet := Vector3.ZERO
	func feet_position() -> Vector3:
		return feet


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)
	var forest: ForestWorld = run.forest_world

	# Sanity: chunks start around the spawn.
	_check("Chunks start around the spawn", forest.center_chunk == Vector2i.ZERO)

	# XR case: root glued at the spawn, feet walked 60 m out.
	var rig := FakeXrFollow.new()
	add_child(rig)
	forest.follow = rig
	rig.feet = Vector3(60.0, 0.0, 0.0)
	await _frames(10)
	_check("Chunks follow the feet, not the rig root (center %s)" % forest.center_chunk,
		forest.center_chunk == Vector2i(2, 0))
	_check("Trees are drawn around the feet (%d instances)" % _drawn_trees(forest),
		_drawn_trees(forest) > 0)

	# Desktop case: no feet_position, the origin itself is the anchor.
	var plain := Node3D.new()
	plain.position = Vector3(-60.0, 0.0, 0.0)
	add_child(plain)
	forest.follow = plain
	await _frames(10)
	_check("Plain follows still anchor on their origin (center %s)" % forest.center_chunk,
		forest.center_chunk == Vector2i(-2, 0))

	rig.queue_free()
	plain.queue_free()
	run.queue_free()


## Trees drawn at any detail: full crowns in the chunks plus the far-crown MultiMeshes.
## A spot on a path has no full crown within the LOD band (the sky strip is kept open), so far crowns count too.
func _drawn_trees(forest: ForestWorld) -> int:
	var total := 0
	for key in forest._chunks:
		var inst := (forest._chunks[key] as Node3D).get_node_or_null("Trees0") as MultiMeshInstance3D
		if inst and inst.multimesh:
			total += inst.multimesh.instance_count
	for node in forest._far_tree_nodes.values():
		var far := node as MultiMeshInstance3D
		if far and far.multimesh:
			total += far.multimesh.instance_count
	return total


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

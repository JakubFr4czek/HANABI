extends Node
## P2 (playtest note 2): trees must not pop in while walking. A chunk that arrives
## while the player walks is built a few frames after the border crossing; its trees
## used to appear at full size 25–40 m away, where the fog is already partly thick.
## Walks a square of 60 m legs across chunk borders and checks every crown as it is drawn.

const RUN_SCENE := preload("res://scenes/run.tscn")
## Inside this radius (metres) a crown that appears must already be growing from zero.
## Trees beyond it sit in the fog and enter through the draw radius, not through a chunk.
const POP_RANGE := 37.0
## Largest growth change one crown may show in one physics frame.
const MAX_GROWTH_STEP := 0.1
const WALK_STEP := 0.05
const LEG_FRAMES := 1200
const LEGS := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]

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
	forest.finish_pending()

	# A marker stands in for the player: its path is exact, with no physics shove.
	var walker := Node3D.new()
	run.add_child(walker)
	forest.follow = walker
	walker.global_position = Vector3(-30.0, 0.0, 20.0)
	await _frames(3)
	forest.finish_pending()
	var prev := {}
	var stamped := {}
	var arrived_crowns := 0
	var arrived_grown := 0
	var pops := 0
	var worst_pop := 0.0
	var worst_step := 0.0
	var steps := 0
	for leg in LEGS:
		for i in LEG_FRAMES:
			walker.global_position += (leg as Vector3) * WALK_STEP
			await get_tree().physics_frame
			var cur := _drawn_growth(forest)
			var at := walker.global_position
			# A chunk stamped this frame was built while walking: its crowns must start from zero.
			for key in forest._chunks:
				var chunk := forest._chunks[key] as Node3D
				if chunk.has_meta("grow_from") and not stamped.has(key):
					stamped[key] = true
					for child in chunk.get_children():
						if not (child is MultiMeshInstance3D) or not ForestWorld._is_tree_node(String(child.name)):
							continue
						for xf in chunk.get_meta("xfs_" + String(child.name), []):
							var o: Vector3 = chunk.position + (xf as Transform3D).origin
							if cur.has(o):
								arrived_crowns += 1
								if cur[o] > 0.05:
									arrived_grown += 1
			# The first sample has no earlier frame to compare with: the start ring is not an arrival.
			if prev.is_empty():
				prev = cur
				continue
			for o in cur:
				var d := Vector2(o.x - at.x, o.z - at.z).length()
				var g: float = cur[o]
				if not prev.has(o):
					if d <= POP_RANGE and g > 0.05:
						pops += 1
						worst_pop = maxf(worst_pop, d)
				else:
					worst_step = maxf(worst_step, absf(g - float(prev[o])))
					steps += 1
			prev = cur

	_check("Chunks were built while walking (%d arrived)" % stamped.size(), stamped.size() >= 4)
	_check("Arriving crowns start from zero growth (%d of %d already grown)" % [arrived_grown, arrived_crowns],
		arrived_crowns > 0 and arrived_grown == 0)
	_check("No crown pops in full size inside %.0f m (%d popped, farthest %.1f m)" % [POP_RANGE, pops, worst_pop],
		pops == 0)
	_check("Growth changes smoothly, at most %.2f per frame (worst %.3f over %d crowns)" % [MAX_GROWTH_STEP, worst_step, steps],
		worst_step <= MAX_GROWTH_STEP)
	run.queue_free()


## Every crown the last refresh drew (full, far and scene), world origin -> growth.
func _drawn_growth(forest: ForestWorld) -> Dictionary:
	var out := {}
	for i in forest.drawn_full_origins.size():
		out[forest.drawn_full_origins[i]] = forest.drawn_full_growth[i]
	for i in forest.drawn_far_origins.size():
		out[forest.drawn_far_origins[i]] = forest.drawn_far_growth[i]
	for i in forest.drawn_scene_origins.size():
		out[forest.drawn_scene_origins[i]] = forest.drawn_scene_growth[i]
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

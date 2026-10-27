extends Node

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	_check("VfxPool autoload prewarms soul orbs", VfxPool != null and VfxPool._soul_free.size() >= 40)
	VfxPool.ensure_run_budget(0)
	var alloc_before: int = int(VfxPool.pool_stats().get("sparks_allocated", 0))
	for _j in 16:
		SparkBurst.spawn(self, Vector3.ZERO, Vector3.UP, Color.WHITE, 6, 2.0)
	await _frames(36)
	var alloc_after: int = int(VfxPool.pool_stats().get("sparks_allocated", 0))
	_check("Spark pool does not grow after warmup burst", alloc_after == alloc_before)
	_check("Spark pool respects hard cap", alloc_after <= VfxPool.MAX_SPARK)

	var root := Node3D.new()
	add_child(root)
	var pool_before := VfxPool._soul_free.size()
	var orbs := SoulOrb.spawn_cluster(root, Vector3(0, 1, -1), 6, 5, Elements.SAKURA)
	_check("Soul cluster uses pooled orbs", orbs.size() == 6)
	for orb in orbs:
		orb._collect()
	await _frames(6)
	_check("Collected souls return to VfxPool", VfxPool._soul_free.size() >= pool_before)
	root.queue_free()

	# A scene freed while it holds pooled VFX must not take them with it:
	# sparks stay in the pool, and orbs that did die are written off so the
	# cap still leaves room (before, a few scene changes ran the pools dry).
	var scene := Node3D.new()
	add_child(scene)
	await _frames(1)
	var sparks_before: int = int(VfxPool.pool_stats().sparks_allocated)
	for _j in 10:
		SparkBurst.spawn(scene, Vector3.ZERO, Vector3.UP, Color.WHITE, 6, 2.0)
	var lent := SoulOrb.spawn_cluster(scene, Vector3(0, 1, -1), 8, 5, Elements.NONE)
	scene.free()
	await _frames(40)
	var alive_sparks := 0
	for c in VfxPool.get_children():
		if c is SparkBurst:
			alive_sparks += 1
	_check("sparks survive the scene they burst in (%d of %d)" % [alive_sparks, sparks_before], alive_sparks == sparks_before)
	_check("a freed scene's soul orbs are written off, not counted against the cap",
		lent.size() == 8 and lent.all(func(o): return not is_instance_valid(o)))
	VfxPool._heal_soul_count()
	var room := VfxPool.MAX_SOUL - int(VfxPool.pool_stats().souls_allocated) + VfxPool._soul_free.size()
	_check("the soul pool still has room after the scene died (%d)" % room, room >= 8)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame

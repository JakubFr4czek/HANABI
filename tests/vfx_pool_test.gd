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


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame

extends Node
## Death fireworks must not spawn unbounded OmniLight3D nodes (Quest perf).
##   godot --headless --path . --fixed-fps 90 res://tests/firework_flash_cap_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _firework_behaviour()
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(8)
	var origin := Vector3(0.0, 1.1, -1.5)
	for i in 16:
		ElementFirework.spawn(run, origin + Vector3(float(i % 4) * 0.35, 0.0, float(i / 4) * 0.25), Elements.STORM, 1.0)
	await _frames(2)
	var pool := get_node_or_null("/root/VfxPool")
	_check("VfxPool caps simultaneous firework flash lights",
		pool != null and pool.active_firework_flash_count() <= VfxPool.MAX_FIREWORK_FLASH_LIGHTS)
	var lights := 0
	for n in run.find_children("*", "OmniLight3D", true, false):
		if (n as OmniLight3D).name == "FireworkFlash":
			lights += 1
	_check("Scene has at most %d FireworkFlash lights right after burst" % VfxPool.MAX_FIREWORK_FLASH_LIGHTS,
		lights <= VfxPool.MAX_FIREWORK_FLASH_LIGHTS)
	run.queue_free()


## The burst itself: element colours, the particle cap, and the lamp rules that
## Settings > ACCESS (flash strength) controls. Fallback paths run directly so
## they are checked even though VfxPool normally takes over.
func _firework_behaviour() -> void:
	var host := Node3D.new()
	add_child(host)
	var at := Vector3(0.0, 1.0, -2.0)
	ElementFirework.spawn(null, at, Elements.STORM)
	_check("a firework without a parent adds nothing anywhere", host.get_child_count() == 0)
	var pool := get_node("/root/VfxPool")
	var before: Dictionary = pool.pool_stats()
	ElementFirework.spawn(host, at, Elements.STORM, 1.0)
	var after: Dictionary = pool.pool_stats()
	var sparks_out: int = (after.sparks_allocated - after.spark_free) - (before.sparks_allocated - before.spark_free)
	var rings_out: int = (after.rings_allocated - after.ring_free) - (before.rings_allocated - before.ring_free)
	_check("a firework takes two spark bursts and one ring from the pool", sparks_out == 2 and rings_out == 1)

	var colors := {}
	for el in [Elements.NONE, Elements.SAKURA, Elements.STORM, Elements.INK, Elements.SHADOW]:
		colors[el] = ElementFirework._burst_color(el)
	var distinct := {}
	for c in colors.values():
		distinct[str(c)] = true
	_check("each element bursts in its own colour", distinct.size() == colors.size())
	_check("an unknown element falls back to the fire colour",
		ElementFirework._burst_color("not_an_element") == colors[Elements.NONE])

	var ring_host := Node3D.new()
	add_child(ring_host)
	ElementFirework._ring_ephemeral(ring_host, at, Color(1, 0.4, 0.2), 6.0)
	var rings := ring_host.find_children("*", "CPUParticles3D", false, false)
	_check("the fallback ring is one-shot and emitting", rings.size() == 1
		and (rings[0] as CPUParticles3D).one_shot and (rings[0] as CPUParticles3D).emitting)
	_check("the fallback ring never exceeds %d particles on a big burst" % ElementFirework.MAX_PARTICLES,
		rings.size() == 1 and (rings[0] as CPUParticles3D).amount <= ElementFirework.MAX_PARTICLES)

	var flash_host := Node3D.new()
	add_child(flash_host)
	var saved_flash := VrComfortSettings.flash_percent
	VrComfortSettings.flash_percent = 100
	ElementFirework._fog_flash_ephemeral(flash_host, at, Color(0.5, 0.7, 1.0), 1.0)
	var lamps := flash_host.find_children("*", "OmniLight3D", false, false)
	_check("with flash on, the fallback burst adds one lamp above the spot", lamps.size() == 1
		and (lamps[0] as OmniLight3D).global_position.is_equal_approx(at + Vector3(0, 0.35, 0)))
	VrComfortSettings.flash_percent = 0
	var dark_host := Node3D.new()
	add_child(dark_host)
	ElementFirework._fog_flash_ephemeral(dark_host, at, Color(0.5, 0.7, 1.0), 1.0)
	ElementFirework.spawn(dark_host, at, Elements.SAKURA, 1.0)
	await _frames(2)
	var dark_lamps := dark_host.find_children("*", "OmniLight3D", true, false).size()
	_check("with flash at 0%, no burst adds a light (sparks only)", dark_lamps == 0)
	VrComfortSettings.flash_percent = saved_flash
	host.queue_free()
	ring_host.queue_free()
	flash_host.queue_free()
	dark_host.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

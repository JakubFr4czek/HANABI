extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = false
	add_child(run)
	await _frames(6)
	var player := run.player as DesktopPlayer
	var seal := run.get_node("Arena/SpawnSeal") as MeshInstance3D
	var seal_mat := seal.material_override as ShaderMaterial
	var glow := float(seal_mat.get_shader_parameter("intro_seal_glow"))
	_check("Run intro begins levitating with a glowing seal", run.state == RunGame.RunState.INTRO
		and glow > 0.2 and player.movement_locked)
	_check("Katana is withheld until touchdown", not run.katana.is_held())
	var y0 := player.global_position.y
	await _frames(110)
	_check("Descent is smooth and linear (player lowers without walking)",
		player.global_position.y < y0 - 0.22 and player.velocity.length() < 0.05)
	run.run_intro.skip()
	await _frames(16)
	_check("Skipping intro grants the katana and starts the run",
		run.state == RunGame.RunState.PLAYING and run.katana.is_held()
		and run.wave_director.active)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame

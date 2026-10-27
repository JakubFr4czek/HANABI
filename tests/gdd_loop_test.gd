extends Node
## GDD §3–6, §9 loop audit (NIGHT_PLAN §11): spawn seal progression, element slot
## cap, and diegetic parry feedback. Run/combat/elements tests cover the rest.
##   godot --headless --path . --fixed-fps 90 res://tests/gdd_loop_test.tscn -- --desktop

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
	await _frames(12)

	var seal := run.get_node("Arena/SpawnSeal") as MeshInstance3D
	var seal_mat := seal.material_override as ShaderMaterial
	_check("Spawn seal starts dark (no elements lit)",
		int(seal_mat.get_shader_parameter("active_elements_mask")) == 0)

	run._apply_upgrade({"id": "sakura_petals"})
	run._update_element_seal()
	_check("Seal lights Sakura quadrant (桜) after first element pick",
		int(seal_mat.get_shader_parameter("active_elements_mask")) == 1)

	run._apply_upgrade({"id": "storm_chain"})
	run._update_element_seal()
	_check("Seal lights Storm quadrant (雷) with two elements",
		int(seal_mat.get_shader_parameter("active_elements_mask")) == 3)

	run._apply_upgrade({"id": "ink_pool"})
	_check("Third element is rejected (max 2 elements per GDD §5)",
		run.element_system.active_elements.size() == 2
		and not run.element_system.active_elements.has(Elements.INK))

	run.start_run()
	await _frames(8)
	for id in ["sakura_petals", "sakura_orbit", "sakura_heal", "storm_chain", "storm_charge", "storm_overload"]:
		run._apply_upgrade({"id": id})
	run._apply_upgrade({"id": "ink_pool"})
	_check("Seventh element upgrade type is blocked at six slots (GDD §5)",
		UpgradePool.element_slot_count(run.upgrade_stacks) == UpgradePool.ELEMENT_SLOT_LIMIT
		and not run.upgrade_stacks.has("ink_pool"))

	run.diegetic_hud.on_parry()
	_check("Parry triggers diegetic tsuba glow (not screen-space UI)",
		run.diegetic_hud._parry_glow > 0.25)

	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

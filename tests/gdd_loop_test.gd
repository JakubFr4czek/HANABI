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

	# New system (ELEMENTS_PLAN): blade element comes only from Torii gates.
	# Level-up cards never imbue the blade.
	run._apply_upgrade({"id": "damage"})
	run._update_element_seal()
	_check("Level-up card does NOT imbue the blade (Torii gates only)",
		run.element_system.current_element == Elements.NONE
		and int(seal_mat.get_shader_parameter("active_elements_mask")) == 0)

	run.element_system.imbue(Elements.SAKURA)
	run._update_element_seal()
	_check("Seal lights Sakura quadrant (桜) after Sakura gate imbue",
		int(seal_mat.get_shader_parameter("active_elements_mask")) == 1)

	run.element_system.imbue(Elements.STORM)
	run._update_element_seal()
	_check("Different gate replaces the element (one element at a time)",
		run.element_system.current_element == Elements.STORM)

	run.element_system.imbue(Elements.INK)
	_check("Blade still holds exactly one element after another gate",
		run.element_system.current_element == Elements.INK)

	run.start_run()
	await _frames(8)
	# E2c: progression lives in the per-element Ofuda skill trees. Unlocking
	# Sakura nodes must not unlock another element's nodes, and a master
	# node stays locked until its whole prerequisite chain is bought.
	run.add_ofuda(24)
	var s1: Dictionary = run.unlock_skill("petal_sense")
	var s2: Dictionary = run.unlock_skill("razor_petals")
	_check("Skill tree unlocks the Sakura chain with Ofuda",
		s1.get("ok", false) and s2.get("ok", false) and run.skill_tree.is_unlocked("razor_petals"))
	var locked: Dictionary = run.unlock_skill("ikazuchi_avatar")
	_check("Another element's master node stays locked without its prerequisites",
		not locked.get("ok", true) and not run.skill_tree.is_unlocked("ikazuchi_avatar"))

	run.diegetic_hud.on_parry()
	_check("Parry triggers the wrist charm glow (not screen-space UI)",
		run.diegetic_hud._parry_glow > 0.25)

	var rain := run.get_node_or_null("RunStormRain") as StormRain
	_check("Survival run has storm rain streaks (GDD §9, not arena-only)",
		rain != null and rain.rain != null)
	_check("Katana carries blade drip particles in run",
		run.katana != null and run.katana.get_node_or_null("BladeDrips") != null)

	var fake := Yokai.new()
	fake.elite_element = Elements.STORM
	fake.kind = Yokai.Kind.ELITE
	_check("Elite soul drops use elite element tint (GDD §6)",
		run._soul_element_for_kill(fake) == Elements.STORM)

	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

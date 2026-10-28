extends Node
## Headless verification for E2c (docs/ELEMENTS_PLAN.md Phase E2c):
## - Skill tree data: 4 elements x 5 nodes, costs 3/5/5/8/12 (33 per tree)
## - Cannot unlock without the prerequisite or without enough Ofuda
## - Node 4 accepts Node 2 OR Node 3; Node 5 needs Node 4
## - An unlock measurably changes the ability (petal count, cooldown,
##   imbue duration, damage reduction) through ElementSystem
## - Per-run reset clears unlocks
##   godot --headless --path . --fixed-fps 90 res://tests/skill_tree_data_test.tscn -- --desktop

const KATANA_SCENE := preload("res://scenes/weapons/katana.tscn")
const BalanceModel := preload("res://tools/balance_model.gd")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	_test_data_shape()
	_test_purchase_rules()
	_test_balance_targets()

	var katana: HeldWeapon = KATANA_SCENE.instantiate()
	add_child(katana)
	var elem_sys := ElementSystem.new()
	elem_sys.name = "ElementSystem"
	add_child(elem_sys)
	elem_sys.setup(null, katana)
	var tree := SkillTreeData.new()
	elem_sys.skill_tree = tree
	await _frames(3)

	await _test_unlock_changes_abilities(elem_sys, tree, katana)

	katana.queue_free()
	elem_sys.queue_free()


func _test_data_shape() -> void:
	_check("Skill tree defines exactly 20 nodes", SkillTreeData.NODES.size() == 20)
	var shape_ok := true
	for element: String in Elements.COMBAT_ELEMENTS:
		var nodes := SkillTreeData.nodes_for_element(element)
		if nodes.size() != 5:
			shape_ok = false
			continue
		var costs: Array[int] = []
		for n: Dictionary in nodes:
			costs.append(int(n.cost))
			# Every prerequisite id must reference a real node of this element.
			for req: String in n.get("requires_all", []):
				if String(SkillTreeData.node_by_id(req).get("element", "")) != element:
					shape_ok = false
			for req: String in n.get("requires_any", []):
				if String(SkillTreeData.node_by_id(req).get("element", "")) != element:
					shape_ok = false
		if costs != [3, 5, 5, 8, 12]:
			shape_ok = false
	_check("Each element has 5 nodes costing 3/5/5/8/12 with same-element prerequisites", shape_ok)
	var totals_ok := true
	for element: String in Elements.COMBAT_ELEMENTS:
		if SkillTreeData.tree_cost(element) != 33:
			totals_ok = false
	_check("Full tree costs 33 Ofuda per element", totals_ok)


## E4 guardrails: the progression curve and the school identities that
## docs/ELEMENTS_PLAN.md (Phase E4) promises, measured by the balance model
## (tools/balance_model.gd, ~1 s). A later tweak that breaks the feel of a
## 5–10 minute demo run fails here instead of in a headset.
func _test_balance_targets() -> void:
	var order := BalanceModel.full_order(Elements.SAKURA)
	var costs: Array[int] = BalanceModel.cumulative_costs(order)
	var avg: Dictionary = BalanceModel.economy("average", 600.0)
	var careful: Dictionary = BalanceModel.economy("careful", 600.0)
	var first: float = BalanceModel.time_to_afford(avg.timeline, costs[0])
	_check("average player buys the first node inside the first minute (%.0f s)" % first, first > 0.0 and first <= 60.0)
	var third: float = BalanceModel.time_to_afford(avg.timeline, costs[2])
	_check("three nodes by ~3 minutes (%.0f s)" % third, third > 0.0 and third <= 180.0)
	var master: float = BalanceModel.time_to_afford(avg.timeline, costs[4])
	_check("the master technique lands between 4 and 8 minutes (%.0f s)" % master, master >= 240.0 and master <= 480.0)
	var at5: int = int(avg.timeline[mini(30, avg.timeline.size() - 1)].ofuda)
	var at10: int = int(avg.timeline[mini(60, avg.timeline.size() - 1)].ofuda)
	_check("Ofuda earned: 22–40 by minute 5 (%d), 45–70 by minute 10 (%d)" % [at5, at10],
		at5 >= 22 and at5 <= 40 and at10 >= 45 and at10 <= 70)
	var careful_nodes := 0
	for c in costs:
		if int(careful.timeline[mini(30, careful.timeline.size() - 1)].ofuda) >= c:
			careful_nodes += 1
	_check("even a careful player owns 3+ nodes by minute 5 (%d)" % careful_nodes, careful_nodes >= 3)

	# Each school adds something real, none of them dwarfs the sword.
	var identity_ok := true
	var detail := ""
	for school: String in Elements.COMBAT_ELEMENTS:
		var nodes := BalanceModel.full_order(school)
		var bare: Dictionary = BalanceModel.kit(school, [], 1)
		var full1: Dictionary = BalanceModel.kit(school, nodes, 1)
		var full4_late: Dictionary = BalanceModel.kit(school, nodes, 4, 10)
		var utility := float(bare.control) + float(bare.guard)
		if float(bare.ratio) < 0.12 or float(bare.ratio) > 0.40:
			identity_ok = false
		if float(full1.ratio) <= float(bare.ratio) * 1.5:
			identity_ok = false   # the tree must visibly matter
		if float(full4_late.ratio) > 2.4:
			identity_ok = false   # ...but never turn the sword into a prop
		if float(bare.ratio) < 0.25 and utility < 6.0:
			identity_ok = false   # a weak damage dealer must bring control or protection
		detail += " %s %.0f%%->%.0f%%" % [school, float(bare.ratio) * 100.0, float(full1.ratio) * 100.0]
	_check("every school: 12–40%% of the sword bare, clearly stronger fully upgraded, never above 240%% (%s )" % detail, identity_ok)
	var kits_differ := absf(float(BalanceModel.kit(Elements.INK, [], 4).control)
		- float(BalanceModel.kit(Elements.SAKURA, [], 4).control)) > 20.0 \
		and float(BalanceModel.kit(Elements.SHADOW, [], 1).guard) > float(BalanceModel.kit(Elements.STORM, [], 1).guard) \
		and float(BalanceModel.kit(Elements.SAKURA, [], 4).d1) > float(BalanceModel.kit(Elements.SAKURA, [], 1).d1) * 1.5
	_check("identities stay distinct: Ink controls, Shadow guards, Sakura cuts packs", kits_differ)


func _test_purchase_rules() -> void:
	var tree := SkillTreeData.new()

	var no_prereq: Dictionary = tree.try_unlock("razor_petals", 99)
	_check("Cannot unlock Node 2 without Node 1 (prerequisite)",
		not no_prereq.get("ok", true) and no_prereq.get("reason") == SkillTreeData.REASON_PREREQUISITE
		and not tree.is_unlocked("razor_petals"))

	var poor: Dictionary = tree.try_unlock("petal_sense", 2)
	_check("Cannot unlock without enough Ofuda (needs 3, has 2)",
		not poor.get("ok", true) and poor.get("reason") == SkillTreeData.REASON_OFUDA
		and not tree.is_unlocked("petal_sense"))

	var unknown: Dictionary = tree.try_unlock("not_a_node", 99)
	_check("Unknown node id is rejected",
		not unknown.get("ok", true) and unknown.get("reason") == SkillTreeData.REASON_UNKNOWN_NODE)

	var bought: Dictionary = tree.try_unlock("petal_sense", 3)
	_check("Node 1 unlocks with exactly its cost in Ofuda",
		bought.get("ok", false) and int(bought.get("cost", 0)) == 3 and tree.is_unlocked("petal_sense"))

	var again: Dictionary = tree.try_unlock("petal_sense", 99)
	_check("Unlocking the same node twice is rejected",
		not again.get("ok", true) and again.get("reason") == SkillTreeData.REASON_ALREADY_UNLOCKED)

	# Node 4 takes Node 2 OR Node 3: only the Ability-2 branch is bought here.
	tree.try_unlock("hanami_storm", 99)
	var node4: Dictionary = tree.try_unlock("life_bloom", 99)
	_check("Node 4 unlocks via Node 3 alone (OR prerequisite)",
		node4.get("ok", false) and tree.is_unlocked("life_bloom"))

	var tree2 := SkillTreeData.new()
	tree2.try_unlock("petal_sense", 99)
	var node4_locked: Dictionary = tree2.try_unlock("life_bloom", 99)
	_check("Node 4 stays locked with only Node 1 bought",
		not node4_locked.get("ok", true) and node4_locked.get("reason") == SkillTreeData.REASON_PREREQUISITE)
	var node5_locked: Dictionary = tree2.try_unlock("senbonzakura_kageyoshi", 99)
	_check("Node 5 stays locked without Node 4",
		not node5_locked.get("ok", true) and node5_locked.get("reason") == SkillTreeData.REASON_PREREQUISITE)

	tree.reset()
	_check("Per-run reset clears every unlock", tree.unlocked_count() == 0 and not tree.is_unlocked("petal_sense"))


func _test_unlock_changes_abilities(elem_sys: ElementSystem, tree: SkillTreeData, katana: HeldWeapon) -> void:
	# Baseline: untouched Sakura numbers.
	elem_sys.imbue(Elements.SAKURA)
	_check("Baseline imbue lasts ElementBalance.IMBUE_SECONDS (20.0 s)",
		elem_sys.element_time_remaining == 20.0 and ElementBalance.IMBUE_SECONDS == 20.0)
	var counts: Array = []
	var cb := func(type: String, data: Dictionary) -> void:
		if type == "senbonzakura":
			counts.append(int(data.get("count", 0)))
	elem_sys.effect_triggered.connect(cb)
	_check("Baseline Senbonzakura fires", elem_sys.execute_ability_1(Vector3.FORWARD))
	_check("Baseline Senbonzakura releases %d petals" % ElementBalance.SENBONZAKURA_PETALS, counts == [ElementBalance.SENBONZAKURA_PETALS])

	# Unlocks must change the ability, not just a flag in a menu.
	tree.try_unlock("petal_sense", 99)
	elem_sys.imbue(Elements.SAKURA)
	_check("Petal Sense extends the Sakura imbue to 24.0 s", elem_sys.element_time_remaining == 24.0)
	tree.try_unlock("razor_petals", 99)
	elem_sys.ability_1_cooldown = 0.0
	_check("Upgraded Senbonzakura fires", elem_sys.execute_ability_1(Vector3.FORWARD))
	_check("Razor Petals releases %d petals after unlock" % ElementBalance.SENBONZAKURA_PETALS_T2,
		counts == [ElementBalance.SENBONZAKURA_PETALS, ElementBalance.SENBONZAKURA_PETALS_T2])

	tree.try_unlock("hanami_storm", 99)
	elem_sys.ability_2_cooldown = 0.0
	_check("Hanamai fires", elem_sys.execute_ability_2(Vector3.FORWARD))
	_check("Storm of Hanami extends Hanamai to 8.5 s", absf(elem_sys.hanamai_time_remaining - 8.5) < 0.05)
	_check("Storm of Hanami deepens damage reduction to 0.55",
		absf(elem_sys.get_incoming_damage_multiplier() - 0.55) < 0.01)

	# Storm cooldown: 3.5 s baseline, 2.5 s with Thunder Splitter.
	elem_sys.reset()
	elem_sys.imbue(Elements.STORM)
	elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Baseline Raikiri cooldown is 3.5 s", absf(elem_sys.ability_1_cooldown - 3.5) < 0.01)
	tree.try_unlock("static_conduit", 99)
	tree.try_unlock("thunder_splitter", 99)
	elem_sys.ability_1_cooldown = 0.0
	elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("Thunder Splitter cuts Raikiri cooldown to 2.5 s", absf(elem_sys.ability_1_cooldown - 2.5) < 0.01)

	elem_sys.reset()
	_check("Katana returns to plain steel after reset", katana.element == Elements.NONE)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

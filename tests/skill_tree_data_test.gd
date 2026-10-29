extends Node
## Headless verification for E2c (docs/ELEMENTS_PLAN.md Phase E2c):
## - Skill tree data: 4 elements x 5 nodes, costs 1/1/1/2/3 skill points (8 per tree, D12)
## - Cannot unlock without the prerequisite or without enough points
## - Node 4 accepts Node 2 OR Node 3; Node 5 needs Node 4
## - An unlock measurably changes the ability (petal count, cooldown,
##   imbue duration, damage reduction) through ElementSystem
## - Per-run reset clears unlocks
## - Sandbox (D9): every node reads as unlocked and costs nothing; switching it off restores
##   the run's own unlocks exactly; the switch saves without touching other sections; the
##   settings sub-tabs lay out inside the panel
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
	_test_kirisute_finishers()

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
	await _test_sandbox_abilities(elem_sys)
	_test_sandbox_rules()
	_test_sandbox_setting_persists()
	_test_sandbox_page_layout()

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
		if costs != [1, 1, 1, 2, 3]:
			shape_ok = false
	_check("Each element has 5 nodes costing 1/1/1/2/3 with same-element prerequisites", shape_ok)
	var totals_ok := true
	for element: String in Elements.COMBAT_ELEMENTS:
		if SkillTreeData.tree_cost(element) != 8:
			totals_ok = false
	_check("Full tree costs 8 skill points per element", totals_ok)


## E4 guardrails: the progression curve and the school identities that
## docs/ELEMENTS_PLAN.md (Phase E4) promises, measured by the balance model
## (tools/balance_model.gd, ~1 s). A later tweak that breaks the feel of a
## 5–10 minute demo run fails here instead of in a headset.
func _test_balance_targets() -> void:
	# D12 (docs/ELEMENTS_PLAN.md, section D12, ETAP 3): XP from kills, one skill point
	# per level, shrines about one per 216 m of walking. The targets: 5–7 nodes by
	# minute 8 for an average player, and the master technique (node 5, 8 points for
	# the whole school) reachable on a good run in about 6–10 minutes.
	var order := BalanceModel.full_order(Elements.SAKURA)
	var costs: Array[int] = BalanceModel.cumulative_costs(order)
	var avg: Dictionary = BalanceModel.economy("average", 600.0)
	var careful: Dictionary = BalanceModel.economy("careful", 600.0)
	var good: Dictionary = BalanceModel.economy("skilled", 600.0)
	var first: float = BalanceModel.time_to_afford(avg.timeline, costs[0])
	_check("average player buys the first node inside the first minute (%.0f s)" % first, first > 0.0 and first <= 60.0)
	var at8: int = int(avg.timeline[mini(48, avg.timeline.size() - 1)].points)
	_check("Skill points earned by minute 8 (average): 5–7 (%d)" % at8, at8 >= 5 and at8 <= 7)
	var nodes8: int = BalanceModel.nodes_for_budget(at8)
	_check("average player owns 5–7 nodes at minute 8 (%d)" % nodes8, nodes8 >= 5 and nodes8 <= 7)
	var master: float = BalanceModel.time_to_afford(good.timeline, costs[4])
	_check("the master technique is reachable on a good run in 6–10 minutes (%.0f s)" % master,
		master >= 360.0 and master <= 600.0)
	var careful_nodes := BalanceModel.nodes_for_budget(int(careful.timeline[mini(36, careful.timeline.size() - 1)].points))
	_check("even a careful player owns 3+ nodes by minute 6 (%d)" % careful_nodes, careful_nodes >= 3)
	_check("shrines stay rare: one per ~216 m of walking (spacing %.0f m)" % BalanceModel.hokora_spacing(),
		absf(BalanceModel.hokora_spacing() - 216.0) < 5.0)
	_check("XP per kill: yōkai 24, elite 48, Oni 64 (D12)",
		ElementBalance.XP_YOKAI == 24 and ElementBalance.XP_ELITE == 48 and ElementBalance.XP_ONI == 64)

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

	var poor: Dictionary = tree.try_unlock("petal_sense", 0)
	_check("Cannot unlock without enough skill points (needs 1, has 0)",
		not poor.get("ok", true) and poor.get("reason") == SkillTreeData.REASON_POINTS
		and not tree.is_unlocked("petal_sense"))

	var unknown: Dictionary = tree.try_unlock("not_a_node", 99)
	_check("Unknown node id is rejected",
		not unknown.get("ok", true) and unknown.get("reason") == SkillTreeData.REASON_UNKNOWN_NODE)

	var bought: Dictionary = tree.try_unlock("petal_sense", 1)
	_check("Node 1 unlocks with exactly its cost in skill points",
		bought.get("ok", false) and int(bought.get("cost", 0)) == 1 and tree.is_unlocked("petal_sense"))

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


## D4: each school's tier-5 node carries its Kirisute finisher, and only that
## node does. A tier-4 node or another school's finisher grants nothing.
func _test_kirisute_finishers() -> void:
	var names := {}
	for element in Elements.COMBAT_ELEMENTS:
		var tree := SkillTreeData.new()
		var tier5 := ""
		var tier4_ok := true
		for n: Dictionary in SkillTreeData.nodes_for_element(element):
			var tier := int(n.tier)
			if tier == 5:
				tier5 = String(n.id)
			elif tier < 5:
				tier4_ok = tier4_ok and tree.try_unlock(String(n.id), 1000).get("ok", false)
		var before := tree.has_effect(element, "kirisute")
		var verdict := tree.try_unlock(tier5, 1000)
		var after: bool = tree.has_effect(element, "kirisute") and bool(tree.effect_value(element, "kirisute", false))
		var finisher := Elements.kirisute_name(element)
		names[finisher] = true
		_check("%s: tier 4 and the rest of the tree leave the finisher off, and the tier-5 node turns it on" % element,
			tier4_ok and not before and bool(verdict.get("ok", false)) and after)
		var other := SkillTreeData.new()
		var other_element := Elements.SAKURA if element != Elements.SAKURA else Elements.STORM
		for n: Dictionary in SkillTreeData.nodes_for_element(other_element):
			other.try_unlock(String(n.id), 1000)
		_check("%s: another school's full tree, finisher included, does not grant %s" % [element, finisher],
			other.has_effect(other_element, "kirisute") and not other.has_effect(element, "kirisute"))
	_check("each school has its own finisher name (%s)" % ", ".join(names.keys()), names.size() == Elements.COMBAT_ELEMENTS.size() and not names.has(""))


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


## D9 (sandbox): the switch unlocks every node through is_unlocked, so the effects, the
## finishers and the menu all follow; nothing is bought; the real unlocks come back as they were.
func _test_sandbox_rules() -> void:
	var tree := SkillTreeData.new()
	tree.try_unlock("petal_sense", 1)
	var real := tree.unlocked.duplicate()

	tree.sandbox = true
	var all_on := true
	for n: Dictionary in SkillTreeData.NODES:
		all_on = all_on and tree.is_unlocked(String(n.id))
	_check("sandbox: all 20 nodes read as unlocked, tier 5 included", all_on and tree.is_unlocked("ikazuchi_avatar"))
	var poor: Dictionary = tree.can_unlock("razor_petals", 0)
	_check("sandbox: nothing is bought, so no points are needed (%s)" % poor.get("reason", ""),
		poor.get("reason") == SkillTreeData.REASON_ALREADY_UNLOCKED and not tree.try_unlock("razor_petals", 0).get("ok", true))
	_check("sandbox: buying changes no unlock state", tree.unlocked == real)
	_check("sandbox: the finisher is on for every school (%s)" % Elements.kirisute_name(Elements.STORM),
		tree.has_effect(Elements.STORM, "kirisute") and tree.has_effect(Elements.INK, "kirisute"))
	_check("sandbox: a tier-4 effect is live too (Life Bloom heal %.0f)" % tree.effect_value(Elements.SAKURA, "heal_on_kill", 0.0),
		absf(float(tree.effect_value(Elements.SAKURA, "heal_on_kill", 0.0)) - ElementBalance.LIFE_BLOOM_HEAL_KILL) < 0.001)
	tree.reset()
	_check("sandbox survives a run reset (the switch is a setting, not a run unlock)", tree.sandbox and tree.is_unlocked("shadow_clones"))

	tree.sandbox = false
	_check("switching off gives back the run's unlocks exactly", tree.unlocked == {} and not tree.is_unlocked("ikazuchi_avatar"))
	var tree2 := SkillTreeData.new()
	tree2.try_unlock("petal_sense", 1)
	var before := tree2.unlocked.duplicate()
	tree2.sandbox = true
	tree2.sandbox = false
	_check("on, then off: a bought node stays bought and nothing else appears",
		tree2.unlocked == before and tree2.is_unlocked("petal_sense") and not tree2.is_unlocked("razor_petals"))


## D9: the abilities read the sandbox through the same effect path (no cached copy):
## Sakura's Senbonzakura releases the Razor Petals count without a single point spent.
func _test_sandbox_abilities(elem_sys: ElementSystem) -> void:
	var tree := SkillTreeData.new()
	tree.sandbox = true
	elem_sys.skill_tree = tree
	elem_sys.reset()
	elem_sys.imbue(Elements.SAKURA)
	_check("sandbox: the Sakura imbue lasts the Petal Sense 24.0 s", absf(elem_sys.element_time_remaining - 24.0) < 0.01)
	var counts: Array = []
	var cb := func(type: String, data: Dictionary) -> void:
		if type == "senbonzakura":
			counts.append(int(data.get("count", 0)))
	elem_sys.effect_triggered.connect(cb)
	elem_sys.execute_ability_1(Vector3.FORWARD)
	_check("sandbox: Senbonzakura releases the tier-2 petal count (%s)" % [counts],
		counts == [ElementBalance.SENBONZAKURA_PETALS_T2])
	elem_sys.effect_triggered.disconnect(cb)
	elem_sys.reset()
	elem_sys.skill_tree = null


## The SANDBOX switch saves through VrComfortSettings. A section it does not own survives the
## save, and a fresh load brings the switch back. Scratch file only: the real settings stay put.
func _test_sandbox_setting_persists() -> void:
	var real_path := VrComfortSettings.settings_path
	var scratch := "user://test_sandbox_setting.cfg"
	VrComfortSettings.settings_path = scratch
	var seed_cfg := ConfigFile.new()
	seed_cfg.set_value("audio", "music", 50)
	seed_cfg.set_value("future", "keep_me", 7)
	seed_cfg.save(scratch)
	VrComfortSettings.load_settings()
	VrComfortSettings.set_sandbox_enabled(true)

	var after := ConfigFile.new()
	after.load(scratch)
	_check("sandbox switch is saved in its own [sandbox] section", bool(after.get_value("sandbox", "enabled", false)))
	_check("saving keeps the other sections (audio %s, unknown section %s)" % [after.get_value("audio", "music", -1), after.get_value("future", "keep_me", -1)],
		int(after.get_value("audio", "music", -1)) == 50 and int(after.get_value("future", "keep_me", -1)) == 7)
	VrComfortSettings.sandbox_enabled = false
	VrComfortSettings.load_settings()
	_check("loading the file brings the switch back on", VrComfortSettings.sandbox_enabled)

	VrComfortSettings.reset_to_defaults()
	_check("reset to defaults turns the sandbox back off", not VrComfortSettings.sandbox_enabled)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	VrComfortSettings.settings_path = real_path
	VrComfortSettings.sandbox_enabled = false


## The SANDBOX sub-tab is the sixth of six equal tabs: all of them and the switch's buttons sit
## inside the panel and none overlaps another.
func _test_sandbox_page_layout() -> void:
	var panel := Rect2(Vector2.ZERO, SkillTreeCanvas.SIZE)
	var tabs: Array[Rect2] = []
	for key: String in SkillTreeCanvas.SUBNAV_RECTS:
		tabs.append(SkillTreeCanvas.SUBNAV_RECTS[key])
	var inside := true
	var apart := true
	for i in tabs.size():
		inside = inside and panel.encloses(tabs[i])
		for j in range(i + 1, tabs.size()):
			apart = apart and not tabs[i].intersects(tabs[j])
	_check("the six settings sub-tabs sit inside the panel and do not overlap", tabs.size() == 6 and inside and apart)
	var page := Rect2(66.0, 268.0, 1468.0, 300.0)
	var buttons: Array[Rect2] = []
	for key: String in SkillTreeCanvas.SETTINGS_RECTS[SkillTreeCanvas.PAGE_SANDBOX]:
		buttons.append(SkillTreeCanvas.SETTINGS_RECTS[SkillTreeCanvas.PAGE_SANDBOX][key])
	_check("the ON and OFF buttons sit inside the SANDBOX page and do not overlap",
		buttons.size() == 2 and page.encloses(buttons[0]) and page.encloses(buttons[1]) and not buttons[0].intersects(buttons[1]))


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame

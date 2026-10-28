extends Node
## Prints the element balance tables (docs/ELEMENTS_PLAN.md, Phase E4). Fast and
## headless, no scene is loaded:
##   .tools/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/balance_sim.tscn
## (a scene, not `-s`: the autoloads WaveDirector and RunGame need are only there then)
const Model := preload("res://tools/balance_model.gd")


func _ready() -> void:
	print("=== ECONOMY (D1: Ofuda only from hokora shrines, walking distance) ===")
	print("shrine spacing %.0f m, %d Ofuda each, first at %.0f m" % [Model.hokora_spacing(),
		ElementBalance.OFUDA_PER_HOKORA, ElementBalance.HOKORA_OPENING_DISTANCE])
	for profile_name: String in ["careful", "average", "skilled"]:
		var eco: Dictionary = Model.economy(profile_name, 720.0)
		var line := "%-8s" % profile_name
		for minute in [2, 4, 6, 8, 10, 12]:
			var s: Dictionary = eco.timeline[mini(minute * 6, eco.timeline.size() - 1)]
			line += "  %2dmin: %2d shrines %3d札 (%d nodes)" % [minute, s.shrines, int(s.ofuda), Model.nodes_for_budget(int(s.ofuda))]
		print(line)
		var sakura_costs: Array[int] = Model.cumulative_costs(Model.full_order(Elements.SAKURA))
		var parts := ""
		for i in sakura_costs.size():
			parts += "  node%d(%d札)@%s" % [i + 1, sakura_costs[i], _fmt(Model.time_to_afford(eco.timeline, sakura_costs[i]))]
		print("         one school, cumulative:" + parts)
		print("         first shrine @%s, kills %d, elites %d, level %d, wave %d" % [
			_fmt(Model.time_to_afford(eco.timeline, 1)), eco.kills, eco.elites, eco.level, eco.wave])

	print("\n=== KITS: per imbue window, pack of 1 / 4 yōkai, soul rank 1 ===")
	for school: String in Elements.COMBAT_ELEMENTS:
		var order: Array = Model.full_order(school)
		for label in [["bare", []], ["T1", order.slice(0, 1)], ["T1+2", order.slice(0, 2)],
				["T1+3", [order[0], order[2]]], ["full", order]]:
			for pack in [1, 4]:
				_print_kit(school, label[0], label[1], pack, 1)
	print("\n=== RANK SCALING: full tree, abilities vs sword as the run goes on ===")
	for school: String in Elements.COMBAT_ELEMENTS:
		for level in [1, 6, 10]:
			_print_kit(school, "full", Model.full_order(school), 4, level)
	get_tree().quit(0)


func _print_kit(school: String, label: String, nodes: Array, pack: int, level: int) -> void:
	var k: Dictionary = Model.kit(school, nodes, pack, level)
	print("%-7s %-5s L%-2d pack%d  window %4.1fs  A1 %4.0f  A2 %4.0f  passive %4.0f  total %4.0f (%3.0f%% of sword %4.0f)  control %4.1f  guard %4.1f  heal %4.0f" % [
		school, label, level, pack, k.window, k.d1, k.d2, k.passive, k.total, k.ratio * 100.0, k.sword, k.control, k.guard, k.heal])


func _fmt(sec: float) -> String:
	return "never" if sec < 0.0 else "%d:%02d" % [int(sec) / 60, int(sec) % 60]

extends Node
## Prints the element balance tables (docs/ELEMENTS_PLAN.md, Phase E4). Fast and
## headless, no scene is loaded:
##   .tools/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/balance_sim.tscn
## (a scene, not `-s`: the autoloads WaveDirector and RunGame need are only there then)
const Model := preload("res://tools/balance_model.gd")


func _ready() -> void:
	print("=== ECONOMY (D12: XP from kills, one skill point per level, shrine buffs from walking) ===")
	print("shrine spacing %.0f m, first at %.0f m; XP per kill: yokai %d, elite %d, oni %d; level %d needs %d XP, +%d per level" % [
		Model.hokora_spacing(), ElementBalance.HOKORA_OPENING_DISTANCE, ElementBalance.XP_YOKAI,
		ElementBalance.XP_ELITE, ElementBalance.XP_ONI, 1, RunGame.xp_for_level(1), ElementBalance.XP_LEVEL_STEP])
	for profile_name: String in ["careful", "average", "skilled"]:
		var eco: Dictionary = Model.economy(profile_name, 720.0)
		var line := "%-8s" % profile_name
		for minute in [2, 4, 6, 8, 10, 12]:
			var s: Dictionary = eco.timeline[mini(minute * 6, eco.timeline.size() - 1)]
			line += "  %2dmin: LV%2d %2dpt (%d nodes)" % [minute, s.level, int(s.points), Model.nodes_for_budget(int(s.points))]
		print(line)
		var school_costs: Array[int] = Model.cumulative_costs(Model.full_order(Elements.SAKURA))
		var parts := ""
		for i in school_costs.size():
			parts += "  node%d(%dpt)@%s" % [i + 1, school_costs[i], _fmt(Model.time_to_afford(eco.timeline, school_costs[i]))]
		print("         one school, cumulative:" + parts)
		print("         kills %d, elites %d, level %d, points %d, shrines %d, buff uptime %.0f%%, wave %d" % [
			eco.kills, eco.elites, eco.level, eco.points, eco.shrines, float(eco.buff_uptime) * 100.0, eco.wave])

	print("\n=== COUNTER RING (D17): sword multiplier per draft, average player, 8 min ===")
	var wave_profile := WaveProfile.load_default()
	var plain := wave_profile.plain_share(wave_profile.ramp_seconds * 0.5)
	print("plain share at mid-ramp %.0f%%; blind draft mean ×%.3f; read draft ×%.3f (ready counter %.0f%% of fights)" % [
		plain * 100.0, Model.school_mean_matchup(), Model.draft_matchup("read", plain), Model.READY_COUNTER_SHARE * 100.0])
	for draft: String in ["plain", "blind", "read"]:
		var mult := Model.draft_matchup(draft, plain)
		var eco: Dictionary = Model.economy("average", 480.0, 7, mult)
		print("%-6s ×%.3f  kills %3d, elites %2d, level %2d, points %2d, shrines %d" % [
			draft, mult, eco.kills, eco.elites, eco.level, eco.points, eco.shrines])

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

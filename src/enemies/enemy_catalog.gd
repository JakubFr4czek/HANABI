class_name EnemyCatalog
extends RefCounted
## Data-driven enemy builds for the run loop (docs/GDD.md §7, NIGHT_PLAN.md §4).

const ELITE_COUNTER_ELEMENT := {
	Elements.STORM: Elements.INK,
	Elements.INK: Elements.STORM,
	Elements.SAKURA: Elements.SHADOW,
	Elements.SHADOW: Elements.SAKURA,
}

const ELITE_NAMES := {
	Elements.STORM: "Storm Warden",
	Elements.INK: "Ink Shikigami",
	Elements.SAKURA: "Sakura Revenant",
	Elements.SHADOW: "Shadow Stalker",
}


static func make_swarm_profile(max_hp: float) -> EnemyProfile:
	var p := EnemyProfile.new()
	p.display_name = "Yokai"
	p.max_hp = max_hp
	p.poise_per_impulse = 0.045
	p.poise_damage_scale = 0.018
	p.muscle_damage_scale = 0.01
	p.knockdown_time = 0.9
	p.getup_time = 1.1
	p.tactics = {"kind": "swarm"}
	return p


static func make_elite_profile(element: String, max_hp: float) -> EnemyProfile:
	var p := make_swarm_profile(max_hp * 2.35)
	p.display_name = String(ELITE_NAMES.get(element, "Elite Yokai"))
	p.poise_per_impulse = 0.028
	p.poise_damage_scale = 0.012
	p.balance_regen = 0.45
	var weak := String(ELITE_COUNTER_ELEMENT.get(element, Elements.STORM))
	var resist := {}
	resist[element] = 0.34
	resist[weak] = 1.72
	resist["physical"] = 0.42
	p.resistances = resist
	p.tactics = {"kind": "elite", "element": element, "weak_element": weak, "parry_armor": true}
	return p


static func make_oni_profile(max_hp: float) -> EnemyProfile:
	var p := EnemyProfile.new()
	p.display_name = "Oni Warlord"
	p.max_hp = max_hp
	p.poise_per_impulse = 0.022
	p.poise_damage_scale = 0.010
	p.muscle_damage_scale = 0.008
	p.knockdown_time = 1.35
	p.getup_time = 1.55
	p.counter_window = 1.65
	p.counter_multiplier = 1.65
	p.tactics = {
		"kind": "oni",
		"attacks": true,
		"track_player": true,
		"leash_radius": 80.0,
		"engage_distance": 2.2,
		"min_distance": 1.4,
		"block_time": 0.6,
		"interrupt_damage": 30.0,
	}
	return p


static func oni_difficulty() -> DuelistDifficulty:
	var d := DuelistDifficulty.preset("hard")
	d.damage_scale = 1.35
	d.combo_chance = 0.42
	d.block_chance = 0.38
	d.riposte_chance = 0.32
	d.move_speed = 1.15
	d.reaction_time = 0.12
	d.anticipation = 0.65
	d.guard_strength = 0.70
	return d


static func elite_element_for_roll(rng: RandomNumberGenerator) -> String:
	var pool := Elements.COMBAT_ELEMENTS
	return pool[rng.randi_range(0, pool.size() - 1)]

extends RefCounted
## Pure-math balance model of the element system (docs/ELEMENTS_PLAN.md, Phase E4).
##
## No scene tree, no physics: it reads the game's own numbers ([ElementBalance],
## [SkillTreeData], the formulas of [WaveDirector]) and answers two questions fast:
##   1. economy(): how many Ofuda does a 5–10 minute run earn, and when does each
##      skill-tree node become affordable?
##   2. kit(): what does one imbue window of each school deliver (damage, control,
##      protection) against a lone yōkai and against a pack, base and upgraded?
## tools/balance_sim.gd prints the tables; tests/skill_tree_data_test.gd asserts
## the design targets so a later tweak cannot silently break the progression.
##
## Assumptions (kept here, in one place, on purpose):
##  - the player is a serial fighter: one yōkai at a time, `gap` seconds to reach
##    the next one, a fraction of the time lost to walking between gates;
##  - a solid sword cut is 85 HP, `hits_per_second` of them connect on average;
##  - the blade does not grow with level (D1: level-up cards are gone, so power
##    comes from the Ofuda tree only);
##  - Ofuda come ONLY from hokora shrines (D1): a shrine is passed every
##    ElementBalance.HOKORA_SLOT spacing metres of walking, the first one
##    HOKORA_OPENING_DISTANCE metres out, and each gives OFUDA_PER_HOKORA.
##    Yōkai, elites and the Oni give nothing.

const SWORD_HIT := 85.0

## Player skill profiles: effective sword hits per second, seconds lost between
## two kills, the share of the run spent walking and the walking speed (m/s).
## "average" is the design target; "skilled" is the good run the demo is tuned for.
const PROFILES := {
	"careful": {"hits_per_second": 0.55, "gap": 2.2, "idle": 0.30, "walk_share": 0.45, "walk_speed": 2.2},
	"average": {"hits_per_second": 0.80, "gap": 1.4, "idle": 0.25, "walk_share": 0.60, "walk_speed": 2.6},
	"skilled": {"hits_per_second": 1.10, "gap": 0.9, "idle": 0.20, "walk_share": 0.75, "walk_speed": 3.0},
}


## Mean walking distance between two shrines (m). A walk crosses slots of side S
## and meets a slot's shrine only inside the spawn band (2 × spawn radius wide),
## with probability chance × valid share: spacing = S² / (band × chance × valid).
static func hokora_spacing() -> float:
	var side := float(ElementBalance.HOKORA_SLOT_CHUNKS) * ForestWorld.CHUNK_SIZE
	var band := 2.0 * ElementBalance.HOKORA_SPAWN_RADIUS
	return side * side / (band * ElementBalance.HOKORA_SLOT_CHANCE * ElementBalance.HOKORA_VALID_SHARE)


## One run simulated with the real wave formulas. Kills and the rank come from
## the fight; Ofuda come from the distance walked past hokora shrines (D1).
## Returns {"timeline": [{t, kills, ofuda, level, shrines, wave}], "total": int,
## "kills": int, "shrines": int, ...} with one sample every 10 s up to [param seconds].
static func economy(profile_name: String, seconds: float = 600.0, seed_value: int = 7) -> Dictionary:
	var prof: Dictionary = PROFILES[profile_name]
	var wd := WaveDirector.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var dt := 0.1
	var t := 0.0
	var wave := 0
	var pending := 0
	var wave_timer := 0.0
	var next_wave_cd := wd.initial_wave_delay
	var spawn_timer := 0.0
	var oni_cd := wd.oni_spawn_interval * 0.55
	var alive: Array[Dictionary] = []   # {hp, kind}
	var target: Dictionary = {}
	var engage := 0.0
	var kills := 0
	var oni_kills := 0
	var elites := 0
	var xp := 0.0
	var level := 1
	var walked := 0.0
	var shrines := 0
	var next_shrine_at := ElementBalance.HOKORA_OPENING_DISTANCE
	var ofuda := 0
	var timeline: Array[Dictionary] = []
	var next_sample := 0.0

	while t <= seconds:
		if t >= next_sample:
			timeline.append({"t": t, "kills": kills, "ofuda": ofuda, "level": level,
				"wave": wave, "shrines": shrines, "walked": walked})
			next_sample += 10.0
		t += dt
		wave_timer += dt
		walked += float(prof.walk_speed) * float(prof.walk_share) * dt
		while walked >= next_shrine_at:
			shrines += 1
			ofuda += ElementBalance.OFUDA_PER_HOKORA
			next_shrine_at += hokora_spacing()
		var ramp := clampf(t / wd.ramp_seconds, 0.0, 1.0)
		var cap := clampi(wd.start_concurrent_enemies + int(t / wd.seconds_per_extra_enemy),
			wd.start_concurrent_enemies, wd.max_concurrent_enemies)
		if pending > 0 and alive.size() < cap:
			spawn_timer -= dt
			if spawn_timer <= 0.0:
				spawn_timer = lerpf(1.3, 0.35, ramp)
				pending -= 1
				alive.append(_spawn(wd, rng, wave, t))
		if pending == 0 and (alive.is_empty() or wave_timer >= wd.max_wave_duration):
			next_wave_cd -= dt
			if next_wave_cd <= 0.0:
				wave += 1
				wave_timer = 0.0
				next_wave_cd = lerpf(wd.between_wave_delay, 2.0, ramp)
				pending = wd.wave_enemy_count(wave, t)
				var batch := mini(pending, 1 if ramp < 0.35 else maxi(1, cap - alive.size()) / 2)
				for i in batch:
					pending -= 1
					alive.append(_spawn(wd, rng, wave, t))
		oni_cd -= dt
		if oni_cd <= 0.0 and t >= wd.oni_spawn_min_run_time and not _has_kind(alive, "oni"):
			alive.append({"hp": wd.scaled_hp(maxi(wave, 1), t) * 6.5, "kind": "oni"})
			oni_cd = wd.oni_spawn_interval

		# The player fights one yōkai at a time.
		if target.is_empty() and not alive.is_empty():
			target = alive[0]
			engage = float(prof.gap)
		if not target.is_empty():
			if engage > 0.0:
				engage -= dt
			else:
				var power := blade_power(level)
				var dps := SWORD_HIT * float(prof.hits_per_second) * power * (1.0 - float(prof.idle))
				if target.kind == "oni":
					dps *= 0.7   # a boss parries and moves
				target.hp = float(target.hp) - dps * dt
				if float(target.hp) <= 0.0:
					alive.erase(target)
					kills += 1
					if target.kind == "elite":
						elites += 1
					elif target.kind == "oni":
						oni_kills += 1
					xp += 24.0
					while xp >= RunGame.xp_for_level(level):
						xp -= RunGame.xp_for_level(level)
						level += 1
					target = {}
	wd.free()
	return {"timeline": timeline, "kills": kills, "oni_kills": oni_kills, "elites": elites,
		"level": level, "total": ofuda, "shrines": shrines, "wave": wave}


## Most nodes a player can own with [param budget] Ofuda when they always buy the
## cheapest node whose prerequisites are met (what an average player can afford).
static func nodes_for_budget(budget: int) -> int:
	var unlocked := {}
	var spent := 0
	var bought := 0
	while true:
		var best := ""
		var best_cost := 1 << 30
		for n: Dictionary in SkillTreeData.NODES:
			var id := String(n.id)
			if unlocked.has(id):
				continue
			var verdict := SkillTreeData.new()
			verdict.unlocked = unlocked.duplicate()
			if not verdict.prerequisites_met(id):
				continue
			var cost := int(n.cost)
			if cost < best_cost:
				best_cost = cost
				best = id
		if best.is_empty() or spent + best_cost > budget:
			break
		unlocked[best] = true
		spent += best_cost
		bought += 1
	return bought


## D1: the Razor Edge card is gone and nothing else raises the sword, so the
## blade is the same at every level (the Ofuda tree and the rank do the growing).
static func blade_power(_level: int) -> float:
	return 1.0


static func _has_kind(list: Array[Dictionary], kind: String) -> bool:
	for e in list:
		if e.kind == kind:
			return true
	return false


static func _spawn(wd: WaveDirector, rng: RandomNumberGenerator, wave: int, t: float) -> Dictionary:
	var hp := wd.scaled_hp(maxi(wave, 1), t)
	if rng.randf() < wd.elite_spawn_chance(maxi(wave, 1)):
		return {"hp": hp * 2.35, "kind": "elite"}
	return {"hp": hp, "kind": "swarm"}


## Seconds until the cumulative cost of [param costs] is first covered, per the
## timeline of [method economy]; -1 when the run never gets there.
static func time_to_afford(timeline: Array[Dictionary], cumulative_cost: int) -> float:
	for s in timeline:
		if int(floor(float(s.ofuda))) >= cumulative_cost:
			return float(s.t)
	return -1.0


## Cumulative Ofuda needed to own the first [param count] nodes of a buying
## order (ids). Order must respect prerequisites.
static func cumulative_costs(order: Array) -> Array[int]:
	var out: Array[int] = []
	var sum := 0
	for id in order:
		sum += int(SkillTreeData.node_by_id(String(id)).get("cost", 0))
		out.append(sum)
	return out


# --- Kit value -----------------------------------------------------------------------

static func _tree(ids: Array) -> SkillTreeData:
	var tree := SkillTreeData.new()
	for id in ids:
		tree.unlocked[String(id)] = true
	return tree


static func _fx(tree: SkillTreeData, school: String, key: String, base: Variant) -> Variant:
	return tree.effect_value(school, key, base)


## What one imbue window of [param school] is worth against [param pack]
## yōkai standing together, with the nodes [param unlocked] bought and
## soul rank [param level] (sword power and ability power both grow with it,
## see [method ElementSystem.ability_power]). All figures per window.
static func kit(school: String, unlocked: Array, pack: int, level: int = 1,
		profile_name: String = "average") -> Dictionary:
	var blade := blade_power(level)
	var power := blade * (1.0 + ElementBalance.POWER_PER_RANK * float(level - 1))   # ElementSystem.ability_power()
	var tree := _tree(unlocked)
	var prof: Dictionary = PROFILES[profile_name]
	var window: float = float(_fx(tree, school, "imbue_duration", ElementBalance.IMBUE_SECONDS))
	var sword_window := SWORD_HIT * float(prof.hits_per_second) * window * blade * (1.0 - float(prof.idle))
	var react := 0.8   # seconds a human needs to notice a ready ability and press
	var d1 := 0.0      # ability 1 damage
	var d2 := 0.0      # ability 2 damage
	var passive := 0.0 # passive-node damage (extra sword value)
	var control := 0.0 # enemy-seconds of slow / stagger / stun / root
	var guard := 0.0   # seconds the player is protected (barrier, decoy), weighted
	var heal := 0.0    # HP restored
	var cd1 := float(_fx(tree, school, "cooldown_ability_1", _base_cd(school, 1)))
	var cd2 := float(_fx(tree, school, "cooldown_ability_2", _base_cd(school, 2)))
	var n1 := 1 + int(floor(maxf(window - 1.0, 0.0) / (cd1 + react)))
	var n2 := 1 + int(floor(maxf(window - 1.0, 0.0) / (cd2 + react)))
	var hits := float(prof.hits_per_second) * window * (1.0 - float(prof.idle))

	match school:
		Elements.SAKURA:
			var petals := int(_fx(tree, school, "senbonzakura_petal_count", ElementBalance.SENBONZAKURA_PETALS))
			var dmg := float(_fx(tree, school, "senbonzakura_damage", ElementBalance.SENBONZAKURA_DAMAGE))
			var pierce := int(_fx(tree, school, "senbonzakura_pierce", ElementBalance.SENBONZAKURA_PIERCE))
			# ~65% of a fan lands on a yōkai at 3 m; pierce lets it carry on, but a
			# petal travels one line, so it threads at most ~3 yōkai of a cluster.
			d1 = n1 * round(petals * 0.65) * dmg * mini(mini(pack, pierce), 3) * power
			var dur := float(_fx(tree, school, "hanamai_duration", ElementBalance.HANAMAI_DURATION))
			var contacts := mini(pack, ElementBalance.HANAMAI_PETALS)
			d2 = n2 * contacts * (ElementBalance.HANAMAI_DAMAGE / ElementBalance.HANAMAI_TICK) * 0.5 * dur * power
			guard = n2 * dur * (1.0 - float(_fx(tree, school, "incoming_damage_multiplier", ElementBalance.HANAMAI_DAMAGE_TAKEN)))
			heal = hits * float(_fx(tree, school, "heal_on_hit", 0.0)) \
				+ float(_fx(tree, school, "heal_on_kill", 0.0)) * hits / 2.0
			if tree.is_unlocked("senbonzakura_kageyoshi"):
				passive += float(_fx(tree, school, "kageyoshi_burst_damage", 0.0)) * mini(pack, 3) * power
		Elements.STORM:
			var chain := int(_fx(tree, school, "raikiri_chain_targets", ElementBalance.RAIKIRI_CHAIN_TARGETS))
			d1 = n1 * (ElementBalance.RAIKIRI_PRIMARY_DAMAGE + mini(pack - 1, chain) * ElementBalance.RAIKIRI_CHAIN_DAMAGE) * power
			control = n1 * float(_fx(tree, school, "raikiri_stun_duration", 0.0))
			var inside := mini(pack, 4)
			d2 = n2 * inside * ElementBalance.SHIDEN_DAMAGE * power
			control += n2 * inside * float(_fx(tree, school, "shiden_stagger", ElementBalance.SHIDEN_STAGGER))
			if tree.is_unlocked("ikazuchi_avatar"):
				d2 += n2 * mini(pack, 3) * float(_fx(tree, school, "shiden_barrier_damage", 0.0)) \
					* float(_fx(tree, school, "shiden_barrier_duration", 0.0)) / 0.5 * 0.35 * power
			var arc := float(_fx(tree, school, "overcharge_damage", 0.0))
			if arc > 0.0 and pack >= 2:
				passive += hits * 0.7 * arc * power
		Elements.INK:
			var half := float(_fx(tree, school, "sumi_cone_half_deg", ElementBalance.SUMI_HALF_DEGREES))
			var hit_n := mini(pack, 3 if half <= 30.0 else 4)
			var dps := float(_fx(tree, school, "ink_dps", ElementBalance.SUMI_POOL_DPS))
			# Slowed yōkai linger in the pool: ~60% of its life is spent on one.
			d1 = n1 * hit_n * (ElementBalance.SUMI_DAMAGE + dps * ElementBalance.SUMI_POOL_SECONDS * 0.6) * power
			var slow := float(_fx(tree, school, "ink_slow_scale", ElementBalance.SUMI_SLOW_SCALE))
			control = n1 * hit_n * ElementBalance.SUMI_SLOW_SECONDS * (1.0 - slow)
			var tn := mini(pack, int(_fx(tree, school, "kage_nawa_targets", ElementBalance.KAGE_NAWA_TARGETS)))
			d2 = n2 * tn * ElementBalance.KAGE_NAWA_DAMAGE * power
			control += n2 * tn * ElementBalance.KAGE_NAWA_ROOT_SECONDS * (1.0 - ElementBalance.KAGE_NAWA_ROOT_SCALE)
			var dragon := float(_fx(tree, school, "dragon_damage_multiplier", 1.0))
			if dragon > 1.0:
				passive += sword_window * 0.5 * (dragon - 1.0)   # half the cuts land on inked yōkai
		Elements.SHADOW:
			var dur := float(_fx(tree, school, "kagemusha_duration", ElementBalance.KAGEMUSHA_SECONDS))
			guard = n1 * dur
			var boom := float(_fx(tree, school, "decoy_explosion_damage", 0.0))
			d1 = n1 * boom * mini(pack, 3) * power
			# Yami-watari: the next cut (80% of the time the player follows up) is doubled.
			d2 = n2 * 0.8 * (ElementBalance.YAMI_CRIT_MULTIPLIER - 1.0) * SWORD_HIT * blade
			var back := float(_fx(tree, school, "backstab_multiplier", 1.0))
			if back > 1.0:
				passive += hits * 0.3 * (back - 1.0) * SWORD_HIT * blade   # 30% of cuts land from behind
			var clones := int(_fx(tree, school, "shadow_clone_count", 0))
			if clones > 0:
				passive += n2 * mini(pack - 1, clones) * SWORD_HIT * blade * 0.8

	var total := d1 + d2 + passive
	return {"window": window, "sword": sword_window, "d1": d1, "d2": d2, "passive": passive,
		"total": total, "ratio": total / maxf(sword_window, 1.0), "control": control,
		"guard": guard, "heal": heal, "casts1": n1, "casts2": n2}


static func _base_cd(school: String, slot: int) -> float:
	match school:
		Elements.SAKURA: return ElementBalance.SENBONZAKURA_COOLDOWN if slot == 1 else ElementBalance.HANAMAI_COOLDOWN
		Elements.STORM: return ElementBalance.RAIKIRI_COOLDOWN if slot == 1 else ElementBalance.SHIDEN_COOLDOWN
		Elements.INK: return ElementBalance.SUMI_COOLDOWN if slot == 1 else ElementBalance.KAGE_NAWA_COOLDOWN
		Elements.SHADOW: return ElementBalance.KAGEMUSHA_COOLDOWN if slot == 1 else ElementBalance.YAMI_COOLDOWN
	return 8.0


## The buying order that spends on the whole tree of [param school] cheapest
## first (Node 1, both augments, the passive, the master technique).
static func full_order(school: String) -> Array:
	var ids: Array = []
	for n in SkillTreeData.nodes_for_element(school):
		ids.append(String(n.id))
	return ids

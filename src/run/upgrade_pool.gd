class_name UpgradePool
extends RefCounted
## Upgrade definitions and selection logic for Ofuda level-ups (docs/NIGHT_PLAN.md §1).
##
## Item 1 provides the six core generic upgrades:
## - damage (斬): +25% blade damage
## - max_hp (命): +25 max HP (+25 immediate heal)
## - heal (癒): restore 50 HP immediately
## - magnet (魂): +45% soul magnet radius
## - arm_strength (迅): +25% blade speed & arm strength
## - regen (生): +2.5 HP/s passive regeneration

const GENERIC_UPGRADES: Array[Dictionary] = [
	{
		"id": "damage",
		"kanji": "斬",
		"title": "RAZOR EDGE",
		"subtitle": "+25% Blade Damage",
		"color": Color(1.0, 0.32, 0.24),
		"max_stacks": 8,
	},
	{
		"id": "max_hp",
		"kanji": "命",
		"title": "IRON VESSEL",
		"subtitle": "+25 Max HP & Heal",
		"color": Color(0.28, 0.90, 0.68),
		"max_stacks": 8,
	},
	{
		"id": "heal",
		"kanji": "癒",
		"title": "SHRINE DRAUGHT",
		"subtitle": "Restore 50 HP",
		"color": Color(0.42, 0.98, 0.74),
		"max_stacks": 99,
	},
	{
		"id": "magnet",
		"kanji": "魂",
		"title": "SPIRIT CALL",
		"subtitle": "+45% Soul Reach",
		"color": Color(0.36, 0.84, 1.0),
		"max_stacks": 6,
	},
	{
		"id": "arm_strength",
		"kanji": "迅",
		"title": "SWIFT ARM",
		"subtitle": "+25% Blade Speed",
		"color": Color(1.0, 0.76, 0.28),
		"max_stacks": 6,
	},
	{
		"id": "regen",
		"kanji": "生",
		"title": "LIVING BLOOD",
		"subtitle": "+2.5 HP / sec",
		"color": Color(0.96, 0.36, 0.66),
		"max_stacks": 6,
	},
]


static func get_upgrade(id: String) -> Dictionary:
	for u: Dictionary in GENERIC_UPGRADES:
		if String(u.get("id", "")) == id:
			return u.duplicate()
	return {}


## Pick [param count] distinct upgrades for a level-up choice.
static func pick_choices(count: int = 3, stacks: Dictionary = {}, hp_ratio: float = 1.0, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var candidates: Array[Dictionary] = []
	for u: Dictionary in GENERIC_UPGRADES:
		var u_id := String(u.get("id", ""))
		var cur_stacks := int(stacks.get(u_id, 0))
		if cur_stacks >= int(u.get("max_stacks", 8)):
			continue
		if u_id == "heal" and hp_ratio >= 0.95:
			continue
		var entry: Dictionary = u.duplicate()
		entry["next_stack"] = cur_stacks + 1
		var weight := 1.0
		if u_id == "heal" and hp_ratio < 0.55:
			weight = 2.2
		entry["weight"] = weight
		candidates.append(entry)

	# Fallback if filtering left fewer than count options.
	if candidates.size() < count:
		for u: Dictionary in GENERIC_UPGRADES:
			var u_id := String(u.get("id", ""))
			if not candidates.any(func(c: Dictionary) -> bool: return String(c.get("id", "")) == u_id):
				var entry: Dictionary = u.duplicate()
				entry["next_stack"] = int(stacks.get(u_id, 0)) + 1
				entry["weight"] = 0.5
				candidates.append(entry)

	var picked: Array[Dictionary] = []
	while picked.size() < count and not candidates.is_empty():
		var total_w := 0.0
		for c: Dictionary in candidates:
			total_w += float(c.get("weight", 1.0))
		var roll := rng.randf() * total_w
		var chosen_idx := 0
		for i in candidates.size():
			roll -= float(candidates[i].get("weight", 1.0))
			if roll <= 0.0:
				chosen_idx = i
				break
		picked.append(candidates[chosen_idx])
		candidates.remove_at(chosen_idx)
	return picked

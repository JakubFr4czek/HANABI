class_name UpgradePool
extends RefCounted
## Upgrade definitions and selection logic for Ofuda level-ups (docs/NIGHT_PLAN.md §1–2).
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

const ELEMENT_SLOT_LIMIT := 6
const ELEMENT_UPGRADES: Array[Dictionary] = [
	{
		"id": "sakura_petals", "element": Elements.SAKURA, "tier": 1,
		"kanji": "桜", "header": "桜 · SAKURA I", "title": "PETAL EDGE",
		"subtitle": "Swift cuts release glass petals", "color": Color(1.0, 0.30, 0.70),
	},
	{
		"id": "sakura_orbit", "element": Elements.SAKURA, "tier": 2, "requires": "sakura_petals",
		"kanji": "花", "header": "桜 · SAKURA II", "title": "BLOOM HALO",
		"subtitle": "Petal blades orbit and cut", "color": Color(1.0, 0.34, 0.76),
	},
	{
		"id": "sakura_heal", "element": Elements.SAKURA, "tier": 3, "requires": "sakura_orbit",
		"kanji": "癒", "header": "桜 · SAKURA III", "title": "HANAMI GRACE",
		"subtitle": "Each fallen yōkai restores life", "color": Color(1.0, 0.40, 0.72),
	},
	{
		"id": "storm_chain", "element": Elements.STORM, "tier": 1,
		"kanji": "雷", "header": "雷 · STORM I", "title": "CHAIN THUNDER",
		"subtitle": "Cuts arc to nearby yōkai", "color": Color(0.30, 0.84, 1.0),
	},
	{
		"id": "storm_charge", "element": Elements.STORM, "tier": 2, "requires": "storm_chain",
		"kanji": "電", "header": "雷 · STORM II", "title": "HEAVEN'S CHARGE",
		"subtitle": "Motion charges a decisive strike", "color": Color(0.38, 0.90, 1.0),
	},
	{
		"id": "storm_overload", "element": Elements.STORM, "tier": 3, "requires": "storm_charge",
		"kanji": "轟", "header": "雷 · STORM III", "title": "THUNDERCLAP",
		"subtitle": "Charged strikes fork farther", "color": Color(0.46, 0.94, 1.0),
	},
	{
		"id": "ink_pool", "element": Elements.INK, "tier": 1,
		"kanji": "墨", "header": "墨 · INK I", "title": "BLACK WAKE",
		"subtitle": "Blade hits paint slowing pools", "color": Color(0.52, 0.65, 0.94),
	},
	{
		"id": "ink_tendrils", "element": Elements.INK, "tier": 2, "requires": "ink_pool",
		"kanji": "縛", "header": "墨 · INK II", "title": "SUMI BIND",
		"subtitle": "Ink tendrils lash trapped yōkai", "color": Color(0.58, 0.70, 0.98),
	},
	{
		"id": "ink_depth", "element": Elements.INK, "tier": 3, "requires": "ink_tendrils",
		"kanji": "淵", "header": "墨 · INK III", "title": "BOTTOMLESS INK",
		"subtitle": "Pools widen and endure", "color": Color(0.62, 0.72, 1.0),
	},
	{
		"id": "shadow_blink", "element": Elements.SHADOW, "tier": 1,
		"kanji": "影", "header": "影 · SHADOW I", "title": "VOID STEP",
		"subtitle": "Blink through the blade's line", "color": Color(0.76, 0.30, 1.0),
	},
	{
		"id": "shadow_darkness", "element": Elements.SHADOW, "tier": 2, "requires": "shadow_blink",
		"kanji": "闇", "header": "影 · SHADOW II", "title": "BLIND MOON",
		"subtitle": "Blink leaves confusing darkness", "color": Color(0.82, 0.34, 1.0),
	},
	{
		"id": "shadow_veil", "element": Elements.SHADOW, "tier": 3, "requires": "shadow_darkness",
		"kanji": "幽", "header": "影 · SHADOW III", "title": "NIGHT VEIL",
		"subtitle": "Longer darkness, faster blink", "color": Color(0.88, 0.38, 1.0),
	},
]


static func get_upgrade(id: String) -> Dictionary:
	for u: Dictionary in GENERIC_UPGRADES:
		if String(u.get("id", "")) == id:
			return u.duplicate()
	for u: Dictionary in ELEMENT_UPGRADES:
		if String(u.get("id", "")) == id:
			return u.duplicate()
	return {}


static func element_for_upgrade(id: String) -> String:
	return String(get_upgrade(id).get("element", Elements.NONE))


static func element_slot_count(stacks: Dictionary) -> int:
	var total := 0
	for u: Dictionary in ELEMENT_UPGRADES:
		if int(stacks.get(String(u.id), 0)) > 0:
			total += 1
	return total


static func available_element_upgrades(stacks: Dictionary, active_elements: Array, slots_used: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var occupied := element_slot_count(stacks) if slots_used < 0 else slots_used
	if occupied >= ELEMENT_SLOT_LIMIT:
		return out
	for u: Dictionary in ELEMENT_UPGRADES:
		var id := String(u.id)
		if int(stacks.get(id, 0)) > 0:
			continue
		var element := String(u.element)
		var tier := int(u.tier)
		if tier == 1:
			# One element per run: the first pick locks the build, later hands
			# only offer its remaining tiers (plus generics).
			if active_elements.has(element) or active_elements.size() >= 1:
				continue
		else:
			if not active_elements.has(element):
				continue
			var required := String(u.get("requires", ""))
			if required != "" and int(stacks.get(required, 0)) <= 0:
				continue
		var entry := u.duplicate()
		entry["next_stack"] = tier
		entry["weight"] = 1.65
		out.append(entry)
	return out


## Pick [param count] distinct upgrades for a level-up choice.
static func pick_choices(count: int = 3, stacks: Dictionary = {}, hp_ratio: float = 1.0,
		rng: RandomNumberGenerator = null, active_elements: Array = [], element_slots: int = -1) -> Array[Dictionary]:
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
		var weight := 0.82
		if u_id == "heal" and hp_ratio < 0.55:
			weight = 2.2
		entry["weight"] = weight
		candidates.append(entry)

	var element_candidates := available_element_upgrades(stacks, active_elements, element_slots)
	candidates.append_array(element_candidates)

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

	# Element identity is the point of this milestone: whenever an eligible
	# element card exists, every hand should contain at least one instead of
	# occasionally dealing three generic stat cards.
	if not element_candidates.is_empty() and not picked.any(func(c: Dictionary) -> bool: return c.has("element")):
		picked[picked.size() - 1] = element_candidates[rng.randi_range(0, element_candidates.size() - 1)]
	return picked

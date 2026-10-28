class_name SkillTreeData
extends RefCounted
## Per-element Ofuda skill trees (docs/ELEMENTS_PLAN.md section (d), Phase E2c).
##
## Four trees (Sakura, Storm, Ink, Shadow) of five nodes each. Node 1 is the
## school awakening, Nodes 2/3 augment Ability 1/2, Node 4 is a passive that
## needs Node 2 OR Node 3, and Node 5 is the master technique needing Node 4.
## Costs are 2/4/4/6/8 Ofuda — 24 for a full tree, calibrated so a single
## 5–10 minute demo run (20–30 Ofuda expected yield) can finish one tree.
##
## This class is pure data + unlock state: it never touches the scene tree.
## [RunGame] owns the Ofuda wallet and spends through [method try_unlock];
## [ElementSystem] reads numeric ability parameters through
## [method effect_value], so an unlock changes the ability it names.
## Unlock state is per-run: [method reset] clears it (called on run start
## and on player death).

const REASON_OK := "ok"
const REASON_UNKNOWN_NODE := "unknown_node"
const REASON_ALREADY_UNLOCKED := "already_unlocked"
const REASON_PREREQUISITE := "missing_prerequisite"
const REASON_OFUDA := "insufficient_ofuda"

## One entry per node. "requires_all" must all be unlocked; "requires_any"
## needs at least one unlocked (empty = no constraint). "effects" maps an
## ElementSystem parameter key to its upgraded value for that node's element.
const NODES: Array[Dictionary] = [
	# --- Sakura (桜) ---------------------------------------------------------
	{
		"id": "petal_sense", "element": Elements.SAKURA, "tier": 1,
		"kanji": "花気", "title": "PETAL SENSE",
		"subtitle": "Senbonzakura +25% damage · imbue 24 s",
		"cost": 2, "requires_all": [], "requires_any": [],
		"effects": {"senbonzakura_damage": 20.0, "imbue_duration": 24.0},
	},
	{
		"id": "razor_petals", "element": Elements.SAKURA, "tier": 2,
		"kanji": "刃花", "title": "RAZOR PETALS",
		"subtitle": "Senbonzakura: 8 petals, pierces all",
		"cost": 4, "requires_all": ["petal_sense"], "requires_any": [],
		"effects": {"senbonzakura_petal_count": 8, "senbonzakura_pierce": 99},
	},
	{
		"id": "hanami_storm", "element": Elements.SAKURA, "tier": 3,
		"kanji": "花宴", "title": "STORM OF HANAMI",
		"subtitle": "Hanamai 8.5 s · damage taken −45%",
		"cost": 4, "requires_all": ["petal_sense"], "requires_any": [],
		"effects": {"hanamai_duration": 8.5, "incoming_damage_multiplier": 0.55},
	},
	{
		"id": "life_bloom", "element": Elements.SAKURA, "tier": 4,
		"kanji": "命咲", "title": "LIFE BLOOM",
		"subtitle": "Sakura cuts heal 4 HP · kills heal 12 HP",
		"cost": 6, "requires_all": [], "requires_any": ["razor_petals", "hanami_storm"],
		"effects": {"heal_on_hit": 4.0, "heal_on_kill": 12.0},
	},
	{
		"id": "senbonzakura_kageyoshi", "element": Elements.SAKURA, "tier": 5,
		"kanji": "景厳", "title": "SENBONZAKURA KAGEYOSHI",
		"subtitle": "Senbonzakura during Hanamai detonates the orbit (80 dmg)",
		"cost": 8, "requires_all": ["life_bloom"], "requires_any": [],
		"effects": {"kageyoshi_burst_damage": 80.0},
	},
	# --- Storm (雷) ----------------------------------------------------------
	{
		"id": "static_conduit", "element": Elements.STORM, "tier": 1,
		"kanji": "導電", "title": "STATIC CONDUIT",
		"subtitle": "Raikiri chains to 5 · imbue 24 s",
		"cost": 2, "requires_all": [], "requires_any": [],
		"effects": {"raikiri_chain_targets": 5, "imbue_duration": 24.0},
	},
	{
		"id": "thunder_splitter", "element": Elements.STORM, "tier": 2,
		"kanji": "雷破", "title": "THUNDER SPLITTER",
		"subtitle": "Raikiri cooldown 2.5 s · primary target stunned",
		"cost": 4, "requires_all": ["static_conduit"], "requires_any": [],
		"effects": {"cooldown_ability_1": 2.5, "raikiri_stun_duration": 1.0},
	},
	{
		"id": "flash_stride", "element": Elements.STORM, "tier": 3,
		"kanji": "瞬歩", "title": "FLASH STRIDE",
		"subtitle": "Shiden dash 6.0 m · stagger 2.2 s",
		"cost": 4, "requires_all": ["static_conduit"], "requires_any": [],
		"effects": {"shiden_distance": 6.0, "shiden_stagger": 2.2},
	},
	{
		"id": "overcharge", "element": Elements.STORM, "tier": 4,
		"kanji": "過負荷", "title": "OVERCHARGE",
		"subtitle": "Storm cuts arc 12 dmg to a nearby yōkai",
		"cost": 6, "requires_all": [], "requires_any": ["thunder_splitter", "flash_stride"],
		"effects": {"overcharge_damage": 12.0},
	},
	{
		"id": "ikazuchi_avatar", "element": Elements.STORM, "tier": 5,
		"kanji": "雷神", "title": "IKAZUCHI AVATAR",
		"subtitle": "Shiden leaves a 4 s lightning barrier",
		"cost": 8, "requires_all": ["overcharge"], "requires_any": [],
		"effects": {"shiden_barrier_duration": 4.0, "shiden_barrier_damage": 20.0},
	},
	# --- Ink (墨) ------------------------------------------------------------
	{
		"id": "sumi_mastery", "element": Elements.INK, "tier": 1,
		"kanji": "墨法", "title": "SUMI MASTERY",
		"subtitle": "Ink slow 75% · imbue 24 s",
		"cost": 2, "requires_all": [], "requires_any": [],
		"effects": {"ink_slow_scale": 0.25, "imbue_duration": 24.0},
	},
	{
		"id": "splatter_tide", "element": Elements.INK, "tier": 2,
		"kanji": "墨浪", "title": "SPLATTER TIDE",
		"subtitle": "Sumi-gaeshi 90° cone · ink damage ×2",
		"cost": 4, "requires_all": ["sumi_mastery"], "requires_any": [],
		"effects": {"sumi_cone_half_deg": 45.0, "ink_dps": 14.0},
	},
	{
		"id": "black_bind", "element": Elements.INK, "tier": 3,
		"kanji": "黒縛", "title": "BLACK BIND",
		"subtitle": "Kage-nawa snares 5 · pulls into melee",
		"cost": 4, "requires_all": ["sumi_mastery"], "requires_any": [],
		"effects": {"kage_nawa_targets": 5},
	},
	{
		"id": "dragon_calligraphy", "element": Elements.INK, "tier": 4,
		"kanji": "墨龍", "title": "DRAGON CALLIGRAPHY",
		"subtitle": "Yōkai standing in ink take +35% sword damage",
		"cost": 6, "requires_all": [], "requires_any": ["splatter_tide", "black_bind"],
		"effects": {"dragon_damage_multiplier": 1.35},
	},
	{
		"id": "abyssal_sea", "element": Elements.INK, "tier": 5,
		"kanji": "墨海", "title": "ABYSSAL SEA",
		"subtitle": "Your ink grants +20% speed and a damage ward",
		"cost": 8, "requires_all": ["dragon_calligraphy"], "requires_any": [],
		"effects": {"abyssal_speed_multiplier": 1.2},
	},
	# --- Shadow (影) ----------------------------------------------------------
	{
		"id": "night_veil", "element": Elements.SHADOW, "tier": 1,
		"kanji": "夜帳", "title": "NIGHT VEIL",
		"subtitle": "Kagemusha decoy 5.0 s · imbue 24 s",
		"cost": 2, "requires_all": [], "requires_any": [],
		"effects": {"kagemusha_duration": 5.0, "imbue_duration": 24.0},
	},
	{
		"id": "phantom_retaliation", "element": Elements.SHADOW, "tier": 2,
		"kanji": "幻影", "title": "PHANTOM RETALIATION",
		"subtitle": "Decoy expiry explodes for 45 dmg",
		"cost": 4, "requires_all": ["night_veil"], "requires_any": [],
		"effects": {"decoy_explosion_damage": 45.0},
	},
	{
		"id": "umbral_reach", "element": Elements.SHADOW, "tier": 3,
		"kanji": "影界", "title": "UMBRAL REACH",
		"subtitle": "Yami-watari range 6.5 m · cooldown 5.5 s",
		"cost": 4, "requires_all": ["night_veil"], "requires_any": [],
		"effects": {"yami_range": 6.5, "cooldown_ability_2": 5.5},
	},
	{
		"id": "backstab_execution", "element": Elements.SHADOW, "tier": 4,
		"kanji": "暗殺", "title": "BACKSTAB EXECUTION",
		"subtitle": "Rear strikes ×2.5 and yield 1 bonus Ofuda",
		"cost": 6, "requires_all": [], "requires_any": ["phantom_retaliation", "umbral_reach"],
		"effects": {"backstab_multiplier": 2.5, "backstab_ofuda": 1},
	},
	{
		"id": "shadow_clones", "element": Elements.SHADOW, "tier": 5,
		"kanji": "影分身", "title": "SHADOW CLONES",
		"subtitle": "Yami-watari: next cut is mirrored on 2 nearby yōkai",
		"cost": 8, "requires_all": ["backstab_execution"], "requires_any": [],
		"effects": {"shadow_clone_count": 2},
	},
]

var unlocked: Dictionary = {}  # node id -> true


static func node_by_id(id: String) -> Dictionary:
	for n: Dictionary in NODES:
		if String(n.get("id", "")) == id:
			return n
	return {}


static func nodes_for_element(element: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n: Dictionary in NODES:
		if String(n.get("element", "")) == element:
			out.append(n)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tier", 0)) < int(b.get("tier", 0)))
	return out


static func tree_cost(element: String) -> int:
	var total := 0
	for n: Dictionary in nodes_for_element(element):
		total += int(n.get("cost", 0))
	return total


func reset() -> void:
	unlocked.clear()


func is_unlocked(id: String) -> bool:
	return bool(unlocked.get(id, false))


func unlocked_count() -> int:
	return unlocked.size()


## True when every "requires_all" entry is unlocked and (when the node has
## a "requires_any" list) at least one of those is unlocked too.
func prerequisites_met(id: String) -> bool:
	var node := node_by_id(id)
	if node.is_empty():
		return false
	for req: String in node.get("requires_all", []):
		if not is_unlocked(req):
			return false
	var any_reqs: Array = node.get("requires_any", [])
	if not any_reqs.is_empty():
		var any_met := false
		for req: String in any_reqs:
			if is_unlocked(req):
				any_met = true
				break
		if not any_met:
			return false
	return true


## Whether [param id] can be bought right now with [param ofuda_available].
## Returns {"ok": bool, "reason": String, "cost": int}; never mutates state.
func can_unlock(id: String, ofuda_available: int) -> Dictionary:
	var node := node_by_id(id)
	if node.is_empty():
		return {"ok": false, "reason": REASON_UNKNOWN_NODE, "cost": 0}
	if is_unlocked(id):
		return {"ok": false, "reason": REASON_ALREADY_UNLOCKED, "cost": int(node.cost)}
	if not prerequisites_met(id):
		return {"ok": false, "reason": REASON_PREREQUISITE, "cost": int(node.cost)}
	if ofuda_available < int(node.cost):
		return {"ok": false, "reason": REASON_OFUDA, "cost": int(node.cost)}
	return {"ok": true, "reason": REASON_OK, "cost": int(node.cost)}


## Attempts the purchase against [param ofuda_available]. On success the
## node is marked unlocked and the caller deducts "cost" from its wallet
## (see RunGame.unlock_skill); on failure nothing changes.
func try_unlock(id: String, ofuda_available: int) -> Dictionary:
	var verdict := can_unlock(id, ofuda_available)
	if bool(verdict.get("ok", false)):
		unlocked[id] = true
	return verdict


## Upgraded value of ElementSystem parameter [param key] for [param element]
## from unlocked nodes of that element, or [param default_value] when no
## unlocked node defines it. Later tiers win when two nodes set the key.
func effect_value(element: String, key: String, default_value: Variant) -> Variant:
	var result: Variant = default_value
	var best_tier := -1
	for n: Dictionary in NODES:
		if String(n.get("element", "")) != element:
			continue
		if not is_unlocked(String(n.get("id", ""))):
			continue
		var effects: Dictionary = n.get("effects", {})
		if effects.has(key) and int(n.get("tier", 0)) >= best_tier:
			best_tier = int(n.get("tier", 0))
			result = effects[key]
	return result


## True when any unlocked node of [param element] defines [param key].
func has_effect(element: String, key: String) -> bool:
	for n: Dictionary in NODES:
		if String(n.get("element", "")) != element:
			continue
		if is_unlocked(String(n.get("id", ""))) and (n.get("effects", {}) as Dictionary).has(key):
			return true
	return false
